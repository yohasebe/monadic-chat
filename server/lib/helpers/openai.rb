# frozen_string_literal: false

module OpenAIHelper
  MAX_FUNC_CALLS = 5
  API_ENDPOINT = "https://api.openai.com/v1"

  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 1
  RETRY_DELAY = 1

  ENV_PATH = File.join(__dir__, "..", "..", "data", ".env")
  FileUtils.mkdir_p(File.dirname(ENV_PATH)) unless File.exist?(File.dirname(ENV_PATH))
  FileUtils.touch(ENV_PATH) unless File.exist?(ENV_PATH)

  def set_api_key(api_key, num_retrial = 0)
    if api_key
      api_key = api_key.strip
      settings.api_key = api_key
    end

    target_uri = "#{API_ENDPOINT}/models"

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{settings.api_key}"
    }
    http = HTTP.headers(headers)
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).get(target_uri)
    res_body = JSON.parse(res.body)
    if res_body && res_body["data"]
      models = res_body["data"].sort_by do |item|
        item["created"]
      end.reverse[0..30].map do |item|
        item["id"]
      end.filter do |item|
        item.include?("gpt") &&
          !item.include?("instruct") &&
          !item.include?("0301") &&
          !item.include?("0613")
      end

      if api_key
        File.open(ENV_PATH, "w") { |f| f.puts "OPENAI_API_KEY=#{settings.api_key}" }
      end
      { "type" => "models", "content" => "API token verified and stored in <code>.env</code> file.", "models" => models }
    else
      File.open(ENV_PATH, "w") { |f| f.puts "OPENAI_API_KEY=" }
      ENV["OPENAI_API_KEY"] = ""
      settings.api_key = ""
      if num_retrial >= MAX_RETRIES
        { "type" => "error", "content" => "ERROR: API token is not accepted" }
      else
        num_retrial += 1
        sleep RETRY_DELAY
        set_api_key(api_key, num_retrial)
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

    http = HTTP.headers(headers)
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      res = { "type" => "error", "content" => "ERROR: #{error_report["message"]}" }
      block&.call res
      return res
    end

    index = 0

    if block_given?
      res.body.each do |chunk|
        index += 1
        content = Base64.strict_encode64(chunk)
        hash_res = { "type" => "audio", "content" => content, "index" => index, "finished" => false }
        block&.call hash_res
      end
      index += 1
      finish = { "type" => "audio", "content" => "", "index" => index, "finished" => true }
      block&.call finish
    else
      results = { "type" => "audio", "content" => Base64.strict_encode64(res) }
      return results
    end
  rescue HTTP::Error, HTTP::TimeoutError
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

  def whisper_api_request(blob, format, lang_code)
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
        "model" => "whisper-1"
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
      puts "Audio file uploaded successfully"
      JSON.parse(response.body)
    else
      pp "Error: #{response.status} - #{response.body}"
      { "type" => "error", "content" => "Whisper API Error" }
    end
  end

  # Connect to OpenAI API and get a response
  def completion_api_request(role, &block)

    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    api_key = settings.api_key
    message = obj["message"].to_s

    # If the app is monadic, the message is passed through the monadic_map function
    if obj["monadic"].to_s == "true" && message != ""
      message = APPS[app].monadic_unit(message) if message != ""
      html = markdown_to_html(obj["message"]) if message != ""
    elsif message != ""
      html = markdown_to_html(message)
    end

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))
    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    max_tokens = obj["max_tokens"].to_i
    temperature = obj["temperature"].to_f
    top_p = obj["top_p"].to_f
    presence_penalty = obj["presence_penalty"].to_f
    frequency_penalty = obj["frequency_penalty"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    # If the message is not empty and the role is "user", the message is displaed
    # in the chat window at this point and it will be sent to the API
    if message != "" && role == "user"
      res = { "type" => "user",
              "content" => {
                "mid" => request_id,
                "text" => obj["message"],
                "html" => html,
                "lang" => detect_language(obj["message"])
              }
      }
      res["image"] = obj["image"] if obj["image"]
      block&.call res
    end

    # if the app uses the PDF tool, the message is passed through
    # the find_closest_text function and the snippet is added to the message
    if obj["pdf"]
      snippet = EMBEDDINGS_DB.find_closest_text(obj["message"])
      message_with_snippet = <<~TEXT
        #{obj["message"]}

        SNIPPET:

        ```
          #{snippet.to_json}
        ```
      TEXT
    end

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
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

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings[:tools]
      body["tool_choice"] = "auto"
      body["stream"] = false
    end


    # the initial prompt is set to the first message in the session
    # if the initial prompt is not empty
    initial = { "role" => "system",
                "text" => initial_prompt,
                "html" => initial_prompt,
                "lang" => detect_language(initial_prompt)
    } if initial_prompt != ""

    # If the role is "user", the message is added to the session
    if message != "" && role == "user"
      res = { "mid" => request_id,
              "role" => role,
              "text" => message,
              "html" => markdown_to_html(message),
              "lang" => detect_language(message),
              "active" => true,
      }
      if obj["image"]
        res["image"] = obj["image"]
      end
      session[:messages] << res
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages].each { |msg| msg["active"] = false }
    latest_messages = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    context = [initial] + latest_messages

    # If the role is "system", the message is added to the context
    # This is the case when the function is called from the assistant
    context << { "role" => role, "text" => message } if message != "" && role == "system"

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = context.last["text"]
    last_text = message_with_snippet if message_with_snippet.to_s != ""
    last_text = last_text + "\n\n" + prompt_suffix if prompt_suffix.to_s != ""
    context.last["text"] = last_text

    # The context is added to the body
    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [ {"type" => "text", "text" => msg["text"]} ] }
      if msg["image"]
        message["content"] << { "type" => "image_url", "image_url" => msg["image"]["data"] }
        messages_containing_img = true
      end
      message
    end

    # If the message contains an image, the model is set to "gpt-4-vision-preview"
    if messages_containing_img
      body["model"] = "gpt-4-vision-preview"
      body.delete("stop") if /\-vision/ =~ body["model"]
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)
    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      res = { "type" => "error", "content" => "ERROR: #{error_report["message"]}" }
      pp res
      block&.call res
      return res
    end

    # results contains the response from the API
    results = nil

    # If the stream is true, the fragments are processed one by one
    # and the accumulated response is returned
    if body["stream"]
      # buffer is used to accumulate the response
      buffer = ""

      res.body.each do |chunk|
        break if /\Rdata: [DONE]\R/ =~ chunk

        buffer << chunk
        scanner = StringScanner.new(buffer)
        pattern = /data: (\{.*?\})(?=\n|\z)/m
        until scanner.eos?
          matched = scanner.scan_until(pattern)
          if matched
            json_data = matched.match(pattern)[1]

            begin
              json = JSON.parse(json_data)
              choice = json.dig("choices", 0)

              fragment = choice.dig("delta", "content").to_s
              next if !fragment || fragment == ""

              res = { "type" => "fragment",
                      "content" => fragment,
                      "finish_reason" => choice["finish_reason"]
              }
              block&.call res

              results ||= json
              results["choices"][0]["text"] ||= +""
              results["choices"][0]["text"] << fragment

              if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
                finish = { "type" => "message", "content" => "DONE" }
                block&.call finish
                break
              end
            rescue JSON::ParserError
              res = { "type" => "error", "content" => "Error: JSON Parsing" }
              pp res
              block&.call res
              res
            end
          else
            buffer = scanner.rest
            break
          end
        end
      end
    else # If the stream is false, the response is processed as a whole
      begin
        results = JSON.parse(res.body)
      rescue JSON::ParserError
        results = { "type" => "error", "content" => "Error: JSON Parsing" }
        pp res
        block&.call res
        return results
      end
    end

    # results contains the response from the API

    # Check if tools are callable
    if obj["tools"] && obj["tools_choice"] != "none"
      functions_callable = true
    else
      functions_callable = false
    end

    # Check if a function is being called
    function_being_called = false
    if results && results.dig("choices", 0, "finish_reason") == "tool_calls"
      function_being_called = true
    end

    # pp body
    # pp results
    # pp functions_callable
    # pp function_being_called

    # If the app uses the tools, the tools are called
    if functions_callable && function_being_called

      # function names are extracted from the response
      custom_function_keys = APPS[app].settings[:tools]

      if obj["monadic"]
        message = results["choices"][0]["text"]
        results["choices"][0]["text"] = APPS[app].monadic_map(message)
      else
        # assistant's response is processed
        json_message = results["choices"][0]["message"]

        # function call (currently only one function call is supported)
        function_call = json_message["tool_calls"].first["function"]
        function_name = function_call["name"]

        # get the arguments of the function call
        begin
          argument_hash = JSON.parse(function_call["arguments"])
        rescue
          argument_hash = {}
        end

        argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_sym] = v
          memo
        end


        pp function_name
        pp argument_hash
        # function_return is the return value of the function call
        pp function_return = APPS[app].send(function_name.to_sym, argument_hash)

        obj["message"] = function_return.to_s
        obj["tools"] = nil
        obj["stream"] = true

        return completion_api_request("system", &block)
      end
    end

    res = { "type" => "message", "content" => "DONE" }
    block&.call res

    # The response is returned
    results
  rescue HTTP::Error, HTTP::TimeoutError
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
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
  end
end
