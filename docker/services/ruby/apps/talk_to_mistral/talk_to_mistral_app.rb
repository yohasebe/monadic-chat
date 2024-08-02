class TalkToMistral < MonadicApp
  include UtilitiesHelper

  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.mistral.ai/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  def icon
    "<i class='fa-solid fa-m'></i>"
  end

  def description
    "This app accesses the Mistral AI API to answer questions about a wide range of topics."
  end

  attr_reader :models

  def initialize
    @models = list_models
    super
  end

  def list_models
    return @models if @models && !@models.empty?

    api_key = CONFIG["MISTRAL_API_KEY"]
    return [] if api_key.nil?

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    target_uri = "#{API_ENDPOINT}/models"
    http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        model_data["data"].sort_by do |model|
          model["created"]
        end.reverse.map do |model|
          model["id"]
        end.filter do |model|
          !model.include?("embed")
        end
      end
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it.
    TEXT

    text.strip
  end

  def prompt_suffix
    "Use the same language as the user and insert an ascii emoji that you deem appropriate for the user's input at the beginning of your response. When you use emoji, it should be something like 😀 instead of `:smiley:`. Avoid repeating words or phrases in your responses."
  end

  def settings
    {
      "disabled": !CONFIG["MISTRAL_API_KEY"],
      "temperature": 0.7,  # Adjusted temperature
      "top_p": 1.0,        # Adjusted top_p
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "prompt_suffix": prompt_suffix,
      "image_generation": false,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": false,
      "app_name": "▷ Mistral AI (Chat)",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "image": false,
      "toggle": false,
      "models": @models
    }
  end

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]

    buffer = ""
    texts = {}
    tools = {}
    finish_reason = nil

    body.each do |chunk|
      begin
        if buffer.valid_encoding? == false
          buffer << chunk
          next
        end

        buffer << chunk

        data_items = buffer.scan(/data: \{.*\}/)
        next if data_items.nil? || data_items.empty?

        data_items.each do |item|
          data_content = item.match(/data: (\{.*\})/)
          next if data_content.nil? || !data_content[1]

          json = JSON.parse(data_content[1])

          finish_reason = json.dig("choices", 0, "finish_reason")
          case finish_reason
          when "length"
            finish_reason = "length"
          when "stop"
            finish_reason = "stop"
          else
            finish_reason = nil
          end

          if json.dig("choices", 0, "delta", "content")
            id = json["id"]
            texts[id] ||= json
            choice = texts[id]["choices"][0]
            choice["message"] ||= choice["delta"].dup
            choice["message"]["content"] ||= ""

            fragment = json.dig("choices", 0, "delta", "content").to_s
            choice["message"]["content"] << fragment

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

            id = json["id"]
            tools[id] ||= json
            choice = tools[id]["choices"][0]
            choice["message"] ||= choice["delta"].dup

            if choice["finish_reason"] == "function_call"
              break
            end
          end
        rescue JSON::ParserError => e
          pp e.message
          pp e.backtrace
          pp e.inspect
        end
        buffer = ""
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.empty? ? nil : texts.first[1]

    if result && obj["monadic"]
      choice = result["choices"][0]
      if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
        message = choice["message"]["content"]
        modified = APPS[app].monadic_map(message)
        choice["text"] = modified
      end
    end

    if tools.any?
      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")
      context = []
      res = { "role" => "assistant" }
      res["tool_calls"] = tools.map do |tool|
        {
          "id" => tool["id"],
          "function" => tool["function"]
        }
      end
      context << res

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tools, context, call_depth, &block)

      if new_results
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
        escaped = function_call["arguments"]
        argument_hash = JSON.parse(escaped)
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = APPS[app].send(function_name.to_sym, **converted)
      rescue StandardError => e
        function_return = "ERROR: #{e.message}"
      end

      context << {
        role: "tool",
        tool_call_id: tool_call["id"],
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    session[:messages].delete_if do |msg|
      msg["role"] == "assistant" && msg["content"].to_s == ""
    end

    begin
      api_key = CONFIG["MISTRAL_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: MISTRAL_API_KEY not found. Please set the MISTRAL_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))
    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    top_p = obj["top_p"].to_f
    top_p = 0.01 if top_p == 0.0
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    if role != "tool"
      message = obj["message"].to_s

      if obj["monadic"].to_s == "true" && message != ""
        message = APPS[app].monadic_unit(message)

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
                } }
        res["image"] = obj["image"] if obj["image"]
        block&.call res
      end

      if message != "" && role == "user"
        res = { "mid" => request_id,
                "role" => role,
                "text" => message,
                "html" => markdown_to_html(message),
                "lang" => detect_language(message),
                "active" => true }
        if obj["image"]
          res["image"] = obj["image"]
        end
        session[:messages] << res
      end
    end

    if initial_prompt != ""
      initial = { "role" => "system",
                  "text" => initial_prompt,
                  "html" => initial_prompt,
                  "lang" => detect_language(initial_prompt) }
    end

    session[:messages].each { |msg| msg["active"] = false }
    latest_messages = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    context = [initial] + latest_messages

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => obj["model"],
      "temperature" => temperature,
      "top_p" => top_p,
      "safe_prompt" => false,
      "stream" => true,
      "tool_choice" => "auto"
    }

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = settings[:tools] || []
    end

    body["max_tokens"] = max_tokens if max_tokens

    if obj["monadic"] || obj["json"]
      body["response_format"] = { "type" => "json_object" }
    end

    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => msg["text"] }
      if msg["image"] && role == "user"
        message["content"] << {
          "type" => "image_url",
          "image_url" => {
            "url" => msg["image"]["data"]
          }
        }
        messages_containing_img = true
      end
      message
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      body["messages"].last["content"] += "\n\n" + settings[:prompt_suffix] if settings[:prompt_suffix]
    end

    if messages_containing_img
      body["model"] = "gpt-4o-mini"
      body.delete("stop")
    end

    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    success = false
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      if res.status.success?
        success = true
        break
      end
      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
      block&.call res
      return [res]
    end

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
end
