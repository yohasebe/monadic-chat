# frozen_string_literal: true

module OpenAIHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.openai.com/v1"
  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    api_key = CONFIG["OPENAI_API_KEY"]

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    max_tokens = obj["max_tokens"]&.to_i
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
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

      html = markdown_to_html(message, mathjax: obj["mathjax"])

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "role" => role,
                  "lang" => detect_language(message)
                } }
        res["images"] = obj["images"] if obj["images"]
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
      "n" => 1,
      "stream" => true,
      "stop" => nil
    }

    body["temperature"] = temperature if temperature
    body["top_p"] = top_p if top_p
    body["presence_penalty"] = presence_penalty if presence_penalty
    body["frequency_penalty"] = frequency_penalty if frequency_penalty
    body["max_tokens"] = max_tokens if max_tokens

    if obj["response_format"]
      body["response_format"] = APPS[app].settings["response_format"]
    end

    if obj["monadic"] || obj["json"]
      body["response_format"] ||= { "type" => "json_object" }
    end

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
      body["parallel_tool_calls"] = false
    else
      body.delete("tools")
      body.delete("tool_choice")
      body.delete("parallel_tool_calls")
    end

    # The context is added to the body
    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user"
        msg["images"].each do |img|
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
        end
        messages_containing_img = true
      end
      message
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    end

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix

    last_text = context.last["text"]
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    if last_text != "" && prompt_suffix.to_s != ""
      new_text = last_text + "\n\n" + prompt_suffix.strip if prompt_suffix.to_s != ""
      if body.dig("messages", -1, "content")
        body["messages"].last["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = new_text
          end
        end
      end
    end

    # initial prompt in the body is appended with the settings["initial_prompt_suffix"
    if initial_prompt != "" && obj["initial_prompt_suffix"].to_s != ""
      new_text = initial_prompt + "\n\n" + obj["initial_prompt_suffix"].strip
      body["messages"].first["content"].each do |content_item|
        if content_item["type"] == "text"
          content_item["text"] = new_text
        end
      end
    end

    if messages_containing_img
      body["model"] = CONFIG["VISION_MODEL"] || "gpt-4o-mini"
      body.delete("stop")
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    body["messages"].each do |msg|
      next unless msg["tool_calls"] || msg[:tool_call]

      if !msg["role"] && !msg[:role]
        msg["role"] = "assistant"
      end
      tool_calls = msg["tool_calls"] || msg[:tool_call]
      tool_calls.each do |tool_call|
        tool_call.delete("index")
      end
    end

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    # return Array
    process_json_data(app, session, res.body, call_depth, &block)
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

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil

    body.each do |chunk|
      if buffer.valid_encoding? == false
        buffer << chunk
        next
      end

      break if /\Rdata: [DONE]\R/ =~ buffer

      buffer << chunk

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      pattern = /data: (\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            finish_reason = json.dig("choices", 0, "finish_reason")
            case finish_reason
            when "length"
              finish_reason = "length"
            when "stop"
              finish_reason = "stop"
            else
              finish_reason = nil
            end

            # Check if the delta contains 'content' (indicating a text fragment) or 'tool_calls'
            if json.dig("choices", 0, "delta", "content")
              # Merge text fragments based on "id"
              id = json["id"]
              texts[id] ||= json
              choice = texts[id]["choices"][0]
              choice["message"] ||= choice["delta"].dup
              choice["message"]["content"] ||= ""
              fragment = json.dig("choices", 0, "delta", "content").to_s

              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

              res = {
                "type" => "fragment",
                "content" => fragment
              }
              block&.call res

              texts[id]["choices"][0].delete("delta")
            end

            if json.dig("choices", 0, "delta", "tool_calls")
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res

              tid = json.dig("choices", 0, "delta", "tool_calls", 0, "id")

              if tid
                tools[tid] = json
                tools[tid]["choices"][0]["message"] ||= tools[tid]["choices"][0]["delta"].dup
                tools[tid]["choices"][0].delete("delta")
              else
                new_tool_call = json.dig("choices", 0, "delta", "tool_calls", 0)
                existing_tool_call = tools.values.last.dig("choices", 0, "message")
                existing_tool_call["tool_calls"][0]["function"]["arguments"] << new_tool_call["function"]["arguments"]
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
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
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

      new_results = process_functions(app, session, tools, context, call_depth, &block)

      # return Array
      if result && new_results
        [result].concat new_results
      elsif new_results
        new_results
      elsif result
        [result]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result["choices"][0]["finish_reason"] = finish_reason
      [result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        argument_hash = JSON.parse(function_call["arguments"])
      rescue JSON::ParserError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      rescue StandardError => e
        pp e.message
        pp e.backtrace
        function_return = "ERROR: #{e.message}"
      end

      context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
