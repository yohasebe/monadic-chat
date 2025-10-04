require 'json'
require_relative 'ssl_configuration'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

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

  # Format API error JSON for better readability
  # @param error_data [Hash] The error data (can be nested)
  # @param provider [String] The provider name (optional, for context)
  # @return [String] Formatted error message
  def format_api_error(error_data, provider = nil)
    return error_data.to_s unless error_data.is_a?(Hash)

    error_parts = []
    
    # Add provider context if available
    error_parts << "[#{provider.upcase}]" if provider

    # Extract main error message
    main_message = extract_error_message(error_data)
    if main_message && main_message != error_data.to_s
      error_parts << main_message
      
      # Add additional context for specific error types
      context = extract_error_context(error_data)
      error_parts << context if context && !context.empty?
    else
      # If we couldn't extract a meaningful message, include the full error data
      # but format it more readably
      formatted_full_error = format_full_error_data(error_data)
      error_parts << formatted_full_error
    end

    # In debug mode, also include the original error data
    if ENV['APP_DEBUG'] && main_message && main_message != error_data.to_s
      error_parts << "(Raw: #{error_data.to_s.slice(0, 200)}#{error_data.to_s.length > 200 ? '...' : ''})"
    end

    error_parts.join(" ")
  end

  private

  def extract_error_message(error_data)
    # Handle string input
    return error_data if error_data.is_a?(String)
    
    # Try various common error message paths
    return error_data["message"] if error_data["message"]
    return error_data.dig("error", "message") if error_data.is_a?(Hash) && error_data["error"].is_a?(Hash)
    return error_data["detail"] if error_data["detail"]
    return error_data["error"] if error_data["error"].is_a?(String)
    
    # For nested structures, try to find the most relevant message
    if error_data["error"].is_a?(Hash)
      nested_error = error_data["error"]
      return nested_error["message"] || nested_error["detail"] || nested_error["description"]
    end

    # Fallback to the entire error object
    error_data.to_s
  end

  def extract_error_context(error_data)
    # Handle string input
    return "" if error_data.is_a?(String)
    
    context_parts = []

    # Handle quota errors specifically
    if (error_data.is_a?(Hash) && error_data["error"].is_a?(Hash) && error_data.dig("error", "code") == 429) || error_data["code"] == 429
      context_parts << "Rate limit exceeded"
      
      # Extract quota information
      if error_data.dig("error", "details")
        details = error_data["error"]["details"]
        quota_failures = details.find { |detail| detail["@type"]&.include?("QuotaFailure") }
        if quota_failures && quota_failures["violations"]
          violations = quota_failures["violations"]
          violation_types = violations.map { |v| v["quotaMetric"]&.split("/")&.last }.compact.uniq
          context_parts << "Quotas: #{violation_types.join(", ")}" unless violation_types.empty?
        end
      end
    end

    # Handle other specific error codes
    error_code = if error_data.is_a?(Hash)
      (error_data["error"].is_a?(Hash) ? error_data.dig("error", "code") : nil) || error_data["code"]
    end
    
    case error_code
    when 401
      context_parts << "Authentication failed"
    when 403
      context_parts << "Access forbidden"
    when 404
      context_parts << "Resource not found"
    when 500, 502, 503
      context_parts << "Server error"
    end

    # Extract status information
    if error_data.is_a?(Hash) && error_data["error"].is_a?(Hash) && error_data.dig("error", "status") && error_data["error"]["status"] != "RESOURCE_EXHAUSTED"
      context_parts << "Status: #{error_data["error"]["status"]}"
    end

    context_parts.join(", ")
  end

  def format_full_error_data(error_data)
    # Try to format the full error data in a more readable way
    # while preserving all information
    case error_data
    when Hash
      # If it's a hash, try to extract key information
      key_info = []
      
      # Look for common error fields and present them clearly
      if error_data["error"]
        if error_data["error"].is_a?(Hash)
          key_info << "Error: #{format_nested_hash(error_data["error"])}"
        else
          key_info << "Error: #{error_data["error"]}"
        end
      end
      
      if error_data["message"]
        key_info << "Message: #{error_data["message"]}"
      end
      
      if error_data["details"]
        key_info << "Details: #{format_nested_hash(error_data["details"])}"
      end
      
      if error_data["code"]
        key_info << "Code: #{error_data["code"]}"
      end
      
      if error_data["status"]
        key_info << "Status: #{error_data["status"]}"
      end
      
      # If we found key information, use it. Otherwise, fall back to JSON.
      if key_info.any?
        key_info.join(", ")
      else
        # Format as readable JSON but limit depth to avoid huge output
        JSON.pretty_generate(error_data).lines.first(10).join.chomp
      end
    else
      error_data.to_s
    end
  rescue JSON::GeneratorError, StandardError
    # If JSON formatting fails, just convert to string
    error_data.to_s
  end

  def format_nested_hash(hash, max_depth = 2, current_depth = 0)
    return hash.to_s if current_depth >= max_depth || !hash.is_a?(Hash)
    
    parts = []
    hash.each do |key, value|
      if value.is_a?(Hash) && current_depth < max_depth - 1
        nested = format_nested_hash(value, max_depth, current_depth + 1)
        parts << "#{key}: {#{nested}}"
      elsif value.is_a?(Array)
        # For arrays, show first few elements
        array_preview = value.first(3).map(&:to_s).join(", ")
        array_preview += "..." if value.length > 3
        parts << "#{key}: [#{array_preview}]"
      else
        parts << "#{key}: #{value}"
      end
    end
    
    parts.join(", ")
  end

  public

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

    # Handle nil text
    return nil if text.nil? || text.empty?
    
    if CONFIG["TTS_DICT"]
      text_converted = text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
    else
      text_converted = text
    end

    num_retrial = 0

    val_speed = speed ? speed.to_f : 1.0
    streaming_supported = true

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
    when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "elevenlabs-v3"
      api_key = CONFIG["ELEVENLABS_API_KEY"]
      headers = {
        "Content-Type" => "application/json",
        "xi-api-key" => api_key
      }

      model = case provider
              when "elevenlabs-v3"
                "eleven_v3"
              when "elevenlabs-multilingual"
                "eleven_multilingual_v2"
              when "elevenlabs-flash", "elevenlabs"
                "eleven_flash_v2_5"
              else
                "eleven_flash_v2_5"
              end

      body = {
        "text" => text_converted,
        "model_id" => model
      }

      streaming_supported = provider != "elevenlabs-v3"

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
      target_uri = if streaming_supported
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}/stream?output_format=#{output_format}"
                   else
                     "https://api.elevenlabs.io/v1/text-to-speech/#{voice}?output_format=#{output_format}"
                   end
    when "web-speech", "webspeech"
      # For Web Speech API, we don't need to make an API call
      # Return early with a special response
      if block_given?
        block.call({ "type" => "web_speech", "content" => text_converted })
        return nil
      else
        return { "type" => "web_speech", "content" => text_converted }
      end
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
      
      # Construct the text with voice instructions (lowercase voice names)
      voice_instruction = case voice.downcase
      when "zephyr"
        "Say cheerfully with bright tone: "
      when "puck"
        "Say with upbeat energy: "
      when "charon"
        "Say in an informative tone: "
      when "kore"
        "Say warmly: "
      when "fenrir"
        "Say expressively: "
      when "aoede"
        "Say creatively: "
      when "orus"
        "Say clearly: "
      when "schedar"
        "Say professionally: "
      else
        ""
      end
      
      prompt_text = voice_instruction + text_converted
      
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
      
      # Use the appropriate Gemini model with TTS capability
      model_name = case provider
                   when "gemini-flash"
                     "gemini-2.5-flash-preview-tts"
                   when "gemini-pro"
                     "gemini-2.5-pro-preview-tts"
                   else
                     "gemini-2.5-flash-preview-tts" # default
                   end
      # Use streaming endpoint when block is given
      if block_given?
        target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:streamGenerateContent?key=#{api_key}"
      else
        target_uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{api_key}"
      end
    else
      # Default error case
      return { "type" => "error", "content" => "ERROR: Unknown TTS provider: #{provider}" }
    end

    begin
      http = HTTP.headers(headers)
      
      # Use streaming for OpenAI TTS when block is given
      if block_given? && (provider.include?("openai-tts") || provider == "openai")
        require 'net/http'
        require 'uri'
        
        uri = URI(target_uri)
        net_http = Net::HTTP.new(uri.host, uri.port)
        net_http.use_ssl = true
        net_http.read_timeout = READ_TIMEOUT
        
        request = Net::HTTP::Post.new(uri.path)
        headers.each { |key, value| request[key] = value }
        request.body = body.to_json
        
        t_index = 0
        
        # Stream the response
        net_http.request(request) do |response|
          unless response.code.to_i == 200
            error_res = { "type" => "error", "content" => "ERROR: OpenAI TTS API error: #{response.code}" }
            block.call(error_res)
            return
          end
          
          response.read_body do |chunk|
            if chunk.length > 0
              t_index += 1
              content = Base64.strict_encode64(chunk)
              hash_res = { "type" => "audio", "content" => content, "t_index" => t_index, "finished" => false }
              block.call(hash_res)
              puts "OpenAI TTS: Streamed chunk #{t_index} (#{chunk.length} bytes)" if ENV["DEBUG_TTS"]
            end
          end
        end
        
        # Send completion signal
        t_index += 1
        finish = { "type" => "audio", "content" => "", "t_index" => t_index, "finished" => true }
        block.call(finish)
        return nil
      end
      
      # Use streaming for Gemini TTS when block is given
      if block_given? && (provider == "gemini" || provider == "gemini-flash" || provider == "gemini-pro")
        require 'net/http'
        require 'uri'
        
        uri = URI(target_uri)
        net_http = Net::HTTP.new(uri.host, uri.port)
        net_http.use_ssl = true
        net_http.read_timeout = READ_TIMEOUT
        
        request = Net::HTTP::Post.new(uri.path + "?" + uri.query)
        headers.each { |key, value| request[key] = value }
        request.body = body.to_json
        
        t_index = 0
        start_time = Time.now
        first_chunk_time = nil
        
        puts "Gemini TTS: Starting streaming request..." if ENV["DEBUG_TTS"]
        
        # Stream the response
        net_http.request(request) do |response|
          unless response.code.to_i == 200
            error_res = { "type" => "error", "content" => "ERROR: Gemini TTS API error: #{response.code}" }
            block.call(error_res)
            return
          end
          
          # Gemini streams JSON objects separated by newlines
          buffer = ""
          response.read_body do |chunk|
            buffer += chunk
            
            # Process complete JSON objects
            while buffer.include?("\n")
              line, buffer = buffer.split("\n", 2)
              next if line.strip.empty?
              
              begin
                json_response = JSON.parse(line.strip)
                
                # Extract audio data from streamed response
                if json_response["candidates"] && 
                   json_response["candidates"][0] && 
                   json_response["candidates"][0]["content"] && 
                   json_response["candidates"][0]["content"]["parts"] &&
                   json_response["candidates"][0]["content"]["parts"][0] &&
                   json_response["candidates"][0]["content"]["parts"][0]["inlineData"]
                  
                  audio_data = json_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
                  mime_type = json_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]
                  
                  if audio_data && !audio_data.empty?
                    t_index += 1
                    
                    if first_chunk_time.nil?
                      first_chunk_time = Time.now
                      latency = first_chunk_time - start_time
                      puts "Gemini TTS: First chunk latency: #{(latency * 1000).round}ms" if ENV["DEBUG_TTS"]
                    end
                    
                    hash_res = { "type" => "audio", "content" => audio_data, "mime_type" => mime_type, "t_index" => t_index, "finished" => false }
                    block.call(hash_res)
                    puts "Gemini TTS: Streamed chunk #{t_index} (#{audio_data.length} bytes)" if ENV["DEBUG_TTS"]
                  end
                end
              rescue JSON::ParserError => e
                puts "Gemini TTS: JSON parse error in stream: #{e.message}" if ENV["DEBUG_TTS"]
                next
              end
            end
          end
        end
        
        # Send completion signal
        t_index += 1
        finish = { "type" => "audio", "content" => "", "t_index" => t_index, "finished" => true }
        block.call(finish)
        return nil
      end
      
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      unless res.status.success?
        error_report = JSON.parse(res.body) rescue { "message" => res.body.to_s }
        
        # Log detailed error for Gemini
        if provider == "gemini" || provider == "gemini-flash" || provider == "gemini-pro"
          puts "Gemini TTS API Error: #{res.status} - #{error_report}"
          puts "Request URI: #{target_uri}"
          puts "Request body: #{body.to_json}"
        end
        
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

      # Handle Gemini response format
      if provider == "gemini" || provider == "gemini-flash" || provider == "gemini-pro"
        begin
          gemini_response = JSON.parse(res.body.to_s)
          
          # Minimal debug logging
          puts "Gemini TTS: Response received" if ENV["DEBUG_TTS"]
          
          # Extract audio data from Gemini response
          if gemini_response["candidates"] && 
             gemini_response["candidates"][0] && 
             gemini_response["candidates"][0]["content"] && 
             gemini_response["candidates"][0]["content"]["parts"] &&
             gemini_response["candidates"][0]["content"]["parts"][0] &&
             gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]
            
            audio_data = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
            mime_type = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]
            
            puts "Gemini TTS: Audio received (#{audio_data.length} bytes)" if ENV["DEBUG_TTS"]
            
            # Audio data is already base64 encoded from Gemini
            
            if block_given?
              # For streaming, send the complete audio at once with MIME type
              hash_res = { "type" => "audio", "content" => audio_data, "mime_type" => mime_type, "t_index" => 1, "finished" => false }
              block&.call hash_res
              finish = { "type" => "audio", "content" => "", "t_index" => 2, "finished" => true }
              block&.call finish
              return nil
            else
              return { "type" => "audio", "content" => audio_data, "mime_type" => mime_type }
            end
          else
            puts "Gemini TTS Error: Invalid response format"
            puts "Full response: #{gemini_response.inspect}"
            error_res = { "type" => "error", "content" => "ERROR: Invalid response format from Gemini API" }
            block&.call error_res if block_given?
            return error_res
          end
        rescue JSON::ParserError => e
          error_res = { "type" => "error", "content" => "ERROR: Failed to parse Gemini response: #{e.message}" }
          block&.call error_res if block_given?
          return error_res
        end
      end

      t_index = 0

      if block_given?
        if streaming_supported
          # For non-OpenAI providers (Gemini, ElevenLabs) that support streaming, emit chunks as they arrive
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
          # ElevenLabs v3 responds with a full file; deliver once even in streaming mode
          encoded = Base64.strict_encode64(res.body.to_s)
          hash_res = { "type" => "audio", "content" => encoded, "t_index" => 1, "finished" => false }
          block&.call hash_res
          finish = { "type" => "audio", "content" => "", "t_index" => 2, "finished" => true }
          block&.call finish
          return nil
        end
      else
        { "type" => "audio", "content" => Base64.strict_encode64(res.body.to_s) }
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
      logger.warn "ElevenLabs voice list error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
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

  def tavily_fetch(url:)
    api_key = CONFIG["TAVILY_API_KEY"]
    
    # Check if API key is present
    if api_key.nil? || api_key.empty?
      return "ERROR: Tavily API key is not configured"
    end
    
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "urls" => [url]  # Must be an array according to API docs
    }

    target_uri = "https://api.tavily.com/extract"

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      if res.status.success?
        res_json = JSON.parse(res.body)
        
        # Debug output
        puts "[DEBUG tavily_fetch] Response structure: #{res_json.keys}"
        puts "[DEBUG tavily_fetch] Full response: #{res_json.inspect}"
        
        # Check for failed results
        if res_json["failed_results"] && !res_json["failed_results"].empty?
          failed = res_json["failed_results"][0]
          puts "[DEBUG tavily_fetch] Failed result details: #{failed.inspect}"
          return { error: "Tavily fetch failed: #{failed['error']} for URL: #{failed['url']}" }
        end
        
        # Extract content from results array
        if res_json["results"] && res_json["results"].is_a?(Array) && !res_json["results"].empty?
          result = res_json["results"][0]
          puts "[DEBUG tavily_fetch] Result keys: #{result.keys}"
          
          # Try different possible content fields
          content = result["raw_content"] || result["content"] || result["text"]
          
          if content.nil? || content.empty?
            puts "[DEBUG tavily_fetch] No content found in result. Available keys: #{result.keys}"
            return { error: "No content found in Tavily response" }
          end
          
          return content
        else
          puts "[DEBUG tavily_fetch] No results in response"
          return { error: "No results found in Tavily response" }
        end
      else
        # Parse the response body only once
        puts "[DEBUG tavily_fetch] HTTP Error: #{res.status}"
        error_report = begin
          JSON.parse(res.body)
        rescue
          res.body.to_s
        end
        puts "[DEBUG tavily_fetch] Error response: #{error_report}"
        error_message = error_report.is_a?(Hash) ? (error_report["error"] || error_report["message"] || "Unknown error") : error_report.to_s
        { error: "Tavily API error: #{error_message}" }
      end
    rescue HTTP::Error, HTTP::TimeoutError => e
      puts "[DEBUG tavily_fetch] Network error: #{e.class} - #{e.message}"
      { error: "Network error occurred: #{e.message}" }
    rescue JSON::ParserError => e
      puts "[DEBUG tavily_fetch] JSON parse error: #{e.message}"
      { error: "Error parsing response: #{e.message}" }
    rescue StandardError => e
      puts "[DEBUG tavily_fetch] Unexpected error: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
      { error: "Unexpected error in tavily_fetch: #{e.message}" }
    end
  end
  
  # Check and notify if model was automatically switched
  # @param response_model [String] The model returned in the response
  # @param requested_model [String] The model that was requested
  # @param session [Hash] The session object
  # @param block [Proc] The block to call for notifications
  def check_model_switch(response_model, requested_model, session, &block)
    return unless response_model && requested_model && block
    return if response_model == requested_model
    return if session[:model_switch_notified]
    
    # Ignore version switches for the same base model (e.g., gpt-4.1 -> gpt-4.1-2025-04-14)
    # Extract base model name (everything before the date)
    response_base = response_model.split(/\d{4}-\d{2}-\d{2}/).first.chomp('-')
    requested_base = requested_model.split(/\d{4}-\d{2}-\d{2}/).first.chomp('-')
    return if response_base == requested_base
    
    session[:model_switch_notified] = true
    system_msg = {
      "type" => "system_info",
      "content" => "Model automatically switched from #{requested_model} to #{response_model}."
    }
    block.call system_msg
  end
end
