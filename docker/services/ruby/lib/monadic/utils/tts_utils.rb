# frozen_string_literal: true

require 'base64'
require 'net/http'
require_relative 'extra_logger'
require_relative 'tts_text_processors'

module InteractionUtils
  # Convert raw PCM audio data to WAV format (in memory, no file I/O)
  # WAV format adds a 44-byte header to the raw PCM data
  # @param pcm_data [String] Raw PCM audio data (binary string)
  # @param sample_rate [Integer] Sample rate in Hz (default: 24000 for Gemini TTS)
  # @param channels [Integer] Number of audio channels (default: 1 for mono)
  # @param bits_per_sample [Integer] Bits per sample (default: 16)
  # @return [String] WAV audio data (binary string)
  def pcm_to_wav(pcm_data, sample_rate: 24000, channels: 1, bits_per_sample: 16)
    data_size = pcm_data.bytesize
    byte_rate = sample_rate * channels * bits_per_sample / 8
    block_align = channels * bits_per_sample / 8

    # WAV file header (44 bytes)
    header = [
      "RIFF",                          # ChunkID
      data_size + 36,                  # ChunkSize (file size - 8)
      "WAVE",                          # Format
      "fmt ",                          # Subchunk1ID
      16,                              # Subchunk1Size (16 for PCM)
      1,                               # AudioFormat (1 = PCM)
      channels,                        # NumChannels
      sample_rate,                     # SampleRate
      byte_rate,                       # ByteRate
      block_align,                     # BlockAlign
      bits_per_sample,                 # BitsPerSample
      "data",                          # Subchunk2ID
      data_size                        # Subchunk2Size
    ].pack("A4VA4A4VvvVVvvA4V")

    header + pcm_data
  end

  def tts_api_request(text,
                      provider:,
                      voice:,
                      response_format:,
                      speed: nil,
                      previous_text: nil,
                      instructions: nil,
                      language: "auto")

    # Handle nil text
    return nil if text.nil? || text.empty?

    if CONFIG["TTS_DICT"]
      text_converted = text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
    else
      text_converted = text
    end

    text_converted = Monadic::Utils::TtsTextProcessors.pre_send(provider, text_converted)

    num_retrial = 0

    val_speed = speed ? speed.to_f : 1.0

    case provider
    when "openai-tts-4o", "openai-tts", "openai-tts-hd"
      api_key = settings.api_key
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      model = resolve_tts_model(provider)

      body = {
        "input" => text_converted,
        "model" => model,
        "voice" => voice,
        "response_format" => response_format
      }

      # Only include speed parameter if explicitly set by user
      # Omitting speed allows OpenAI to use optimal processing without speed conversion
      if speed && speed.to_f != 1.0
        body["speed"] = speed.to_f
      end

      # Include language parameter unless set to "auto"
      # When language is "auto", omit the parameter to let OpenAI auto-detect
      # When language is explicitly set (e.g., "ja", "en"), include it in the request
      unless language == "auto"
        body["language"] = language
      end

      if instructions
        body["instructions"] = instructions
      end

      target_uri = "#{API_ENDPOINT}/audio/speech"
    when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "elevenlabs-v3"
      api_key = CONFIG["ELEVENLABS_API_KEY"]
      headers = {
        "Content-Type" => "application/json",
        "xi-api-key" => api_key
      }

      model = resolve_tts_model(provider)

      body = {
        "text" => text_converted,
        "model_id" => model
      }

      if speed
        body["voice_settings"] = {
          "stability" => 0.5,
          "similarity_boost" => 0.75,
          "speed" => val_speed
        }
      end

      if previous_text.to_s != ""
        body["previous_text"] = previous_text
      end

      unless language == "auto"
        body["language_code"] = language
      end

      # ElevenLabs v3 must use the non-streaming endpoint (full file delivery).
      # All other ElevenLabs models use the /stream endpoint, which starts
      # returning audio earlier (lower TTFA) even when we read the body in one
      # pass. The endpoint choice is independent of our own streaming behavior.
      # optimize_streaming_latency=3 is the highest quality-preserving level
      # (level 4 disables text normalization and hurts pronunciation).
      output_format = "mp3_44100_128"
      target_uri = if provider == "elevenlabs-v3"
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}?output_format=#{output_format}"
                   else
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}/stream?output_format=#{output_format}&optimize_streaming_latency=3"
                   end
    when "mistral"
      api_key = CONFIG["MISTRAL_API_KEY"]
      if api_key.nil?
        return { "type" => "error", "content" => "ERROR: MISTRAL_API_KEY is not set." }
      end

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      model = resolve_tts_model(provider)

      # Mistral Voxtral supports pcm/wav/mp3/flac/opus (no aac). Fall back to mp3
      # when the caller asked for a format Mistral cannot produce.
      mistral_format = %w[mp3 pcm wav flac opus].include?(response_format) ? response_format : "mp3"
      body = {
        "input" => text_converted,
        "model" => model,
        "response_format" => mistral_format,
        "stream" => false
      }
      # Mistral requires voice_id — use selected voice or fetch first available
      if voice && !voice.empty?
        body["voice_id"] = voice
      else
        fallback = fetch_mistral_default_voice(api_key)
        body["voice_id"] = fallback if fallback
      end

      target_uri = "https://api.mistral.ai/v1/audio/speech"
    when "web-speech", "webspeech"
      # For Web Speech API, we don't need to make an API call
      # Return early with a special response
      return { "type" => "web_speech", "content" => text_converted }
    when "gemini", "gemini-flash", "gemini-pro"
      api_key = CONFIG["GEMINI_API_KEY"]
      if api_key.nil?
        return { "type" => "error", "content" => "ERROR: GEMINI_API_KEY is not set." }
      end

      # Minimal debug logging for performance
      puts "Gemini TTS: voice=#{voice}, provider=#{provider}" if ENV["DEBUG_TTS"]

      headers = {
        "Content-Type" => "application/json"
      }

      # Resolve target model first so speed-prefix logic can branch on it.
      # SSOT: providerDefaults.gemini.tts (primary = gemini-3.1-flash-tts-preview).
      model_name = resolve_tts_model(provider)

      # Apply speed control using natural language instructions for the 2.5
      # TTS models. The 3.1 dedicated TTS model (gemini-3.1-flash-tts-preview)
      # routes through a content classifier that treats pace prefixes as
      # anomalous prompts — it can respond with text tokens or a
      # PROHIBITED_CONTENT rejection. For 3.1 we omit the prefix and rely on
      # player-side playback rate instead. Skipping the prefix at speed 1.0
      # also reduces latency for the common path on older models.
      uses_pace_prefix = !model_name.to_s.start_with?("gemini-3")
      speed_instruction = if !uses_pace_prefix
        ""  # 3.x TTS models: never prepend pace instruction
      elsif val_speed >= 1.8
        "[extremely fast] "
      elsif val_speed >= 1.4
        "Speak quickly. "
      elsif val_speed >= 1.2
        "Speak slightly faster. "
      elsif val_speed <= 0.6
        "Speak very slowly. "
      elsif val_speed <= 0.8
        "Speak slowly. "
      elsif val_speed < 1.0
        "Speak slightly slower. "
      else
        ""  # Default speed - no instruction needed for faster response
      end

      prompt_text = speed_instruction + text_converted

      body = {
        "contents" => [{
          "parts" => [{
            "text" => prompt_text
          }]
        }],
        "generationConfig" => {
          "response_modalities" => ["AUDIO"],
          "speech_config" => {
            "voice_config" => {
              "prebuilt_voice_config" => {
                "voice_name" => voice.to_s.downcase
              }
            }
          }
        }
      }

      # Always use non-streaming endpoint for better performance.
      # Gemini TTS returns complete audio in one response anyway. The 3.1
      # model is REST-only (no Live API), so this path covers both.
      target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{api_key}"
    when "grok"
      # Grok dedicated TTS REST API. Uses a single model (grok-tts) with 5
      # voice IDs (eve, ara, rex, sal, leo). Returns MP3 bytes.
      # See https://docs.x.ai/ (Grok TTS) for the public reference.
      api_key = CONFIG["XAI_API_KEY"]
      if api_key.nil?
        return { "type" => "error", "content" => "ERROR: XAI_API_KEY is not set." }
      end

      puts "Grok TTS: voice=#{voice}, provider=#{provider}" if ENV["DEBUG_TTS"]

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      model = resolve_tts_model(provider)

      body = {
        "text" => text_converted,
        "voice_id" => voice.to_s.downcase,
        "language" => (language == "auto" ? "auto" : language),
        "output_format" => {
          "codec" => "mp3",
          "sample_rate" => 24000,
          "bit_rate" => 128000
        }
      }
      body["model"] = model if model && !model.empty?

      target_uri = "https://api.x.ai/v1/tts"
    else
      # Default error case
      return { "type" => "error", "content" => "ERROR: Unknown TTS provider: #{provider}" }
    end

    begin
      Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request: START - provider=#{provider}, text_length=#{text_converted.length}" }

      http = HTTP.headers(headers)

      Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request: Sending HTTP POST to #{target_uri}" }

      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request: HTTP response received - status=#{res.status}, body_size=#{res.body.to_s.length}" }

      unless res.status.success?
        error_report = JSON.parse(res.body) rescue { "message" => res.body.to_s }

        # Log detailed error for Gemini
        if provider == "gemini" || provider == "gemini-flash" || provider == "gemini-pro"
          puts "Gemini TTS API Error: #{res.status} - #{error_report}"
          puts "Request URI: #{target_uri}"
          puts "Request body: #{body.to_json}"
        end

        # For ElevenLabs, suppress "something_went_wrong" errors since audio often still works
        if provider&.start_with?("elevenlabs") &&
           (error_report.dig("detail", "status") == "something_went_wrong" ||
            error_report["detail"].to_s.include?("something_went_wrong"))
          # Log the error but don't send to client
          puts "ElevenLabs API warning (suppressed): #{error_report}"
          # Return a silent success to avoid error display
          return { "type" => "audio", "content" => "" }
        end

        return { "type" => "error", "content" => "ERROR: #{error_report}" }
      end

      # Handle Gemini response format - convert PCM to WAV for browser compatibility
      if provider == "gemini" || provider == "gemini-flash" || provider == "gemini-pro"
        begin
          gemini_response = JSON.parse(res.body.to_s)

          # Debug logging for Gemini TTS response
          Monadic::Utils::ExtraLogger.log { "[DEBUG] Gemini TTS response keys: #{gemini_response.keys.inspect}" }
          if gemini_response["error"]
            Monadic::Utils::ExtraLogger.log { "[DEBUG] Gemini TTS API error: #{gemini_response['error'].inspect}" }
          end

          # Check for API error response
          if gemini_response["error"]
            error_msg = gemini_response["error"]["message"] || gemini_response["error"].to_s
            return { "type" => "error", "content" => "Gemini TTS API Error: #{error_msg}" }
          end

          # Extract audio data from Gemini response
          if gemini_response["candidates"] &&
             gemini_response["candidates"][0] &&
             gemini_response["candidates"][0]["content"] &&
             gemini_response["candidates"][0]["content"]["parts"] &&
             gemini_response["candidates"][0]["content"]["parts"][0] &&
             gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]

            pcm_base64 = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
            original_mime_type = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]

            # Decode base64 PCM data
            pcm_data = Base64.decode64(pcm_base64)

            # Extract sample rate from mime_type (e.g., "audio/L16;codec=pcm;rate=24000")
            sample_rate = 24000  # Default
            if original_mime_type =~ /rate=(\d+)/
              sample_rate = $1.to_i
            end

            # Convert PCM to WAV (in memory, no file I/O)
            wav_data = pcm_to_wav(pcm_data, sample_rate: sample_rate)

            # Re-encode to base64
            wav_base64 = Base64.strict_encode64(wav_data)

            puts "Gemini TTS: PCM (#{pcm_data.length} bytes) -> WAV (#{wav_data.length} bytes)" if ENV["DEBUG_TTS"]

            return { "type" => "audio", "content" => wav_base64, "mime_type" => "audio/wav" }
          else
            # Log detailed error for debugging
            Monadic::Utils::ExtraLogger.log { "[DEBUG] Gemini TTS Error: Invalid response format (no inlineData)\n[DEBUG] Response structure: #{gemini_response.to_json[0..500]}" }
            return { "type" => "error", "content" => "ERROR: Invalid response format from Gemini TTS API. The API may be experiencing issues." }
          end
        rescue JSON::ParserError => e
          return { "type" => "error", "content" => "ERROR: Failed to parse Gemini response: #{e.message}" }
        end
      end

      # Handle Mistral TTS response format - JSON with base64 audio_data
      if provider == "mistral"
        begin
          mistral_response = JSON.parse(res.body.to_s)
          audio_base64 = mistral_response["audio_data"]
          if audio_base64
            return { "type" => "audio", "content" => audio_base64 }
          else
            return { "type" => "error", "content" => "ERROR: Invalid response from Mistral TTS API" }
          end
        rescue JSON::ParserError => e
          return { "type" => "error", "content" => "ERROR: Failed to parse Mistral TTS response: #{e.message}" }
        end
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request: Returning audio - body_size=#{res.body.to_s.length}" }
      { "type" => "audio", "content" => Base64.strict_encode64(res.body.to_s) }
    rescue => e
      Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request: Exception occurred - #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}" }
      { "type" => "error", "content" => "ERROR: TTS request failed: #{e.message}" }
    end
  end

  # Async TTS API request using http.rb gem with thread-based processing
  # @param text [String] Text to convert to speech
  # @param provider [String] TTS provider (OpenAI, ElevenLabs, Gemini)
  # @param voice [String] Voice ID
  # @param speed [Float] Speech speed
  # @param response_format [String] Audio format
  # @param language [String] Language code
  # @param previous_text [String] Previous text for context (optional)
  # @param sequence_id [Integer] Sequence ID for ordering (optional)
  # @param block [Proc] Callback to receive result hash
  def tts_api_request_async(text, provider:, voice:, speed:, response_format:, language:, previous_text: nil, sequence_id: nil, &block)
    return unless block_given?
    return if text.nil? || text.empty?

    # Apply TTS dictionary if configured
    text_converted = if CONFIG["TTS_DICT"]
                      text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
                    else
                      text
                    end

    text_converted = Monadic::Utils::TtsTextProcessors.pre_send(provider, text_converted)

    Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: START - provider=#{provider}, text_length=#{text_converted.length}, sequence_id=#{sequence_id}" }

    # Currently supports OpenAI TTS only
    case provider
    when "openai-tts-4o", "openai-tts", "openai-tts-hd", "openai"
      api_key = settings.api_key
      model = resolve_tts_model(provider)

      body = {
        "input" => text_converted,
        "model" => model,
        "voice" => voice,
        "response_format" => response_format
      }

      # Only include speed parameter if explicitly set
      if speed && speed.to_f != 1.0
        body["speed"] = speed.to_f
      end

      # Include language parameter unless set to "auto"
      # When language is "auto", omit the parameter to let OpenAI auto-detect
      # When language is explicitly set (e.g., "ja", "en"), include it in the request
      unless language == "auto"
        body["language"] = language
      end

      target_uri = "#{API_ENDPOINT}/audio/speech"

      require 'http'

      Thread.new do
        begin
          response = HTTP
            .timeout(connect: 5, read: 15)
            .headers(
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{api_key}"
            )
            .post(target_uri, json: body)

          if response.status.success?
            # Success - encode audio and call block
            audio_content = Base64.strict_encode64(response.body.to_s)
            result = {
              "type" => "audio",
              "content" => audio_content
            }
            result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: SUCCESS (http.rb) - audio_size=#{response.body.to_s.length}, sequence_id=#{sequence_id}" }

            # Call result block in Async context
            Async do
              block.call(result)
            end
          else
            # HTTP error
            error_result = {
              "type" => "error",
              "content" => "ERROR: OpenAI TTS API error: #{response.status}"
            }
            error_result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: HTTP error (http.rb) - status=#{response.status}, sequence_id=#{sequence_id}" }

            Async do
            block.call(error_result)
          end
          end
        rescue => e
          # Connection or other error
          error_result = {
            "type" => "error",
            "content" => "ERROR: TTS connection failed: #{e.message}"
          }
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "elevenlabs-v3"
      api_key = CONFIG["ELEVENLABS_API_KEY"]
      if api_key.nil?
        error_result = {
          "type" => "error",
          "content" => "ERROR: ELEVENLABS_API_KEY is not set."
        }
        error_result["sequence_id"] = sequence_id if sequence_id
        Async do
            block.call(error_result)
          end
        return
      end

      model = resolve_tts_model(provider)

      body = {
        "text" => text_converted,
        "model_id" => model
      }

      val_speed = speed ? speed.to_f : 1.0
      if speed
        body["voice_settings"] = {
          "stability" => 0.5,
          "similarity_boost" => 0.75,
          "speed" => val_speed
        }
      end

      if previous_text.to_s != ""
        body["previous_text"] = previous_text
      end

      unless language == "auto"
        body["language_code"] = language
      end

      # Match the sync-path endpoint selection: v3 uses non-streaming endpoint,
      # others use /stream with optimize_streaming_latency=3 for lowest TTFA.
      output_format = "mp3_44100_128"
      target_uri = if provider == "elevenlabs-v3"
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}?output_format=#{output_format}"
                   else
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}/stream?output_format=#{output_format}&optimize_streaming_latency=3"
                   end

      require 'http'

      Thread.new do
        begin
          response = HTTP
            .timeout(connect: 5, read: 15)
            .headers(
              "Content-Type" => "application/json",
              "xi-api-key" => api_key
            )
            .post(target_uri, json: body)

          if response.status.success?
            # Success - encode audio and call block
            audio_content = Base64.strict_encode64(response.body.to_s)
            result = {
              "type" => "audio",
              "content" => audio_content
            }
            result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: SUCCESS (ElevenLabs/http.rb) - audio_size=#{response.body.to_s.length}, sequence_id=#{sequence_id}" }

            # Call result block in Async context
            Async do
              block.call(result)
            end
          else
            # HTTP error
            error_result = {
              "type" => "error",
              "content" => "ERROR: ElevenLabs TTS API error: #{response.status}"
            }
            error_result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: ElevenLabs HTTP error (http.rb) - status=#{response.status}, sequence_id=#{sequence_id}" }

            Async do
            block.call(error_result)
          end
          end
        rescue => e
          # Connection or other error
          error_result = {
            "type" => "error",
            "content" => "ERROR: ElevenLabs TTS connection failed: #{e.message}"
          }
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: ElevenLabs connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "gemini", "gemini-flash", "gemini-pro"
      api_key = CONFIG["GEMINI_API_KEY"]
      if api_key.nil?
        error_result = {
          "type" => "error",
          "content" => "ERROR: GEMINI_API_KEY is not set."
        }
        error_result["sequence_id"] = sequence_id if sequence_id
        Async do
            block.call(error_result)
          end
        return
      end

      # Note: Voice-specific style instructions removed to let each voice's natural characteristics come through
      prompt_text = text_converted

      body = {
        "contents" => [{
          "parts" => [{
            "text" => prompt_text
          }]
        }],
        "generationConfig" => {
          "response_modalities" => ["AUDIO"],
          "speech_config" => {
            "voice_config" => {
              "prebuilt_voice_config" => {
                "voice_name" => voice.to_s.downcase
              }
            }
          }
        }
      }

      # Use the appropriate Gemini model with TTS capability (SSOT: providerDefaults.gemini.tts)
      model_name = resolve_tts_model(provider)

      target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{api_key}"

      require 'http'

      Thread.new do
        begin
          response = HTTP
            .timeout(connect: 5, read: 15)
            .headers("Content-Type" => "application/json")
            .post(target_uri, json: body)

          if response.status.success?
            begin
              gemini_response = JSON.parse(response.body.to_s)

              # Debug logging for Gemini TTS response
              Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: Gemini response keys: #{gemini_response.keys.inspect}" }
              if gemini_response["error"]
                Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: Gemini TTS API error: #{gemini_response['error'].inspect}" }
              end

              # Check for API error response
              if gemini_response["error"]
                error_msg = gemini_response["error"]["message"] || gemini_response["error"].to_s
                error_result = {
                  "type" => "error",
                  "content" => "Gemini TTS API Error: #{error_msg}"
                }
                error_result["sequence_id"] = sequence_id if sequence_id
                Async do
                  block.call(error_result)
                end
                next
              end

              # Extract audio data from Gemini response and convert PCM to WAV
              if gemini_response["candidates"] &&
                 gemini_response["candidates"][0] &&
                 gemini_response["candidates"][0]["content"] &&
                 gemini_response["candidates"][0]["content"]["parts"] &&
                 gemini_response["candidates"][0]["content"]["parts"][0] &&
                 gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]

                pcm_base64 = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
                original_mime_type = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]

                # Decode base64 PCM data
                pcm_data = Base64.decode64(pcm_base64)

                # Extract sample rate from mime_type (e.g., "audio/L16;codec=pcm;rate=24000")
                sample_rate = 24000  # Default
                if original_mime_type =~ /rate=(\d+)/
                  sample_rate = $1.to_i
                end

                # Convert PCM to WAV (in memory, no file I/O)
                wav_data = pcm_to_wav(pcm_data, sample_rate: sample_rate)

                # Re-encode to base64
                wav_base64 = Base64.strict_encode64(wav_data)

                result = {
                  "type" => "audio",
                  "content" => wav_base64,
                  "mime_type" => "audio/wav"
                }
                result["sequence_id"] = sequence_id if sequence_id

                Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: SUCCESS (Gemini/http.rb) - pcm_size=#{pcm_data.length}, wav_size=#{wav_data.length}, sequence_id=#{sequence_id}" }

                # Return to Async reactor context
                Async do
            block.call(result)
          end
              else
                error_result = {
                  "type" => "error",
                  "content" => "ERROR: Invalid response format from Gemini TTS API. The API may be experiencing issues."
                }
                error_result["sequence_id"] = sequence_id if sequence_id

                Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Invalid Gemini response format (no inlineData), sequence_id=#{sequence_id}\n[DEBUG] Response structure: #{gemini_response.to_json[0..500]}" }

                Async do
            block.call(error_result)
          end
              end
            rescue JSON::ParserError => e
              error_result = {
                "type" => "error",
                "content" => "ERROR: Failed to parse Gemini response: #{e.message}"
              }
              error_result["sequence_id"] = sequence_id if sequence_id

              Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Gemini JSON parse error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

              Async do
            block.call(error_result)
          end
            end
          else
            # HTTP error
            error_result = {
              "type" => "error",
              "content" => "ERROR: Gemini TTS API error: #{response.status}"
            }
            error_result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Gemini HTTP error (http.rb) - status=#{response.status}, sequence_id=#{sequence_id}" }

            Async do
            block.call(error_result)
          end
          end
        rescue => e
          # Connection or other error
          error_result = {
            "type" => "error",
            "content" => "ERROR: Gemini TTS connection failed: #{e.message}"
          }
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Gemini connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "grok"
      # Grok dedicated TTS REST API (non-streaming). Mirrors the synchronous
      # path in tts_api_request; provided here so the streaming/async helper
      # can be used uniformly by callers.
      api_key = CONFIG["XAI_API_KEY"]
      if api_key.nil?
        error_result = {
          "type" => "error",
          "content" => "ERROR: XAI_API_KEY is not set."
        }
        error_result["sequence_id"] = sequence_id if sequence_id
        Async do
          block.call(error_result)
        end
        return
      end

      model_name = resolve_tts_model(provider)
      body = {
        "text" => text_converted,
        "voice_id" => voice.to_s.downcase,
        "language" => (language == "auto" ? "auto" : language),
        "output_format" => {
          "codec" => "mp3",
          "sample_rate" => 24000,
          "bit_rate" => 128000
        }
      }
      body["model"] = model_name if model_name && !model_name.empty?

      target_uri = "https://api.x.ai/v1/tts"
      require 'http'

      Thread.new do
        begin
          response = HTTP
            .timeout(connect: 5, read: 30)
            .headers(
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{api_key}"
            )
            .post(target_uri, json: body)

          if response.status.success?
            audio_bytes = response.body.to_s
            if audio_bytes.empty?
              error_result = { "type" => "error", "content" => "ERROR: Empty audio response from Grok TTS" }
              error_result["sequence_id"] = sequence_id if sequence_id
              Async { block.call(error_result) }
              next
            end

            encoded = Base64.strict_encode64(audio_bytes)
            result = {
              "type" => "audio",
              "content" => encoded,
              "mime_type" => "audio/mpeg"
            }
            result["sequence_id"] = sequence_id if sequence_id

            Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: SUCCESS (Grok) - audio_size=#{audio_bytes.length}, sequence_id=#{sequence_id}" }

            Async { block.call(result) }
          else
            error_result = {
              "type" => "error",
              "content" => "ERROR: Grok TTS API error: #{response.status} - #{response.body.to_s[0..500]}"
            }
            error_result["sequence_id"] = sequence_id if sequence_id
            Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Grok HTTP error - status=#{response.status}, sequence_id=#{sequence_id}" }
            Async { block.call(error_result) }
          end
        rescue => e
          error_result = {
            "type" => "error",
            "content" => "ERROR: Grok TTS connection failed: #{e.message}"
          }
          error_result["sequence_id"] = sequence_id if sequence_id
          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Grok connection error - #{e.message}, sequence_id=#{sequence_id}" }
          Async { block.call(error_result) }
        end
      end

    when "web-speech", "webspeech"
      # Web Speech API doesn't need HTTP request
      result = {
        "type" => "web_speech",
        "content" => text_converted
      }
      result["sequence_id"] = sequence_id if sequence_id

      # Call block asynchronously using Async
      Async do
            block.call(result)
          end

    else
      # Unsupported provider
      error_result = {
        "type" => "error",
        "content" => "ERROR: Provider '#{provider}' not supported in realtime mode. Use post-completion mode instead."
      }
      error_result["sequence_id"] = sequence_id if sequence_id

      Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Unsupported provider - #{provider}" }

      Async do
            block.call(error_result)
          end
    end
  end

  def list_elevenlabs_voices(elevenlabs_api_key)
    return [] unless elevenlabs_api_key

    return @elevenlabs_voices if @elevenlabs_voices

    begin
      url = URI("https://api.elevenlabs.io/v1/voices")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request["xi-api-key"] = elevenlabs_api_key
      response = http.request(request)
      voices = response.read_body
      @elevenlabs_voices = JSON.parse(voices)&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end
    rescue StandardError => e
      # Log ElevenLabs API error and return empty array
      Monadic::Utils::ExtraLogger.log { "ElevenLabs voice list error: #{e.message}" }
      []
    end
  end

  private

  # Resolve TTS provider label to actual model name via providerDefaults.
  # OpenAI TTS list is ordered: [0]=4o-mini, [1]=tts-1-hd, [2]=tts-1
  # Gemini TTS list is ordered: [0]=flash, [1]=pro
  # ElevenLabs TTS list is ordered: [0]=eleven_v3, [1]=eleven_multilingual_v2, [2]=eleven_flash_v2_5
  def resolve_tts_model(provider_label)
    if provider_label =~ /\Agemini/
      tts_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("gemini", "tts")
                   end
      case provider_label
      when "gemini-pro"
        tts_models&.[](1)
      else # "gemini-flash", "gemini"
        tts_models&.[](0)
      end
    elsif provider_label =~ /\Amistral/
      tts_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("mistral", "tts")
                   end
      tts_models&.[](0)
    elsif provider_label =~ /\Agrok/
      # Grok TTS uses a single dedicated model (grok-tts).
      # SSOT: providerDefaults.xai.tts in model_spec.js.
      tts_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("xai", "tts")
                   end
      tts_models&.[](0)
    elsif provider_label =~ /\Aelevenlabs/
      tts_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("elevenlabs", "tts")
                   end
      case provider_label
      when "elevenlabs-v3"
        tts_models&.[](0)
      when "elevenlabs-multilingual"
        tts_models&.[](1)
      else # "elevenlabs-flash", "elevenlabs"
        tts_models&.[](2)
      end
    else
      tts_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("openai", "tts")
                   end
      case provider_label
      when "openai-tts-4o"
        tts_models&.[](0)
      when "openai-tts-hd"
        tts_models&.[](1)
      when "openai-tts"
        tts_models&.[](2)
      else
        tts_models&.[](0)
      end
    end
  end

  # Fetch first available Mistral voice ID (cached per process).
  def fetch_mistral_default_voice(api_key)
    @mistral_default_voice ||= begin
      require 'net/http'
      url = URI("https://api.mistral.ai/v1/audio/voices?limit=1")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5
      request = Net::HTTP::Get.new(url)
      request["Authorization"] = "Bearer #{api_key}"
      response = http.request(request)
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.read_body)
        data.dig("items", 0, "id")
      end
    rescue StandardError
      nil
    end
  end
end
