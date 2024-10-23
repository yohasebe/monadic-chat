module OpenAIUtils
  API_ENDPOINT = "https://api.openai.com/v1"
  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 10 # Timeout for opening a connection (seconds)
  READ_TIMEOUT = 60 # Timeout for reading data (seconds)
  WRITE_TIMEOUT = 60 # Timeout for writing data (seconds)

  # Number of retries for API requests
  MAX_RETRIES = 10
  # Delay between retries (seconds)
  RETRY_DELAY = 2

  # Check if the API key is valid
  # @param api_key [String] The API key to check
  # @return [Hash] A hash containing the result of the check
  def check_api_key(api_key)
    if api_key
      api_key = api_key.strip
      settings.api_key = api_key
    end

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

      if res_body && res_body["data"]
        models = res_body["data"].sort_by do |item|
          item["created"]
        end.reverse[0..20].map do |item|
          item["id"]
        end.filter do |item|
          (item.include?("gpt") || item.include?("o1-")) &&
          !item.include?("vision") &&
          !item.include?("instruct") &&
          !item.include?("gpt-3.5")
        end
        { "type" => "models", "content" => "API token verified", "models" => models }
      else
        { "type" => "error", "content" => "ERROR: API token is not accepted" }
      end

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        pp error_message = "API request failed after #{MAX_RETRIES} retries: #{e.message}"
        return { "type" => "error", "content" => "ERROR: #{error_message}" }
      end
    end
  end

  def tts_api_request(text, voice, speed, response_format, model, &block)
    body = {
      "input" => text,
      "model" => model,
      "voice" => voice,
      "speed" => speed,
      "response_format" => response_format
    }

    num_retrial = 0
    api_key = settings.api_key

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    target_uri = "#{API_ENDPOINT}/audio/speech"

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      unless res.status.success?
        error_report = JSON.parse(res.body)["error"]
        res = { "type" => "error", "content" => "ERROR: #{error_report["message"]}" }
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
      else
        { "type" => "audio", "content" => Base64.strict_encode64(res) }
      end

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        pp error_message = "The request has timed out."
        res = { "type" => "error", "content" => "ERROR: #{error_message}" }
        block&.call res
        false
      end
    end
  end

  def whisper_api_request(blob, format, lang_code)
    lang_code = nil if lang_code == "auto"

    num_retrial = 0

    url = "#{API_ENDPOINT}/audio/transcriptions"
    file_name = TEMP_AUDIO_FILE
    response = nil

    begin
      temp_file = Tempfile.new([file_name, ".#{format}"])
      temp_file.write(blob)
      temp_file.flush

      options = {
        "file" => HTTP::FormData::File.new(temp_file.path),
        "model" => "whisper-1",
        "response_format" => "verbose_json"
      }
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
        pp e.message
        pp e.backtrace
        return { "type" => "error", "content" => "ERROR: #{e.message}" }
      end
    ensure
      temp_file.close
      temp_file.unlink
    end

    if response.status.success?
      # puts "Audio file uploaded successfully"
      JSON.parse(response.body)
    else
      pp "Error: #{response.status} - #{response.body}"
      { "type" => "error", "content" => "Whisper API Error" }
    end
  end
end
