module ClaudeHelper
  include UtilitiesHelper

  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  attr_accessor :thinking

  def initialize
    @leftover = []
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
      result = result.gsub(/#{old}\n?/m) { new }
    end

    result
  end

  def get_thinking_text(result)
    @thinking += result.scan(%r{<thinking>.*?</thinking>}m) if result
  end

  def process_json_data(app, session, body, call_depth, &block)
    buffer = String.new
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

              new_content_type = json.dig("content_block", "type")
              if new_content_type == "tool_use"
                json["content_block"]["input"] = ""
                tool_calls << json["content_block"]
              end
              content_type = new_content_type if new_content_type

              if content_type == "tool_use"
                if json.dig("delta", "partial_json")
                  fragment = json.dig("delta", "partial_json").to_s
                  next if !fragment || fragment == ""

                  tool_calls.last["input"] << fragment
                end

                if json.dig("delta", "stop_reason")
                  stop_reason = json.dig("delta", "stop_reason")
                  case stop_reason
                  when "tool_use"
                    fragment = <<~FRAG
                      <div class='toggle'><pre>
                      #{JSON.pretty_generate(tool_calls.last)}
                      </pre></div>
                    FRAG

                    texts << "\n" + fragment.strip

                    finish_reason = "tool_use"
                    res1 = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                    block&.call res1
                  end
                end
              else
                if json.dig("delta", "text")
                  fragment = json.dig("delta", "text").to_s
                  next if !fragment || fragment == ""

                  texts << fragment

                  res = {
                    "type" => "fragment",
                    "content" => fragment
                  }
                  block&.call res
                end

                if json.dig("delta", "stop_reason")
                  stop_reason = json.dig("delta", "stop_reason")
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

    # if tool_calls.empty? && !result.to_s.empty?
    #   result.scan(%r{<div class='toggle'><pre>(.*?)</pre></div>}m).each do |x|
    #     json_string = x.first.strip
    #     json = JSON.parse(json_string)
    #     if json["type"] && json["id"] && json["name"] && json["input"]
    #       result = <<~COMMENT
    #       <hr />
    #       Tool call is not complete yet. Please wait for the result.
    #       <hr />
    #       COMMENT
    #       tool_calls << json
    #     end
    #   rescue JSON::ParserError
    #     next
    #   end
    # end

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

      if result
        context.last["content"] << {
          "type" => "text",
          "text" => result
        }
      end

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

      case session[:parameters]["model"]
      when /opus/
        result = add_replacements(result)
        result = add_replacements(@thinking.join("\n")) + result
        result = result.gsub(%r{<thinking>.*?</thinking>}m, "")
      when /sonnet/
        unless @leftover.empty?
          leftover_assistant = @leftover.filter { |x| x["role"] == "assistant" }
          result = leftover_assistant.map { |x| x.dig("content", 0, "text") }.join("\n") + result
        end
      end
      @leftover.clear

      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result }
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
      pp error_message = "ERROR: ANTHROPIC_API_KEY not found.  Please set the ANTHROPIC_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    pp obj = session[:parameters]
    app = obj["app_name"]

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))
    system_prompts = []
    system_prompts << { type: "text", text: initial_prompt }
    if obj["prompt_caching"] && MonadicApp::TOKENIZER.count_tokens(initial_prompt).to_i > 1024
      system_prompts[-1]["cache_control"] = { "type" => "ephemeral" }
    end

    session[:messages].each do |msg|
      next if msg["role"] != "system"

      sp = { type: "text", text: msg["text"] }
      if obj["prompt_caching"] && msg["tokens"] > 1024
        sp["cache_control"] = { "type" => "ephemeral" }
      end
      system_prompts << sp
    end

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i
    top_p = obj["top_p"]&.to_f

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    if message != "" && role == "user"
      @thinking.clear
      res = { "type" => "user",
              "content" => {
                "role" => role,
                "mid" => request_id,
                "text" => obj["message"],
                "html" => markdown_to_html(message),
                "lang" => detect_language(obj["message"]),
                "active" => true
              } }

      num_tokens = MonadicApp::TOKENIZER.count_tokens(obj["message"])
      res["content"]["tokens"] = num_tokens
      res["content"]["cache_control"] = { "type" => "ephemeral" } if num_tokens > 1024

      res["images"] = obj["images"] if obj["images"]
      block&.call res
      session[:messages] << res["content"]
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    begin
      session[:messages].each { |msg| msg["active"] = false }

      context = session[:messages].filter do |msg|
        msg["role"] == "user" || msg["role"] == "assistant"
      end.last(context_size).each { |msg| msg["active"] = true }

      session[:messages].filter do |msg|
        msg["role"] == "system"
      end.each { |msg| msg["active"] = true }
    rescue StandardError
      context = []
    end

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "anthropic-beta" => "prompt-caching-2024-07-31",
      "x-api-key" => api_key
    }

    # Set the body for the API request
    body = {
      "system" => system_prompts,
      "model" => obj["model"],
      "stream" => true,
      "tool_choice" => {
        "type": "auto"
      }
    }

    body["temperature"] = temperature if temperature
    body["max_tokens"] = max_tokens if max_tokens
    body["top_p"] = top_p if top_p

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # The context is added to the body
    messages = context.compact.map do |msg|
      content = { "type" => "text", "text" => msg["text"] }
      if obj["prompt_caching"] && msg["tokens"] > 10
        content["cache_control"] = { "type" => "ephemeral" }
      end
      { "role" => msg["role"], "content" => [content] }
    end

    if messages.last["role"] == "user" && obj["images"]
      obj["images"].each do |img|
        messages.last["content"] << {
          "type" => "image",
          "source" => {
            "type" => "base64",
            "media_type" => img["type"],
            "data" => img["data"].split(",")[1]
          }
        }
      end
    end

    # Remove assistant messages until the first user message
    messages.shift while messages.first["role"] != "user"

    modified = []

    messages.each do |msg|
      if modified.empty?
        modified << msg
        next
      end

      if modified.last["role"] == msg["role"]
        the_other_role = modified.last["role"] == "user" ? "assistant" : "user"
        modified << {
          "role" => the_other_role,
          "content" => [
            {
              "type" => "text",
              "text" => "OK"
            }
          ]
        }
      end
      modified << msg
    end

    # if there is no user message, add a placeholder
    if modified.empty? || modified.last["role"] == "assistant"
      modified << {
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "OK"
          }
        ]
      }
    end

    if modified.last["role"] == "user"
      modified.last["content"].each do |content|
        if content["type"] == "text"
          content["text"] += "\n\n#{obj["prompt_suffix"]}"
          break
        end
      end
    end

    body["messages"] = modified

    if role == "tool"
      body["messages"] += obj["function_returns"]
      @leftover += obj["function_returns"]
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

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]
    tools.each do |tool_call|
      tool_name = tool_call["name"]

      begin
        argument_hash = tool_call["input"]
      rescue StandardError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      tool_return = APPS[app].send(tool_name.to_sym, **argument_hash)

      unless tool_return
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
