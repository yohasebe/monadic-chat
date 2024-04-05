# frozen_string_literal: false

module OpenAIHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.openai.com/v1"

  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 1
  RETRY_DELAY = 1

  if IN_CONTAINER
    ENV_PATH = "/monadic/data/.env"
    SCRIPTS_PATH = "/monadic/data/scripts"
    APPS_PATH = "/monadic/data/apps"
  else
    ENV_PATH = File.join(Dir.home, "monadic", "data", ".env")
    SCRIPTS_PATH = File.join(Dir.home, "monadic", "data", "scripts")
    APPS_PATH = File.join(Dir.home, "monadic", "data", "apps")
  end

  FileUtils.mkdir_p(File.dirname(ENV_PATH)) unless File.exist?(File.dirname(ENV_PATH))
  FileUtils.touch(ENV_PATH) unless File.exist?(ENV_PATH)

  FileUtils.mkdir_p(SCRIPTS_PATH) unless File.exist?(SCRIPTS_PATH)
  FileUtils.mkdir_p(APPS_PATH) unless File.exist?(APPS_PATH)

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
          !item.include?("vision") &&
          !item.include?("instruct") &&
          !item.include?("0301") &&
          !item.include?("0613")
      end

      if api_key
        env_vars = File.read(ENV_PATH).split("\n")
        env_vars_hash = env_vars.map { |line| line.split("=") }.to_h
        env_vars_hash["OPENAI_API_KEY"] = api_key
        File.open(ENV_PATH, "w") do |f|
          env_vars_hash.each do |key, value|
            f.puts "#{key}=#{value}"
          end
        end
        ENV["OPENAI_API_KEY"] = api_key
      end
      { "type" => "models", "content" => "API token verified and stored in <code>.env</code> file.", "models" => models }
    else
      env_vars = File.read(ENV_PATH).split("\n")
      env_vars_hash = env_vars.map { |line| line.split("=") }.to_h
      env_vars_hash["OPENAI_API_KEY"] = ""
      File.open(ENV_PATH, "w") do |f|
        env_vars_hash.each do |key, value|
          f.puts "#{key}=#{value}"
        end
      end
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
      # puts "Audio file uploaded successfully"
      JSON.parse(response.body)
    else
      pp "Error: #{response.status} - #{response.body}"
      { "type" => "error", "content" => "Whisper API Error" }
    end
  end

  def process_json_data(app, obj, body, call_depth, &block)
    buffer = ""
    tool_calls = false
    texts = {}
    tools = {}

    body.each do |chunk|
      break if /\Rdata: [DONE]\R/ =~ chunk

      buffer << chunk
      scanner = StringScanner.new(buffer)
      # pattern = /data: (\{.*?\})(?=\n|\z)/m
      pattern = /data: (\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            # Check if the delta contains 'content' (indicating a text fragment) or 'tool_calls'
            if json.dig('choices', 0, 'delta', 'content')
              # Merge text fragments based on 'id'
              id = json['id']
              texts[id] ||= json
              choice = texts[id]['choices'][0]
              choice['message'] ||= choice['delta'].dup
              choice["message"]["content"] ||= ""
              fragment = json.dig('choices', 0, 'delta', 'content').to_s
              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

              res = { "type" => "fragment",
                      "content" => fragment,
                      "finish_reason" => choice["finish_reason"]
              }
              block&.call res

              texts[id]['choices'][0].delete('delta')

              if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
                finish = { "type" => "message", "content" => "DONE" }
                block&.call finish
                break
              end
            end

            if json.dig('choices', 0, 'delta', 'tool_calls')

              res = { "type" => "wait", "content" => "CALLING FUNCTIONS" }
              block&.call res

              # Merge tool calls based on 'id'
              id = json['id']
              tools[id] ||= json
              choice = tools[id]['choices'][0]
              choice['message'] ||= choice['delta'].dup

              json.dig('choices', 0, 'delta', 'tool_calls').each do |new_tool_call|
                existing_tool_call = choice['message']['tool_calls'].find { |tc| tc['index'] == new_tool_call['index'] }
                if existing_tool_call
                  existing_tool_call['function']['arguments'] += new_tool_call.dig('function', 'arguments').to_s
                else
                  choice['message']['tool_calls'] << new_tool_call
                end
              end
              tools[id]['choices'][0].delete('delta')

              if choice["finish_reason"] == "function_call"
                break
              end

            end
          rescue JSON::ParserError
            # if the JSON parsing fails, the next chunk should be appended to the buffer
            # and the loop should continue to the next iteration
          end

        else
          buffer = scanner.rest
          break
        end
      end
    end

    result = texts.empty? ? nil : texts.first[1]

    if result
      if obj["monadic"]
        choice = result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          modified = APPS[app].monadic_map(message)
          choice["text"] = modified
        end
      end
    end

    if tools.any?
      context = []
      if result
        merged = result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
        context << merged
      else
        context << tools.first[1].dig("choices", 0, "message")
      end

      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, obj, tools, context, call_depth, &block)

      # return Array
      if result && new_results
        [result].concat new_results
      elsif new_results
        new_results
      elsif results
        [result]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  def process_functions(app, obj, tools, context, call_depth, &block)
    results = []
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        argument_hash = JSON.parse(function_call["arguments"])
      rescue
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      function_return = APPS[app].send(function_name.to_sym, **argument_hash)

      context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    # return Array
    completion_api_request("tool", obj: obj, call_depth: call_depth, &block)
  end

  # Connect to OpenAI API and get a response
  def completion_api_request(role, obj: nil, call_depth: 0, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj ||= session[:parameters]
    app = obj["app_name"]
    api_key = settings.api_key

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

    if role != "tool"
      message = obj["message"].to_s

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        message = APPS[app].monadic_unit(message) if message != ""
        html = markdown_to_html(obj["message"]) if message != ""
      elsif message != ""
        html = markdown_to_html(message)
      end

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
    end

    # the initial prompt is set to the first message in the session
    # if the initial prompt is not empty
    initial = { "role" => "system",
                "text" => initial_prompt,
                "html" => initial_prompt,
                "lang" => detect_language(initial_prompt)
    } if initial_prompt != ""

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages].each { |msg| msg["active"] = false }
    latest_messages = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    context = [initial] + latest_messages

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

      unless body["tools"] and body["tools"].any?
        body.delete("tools")
        body.delete("tool_choice")
      end
    end

    if role != "tool"
      # Decorate the last message in the context with the message with the snippet
      # and the prompt suffix
      last_text = context.last["text"]
      last_text = message_with_snippet if message_with_snippet.to_s != ""
      last_text = last_text + "\n\n" + prompt_suffix if prompt_suffix.to_s != ""
      context.last["text"] = last_text
    end

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

    if role == "tool"
      body["messages"] += obj["function_returns"]
    end

    # If the message contains an image, the model is set to "gpt-4-vision-preview"
    if messages_containing_img && role != "tool"
      body["model"] = "gpt-4-vision-preview"
      body.delete("stop") if /\-vision/ =~ body["model"]
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    body["messages"].each do |message|
      if message["tool_calls"] || message[:tool_call]
        if !message["role"] && !message[:role]
          message["role"] = "assistant"
        end
      end
    end

    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    # return Array
    return process_json_data(app, obj, res.body, call_depth, &block)

  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      pp error_message = "The request has timed out."
      res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
      block&.call res
      [res]
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
    block&.call res
    [res]
  end
end
