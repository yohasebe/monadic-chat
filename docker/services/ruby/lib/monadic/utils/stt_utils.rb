# frozen_string_literal: true

require 'json'
require 'base64'
require 'tempfile'

require_relative 'extra_logger'

module InteractionUtils
  def gemini_stt_api_request(blob, format, lang_code, model)
    # Base64 encode the audio data
    base64_audio = Base64.strict_encode64(blob)

    # Map format to MIME type
    mime_type = case format.to_s.downcase
    when "mp3", "mpeg" then "audio/mp3"
    when "wav", "wave", "x-wav" then "audio/wav"
    when "m4a", "mp4", "mp4a-latm" then "audio/aac"
    when "ogg" then "audio/ogg"
    when "flac" then "audio/flac"
    when "aac" then "audio/aac"
    when "aiff" then "audio/aiff"
    else "audio/#{format}"
    end

    # Gemini API endpoint
    # Use GeminiHelper::API_ENDPOINT if available, otherwise fallback
    api_endpoint = defined?(GeminiHelper::API_ENDPOINT) ? GeminiHelper::API_ENDPOINT : "https://generativelanguage.googleapis.com/v1alpha"
    url = "#{api_endpoint}/models/#{model}:generateContent"

    # Build language-specific transcription prompt
    # Ignore "auto" language code as it means automatic detection
    transcription_prompt = if lang_code && lang_code != "auto"
      # Create language-specific instruction
      language_names = {
        "en" => "English",
        "ja" => "Japanese",
        "zh" => "Chinese",
        "es" => "Spanish",
        "fr" => "French",
        "de" => "German",
        "it" => "Italian",
        "pt" => "Portuguese",
        "ru" => "Russian",
        "ko" => "Korean",
        "ar" => "Arabic",
        "hi" => "Hindi"
      }
      language = language_names[lang_code] || lang_code.upcase

      # Flexible language handling: specify primary language but allow others
      # This matches OpenAI STT behavior where language is a hint, not a constraint
      base_prompt = "Please transcribe the spoken words. The primary language is expected to be #{language}, but transcribe any language if spoken. Do not describe sound effects or audio characteristics."

      # Add spacing instruction for Japanese
      if lang_code == "ja"
        base_prompt + " For Japanese text, do not insert spaces between words."
      else
        base_prompt
      end
    else
      # Default prompt for auto-detection
      "Please transcribe the spoken words. Do not describe sound effects or audio characteristics."
    end

    # Prepare request body
    body = {
      contents: [{
        parts: [
          {text: transcription_prompt},
          {inline_data: {mime_type: mime_type, data: base64_audio}}
        ]
      }]
    }

    num_retrial = 0

    begin
      response = HTTP.headers("Content-Type" => "application/json")
        .timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT)
        .post("#{url}?key=#{CONFIG['GEMINI_API_KEY']}", json: body)

      if response.status.success?
        result = JSON.parse(response.body)
        text = result.dig("candidates", 0, "content", "parts", 0, "text")&.strip || ""

        # Remove morpheme-level spacing for Japanese only
        # Japanese text from Gemini STT often has spaces between morphemes (tokens)
        # which is not standard Japanese writing convention
        if lang_code == "ja"
          # Remove spaces between Japanese characters (Hiragana, Katakana, Kanji)
          loop do
            new_text = text.gsub(/([\p{Hiragana}\p{Katakana}\p{Han}])\s+([\p{Hiragana}\p{Katakana}\p{Han}])/, '\1\2')
            break if new_text == text
            text = new_text
          end
        end

        return {
          "text" => text,
          "logprobs" => [] # Gemini does not support logprobs for STT
        }
      else
        error_body = JSON.parse(response.body) rescue {}
        error_message = error_body.dig("error", "message") || "Unknown error"
        return {
          "type" => "error",
          "content" => "Gemini API error (#{response.status}): #{error_message}"
        }
      end
    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        return {
          "type" => "error",
          "content" => "ERROR: #{e.message}"
        }
      end
    rescue StandardError => e
      return {
        "type" => "error",
        "content" => "ERROR: #{e.message}"
      }
    end
  end

  # ElevenLabs Speech-to-Text API request
  # @param blob [String] The audio data
  # @param format [String] The audio format (e.g., "webm", "mp3", "wav")
  # @param lang_code [String] The language code (e.g., "en", "ja", "auto")
  # @param model [String] The model to use (e.g., "scribe_v2", "scribe_v1")
  # @return [Hash] The transcription result or error
  def elevenlabs_stt_api_request(blob, format, lang_code, model)
    api_key = CONFIG["ELEVENLABS_API_KEY"]

    if api_key.nil? || api_key.to_s.strip.empty?
      return {
        "type" => "error",
        "content" => "ElevenLabs API key is not configured"
      }
    end

    # ElevenLabs STT endpoint
    url = "https://api.elevenlabs.io/v1/speech-to-text"

    # Normalize format for file extension
    normalized_format = format.to_s.downcase
    normalized_format = "mp3" if normalized_format == "mpeg"
    normalized_format = "mp4" if normalized_format == "mp4a-latm"
    normalized_format = "wav" if %w[x-wav wave].include?(normalized_format)

    num_retrial = 0

    begin
      # Create temporary file with audio data
      temp_file = Tempfile.new([TEMP_AUDIO_FILE, ".#{normalized_format}"])
      temp_file.binmode
      temp_file.write(blob)
      temp_file.flush

      # Build multipart form data
      # ElevenLabs accepts file_format: "other" for standard audio formats
      options = {
        "model_id" => model,
        "file" => HTTP::FormData::File.new(temp_file.path),
        "file_format" => "other",
        "timestamps_granularity" => "word"
      }

      # Add language code if specified (not "auto")
      if lang_code && lang_code != "auto"
        options["language_code"] = lang_code
      end

      form_data = HTTP::FormData.create(options)

      response = HTTP.headers(
        "xi-api-key" => api_key,
        "Content-Type" => form_data.content_type
      ).timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT)
       .post(url, body: form_data.to_s)

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        return { "type" => "error", "content" => "ERROR: #{e.message}" }
      end
    ensure
      if temp_file
        temp_file.close
        temp_file.unlink
      end
    end

    if response.status.success?
      result = JSON.parse(response.body)

      # ElevenLabs response format:
      # {
      #   "language_code": "en",
      #   "language_probability": 0.99,
      #   "text": "transcribed text",
      #   "words": [{"text": "word", "start": 0.0, "end": 0.5, "type": "word", ...}]
      # }

      text = result["text"]&.strip || ""

      # Build logprobs from word-level data if available
      # ElevenLabs provides logprob per word
      logprobs = []
      if result["words"].is_a?(Array)
        result["words"].each do |word|
          if word["logprob"]
            logprobs << { "logprob" => word["logprob"].to_f }
          end
        end
      end

      return {
        "text" => text,
        "logprobs" => logprobs,
        "language_code" => result["language_code"],
        "language_probability" => result["language_probability"]
      }
    else
      # Parse error from response
      error_message = begin
        error_data = JSON.parse(response.body)
        detail = error_data["detail"]
        if detail.is_a?(Hash)
          detail["message"] || detail.to_s
        elsif detail.is_a?(String)
          detail
        else
          "Unknown error"
        end
      rescue JSON::ParserError
        response.body.to_s
      end

      return {
        "type" => "error",
        "content" => "ElevenLabs STT Error (#{response.status}): #{error_message}"
      }
    end
  end

  # Format diarized transcript segments into readable text
  # @param segments [Array<Hash>] Array of segment hashes with 'speaker' and 'text' keys
  # @return [String] Formatted transcript with speaker labels
  def format_diarized_segments(segments)
    return "" unless segments && segments.is_a?(Array)

    segments.map do |seg|
      speaker = seg["speaker"] || "Unknown"
      text = seg["text"] || ""
      "#{speaker}: #{text}"
    end.join("\n")
  end

  def stt_api_request(blob, format, lang_code, model = nil)
    model ||= if defined?(Monadic::Utils::ModelSpec)
                 Monadic::Utils::ModelSpec.default_audio_model("openai")
               end
    # Route to Gemini API if model starts with "gemini-"
    if model.start_with?("gemini-")
      return gemini_stt_api_request(blob, format, lang_code, model)
    end

    # Route to ElevenLabs API if model starts with "scribe"
    if model.start_with?("scribe")
      return elevenlabs_stt_api_request(blob, format, lang_code, model)
    end

    lang_code = nil if lang_code == "auto"

    # Normalize format to one that OpenAI API supports
    # OpenAI API officially supports: "mp3", "mp4", "mpeg", "mpga", "m4a", "wav", or "webm"
    normalized_format = format.to_s.downcase
    normalized_format = "mp3" if normalized_format == "mpeg"
    normalized_format = "mp4" if normalized_format == "mp4a-latm"
    normalized_format = "wav" if %w[x-wav wave].include?(normalized_format)

    num_retrial = 0

    url = "#{API_ENDPOINT}/audio/transcriptions"
    file_name = TEMP_AUDIO_FILE
    response = nil

    begin
      temp_file = Tempfile.new([file_name, ".#{normalized_format}"])
      temp_file.write(blob)
      temp_file.flush

      options = {
        "file" => HTTP::FormData::File.new(temp_file.path),
        "model" => model,
      }

      case model
      when "whisper-1"
        options["response_format"] = "verbose_json"
      when "gpt-4o-transcribe-diarize"
        options["response_format"] = "diarized_json"
        options["chunking_strategy"] = "auto"
        # Note: gpt-4o-transcribe-diarize does not support:
        # - prompt parameter
        # - logprobs parameter
        # - timestamp_granularities[]
      else
        options["response_format"] = "json"
        options["include[]"] = ["logprobs"]
      end

      options["language"] = lang_code if lang_code
      form_data = HTTP::FormData.create(options)
      response = HTTP.headers(
        "Authorization" => "Bearer #{settings.api_key}",
        "Content-Type" => form_data.content_type
      ).timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(url, body: form_data.to_s)

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        # Debug output removed
        return { "type" => "error", "content" => "ERROR: #{e.message}" }
      end
    ensure
      temp_file.close
      temp_file.unlink
    end

    if response.status.success?
      # Audio file uploaded successfully
      result = JSON.parse(response.body)

      # Format diarized segments if using diarize model
      if model == "gpt-4o-transcribe-diarize" && result["segments"]
        result["text"] = format_diarized_segments(result["segments"])
      end

      result
    else
      # Parse error details from response body
      error_message = begin
        error_data = JSON.parse(response.body)
        formatted_error = format_api_error(error_data, "openai")
        "Speech-to-Text API Error: #{formatted_error}"
      rescue JSON::ParserError
        "Speech-to-Text API Error: #{response.status} - #{response.body}"
      end

      { "type" => "error", "content" => error_message }
    end
  end
end
