# frozen_string_literal: true

# VideoAnalyzeAgent provides provider-independent video analysis
# by extracting frames and sending them to each provider's native Vision API.
#
# Supported vision providers: OpenAI, Claude (Anthropic), Gemini (Google), Grok (xAI)
# Non-vision providers fall back to the first available vision provider.
#
# Dependencies:
#   - ImageAnalysisAgent (included in MonadicApp) for:
#     resolve_vision_provider, vision_http_post, VISION_MODELS, VISION_API_KEYS
#   - AudioTranscriptionAgent (included in MonadicApp) for:
#     audio_transcription_agent (provider-independent STT)
#   - send_command (from MonadicApp) for:
#     extract_frames.py (Python container only)

module VideoAnalyzeAgent
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

    # Step 1: Extract frames using Python container (provider-independent)
    split_command = <<~CMD
      bash -c 'extract_frames.py "#{file}" ./ --fps #{fps} --format png --json --audio'
    CMD

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
      puts "[VideoAnalyzeAgent] Loaded #{frames.size} frames from #{json_file}"
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
    if audio_file
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

  # Read the frames JSON file from the shared volume
  def read_frames_json(json_path)
    return "ERROR: Invalid file path (path traversal not allowed)" if json_path.to_s.match?(%r{(?:\A|/)\.\.(?:/|\z)})

    # Strip leading ./ and resolve to shared volume
    clean_path = json_path.sub(%r{\A\./}, "")

    path = if File.exist?(json_path)
             json_path
           elsif defined?(SHARED_VOL) && File.exist?(File.join(SHARED_VOL, clean_path))
             File.join(SHARED_VOL, clean_path)
           elsif defined?(LOCAL_SHARED_VOL) && File.exist?(File.join(LOCAL_SHARED_VOL, clean_path))
             File.join(LOCAL_SHARED_VOL, clean_path)
           end

    return "ERROR: Frames JSON file not found: #{json_path}" unless path && File.exist?(path)

    json_data = JSON.parse(File.read(path))

    unless json_data.is_a?(Array) && json_data.all? { |item| item.is_a?(String) }
      return "ERROR: Invalid frames JSON format"
    end

    # Normalize: strip data URL prefix, keep raw base64
    json_data.map do |frame|
      if frame.start_with?("data:image/")
        frame.sub(%r{\Adata:image/[^;]+;base64,}, "")
      else
        frame
      end
    end
  rescue JSON::ParserError => e
    "ERROR: Failed to parse frames JSON: #{e.message}"
  end

  # Send frames to Vision API for analysis (provider-independent)
  def video_vision_query(query, frames)
    provider = resolve_vision_provider
    api_key_name = ImageAnalysisAgent::VISION_API_KEYS[provider]
    api_key = CONFIG[api_key_name]&.strip
    return "ERROR: No API key for provider '#{provider}'" if api_key.nil? || api_key.empty?

    model = ImageAnalysisAgent::VISION_MODELS[provider]

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

    step = (total - 1).to_f / (max_frames - 1)
    (0...max_frames).map { |i| frames[(i * step).round] }
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
      content << {
        type: "image_url",
        image_url: { url: "data:image/png;base64,#{frame_b64}" }
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

    content = []
    frames.each do |frame_b64|
      content << {
        type: "image",
        source: {
          type: "base64",
          media_type: "image/png",
          data: frame_b64
        }
      }
    end
    content << { type: "text", text: query }

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
    uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
    headers = {
      "Content-Type" => "application/json"
    }

    parts = []
    frames.each do |frame_b64|
      parts << {
        inline_data: {
          mime_type: "image/png",
          data: frame_b64
        }
      }
    end
    parts << { text: query }

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
      content << {
        type: "image_url",
        image_url: { url: "data:image/png;base64,#{frame_b64}" }
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
