# frozen_string_literal: true

require "base64"
require "http"

# AudioTranscriptionAgent provides provider-independent audio transcription.
#
# Supported providers:
#   - OpenAI: Dedicated /v1/audio/transcriptions endpoint (Whisper, gpt-4o-transcribe models)
#   - Gemini: Multimodal generateContent with audio inline_data
#
# Non-STT providers (Claude, Grok, Cohere, DeepSeek, Mistral, Perplexity, Ollama)
# fall back to the first available audio provider (preference: OpenAI -> Gemini).

module AudioTranscriptionAgent
  AUDIO_MODELS = {
    "openai" => "gpt-4o-mini-transcribe-2025-12-15",
    "google" => "gemini-3.1-flash-lite-preview"
  }.freeze

  AUDIO_API_KEYS = {
    "openai" => "OPENAI_API_KEY",
    "google" => "GEMINI_API_KEY"
  }.freeze

  AUDIO_PROVIDERS = AUDIO_MODELS.keys.freeze

  AUDIO_CONNECT_TIMEOUT = 10
  AUDIO_READ_TIMEOUT = 180  # 3 minutes for long audio files
  AUDIO_WRITE_TIMEOUT = 60
  AUDIO_MAX_RETRIES = 1
  AUDIO_MAX_FILE_SIZE = 25 * 1024 * 1024 # 25MB (OpenAI limit)

  # MIME types for Gemini inline_data
  AUDIO_MIME_TYPES = {
    "mp3"  => "audio/mpeg",
    "mp4"  => "audio/mp4",
    "mpeg" => "audio/mpeg",
    "mpga" => "audio/mpeg",
    "m4a"  => "audio/mp4",
    "wav"  => "audio/wav",
    "webm" => "audio/webm",
    "ogg"  => "audio/ogg",
    "flac" => "audio/flac"
  }.freeze

  # Main entry point for audio transcription
  # @param audio_path [String] Path to the audio file
  # @param model [String, nil] Override model selection (for OpenAI STT model from Web UI)
  # @param response_format [String] Response format ("text", "json") — OpenAI only
  # @param lang_code [String, nil] Language code hint
  # @return [String] Transcription text or error message
  def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
    # 1. Resolve audio file path
    path = resolve_audio_path(audio_path)
    return path if path.is_a?(String) && path.start_with?("ERROR:")

    # 2. Check file size
    file_size = File.size(path)
    if file_size > AUDIO_MAX_FILE_SIZE
      return "ERROR: Audio file too large (#{file_size / 1024 / 1024}MB). Maximum: 25MB"
    end

    # 3. Determine provider
    provider = resolve_audio_provider

    # 4. Get API key
    api_key_name = AUDIO_API_KEYS[provider]
    api_key = CONFIG[api_key_name]&.strip
    return "ERROR: No API key for provider '#{provider}'" if api_key.nil? || api_key.empty?

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[AudioTranscriptionAgent] Using provider: #{provider}, path: #{path}"
    end

    # 5. Call provider-specific transcription API
    case provider
    when "openai"
      stt_model = model || AUDIO_MODELS["openai"]
      transcribe_openai(path, stt_model, api_key, response_format, lang_code)
    when "google"
      transcribe_gemini(path, AUDIO_MODELS["google"], api_key, lang_code)
    end
  rescue => e
    "ERROR: Audio transcription failed: #{e.message}"
  end

  private

  # Resolve audio file path from shared volume
  def resolve_audio_path(audio_path)
    return "ERROR: Invalid file path (path traversal not allowed)" if audio_path.to_s.match?(%r{(?:\A|/)\.\.(?:/|\z)})

    clean_path = audio_path.to_s.sub(%r{\A\./}, "")

    path = if File.exist?(audio_path.to_s)
             audio_path.to_s
           elsif defined?(SHARED_VOL) && File.exist?(File.join(SHARED_VOL, clean_path))
             File.join(SHARED_VOL, clean_path)
           elsif defined?(LOCAL_SHARED_VOL) && File.exist?(File.join(LOCAL_SHARED_VOL, clean_path))
             File.join(LOCAL_SHARED_VOL, clean_path)
           end

    return "ERROR: Audio file not found: #{audio_path}" unless path && File.exist?(path)
    path
  end

  # Determine which provider to use for audio transcription
  def resolve_audio_provider
    provider_raw = settings["provider"] || settings[:provider] || ""

    # Only OpenAI and Gemini support audio transcription natively
    normalized = case provider_raw.to_s.downcase
                 when "openai" then "openai"
                 when "google", "gemini" then "google"
                 else nil
                 end

    if normalized && AUDIO_PROVIDERS.include?(normalized)
      api_key = CONFIG[AUDIO_API_KEYS[normalized]]&.strip
      return normalized unless api_key.nil? || api_key.empty?
    end

    # Fallback: OpenAI first, then Gemini
    AUDIO_PROVIDERS.each do |ap|
      api_key = CONFIG[AUDIO_API_KEYS[ap]]&.strip
      return ap unless api_key.nil? || api_key.empty?
    end

    "openai"
  end

  # --- OpenAI Transcription API ---
  # Uses dedicated /v1/audio/transcriptions endpoint with multipart form upload
  # (follows the same pattern as the original stt_query.rb)

  def transcribe_openai(path, model, api_key, response_format, lang_code)
    uri = "https://api.openai.com/v1/audio/transcriptions"

    options = {
      file: HTTP::FormData::File.new(path),
      model: model,
      response_format: response_format
    }
    options[:language] = lang_code if lang_code && !lang_code.empty?

    form = HTTP::FormData.create(options)

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[AudioTranscriptionAgent] OpenAI STT model: #{model}, format: #{response_format}"
    end

    retries = 0
    begin
      res = HTTP.headers(
        "Content-Type" => form.content_type,
        "Authorization" => "Bearer #{api_key}"
      ).timeout(
        connect: AUDIO_CONNECT_TIMEOUT,
        write: AUDIO_WRITE_TIMEOUT,
        read: AUDIO_READ_TIMEOUT
      ).post(uri, body: form.to_s)
    rescue HTTP::Error, HTTP::TimeoutError => e
      if retries < AUDIO_MAX_RETRIES
        retries += 1
        sleep 1
        retry
      end
      raise e
    end

    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: OpenAI STT API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    res.body.to_s
  end

  # --- Gemini Transcription ---
  # Uses generateContent with audio inline_data (multimodal input)

  def transcribe_gemini(path, model, api_key, lang_code)
    uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"

    # Detect MIME type
    ext = File.extname(path).delete_prefix(".").downcase
    mime_type = AUDIO_MIME_TYPES[ext] || "audio/mpeg"

    # Read and encode audio
    raw = File.binread(path)
    base64_data = Base64.strict_encode64(raw)

    # Build transcription prompt
    prompt = "Transcribe the following audio accurately."
    prompt += " The audio is in #{lang_code}." if lang_code && !lang_code.empty?
    prompt += " Return only the transcription text, without any additional commentary."

    body = {
      contents: [
        {
          parts: [
            {
              inline_data: {
                mime_type: mime_type,
                data: base64_data
              }
            },
            { text: prompt }
          ]
        }
      ]
    }

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[AudioTranscriptionAgent] Gemini model: #{model}, mime: #{mime_type}, size: #{raw.size} bytes"
    end

    retries = 0
    begin
      res = HTTP.headers("Content-Type" => "application/json")
               .timeout(
                 connect: AUDIO_CONNECT_TIMEOUT,
                 write: AUDIO_WRITE_TIMEOUT,
                 read: AUDIO_READ_TIMEOUT
               ).post(uri, json: body)
    rescue HTTP::Error, HTTP::TimeoutError => e
      if retries < AUDIO_MAX_RETRIES
        retries += 1
        sleep 1
        retry
      end
      raise e
    end

    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Gemini STT API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    parsed = JSON.parse(res.body.to_s)
    parsed.dig("candidates", 0, "content", "parts", 0, "text") || "ERROR: Empty response from Gemini"
  end
end
