# frozen_string_literal: true

module OpenAIHelper
  API_ENDPOINT = "https://api.openai.com/v1"

  TEMP_AUDIO_FILE = "temp_audio_file"

  STREAMING_TIMEOUT = 30
  COMPLETION_TIMEOUT = 300
  WHISPER_TIMEOUT = 60
  RETRY_DELAY = 1
  ENV_PATH = File.join(__dir__, "..", "..", "data", ".env")
  # create ENV_PATH if it doesn't exist
  FileUtils.touch(ENV_PATH) unless File.exist?(ENV_PATH)

  def set_api_key(api_key = nil, num_retrial = 0)
    api_key = api_key.strip if api_key
    settings.api_key = api_key if settings.api_key.nil? || settings.api_key == ""
    target_uri = "#{API_ENDPOINT}/models"

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{settings.api_key}"
    }
    http = HTTP.headers(headers)
    res = http.timeout(STREAMING_TIMEOUT).get(target_uri)
    res_body = JSON.parse(res.body)
    if res_body && res_body["data"]
      models = res_body["data"].sort_by { |item| item["created"] }.reverse[0..10].map { |item| item["id"] }.filter { |item| item.include?("gpt") && item.include?("0613") }
      if api_key
        File.open(ENV_PATH, "w") { |f| f.puts "OPENAI_API_KEY=#{settings.api_key}" }
        { "type" => "models", "content" => "A new API token has been verified and stored in <code>.env</code> file.", "models" => models }
      else
        { "type" => "models", "content" => "API token stored in <code>.env</code> file has been verified.", "models" => models }
      end
    else
      return { "type" => "error", "content" => "ERROR: API token is not accepted" } if num_retrial >= 3

      sleep RETRY_DELAY
      set_api_key(api_key, num_retrial + 1)
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    { "type" => "error", "content" => "ERROR: #{e.message}" }
  end

  def whisper_api_request(blob, format, lang_code)
    url = "#{API_ENDPOINT}/audio/transcriptions"
    file_name = TEMP_AUDIO_FILE
    response = nil

    begin
      temp_file = Tempfile.new([file_name, ".#{format}"])
      temp_file.write(blob)
      temp_file.flush

      options = {
        "file" => HTTP::FormData::File.new(temp_file.path),
        "model" => "whisper-1"
      }
      options["language"] = lang_code if lang_code
      form_data = HTTP::FormData.create(options)
      response = HTTP.headers(
        "Authorization" => "Bearer #{settings.api_key}",
        "Content-Type" => form_data.content_type
      ).timeout(WHISPER_TIMEOUT).post(url, body: form_data.to_s)
    rescue HTTP::Error, HTTP::TimeoutError => e
      return { "type" => "error", "content" => "ERROR: #{e.message}" }
    ensure
      temp_file.close
      temp_file.unlink
    end

    if response.status.success?
      puts "Audio file uploaded successfully"
      JSON.parse(response.body)
    else
      pp "Error: #{response.status} - #{response.body}"
      { "type" => "error", "content" => "Whisper API Error" }
    end
  end

  # Connect to OpenAI API and get a response
  def completion_api_request(role, &block)
    obj = session[:parameters]
    app = obj["app_name"]

    api_key = settings.api_key

    message = obj["message"].to_s
    if obj["monadic"].to_s == "true" && message != ""
      message = APPS[app].monadic_unit(message) if message != ""
      html = markdown_to_html(obj["message"]) if message != ""
    elsif message != ""
      html = markdown_to_html(message)
    end

    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))
    model = obj["model"]
    max_tokens = obj["max_tokens"].to_i
    temperature = obj["temperature"].to_f
    top_p = obj["top_p"].to_f
    presence_penalty = obj["presence_penalty"].to_f
    frequency_penalty = obj["frequency_penalty"].to_f

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    if message != "" && role == "user"
      res = { "type" => "user", "content" => { "mid" => request_id, "text" => obj["message"], "html" => html, "lang" => detect_language(obj["message"]) } }
      block&.call res
    end

    if obj["pdf"]
      snippet = EMBEDDINGS_DB.find_closest_text(obj["message"])
      message_with_snippet = <<~TEXT
        #{obj["message"]}

        SNIPPET:```
          #{snippet.to_json}
        ```
      TEXT
    end

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => model,
      "temperature" => temperature,
      "top_p" => top_p,
      "n" => 1,
      "stream" => true,
      "stop" => nil,
      "max_tokens" => max_tokens,
      "presence_penalty" => presence_penalty,
      "frequency_penalty" => frequency_penalty
    }

    if obj["functions"] && !obj["functions"].empty?
      body["functions"] = APPS[app].settings[:functions]
      body["function_call"] = "auto"
      body["stream"] = false
    end

    case MODE
    when "completions"
      body["prompt"] = message
    when "chat/completions"
      initial = { "role" => "system", "text" => initial_prompt, "html" => initial_prompt, "lang" => detect_language(initial_prompt) } if initial_prompt != ""
      if message != "" && role == "user"
        res = { "mid" => request_id, "role" => role, "text" => message, "html" => markdown_to_html(message), "lang" => detect_language(message), "active" => true }
        session[:messages] << res
      end
      session[:messages].each { |msg| msg["active"] = false }
      latest_messages = session[:messages].last(context_size).each { |msg| msg["active"] = true }
      context = [initial] + latest_messages
      context << { "role" => role, "text" => message } if message != "" && role == "system"
      context.last["text"] = message_with_snippet if message_with_snippet
      body["messages"] = context.compact.map { |msg| { "role" => msg["role"], "content" => msg["text"] } }
    end

    target_uri = "#{API_ENDPOINT}/#{MODE}"
    headers["Accept"] = "text/event-stream"

    http = HTTP.headers(headers)
    res = http.timeout(COMPLETION_TIMEOUT).post(target_uri, json: body)

    json = nil

    last_processed_time = Time.now

    if body["stream"] && !(res["choices"] && res["choices"][0]["finish_reason"] == "stop")
      res.body.each do |chunk|
        chunk.split("\n\n").each do |data|
          current_time = Time.now
          elapsed_time = current_time - last_processed_time

          if elapsed_time > STREAMING_TIMEOUT
            error_message = "Error: No new response received within 5 seconds after the last response has been processed."
            res = { "type" => "error", "content" => "ERROR: #{error_message}" }
            pp res
            block&.call res
            return res
          end

          unless data[0..5] == "data: "
            typecheck = JSON.parse(data)
            begin
              if typecheck["error"]
                res = { "type" => "error", "content" => typecheck["error"]["message"] }
                pp res
                block&.call res
                return res
              end
            rescue JSON::ParserError
              res = { "type" => "error", "content" => "Error: JSON Parsing" }
              pp res
              block&.call res
              return res
            end
          end

          content = data.strip[6..]
          # pp content
          break if content == "[DONE]"

          begin
            stream = JSON.parse(content)
          rescue JSON::ParserError
            next
          end

          fragment = case MODE
                     when "completions"
                       stream["choices"][0]["text"]
                     when "chat/completions"
                       stream["choices"][0]["delta"]["content"] || ""
                     end
          res = { "type" => "fragment", "content" => fragment, "finish_reason" => stream["finish_reason"] }
          block&.call res
          if !json
            json = stream
          else
            case MODE
            when "completions"
              json["choices"][0]["text"] << fragment
            when "chat/completions"
              json["choices"][0]["text"] ||= +""
              json["choices"][0]["text"] << fragment
            end
          end
          last_processed_time = Time.now
        rescue Timeout::Error
          error_message = "Error: No new response received within #{STREAMING_TIMEOUT} seconds after the last response has been processed."
          res = { "type" => "error", "content" => "ERROR: #{error_message}" }
          pp res
          block&.call res
          return res
        rescue StandardError => e
          res = { "type" => "error", "content" => "ERROR: #{e.message}" }
          pp res
          block&.call res
          return res
        end
      end
    else
      begin
        json = JSON.parse(res.body)
      rescue JSON::ParserError
        res = { "type" => "error", "content" => "Error: JSON Parsing" }
        pp res
        block&.call res
        return res
      end
    end

    if role == "user" && obj["functions"] && (!json["choices"] || json["choices"] && json["choices"][0]["finish_reason"] != "stop")
      custom_function_keys = APPS[app].settings[:functions]
      if custom_function_keys && !custom_function_keys.empty?
        function_call = json["choices"][0]["message"]["function_call"]
        function_name = function_call["name"]
        argument_hash = JSON.parse(function_call["arguments"])
        argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_sym] = v
          memo
        end

        # function_record = { "mid" => SecureRandom.hex(4),
        #                     "role" => "assistant",
        #                     "text" => "#{custom_function_key}(\"#{argument_hash}\")",
        #                     "type" => "function calling" }
        # session[:messages] << function_record
        # obj.delete("functions")
        # obj["function_call"] = "none"

        message = APPS[app].send(function_name.to_sym, argument_hash)
        obj["message"] = message if message
        obj["stream"] = true
        return completion_api_request("system", &block)
      elsif obj["monadic"]
        message = json["choices"][0]["text"]
        json["choices"][0]["text"] = APPS[app].monadic_map(message)
      end
    end

    res = { "type" => "message", "content" => "DONE" }
    block&.call res
    json
  rescue HTTP::TimeoutError
    pp error_message = "The request has timed out after #{COMPLETION_TIMEOUT} seconds."
    res = { "type" => "error", "content" => "ERROR: #{error_message}" }
    block&.call res
    false
  rescue StandardError => e
    pp json
    puts e.message
    puts e.backtrace
    puts e.inspect
    hint = if json.dig("error", "message").present?
             case json["error"]["message"]
             when /overloaded/
               "Server overloaded, please try again later."
             else
               "Something went wrong."
             end
           else
             "Something went wrong."
           end
    res = { "type" => "error", "content" => "ERROR: #{hint}" }
    block&.call res
    false
  end
end
