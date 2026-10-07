# frozen_string_literal: true

require 'shellwords'
require_relative '../utils/environment'
require_relative '../utils/provider_capabilities'

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

  def analyze_video(file:, fps: 1, query: nil, session: nil)
    return "Error: file is required." if file.to_s.empty?

    resolution = Monadic::Utils::ProviderCapabilities.resolve(:video, settings["provider"] || settings[:provider])
    return resolution[:error] if resolution[:error]

    provider = resolution[:provider]
    frame_limit = PROVIDER_FRAME_LIMITS.fetch(provider)

    # Quote both shell levels: filenames may contain spaces or shell syntax.
    safe_fps = fps.to_i
    safe_fps = 1 if safe_fps <= 0
    arguments = ["extract_frames.py", file.to_s, "./", "--fps", safe_fps.to_s,
                 "--format", "png", "--frames", frame_limit.to_s, "--json", "--audio"]
    safe_command = Shellwords.escape(Shellwords.join(arguments))
    split_command = "bash -c #{safe_command}"

    split_res = send_command(command: split_command, container: "python")

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] extract_frames output: #{split_res.inspect}"
    end

    # Parse frame and audio file paths from output
    json_file = nil
    audio_file = nil

    if split_res =~ /Base64-encoded frames saved to (.+\.json)/
      json_file = $1.strip
    end

    if split_res =~ /Audio extracted to (.+\.mp3)/
      audio_file = $1.strip
    end

    if json_file.nil? || json_file.empty?
      return "Error: Failed to extract frames from video. Output: #{split_res}"
    end

    # Step 2: Read frames JSON directly from shared volume
    frames = read_frames_json(json_file)
    return frames if frames.is_a?(String) # Error message

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] Loaded frames from #{json_file}"
    end

    # Step 3: Call Vision API directly (provider-independent)
    video_query = query || "Describe what happens in the video by analyzing the image data extracted from the video."
    description = video_vision_query(video_query, frames)

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "[VideoAnalyzeAgent] Vision query result: #{description&.slice(0, 200).inspect}"
    end

    # Check if there was an error
    if description.to_s.start_with?("ERROR:", "Error:")
      return "Video analysis failed: #{description}"
    end

    # Step 4: Audio transcription (via AudioTranscriptionAgent — provider-independent)
    if audio_file && !Monadic::Utils::ProviderCapabilities.supports?(:audio, provider)
      description += "\n\nAudio Transcript: Audio transcription is not supported by this provider."
    elsif audio_file
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

      description += "\n\n---\n\n"
      description += "Audio Transcript:\n#{audio_description}"
    end

    description
  end

  private

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
  def video_vision_query(query, frames)
    resolution = Monadic::Utils::ProviderCapabilities.resolve(:video, settings["provider"] || settings[:provider])
    return resolution[:error] if resolution[:error]

    provider = resolution[:provider]
    # The model sees still frames only. Without saying so it reports that no
    # audio was provided, which then sits next to the transcript that is
    # appended separately and reads as a contradiction.
    query = "#{VIDEO_FRAMES_ONLY_NOTE}\n#{query}"
    if frames.is_a?(Hash)
      duration = video_timestamp(frames.fetch("duration_ms"))
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

  def video_timestamp(milliseconds)
    value = milliseconds.round
    hours, rest = value.divmod(3_600_000)
    minutes, rest = rest.divmod(60_000)
    seconds, millis = rest.divmod(1000)
    hours.positive? ? format("%02d:%02d:%02d.%03d", hours, minutes, seconds, millis) : format("%02d:%02d.%03d", minutes, seconds, millis)
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
