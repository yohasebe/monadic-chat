# frozen_string_literal: true

require_relative 'tts_provider'

require 'base64'
require 'net/http'
require_relative 'extra_logger'
require_relative 'tts_text_processors'
require_relative 'tts_audio'
require_relative 'privacy/outbound'

module InteractionUtils
  # What a speech request gives back when the text holds a word the user
  # marked for the Privacy Filter: nothing was sent, and the page shows a
  # notice for the speech only (the reply itself is fine).
  TTS_WITHHELD = { "type" => "privacy_withheld" }.freeze

  def pcm_to_wav(pcm_data, **options)
    Monadic::Utils::TtsAudio.pcm_to_wav(pcm_data, **options)
  end

  # The text as a TTS service receives it: the user's dictionary applied,
  # then the provider's own conversion (markers, tags). What is checked for
  # words the user marked is this text, not the one before.
  def tts_text_as_sent(text, provider)
    converted = if CONFIG["TTS_DICT"]
                  text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
                else
                  text
                end
    Monadic::Utils::TtsTextProcessors.pre_send(provider, converted)
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

    text_converted = tts_text_as_sent(text, provider)

    num_retrial = 0

    val_speed = speed ? speed.to_f : 1.0

    case Monadic::Utils::TtsProvider.provider_of(provider)
    when "openai"
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

      # NOTE: `language` is intentionally NOT forwarded to OpenAI's
      # /v1/audio/speech endpoint. The current API reference (May 2026)
      # does not list a `language` parameter on this endpoint — only
      # `model`, `input`, `voice`, `instructions`, `response_format`, and
      # `speed`. Sending an undocumented field is at best ignored and at
      # worst could affect how the model interprets the structured
      # `instructions` block (e.g., reading it back as part of the
      # transcript). Multilingual handling is already covered implicitly
      # by `input` text plus `instructions` style notes.

      if instructions
        body["instructions"] = instructions
      end

      target_uri = "#{API_ENDPOINT}/audio/speech"
    when "elevenlabs"
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

      # Eleven v3 refuses previous_text (400, checked 2026-10-18).
      if previous_text.to_s != "" && Monadic::Utils::ModelSpec.get_model_property(model, "tts_previous_text") != false
        body["previous_text"] = previous_text
      end

      unless language == "auto"
        body["language_code"] = language
      end

      # The endpoint and the latency option come from the model's entry
      # (see elevenlabs_tts_uri).
      output_format = "mp3_44100_128"
      target_uri = elevenlabs_tts_uri(model, voice, output_format)
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
    when "webspeech"
      # For Web Speech API, we don't need to make an API call
      # Return early with a special response
      return { "type" => "web_speech", "content" => text_converted }
    when "gemini"
      api_key = CONFIG["GEMINI_API_KEY"]
      if api_key.nil?
        return { "type" => "error", "content" => "ERROR: GEMINI_API_KEY is not set." }
      end

      # Minimal debug logging for performance
      puts "Gemini TTS: voice=#{voice}, provider=#{provider}" if ENV["DEBUG_TTS"]

      headers = {
        "Content-Type" => "application/json",
        "x-goog-api-key" => api_key
      }

      # Resolve target model first so speed-prefix logic can branch on it.
      # The model comes from ttsChoices (model_spec.js).
      model_name = resolve_tts_model(provider)

      # Speed is a natural-language instruction at the start of the text for
      # the models whose SSOT entry sets tts_pace_prefix. Other models can
      # answer such a prefix with text tokens or a PROHIBITED_CONTENT
      # rejection, so they get none and the player's playback rate sets the
      # speed. Speed 1.0 adds no prefix.
      uses_pace_prefix = Monadic::Utils::ModelSpec.tts_pace_prefix?(model_name)
      speed_instruction = if !uses_pace_prefix
        ""
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

      # Style directives are in-band. SSOT selects bracket cues for models
      # that read the legacy prose prefix aloud; older models keep it.
      # "omit" is for models that speak even a bracketed cue as part of the
      # script, and not on every call, so no in-band form is safe for them.
      style_directive = Monadic::Utils::ModelSpec.tts_style_directive(model_name)
      style_prefix = if style_directive == "omit"
        ""
      elsif instructions && !instructions.to_s.empty?
        if style_directive == "bracket_cue"
          cue = instructions.to_s.tr("[]", "  ").gsub(/\s+/, " ").strip
          cue.empty? ? "" : "[#{cue}] "
        else
          "Say with this voice and style:\n#{instructions.to_s.strip}\n\n"
        end
      else
        ""
      end
      prompt_text = style_prefix + speed_instruction + text_converted

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
      target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent"
    when "xai"
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

        # The request body holds the user's text: only the status and the error go to the log.
        Monadic::Utils::ExtraLogger.log { "[TTS] #{provider} API error: #{res.status} - #{error_report}" }

        # For ElevenLabs, suppress "something_went_wrong" errors since audio often still works
        if provider&.start_with?("elevenlabs") &&
           (error_report.dig("detail", "status") == "something_went_wrong" ||
            error_report["detail"].to_s.include?("something_went_wrong"))
          # Log the error but don't send to client
          Monadic::Utils::ExtraLogger.log { "[TTS] ElevenLabs API warning (suppressed): #{error_report}" }
          # Return a silent success to avoid error display
          return { "type" => "audio", "content" => "" }
        end

        return { "type" => "error", "content" => "ERROR: #{error_report}" }
      end

      # Handle Gemini response format - normalize audio to WAV for browser compatibility
      if Monadic::Utils::TtsProvider.gemini?(provider)
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

            audio_data = Base64.decode64(pcm_base64)
            wav_data = Monadic::Utils::TtsAudio.to_wav(audio_data, mime_type: original_mime_type)

            # Re-encode to base64
            wav_base64 = Base64.strict_encode64(wav_data)

            puts "Gemini TTS: Audio (#{audio_data.length} bytes) -> WAV (#{wav_data.length} bytes)" if ENV["DEBUG_TTS"]

            return { "type" => "audio", "content" => wav_base64, "mime_type" => "audio/wav" }
          else
            # Log detailed error for debugging
            Monadic::Utils::ExtraLogger.log { "[DEBUG] Gemini TTS Error: Invalid response format (no inlineData)\n[DEBUG] Response structure: #{gemini_response.to_json[0..500]}" }
            return { "type" => "error", "content" => "ERROR: Invalid response format from Gemini TTS API. The API may be experiencing issues." }
          end
        rescue JSON::ParserError, Monadic::Utils::TtsAudio::InvalidWav => e
          return { "type" => "error", "content" => "ERROR: Failed to parse Gemini response: #{e.message}" }
        end
      end

      # Handle Mistral TTS response format - JSON with base64 audio_data
      if Monadic::Utils::TtsProvider.provider_of(provider) == "mistral"
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
    rescue Monadic::Utils::Privacy::Outbound::Refused
      TTS_WITHHELD.dup
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
    text_converted = tts_text_as_sent(text, provider)

    Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: START - provider=#{provider}, text_length=#{text_converted.length}, sequence_id=#{sequence_id}" }

    # Currently supports OpenAI TTS only
    case Monadic::Utils::TtsProvider.provider_of(provider)
    when "openai"
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
          error_result = TTS_WITHHELD.dup if e.is_a?(Monadic::Utils::Privacy::Outbound::Refused)
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "elevenlabs"
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

      # Eleven v3 refuses previous_text (400, checked 2026-10-18).
      if previous_text.to_s != "" && Monadic::Utils::ModelSpec.get_model_property(model, "tts_previous_text") != false
        body["previous_text"] = previous_text
      end

      unless language == "auto"
        body["language_code"] = language
      end

      # Same endpoint selection as the sync path (elevenlabs_tts_uri).
      output_format = "mp3_44100_128"
      target_uri = elevenlabs_tts_uri(model, voice, output_format)

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
          error_result = TTS_WITHHELD.dup if e.is_a?(Monadic::Utils::Privacy::Outbound::Refused)
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: ElevenLabs connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "gemini"
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

      # The model comes from ttsChoices (model_spec.js)
      model_name = resolve_tts_model(provider)

      target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent"

      require 'http'

      Thread.new do
        begin
          response = HTTP
            .timeout(connect: 5, read: 15)
            .headers("Content-Type" => "application/json", "x-goog-api-key" => api_key)
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

              # Extract audio data from Gemini response and normalize audio to WAV
              if gemini_response["candidates"] &&
                 gemini_response["candidates"][0] &&
                 gemini_response["candidates"][0]["content"] &&
                 gemini_response["candidates"][0]["content"]["parts"] &&
                 gemini_response["candidates"][0]["content"]["parts"][0] &&
                 gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]

                pcm_base64 = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
                original_mime_type = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]

                audio_data = Base64.decode64(pcm_base64)
                wav_data = Monadic::Utils::TtsAudio.to_wav(audio_data, mime_type: original_mime_type)

                # Re-encode to base64
                wav_base64 = Base64.strict_encode64(wav_data)

                result = {
                  "type" => "audio",
                  "content" => wav_base64,
                  "mime_type" => "audio/wav"
                }
                result["sequence_id"] = sequence_id if sequence_id

                Monadic::Utils::ExtraLogger.log { "[DEBUG] tts_api_request_async: SUCCESS (Gemini/http.rb) - audio_size=#{audio_data.length}, wav_size=#{wav_data.length}, sequence_id=#{sequence_id}" }

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
            rescue JSON::ParserError, Monadic::Utils::TtsAudio::InvalidWav => e
              error_result = {
                "type" => "error",
                "content" => "ERROR: Failed to parse Gemini response: #{e.message}"
              }
              error_result["sequence_id"] = sequence_id if sequence_id

              Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Gemini response parse error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

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
          error_result = TTS_WITHHELD.dup if e.is_a?(Monadic::Utils::Privacy::Outbound::Refused)
          error_result["sequence_id"] = sequence_id if sequence_id

          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Gemini connection error (http.rb) - #{e.message}, sequence_id=#{sequence_id}" }

          Async do
            block.call(error_result)
          end
        end
      end

    when "xai"
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
          error_result = TTS_WITHHELD.dup if e.is_a?(Monadic::Utils::Privacy::Outbound::Refused)
          error_result["sequence_id"] = sequence_id if sequence_id
          Monadic::Utils::ExtraLogger.log { "[ERROR] tts_api_request_async: Grok connection error - #{e.message}, sequence_id=#{sequence_id}" }
          Async { block.call(error_result) }
        end
      end

    when "webspeech"
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

  # The model a TTS provider selector value sends, from ttsChoices in
  # model_spec.js (Monadic::Utils::TtsProvider). nil for an unknown value.
  def resolve_tts_model(provider_label)
    Monadic::Utils::TtsProvider.model_for(provider_label)
  end

  # ElevenLabs: the convert endpoint returns the whole file; /stream starts
  # sending audio earlier. Which one, and whether the latency option is sent
  # (optimize_streaming_latency=3 is the highest quality-preserving level),
  # come from the model's entry.
  def elevenlabs_tts_uri(model, voice, output_format)
    base = "https://api.elevenlabs.io/v1/text-to-speech/#{voice}"
    return "#{base}?output_format=#{output_format}" if Monadic::Utils::ModelSpec.get_model_property(model, "tts_endpoint") == "convert"

    query = "output_format=#{output_format}"
    query += "&optimize_streaming_latency=3" unless Monadic::Utils::ModelSpec.get_model_property(model, "tts_latency_option") == false
    "#{base}/stream?#{query}"
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
