# frozen_string_literal: true

require 'shellwords'
require_relative '../utils/environment'
require_relative '../utils/provider_capabilities'
require_relative '../utils/shared_path_guard'
require_relative '../utils/video_probe'
require_relative '../utils/model_spec'
require_relative '../utils/segment_transcriber'
require_relative '../shell'
require_relative '../workspace'

# VideoAnalyzeAgent provides provider-independent video analysis
# by extracting frames and sending them to each provider's native Vision API.
#
# Supported vision providers: OpenAI, Claude (Anthropic), Gemini (Google), Grok (xAI)
# Unsupported providers are rejected without cross-provider fallback.
#
# Dependencies:
#   - ImageAnalysisAgent (included in MonadicApp) for:
#     vision_model_for, VISION_API_KEYS
#   - AudioTranscriptionAgent (included in MonadicApp) for:
#     audio_transcription_agent (provider-independent STT)
#   - send_command (from MonadicApp) for:
#     extract_frames.py (Python container only)

module VideoAnalyzeAgent
  VIDEO_FRAMES_ONLY_NOTE = "You are shown still frames from a video, not its sound. The audio track, if any, " \
                           "is transcribed separately and added after your answer. Describe only what the frames " \
                           "show; do not mention audio, speech or sound, and do not say that audio is missing."
  # For speech with exact times (e.g. word times from the provider), the frames
  # can be described together with it. Video Describer does not pass speech
  # today: its segments are too coarse, so the app's model relates the two.
  VIDEO_WITH_SPEECH_NOTE = "You are shown still frames from a video and, after this note, what was said in it: " \
                           "each line starts with the video times of the speech it holds. Describe what happens by " \
                           "relating the speech to the frames whose times fall within or next to its span, quoting " \
                           "briefly and exactly. Do not place speech at times finer than its span, do not add " \
                           "sounds or words that are not in the lines, and do not repeat the whole transcript: " \
                           "it is shown to the reader separately."
  # Speech passed with the frames, at most this many characters (whole lines).
  VIDEO_SPEECH_CHAR_LIMIT = 20_000
  VIDEO_MAX_FRAMES = 50
  VIDEO_CONNECT_TIMEOUT = 10
  VIDEO_READ_TIMEOUT = 300   # 5 minutes for vision API to process many frames
  VIDEO_WRITE_TIMEOUT = 120  # 2 minutes to upload base64 images

  # Per-provider frame limits (Claude has a documented 20-image limit per request)
  PROVIDER_FRAME_LIMITS = {
    "openai"    => 50,
    "anthropic" => 20,
    "google"    => 50,
    "xai"       => 50
  }.freeze

  # Seconds the frame and audio extraction may take (long videos decode
  # slowly; the default command timeout of two minutes cut them off).
  VIDEO_EXTRACT_TIMEOUT = 900
  EXTRACT_SCRIPT = "/monadic/scripts/converters/extract_frames.py"
  # Mono at a constant 64 kbps: about 0.48 MB a minute, so the audio of the
  # longest video VideoProbe accepts (50 minutes) stays under the 25 MB that
  # transcription takes.
  AUDIO_ARGS = ["--audio", "--audio-bitrate", "64k", "--audio-channels", "1"].freeze
  OLD_PYTHON_IMAGE = "The Python container predates this version of Monadic Chat and cannot prepare the video. " \
                     "Rebuild it (Actions > Build Python Container) and try again."
  # Finds speech in the attached video's audio and cuts it into segments of
  # at most 30 seconds, with times on the video's clock (Python container).
  SEGMENT_SCRIPT = "/monadic/scripts/converters/speech_segments.py"
  # Providers whose own speech-to-text transcribes the speech segments:
  # OpenAI over a realtime session, the others one request per segment.
  SEGMENT_TRANSCRIPTION_PROVIDERS = %w[openai google xai].freeze
  UNTIMED_NOTE = "(Without times: the Python container predates timed transcripts. " \
                 "Rebuild it with Actions > Build Python Container to get them.)"

  # attachment_id: a video the user attached to this chat (preferred).
  # file: a file in the shared folder, for videos placed there by hand.
  def analyze_video(file: nil, attachment_id: nil, fps: 1, query: nil, session: nil)
    return "Error: attachment_id or file is required." if attachment_id.to_s.empty? && file.to_s.empty?

    resolution = Monadic::Utils::ProviderCapabilities.resolve(:video, settings["provider"] || settings[:provider])
    return resolution[:error] if resolution[:error]

    provider = resolution[:provider]
    frame_limit = PROVIDER_FRAME_LIMITS.fetch(provider)
    safe_fps = fps.to_i
    safe_fps = 1 if safe_fps <= 0

    extracted = if attachment_id.to_s.empty?
                  extract_from_shared_file(file, safe_fps, frame_limit)
                else
                  extract_from_attachment(attachment_id.to_s, session, safe_fps, frame_limit)
                end
    return extracted if extracted.is_a?(String) # Error message

    json_file = extracted[:json]

    # Step 2: Read frames JSON directly from shared volume
    frames = read_frames_json(json_file)
    return frames if frames.is_a?(String) # Error message

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] Loaded frames from #{json_file}"
    end

    # Step 3: The audio and the frames at the same time. They do not wait for
    # each other: the app's model relates them afterwards by their video
    # times, and one failing does not hold up the other.
    audio = Thread.new { video_transcript_section(extracted, provider, session) }
    audio.report_on_exception = false

    # Step 4: Call Vision API directly (provider-independent)
    video_query = query || "Describe what happens in the video by analyzing the image data extracted from the video."
    description = video_vision_query(video_query, frames)
    transcript = begin
      audio.value
    rescue StandardError => e
      "\n\n---\n\nAudio Transcript:\nAudio transcription failed: #{e.class.name.split('::').last}"
    end

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] Vision query result: #{description&.slice(0, 200).inspect}"
    end

    # Check if there was an error
    if description.to_s.start_with?("ERROR:", "Error:")
      return "Video analysis failed: #{description}"
    end

    "#{description}#{transcript}"
  end

  # The "Audio Transcript" part of the answer.
  def video_transcript_section(extracted, provider, session)
    audio_file = extracted[:audio]
    return "" unless audio_file

    timed = timed_transcript(extracted, provider, session)
    return "\n\n---\n\nAudio Transcript:\n#{timed[:text]}" if timed && !timed[:fallback]

    unless Monadic::Utils::ProviderCapabilities.supports?(:audio, provider)
      return "\n\nAudio Transcript: Audio transcription is not supported by this provider."
    end

    stt_model = session&.dig(:parameters, "stt_model") ||
                settings.dig(:agents, :speech_to_text) ||
                nil  # Let the agent use its default

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[VideoAnalyzeAgent] Using STT model: #{stt_model || 'default'}"
    end

    audio_description = audio_transcription_agent(
      audio_path: audio_file,
      model: stt_model,
      response_format: "text"
    )

    if audio_description.to_s.start_with?("ERROR:", "Error:")
      audio_description = "Audio transcription failed: #{audio_description}"
    end

    section = "\n\n---\n\nAudio Transcript:\n#{audio_description}"
    section += "\n\n#{UNTIMED_NOTE}" if timed&.dig(:fallback)
    section
  end

  private

  # The attached video, run in a folder of its own inside the chat's folder.
  # The chat is the session's; an id from another chat is refused.
  def extract_from_attachment(attachment_id, session, fps, frame_limit)
    chat_id = session && session[Monadic::Workspace::Chats::SESSION_KEY]
    record = Monadic::Workspace::Attachments.resolve!(chat_id: chat_id, attachment_id: attachment_id)
    return "Error: attachment #{record[:original_name]} is not a video." unless record[:purpose] == "video"

    workspace = Monadic::Workspace::Ledger.default.workspace(record[:workspace_id])
    job = Monadic::Workspace::Jobs.create!(workspace[:relative_dir])
    input = Monadic::Utils::SharedPathGuard.command_path(record[:path], container: "python")
    output = Monadic::Utils::SharedPathGuard.command_path(job[:path], container: "python", must_exist: false)
    return "Error: the attachment or its run folder is outside the shared folder." unless input && output

    Monadic::Utils::VideoProbe.check!(input)
    _stdout, stderr, status = run_extractor(input, output, fps, frame_limit)
    return "Error: #{OLD_PYTHON_IMAGE}" if stderr.to_s.include?("unrecognized arguments")

    json = Monadic::Workspace::Jobs.outputs(job, /\Aframes_[0-9_]+\.json\z/).first
    unless status.success? && json
      detail = stderr.to_s.lines.last.to_s.strip
      return "Error: Failed to extract frames from the video.#{" #{detail}" unless detail.empty?}"
    end

    { json: json, audio: Monadic::Workspace::Jobs.outputs(job, /\Aaudio_[0-9_]+\.mp3\z/).first,
      job: job, input: input, output: output }
  rescue Monadic::Workspace::Attachments::Unusable, Monadic::Utils::VideoProbe::Rejected => e
    "Error: #{e.message}"
  rescue Monadic::Workspace::Jobs::Unavailable, Monadic::Workspace::Ledger::Unreadable => e
    "Error: #{e.message}"
  rescue Monadic::Shell::TimedOut
    "Error: extracting frames took longer than #{VIDEO_EXTRACT_TIMEOUT / 60} minutes. Try a shorter video."
  end

  # A video placed in the shared folder by name (the way before attachments).
  def extract_from_shared_file(file, fps, frame_limit)
    # The same check before decoding as for attachments.
    input = Monadic::Utils::SharedPathGuard.command_path(file.to_s, container: "python")
    return "Error: #{file} was not found in the shared folder." unless input

    begin
      Monadic::Utils::VideoProbe.check!(input)
    rescue Monadic::Utils::VideoProbe::Rejected => e
      return "Error: #{e.message}"
    end

    # Written next to the video, in the shared folder (the way before attachments).
    stdout, stderr, status = run_extractor(input, "./", fps, frame_limit)
    return "Error: #{OLD_PYTHON_IMAGE}" if stderr.to_s.include?("unrecognized arguments")

    split_res = "#{stdout}#{stderr}"
    return "Error: Failed to extract frames from video. Output: #{split_res}" unless status.success?

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] extract_frames output: #{split_res.inspect}"
    end

    json_file = split_res[/Base64-encoded frames saved to (.+\.json)/, 1]&.strip
    audio_file = split_res[/Audio extracted to (.+\.mp3)/, 1]&.strip
    return "Error: Failed to extract frames from video. Output: #{split_res}" if json_file.nil? || json_file.empty?

    { json: json_file, audio: audio_file, input: input }
  rescue Monadic::Shell::TimedOut
    "Error: extracting frames took longer than #{VIDEO_EXTRACT_TIMEOUT / 60} minutes. Try a shorter video."
  end

  # The extractor in the Python container: no shell, the script by its
  # absolute path (scripts in the shared folder come first on PATH there, so
  # a file named like it must not run instead), and a time limit long enough
  # for the longest video VideoProbe accepts.
  def run_extractor(input, output, fps, frame_limit)
    argv = ["python", EXTRACT_SCRIPT, input, output, "--fps", fps.to_s, "--format", "png",
            "--frames", frame_limit.to_s, "--json", *AUDIO_ARGS]
    Monadic::Shell.exec(container: :python, argv: argv, timeout: VIDEO_EXTRACT_TIMEOUT)
  end

  # A transcript whose lines carry the video time of the speech they hold:
  # speech_segments.py cuts the audio into segments, and each segment is
  # transcribed on its own over a realtime transcription session, so the
  # times are the segments' own positions, never the model's guesses.
  # Returns nil when this path does not apply (another provider, or no model
  # that can do it), { fallback: true } when the Python container is too old
  # (the untimed transcript is used, with a note saying so), or { text: }.
  # Stops sending when the chat changes; the result stays in the run folder.
  def timed_transcript(extracted, provider, session)
    return nil unless SEGMENT_TRANSCRIPTION_PROVIDERS.include?(provider)

    chat_id = session && session[Monadic::Workspace::Chats::SESSION_KEY]
    return nil unless extracted[:job] || Monadic::Workspace::Ids.valid?(:chat, chat_id)

    model = segment_transcription_model(provider, session)
    return nil unless model

    job, output = transcript_job(extracted, session)
    return nil unless job

    _stdout, stderr, status = Monadic::Shell.exec(
      container: :python, argv: ["python", SEGMENT_SCRIPT, extracted[:input], output],
      timeout: VIDEO_EXTRACT_TIMEOUT
    )
    return { fallback: true } if old_python_image?(stderr)

    segments_path = Monadic::Workspace::Jobs.outputs(job, /\Asegments\.json\z/).first
    unless status.success? && segments_path
      detail = stderr.to_s.lines.last.to_s.strip
      return { text: "Audio transcription failed: could not find speech in the audio.#{" #{detail}" unless detail.empty?}" }
    end

    doc = JSON.parse(File.read(segments_path))
    return { text: "(The video has no audio track.)" } if doc["status"] == "absent"
    return { text: "(No speech was detected in the audio.)" } if doc["status"] == "no_speech_detected"

    key_name = AudioTranscriptionAgent::AUDIO_API_KEYS[provider]
    api_key = CONFIG[key_name].to_s.strip
    return { text: "Audio transcription failed: #{key_name} is not set." } if api_key.empty?

    pcm_path = Monadic::Workspace::Jobs.outputs(job, /\Aaudio_24k\.pcm\z/).first
    chat_at_start = session && session[Monadic::Workspace::Chats::SESSION_KEY]
    cancelled = -> { session && session[Monadic::Workspace::Chats::SESSION_KEY] != chat_at_start }
    result = if provider == "openai"
               Sync do
                 Monadic::Utils::SegmentTranscriber.new(
                   segments: doc, pcm_path: pcm_path, model: model, cancelled: cancelled,
                   connect: -> { Monadic::Utils::SegmentTranscriber::WebSocketConnection.open(api_key) }
                 ).run
               end
             else
               Monadic::Utils::SegmentTranscriber::Batch.new(
                 segments: doc, pcm_path: pcm_path, model: model, cancelled: cancelled,
                 transcribe: ->(wav) { transcribe_audio_bytes(provider, wav, "wav", model) }
               ).run
             end
    File.write(File.join(job[:path], "transcript.json"), JSON.pretty_generate(result))
    File.delete(pcm_path) if pcm_path && File.exist?(pcm_path)
    { text: format_timed_transcript(result) }
  rescue Monadic::Shell::TimedOut
    { text: "Audio transcription failed: finding speech took longer than #{VIDEO_EXTRACT_TIMEOUT / 60} minutes." }
  rescue JSON::ParserError, SystemCallError => e
    { text: "Audio transcription failed: #{e.class.name.split('::').last}" }
  end

  # The run folder for the transcript: the attachment's own, or for a video
  # named from the shared folder a new one in the chat's folder. Without a
  # chat (e.g. an MCP call) there is nowhere to keep it, so none.
  def transcript_job(extracted, session)
    return [extracted[:job], extracted[:output]] if extracted[:job]

    chat_id = session && session[Monadic::Workspace::Chats::SESSION_KEY]
    return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id) && extracted[:input]

    workspace = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: self.class.name)
    job = Monadic::Workspace::Jobs.create!(workspace[:relative_dir])
    output = Monadic::Utils::SharedPathGuard.command_path(job[:path], container: "python", must_exist: false)
    output ? [job, output] : nil
  rescue Monadic::Workspace::Jobs::Unavailable, Monadic::Workspace::Ledger::Unreadable
    nil
  end

  # The model that transcribes the segments. For OpenAI, the chat's STT
  # selection when it can transcribe committed segments in a realtime
  # session, otherwise the default when that can, otherwise none. For the
  # others, the chat's selection when it is theirs, otherwise their default.
  def segment_transcription_model(provider, session)
    selected = session&.dig(:parameters, "stt_model") || settings.dig(:agents, :speech_to_text)
    return AudioTranscriptionAgent.model_for(provider, selected) unless provider == "openai"

    [AudioTranscriptionAgent.model_for("openai", selected), AudioTranscriptionAgent.audio_model_for("openai")]
      .compact.find { |m| Monadic::Utils::ModelSpec.supports_segment_transcription?(m) }
  end

  def old_python_image?(stderr)
    text = stderr.to_s
    text.include?("can't open file") || text.include?("No module named 'onnxruntime'") ||
      text.include?("Speech detection model not found")
  end

  # One line per segment: "[start–end] text", times on the video's clock.
  def format_timed_transcript(result)
    if result["status"] == "failed"
      reason = result["segments"].filter_map { |seg| seg["error"] }.first
      return "Audio transcription failed#{": #{reason}" if reason}."
    end

    rate = result["sample_rate_hz"].to_f
    shown = result["segments"].reject do |seg|
      seg["status"] == "pending" || (seg["status"] == "complete" && seg["text"].to_s.strip.empty?)
    end
    lines = shown.map do |seg|
      # Rounded outward, so the span never cuts into the speech it holds.
      span = "[#{video_clock((seg['start_sample'] / rate).floor)}–#{video_clock((seg['end_sample'] / rate).ceil)}]"
      text = case seg["status"]
             when "complete" then seg["text"].to_s.strip
             else "(transcription failed)"
             end
      "#{span} #{text}"
    end
    case result["status"]
    when "partial" then lines << "(Some segments could not be transcribed.)"
    when "cancelled" then lines << "(Stopped because the chat changed.)"
    end
    lines.join("\n")
  end

  # Read the frames JSON file from the shared volume.
  #
  # `extract_frames.py` writes the JSON file to the shared volume and reports
  # the path as `./frames_<timestamp>.json` (relative to the script's CWD,
  # which is the shared volume itself). This method resolves that filename
  # against the shared volume returned by `Monadic::Utils::Environment`
  # (`/monadic/data` inside the Ruby container, `~/monadic/data` on the host
  # in dev mode).
  def read_frames_json(json_path)
    return "ERROR: Invalid file path (path traversal not allowed)" if json_path.to_s.match?(%r{(?:\A|/)\.\.(?:/|\z)})

    # Strip leading ./ and resolve to the active shared volume.
    clean_path = json_path.sub(%r{\A\./}, "")
    shared_path = File.join(Monadic::Utils::Environment.shared_volume, clean_path)

    path = if File.exist?(json_path)
             json_path
           elsif File.exist?(shared_path)
             shared_path
           end

    return "ERROR: Frames JSON file not found: #{json_path}" unless path && File.exist?(path)

    json_data = JSON.parse(File.read(path))

    if json_data.is_a?(Array) && !json_data.empty? && json_data.all? { |item| item.is_a?(String) }
      # Legacy input: never invent timestamps from array positions.
      return json_data.map { |frame| frame.sub(%r{\Adata:image/[^;]+;base64,}, "") }
    end

    valid_number = ->(value) { value.is_a?(Numeric) && value.finite? && value >= 0 }
    unless json_data.is_a?(Hash) && json_data["schema_version"] == 1 &&
           valid_number.call(json_data["duration_ms"]) &&
           json_data["timestamp_source"].is_a?(String) && !json_data["timestamp_source"].empty? &&
           json_data["frames"].is_a?(Array) && !json_data["frames"].empty?
      return "ERROR: Invalid frames JSON format"
    end
    valid = json_data["frames"].all? do |frame|
      frame.is_a?(Hash) && frame["frame_id"].is_a?(String) && frame["frame_id"].match?(/\Af[0-9]+\z/) &&
        frame["source_frame_index"].is_a?(Integer) && frame["source_frame_index"] >= 0 &&
        valid_number.call(frame["timestamp_ms"]) && frame["timestamp_ms"] <= json_data["duration_ms"] &&
        frame["image"].is_a?(String) && !frame["image"].empty? &&
        %w[image/png image/jpeg].include?(frame["mime_type"]) &&
        (!frame.key?("change_score") || valid_number.call(frame["change_score"]))
    end
    return "ERROR: Invalid frame metadata" unless valid

    frames = json_data["frames"].sort_by { |frame| frame["timestamp_ms"] }
    unless frames.map { |frame| frame["frame_id"] }.uniq.size == frames.size &&
           frames.each_cons(2).all? { |a, b| a["timestamp_ms"] < b["timestamp_ms"] && a["source_frame_index"] < b["source_frame_index"] }
      return "ERROR: Invalid frame timeline"
    end
    json_data.merge("frames" => frames)
  rescue JSON::ParserError => e
    "ERROR: Failed to parse frames JSON: #{e.message}"
  end

  # Send frames to Vision API for analysis (provider-independent)
  def video_vision_query(query, frames, speech: nil)
    resolution = Monadic::Utils::ProviderCapabilities.resolve(:video, settings["provider"] || settings[:provider])
    return resolution[:error] if resolution[:error]

    provider = resolution[:provider]
    # The model sees still frames only. Without saying so it reports that no
    # audio was provided, which then sits next to the transcript that is
    # appended separately and reads as a contradiction.
    query = if speech&.any?
              "#{VIDEO_WITH_SPEECH_NOTE}\nSpeech:\n#{video_speech_excerpt(speech)}\n\n#{query}"
            else
              "#{VIDEO_FRAMES_ONLY_NOTE}\n#{query}"
            end
    if frames.is_a?(Hash)
      duration = video_clock((frames.fetch("duration_ms") / 1000.0).round)
      query = "Video duration: #{duration}. These images are non-uniform excerpts, not continuous footage. " \
              "Cite frame IDs and observed times. Do not infer events or durations between frames.\n#{query}"
      frames = frames.fetch("frames").sort_by { |frame| frame.fetch("timestamp_ms") }
    else
      query = "These images are excerpts with unknown timestamps. Do not invent times or durations between frames.\n#{query}"
    end
    api_key_name = ImageAnalysisAgent::VISION_API_KEYS[provider]
    api_key = CONFIG[api_key_name]&.strip
    return "ERROR: No API key for provider '#{provider}'" if api_key.nil? || api_key.empty?

    model = ImageAnalysisAgent.vision_model_for(provider)

    # Apply per-provider frame limit
    max_frames = PROVIDER_FRAME_LIMITS[provider] || VIDEO_MAX_FRAMES
    if frames.size > max_frames
      frames = balance_frames(frames, max_frames)
    end

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[VideoAnalyzeAgent] Using provider: #{provider}, model: #{model}, frames: #{frames.size}"
    end

    case provider
    when "openai"    then video_vision_openai(query, frames, model, api_key)
    when "anthropic" then video_vision_claude(query, frames, model, api_key)
    when "google"    then video_vision_gemini(query, frames, model, api_key)
    when "xai"       then video_vision_grok(query, frames, model, api_key)
    end
  rescue => e
    "ERROR: Video vision analysis failed: #{e.message}"
  end

  # Evenly sample frames to fit within limit
  def balance_frames(frames, max_frames)
    total = frames.size
    return frames if total <= max_frames
    return [frames.first] if max_frames <= 1

    if frames.first.is_a?(Hash)
      frames = frames.sort_by { |frame| frame.fetch("timestamp_ms") }
      chosen = [0, total - 1]
      coverage = [2, (max_frames + 1) / 2].max
      first_time, last_time = frames.first["timestamp_ms"], frames.last["timestamp_ms"]
      coverage.times do |i|
        target = first_time + (last_time - first_time) * i / (coverage - 1).to_f
        chosen << (0...total).min_by { |j| (frames[j]["timestamp_ms"] - target).abs }
      end
      chosen.uniq!
      while chosen.size < max_frames
        index = ((0...total).to_a - chosen).max_by do |j|
          gap = chosen.map { |k| (frames[j]["timestamp_ms"] - frames[k]["timestamp_ms"]).abs }.min
          frames[j].fetch("change_score", 0) + gap / [last_time - first_time, 1].max.to_f * 0.1
        end
        chosen << index
      end
      return chosen.sort.map { |index| frames[index] }
    end

    step = (total - 1).to_f / (max_frames - 1)
    (0...max_frames).map { |i| frames[(i * step).round] }
  end

  # Whole lines up to VIDEO_SPEECH_CHAR_LIMIT, saying how many were left out.
  def video_speech_excerpt(lines)
    kept = []
    size = 0
    lines.each do |line|
      break if size + line.size + 1 > VIDEO_SPEECH_CHAR_LIMIT

      kept << line
      size += line.size + 1
    end
    omitted = lines.size - kept.size
    omitted.positive? ? (kept + ["(#{omitted} later lines of speech omitted)"]).join("\n") : kept.join("\n")
  end

  # Video times as people read them: whole seconds ("01:05", "1:02:03").
  def video_clock(seconds)
    hours, rest = seconds.to_i.divmod(3600)
    minutes, secs = rest.divmod(60)
    hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%02d:%02d", minutes, secs)
  end

  # A frame's time: whole seconds, with tenths only for a frame between two
  # seconds, so that frames taken less than a second apart keep their order.
  def video_timestamp(milliseconds)
    tenths = (milliseconds / 100.0).round
    seconds, tenth = tenths.divmod(10)
    tenth.zero? ? video_clock(seconds) : "#{video_clock(seconds)}.#{tenth}"
  end

  def video_frame_label(frame)
    return nil unless frame.is_a?(Hash)

    "Frame #{frame.fetch('frame_id')}, video time #{video_timestamp(frame.fetch('timestamp_ms'))}"
  end

  def video_frame_image(frame)
    frame.is_a?(Hash) ? frame.fetch("image") : frame
  end

  def video_frame_mime(frame)
    frame.is_a?(Hash) ? frame.fetch("mime_type") : "image/png"
  end

  # HTTP POST with video-specific timeouts
  def video_vision_http_post(uri, headers, body)
    retries = 0
    begin
      res = HTTP.headers(headers)
               .timeout(connect: VIDEO_CONNECT_TIMEOUT,
                        write: VIDEO_WRITE_TIMEOUT,
                        read: VIDEO_READ_TIMEOUT)
               .post(uri, json: body)
      res
    rescue HTTP::Error, HTTP::TimeoutError => e
      if retries < 1
        retries += 1
        sleep 1
        retry
      end
      raise e
    end
  end

  # --- Provider-specific multi-frame Vision API calls ---

  def video_vision_openai(query, frames, model, api_key)
    uri = "https://api.openai.com/v1/chat/completions"
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    content = [{ type: "text", text: query }]
    frames.each do |frame_b64|
      label = video_frame_label(frame_b64)
      content << { type: "text", text: label } if label
      content << {
        type: "image_url",
        image_url: { url: "data:#{video_frame_mime(frame_b64)};base64,#{video_frame_image(frame_b64)}" }
      }
    end

    # Output-token key sourced from OpenAIHelper::OUTPUT_TOKEN_KEY (SSOT).
    # GPT-5.x requires `max_completion_tokens`; older models accept it.
    # Omit temperature: GPT-5.x rejects it, and a deterministic value isn't
    # critical for a single-shot vision query.
    body = {
      model: model,
      OpenAIHelper::OUTPUT_TOKEN_KEY => 1000,
      messages: [{ role: "user", content: content }]
    }

    res = video_vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: OpenAI Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    JSON.parse(res.body.to_s).dig("choices", 0, "message", "content") || "ERROR: Empty response from OpenAI"
  end

  def video_vision_claude(query, frames, model, api_key)
    uri = "https://api.anthropic.com/v1/messages"
    headers = {
      "Content-Type" => "application/json",
      "x-api-key" => api_key,
      "anthropic-version" => "2023-06-01"
    }

    content = [{ type: "text", text: query }]
    frames.each do |frame_b64|
      label = video_frame_label(frame_b64)
      content << { type: "text", text: label } if label
      content << {
        type: "image",
        source: {
          type: "base64",
          media_type: video_frame_mime(frame_b64),
          data: video_frame_image(frame_b64)
        }
      }
    end

    body = {
      model: model,
      max_tokens: 1000,
      messages: [{ role: "user", content: content }]
    }

    res = video_vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Claude Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    parsed = JSON.parse(res.body.to_s)
    content_blocks = parsed["content"]
    if content_blocks.is_a?(Array) && content_blocks.first
      content_blocks.first["text"] || "ERROR: Empty response from Claude"
    else
      "ERROR: Unexpected response format from Claude"
    end
  end

  def video_vision_gemini(query, frames, model, api_key)
    uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"
    headers = {
      "Content-Type" => "application/json", "x-goog-api-key" => api_key
    }

    parts = [{ text: query }]
    frames.each do |frame_b64|
      label = video_frame_label(frame_b64)
      parts << { text: label } if label
      parts << {
        inline_data: {
          mime_type: video_frame_mime(frame_b64),
          data: video_frame_image(frame_b64)
        }
      }
    end

    body = {
      contents: [{ parts: parts }]
    }

    res = video_vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Gemini Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    JSON.parse(res.body.to_s).dig("candidates", 0, "content", "parts", 0, "text") || "ERROR: Empty response from Gemini"
  end

  def video_vision_grok(query, frames, model, api_key)
    # Grok uses OpenAI-compatible API format
    uri = "https://api.x.ai/v1/chat/completions"
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    content = [{ type: "text", text: query }]
    frames.each do |frame_b64|
      label = video_frame_label(frame_b64)
      content << { type: "text", text: label } if label
      content << {
        type: "image_url",
        image_url: { url: "data:#{video_frame_mime(frame_b64)};base64,#{video_frame_image(frame_b64)}" }
      }
    end

    body = {
      model: model,
      temperature: 0.0,
      max_tokens: 1000,
      messages: [{ role: "user", content: content }]
    }

    res = video_vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Grok Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    JSON.parse(res.body.to_s).dig("choices", 0, "message", "content") || "ERROR: Empty response from Grok"
  end
end
