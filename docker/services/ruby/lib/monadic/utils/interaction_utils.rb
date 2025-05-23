module InteractionUtils
  API_ENDPOINT = "https://api.openai.com/v1"
  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 10 # Timeout for opening a connection (seconds)
  READ_TIMEOUT = 60 # Timeout for reading data (seconds)
  WRITE_TIMEOUT = 60 # Timeout for writing data (seconds)

  # Number of retries for API requests
  MAX_RETRIES = 10
  # Delay between retries (seconds)
  RETRY_DELAY = 2

  # Cache class for API key validation
  class ApiKeyCache
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize { @cache[key] }
    end

    def set(key, value)
      @mutex.synchronize { @cache[key] = value }
    end

    def clear
      @mutex.synchronize { @cache.clear }
    end
  end

  # Initialize cache as a singleton
  def self.api_key_cache
    @api_key_cache ||= ApiKeyCache.new
  end

  # Check if the API key is valid with caching mechanism
  # @param api_key [String] The API key to check
  # @return [Hash] A hash containing the result of the check
  def check_api_key(api_key)
    if api_key
      api_key = api_key.strip
      settings.api_key = api_key
    else
      return { "type" => "error", "content" => "ERROR: API key is empty" }
    end

    # Return cached result if available
    cached_result = InteractionUtils.api_key_cache.get(api_key)
    return cached_result if cached_result

    target_uri = "#{API_ENDPOINT}/models"

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{settings.api_key}"
    }

    num_retrial = 0

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).get(target_uri)
      res_body = JSON.parse(res.body)

      result = if res_body && res_body["data"]
                 { "type" => "models", "content" => "API token verified"}
               else
                 { "type" => "error", "content" => "ERROR: API token is not accepted" }
               end

      # Cache the result
      InteractionUtils.api_key_cache.set(api_key, result)
      result

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        error_message = "API request failed after #{MAX_RETRIES} retries: #{e.message}"
        # Debug output removed
        error_result = { "type" => "error", "content" => "ERROR: #{error_message}" }
        # Cache the error result as well
        InteractionUtils.api_key_cache.set(api_key, error_result)
        return error_result
      end
    end
  end

  def tts_api_request(text,
                      provider:,
                      voice:,
                      response_format:,
                      speed: nil,
                      previous_text: nil,
                      instructions: nil,
                      language: "auto",
                      &block)

    if CONFIG["TTS_DICT"]
      text_converted = text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
    else
      text_converted = text
    end

    num_retrial = 0

    val_speed = speed ? speed.to_f : 1.0

    case provider
    when "openai-tts-4o", "openai-tts", "openai-tts-hd"
      api_key = settings.api_key
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      model = case provider
              when "openai-tts-4o"
                "gpt-4o-mini-tts"
              when "openai-tts-hd"
                "tts-1-hd"
              when "openai-tts"
                "tts-1"
              else
                "gpt-4o-mini-tts"
              end

      body = {
        "input" => text_converted,
        "model" => model,
        "voice" => voice,
        "speed" => val_speed,
        "response_format" => response_format
      }

      unless language == "auto"
        body["language"] = language
      end

      if instructions
        body["instructions"] = instructions
      end

      target_uri = "#{API_ENDPOINT}/audio/speech"
    when "elevenlabs"
      api_key = ENV["ELEVENLABS_API_KEY"]
      headers = {
        "Content-Type" => "application/json",
        "xi-api-key" => api_key
      }

      body = {
        "text" => text_converted,
        "model_id" => "eleven_flash_v2_5"
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

      output_format = "mp3_44100_128"
      target_uri = "https://api.elevenlabs.io/v1/text-to-speech/#{voice}/stream?output_format=#{output_format}"
    when "web-speech", "webspeech"
      # For Web Speech API, we don't need to make an API call
      # Return early with a special response
      if block_given?
        block.call({ "type" => "web_speech", "content" => text_converted })
        return nil
      else
        return { "type" => "web_speech", "content" => text_converted }
      end
    end

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      unless res.status.success?
        error_report = JSON.parse(res.body) rescue { "message" => res.body.to_s }
        
        # For ElevenLabs, suppress "something_went_wrong" errors since audio often still works
        if provider == "elevenlabs" && 
           (error_report.dig("detail", "status") == "something_went_wrong" ||
            error_report["detail"].to_s.include?("something_went_wrong"))
          # Log the error but don't send to client
          puts "ElevenLabs API warning (suppressed): #{error_report}"
          # Don't call the block with error and don't return error
          # This prevents the error from being sent to the client
          return nil if block_given?
          # For non-streaming calls, return a silent success to avoid error display
          return { "type" => "audio", "content" => "" }
        end
        
        res = { "type" => "error", "content" => "ERROR: #{error_report}" }
        block&.call res
        return res
      end

      t_index = 0

      if block_given?
        res.body.each do |chunk|
          t_index += 1
          content = Base64.strict_encode64(chunk)
          hash_res = { "type" => "audio", "content" => content, "t_index" => t_index, "finished" => false }
          block&.call hash_res
        end
        t_index += 1
        finish = { "type" => "audio", "content" => "", "t_index" => t_index, "finished" => true }
        block&.call finish
        return nil
      else
        { "type" => "audio", "content" => Base64.strict_encode64(res) }
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
      []
    end
  end

  def stt_api_request(blob, format, lang_code, model = "gpt-4o-transcribe")
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
      JSON.parse(response.body)
    else
      # Debug output removed
      { "type" => "error", "content" => "Speech-to-Text API Error" }
    end
  end

  def tavily_fetch(url:)
    api_key = CONFIG["TAVILY_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "urls" => url,
      "include_images": false,
      "extract_depth": "basic"
    }

    target_uri = "https://api.tavily.com/extract"

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      if res.status.success?
        res = JSON.parse(res.body)
      else
        # Parse the response body only once
        error_report = JSON.parse(res.body)
        res = "ERROR: #{error_report}"
      end

      res.dig("results", 0, "raw_content") || "No content found"
    rescue HTTP::Error, HTTP::TimeoutError => e
      "Error occurred: #{e.message}"
    end
  end
end
