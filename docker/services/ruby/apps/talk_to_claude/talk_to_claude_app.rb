class Claude < MonadicApp
  include UtilitiesHelper

  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    text = "This app accesses the Anthropic API to answer questions about a wide range of topics."
    text += " (Model: <code>#{CONFIG['ANTHROPIC_MODEL']}</code>)" if CONFIG["ANTHROPIC_MODEL"]
    text
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.

      Please use `fetch_web_content` tool to fetch the content of the web page of the given URL if the user's request is related to a specific web page.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Talk to Anthropic Claude",
      "context_size": 100,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "toggle": true,
      "image": true,
      "models": [
        "claude-3-5-sonnet-20240620",
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307"
      ],
      "tools": [
        {
          "name": "fetch_web_content",
          "description": "Fetch the content of the web page of the given URL and return it.",
          "input_schema": {
            "type": "object",
            "properties": {
              "url": {
                "type": "string",
                "description": "URL of the web page."
              }
            },
            "required": ["url"]
          }
        }
      ]
    }
  end

  attr_accessor :thinking
  def initialize
    @thinking = []
    super
  end

  def add_replacements(result)
    result.strip!
    replacements = {
      "<thinking>" => "<div data-title='Thinking' class='toggle'><div class='toggle-open'>",
      "</thinking>" => "</div></div>",

      "<search_quality_reflection>" => "<div data-title='Search Quality Reflection' class='toggle'><div class='toggle-open'>",
      "</search_quality_reflection>" => "</div></div>",

      "<search_quality_score>" => "<div data-title='Search Quality Score' class='toggle'><div class='toggle-open'>",
      "</search_quality_score>" => "</div></div>",

      "<result>" => "",
      "</result>" => ""
    }

    replacements.each do |old, new|
      result = result.gsub(/#{old}\n?/m){ new }
    end

    result
  end

  def get_thinking_text(result)
    @thinking += result.scan(/<thinking>.*?<\/thinking>/m) if result
  end

  def process_json_data(app, session, body, call_depth, &block)

    obj = session[:parameters]

    buffer = ""
    texts = []
    tool_calls = []
    finish_reason = nil
    content_type = "text"

    if body.respond_to?(:each)
      body.each do |chunk|
        break if /\Rdata: [DONE]\R/ =~ chunk

        buffer << chunk
        scanner = StringScanner.new(buffer)
        pattern = /data: (\{.*?\})(?=\n|\z)/

        until scanner.eos?
          matched = scanner.scan_until(pattern)
          if matched
            json_data = matched.match(pattern)[1]
            begin
              json = JSON.parse(json_data)

              new_content_type = json.dig('content_block', 'type')
              if new_content_type == "tool_use"
                json["content_block"]["input"] = ""
                tool_calls << json["content_block"]
              end
              content_type = new_content_type if new_content_type

              if content_type == "tool_use"
                if json.dig('delta', 'partial_json')
                  fragment = json.dig('delta', 'partial_json').to_s
                  next if !fragment || fragment == ""
                  tool_calls.last["input"] << fragment
                end

                if json.dig('delta', 'stop_reason')
                  stop_reason = json.dig('delta', 'stop_reason')
                  case stop_reason
                  when "tool_use"
                    finish_reason = "tool_use"
                    res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                    block&.call res
                  end
                end
              else
                if json.dig('delta', 'text')
                  fragment = json.dig('delta', 'text').to_s
                  next if !fragment || fragment == ""
                  texts << fragment

                  fragment.split(//).each do |char|
                    res = { "type" => "fragment", "content" => char }
                    block&.call res
                    sleep 0.01
                  end
                end

                if json.dig('delta', 'stop_reason')
                  stop_reason = json.dig('delta', 'stop_reason')
                  case stop_reason
                  when "max_tokens"
                    finish_reason = "length"
                  when "end_turn"
                    finish_reason = "stop"
                  end
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
    end

    result = if texts.empty?
               nil
             else
               texts.join("")
             end


    if tool_calls.any?
      get_thinking_text(result)

      call_depth += 1

      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      context = []
      context << {
        "role" => "assistant",
        "content" => []
      }

      context.last["content"] << {
        "type" => "text",
        "text" => result
      } if result

      tool_calls.each do |tool_call|
        begin
          input_hash = JSON.parse(tool_call["input"])
        rescue JSON::ParserError
          input_hash = {}
        end

        tool_call["input"] = input_hash
        context.last["content"] << {
          "type" => "tool_use",
          "id" => tool_call["id"],
          "name" => tool_call["name"],
          "input" => tool_call["input"]
        }
      end

      process_functions(app, session, tool_calls, context, call_depth, &block)

    elsif result
      result = add_replacements(result)
      result = add_replacements(@thinking.join("\n")) + result
      result = result.gsub(/<thinking>.*?<\/thinking>/m, "")

      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason}
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => {"content" => result}
            }
          ]
        }
      ]
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["ANTHROPIC_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      puts "ERROR: ANTHROPIC_API_KEY not found."
      exit
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))

    temperature = obj["temperature"] ? obj["temperature"].to_f : nil
    max_tokens = obj["max_tokens"] ? obj["max_tokens"].to_i : nil
    top_p = obj["top_p"] ? obj["top_p"].to_f : nil

    tools = settings[:tools] ? settings[:tools] : []

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    # If the app is monadic, the message is passed through the monadic_map function
    if obj["monadic"].to_s == "true" && message != ""
      message = monadic_unit(message) if message != ""
      html = markdown_to_html(obj["message"]) if message != ""
    elsif message != ""
      html = markdown_to_html(message)
    end

    if message != "" && role == "user"
      @thinking.clear
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
    begin
      session[:messages].each { |msg| msg["active"] = false }
      context = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    rescue
      context = []
    end

    # Set the headers for the API request
    headers = {
      "anthropic-version" => "2023-06-01",
      # "anthropic-beta" => "messages-2023-12-15",
      # "anthropic-beta" => "tools-2024-05-16",
      "content-type" => "application/json",
      "x-api-key" => api_key
    }

    # Set the body for the API request
    body = {
      "system" => initial_prompt,
      "model" => obj["model"],
      "stream" => true,
      "tool_choice" => {"type": "auto"}
    }

    body["temperature"] = temperature if temperature
    body["max_tokens"] = max_tokens if max_tokens
    body["top_p"] = top_p if top_p

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings[:tools]

      unless body["tools"] and body["tools"].any?
        body.delete("tools")
        body.delete("tool_choice")
      end
    end

    # The context is added to the body

    messages = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [ {"type" => "text", "text" => msg["text"]} ] }
      if msg["image"] && role == "user"
        message["content"] << {
          "type" => "image",
          "source" => {
            "type" => "base64",
            "media_type" => msg["image"]["type"],
            "data" => msg["image"]["data"].split(",")[1]
          }
        }
      end
      message
    end

    messages.unshift({
      "role" => "user",
      "content" => [
        {
          "type" => "text",
          "text" => "OK"
        }
      ]
    }) if messages.first["role"] != "user"

    messages = messages.each_with_index.flat_map do |msg, i|
      if i > 0 && msg["role"] == messages[i - 1]["role"]
        the_other = msg["role"] == "user" ? "assistant" : "user"
        [ { "role" => the_other, "content" => [ { "type" => "text", "text" => "OK" } ] }, msg]
      else
        msg
      end
    end

    body["messages"] = messages

    if role == "tool"
      body["messages"] += obj["function_returns"]
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/messages"
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
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    return process_json_data(app, session, res.body, call_depth, &block)

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

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]
    tools.each do |tool_call|
      tool_name = tool_call["name"]

      begin
        argument_hash = tool_call["input"]
      rescue
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      tool_return = APPS[app].send(tool_name.to_sym, **argument_hash) 

      if !tool_return
        return [{ "type" => "error", "content" => "ERROR: Tool '#{tool_name}' failed" }]
      end

      content << {
        type: "tool_result",
        tool_use_id: tool_call["id"],
        content: tool_return.to_s 
      }
    end

    context << {
      role: "user",
      content: content
    }

    obj["function_returns"] = context

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end
end

