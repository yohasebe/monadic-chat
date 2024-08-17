module CommandRHelper
  include UtilitiesHelper

  API_ENDPOINT = "https://api.cohere.ai/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5

  def process_json_data(app, session, body, call_depth, &block)
    texts = []
    tool_calls = []
    finish_reason = nil

    in_text_generation = false

    if body.respond_to?(:each)
      body.each do |chunk|
        begin
          json = JSON.parse(chunk)

          finish_reason = json["finish_reason"]
          case finish_reason
          when "MAX_TOKENS"
            finish_reason = "length"
          when "COMPLETE"
            finish_reason = "stop"
          end

          case json["event_type"]
          when "text-generation"
            in_text_generation = true
          when "citation-generation"
            break if in_text_generation
          when "tool-calls-generation"
            tool_calls = json["tool_calls"]
            res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
            block&.call res
          end

          is_finished = json["is_finished"]
          break if is_finished

          fragment = json["text"]
          next unless fragment

          texts << fragment

          res = {
            "type" => "fragment",
            "content" => fragment
          }
          block&.call res
        rescue JSON::ParserError
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
      rescue StandardError => e
        pp e.message
        pp e.backtrace
        pp e.inspect
      end
    end

    result = texts.empty? ? nil : texts

    if tool_calls.any?
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tool_calls, call_depth, &block)
      # check if result is a hash and has "error" key
      if result.is_a?(Hash) && result["error"]
        res = { "type" => "error", "content" => result["error"] }
      elsif result && new_results
        result = result.join("") + "\n\n" + new_results.dig(0, "choices", 0, "message", "content")
        res = { "choices" => [{ "message" => { "content" => result } }] }
      elsif new_results
        res = new_results
      elsif result
        res = { "choices" => [{ "message" => { "content" => result.join("") } }] }
      end
      block&.call res
      block&.call res
      [res]
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result.join("") }
            }
          ]
        }
      ]
    else
      api_request("empty_tool_results", session, call_depth: call_depth, &block)
    end
  end

  def process_functions(_app, session, tool_calls, call_depth, &block)
    obj = session[:parameters]
    tool_results = []
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        argument_hash = tool_call["parameters"]
      rescue StandardError
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      function_return = send(function_name.to_sym, **argument_hash)

      tool_results << {
        call: tool_call,
        outputs: [{ result: function_return.to_s }]
      }
    end

    obj["tool_results"] = tool_results

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def translate_role(role)
    case role
    when "user"
      "USER"
    when "assistant"
      "CHATBOT"
    when "system"
      "SYSTEM"
    else
      role.upcase
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    empty_tool_results = role == "empty_tool_results"

    num_retrial = 0

    begin
      api_key = CONFIG["COHERE_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: COHERE_API_KEY not found. Please set the COHERE_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i
    top_p = obj["top_p"]&.to_f

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    if role != "tool"
      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
      else
        message = "Hi, there!"
      end

      # If the role is "user", the message is added to the session
      if message != "" && role == "user"
        res = { "mid" => request_id,
                "role" => role,
                "text" => message,
                "html" => markdown_to_html(message),
                "lang" => detect_language(message),
                "active" => true }
        session[:messages] << res
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages][0...-1].last(context_size).each { |msg| msg["active"] = true }

    # Set the headers for the API request
    headers = {
      "accept" => "application/json",
      "content-type" => "application/json",
      "Authorization" => "bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "preamble" => initial_prompt,
      "model" => obj["model"],
      "stream" => true,
      "prompt_truncation" => "AUTO"
      # "connectors" => [{"id" => "web-search"}]
    }

    body["message"] = message if role != "tool"
    body["temperature"] = temperature if temperature
    body["max_tokens"] = max_tokens if max_tokens
    body["p"] = top_p if top_p

    body["chat_history"] = context.compact.map do |msg|
      {
        "role" => translate_role(msg["role"]),
        "message" => msg["text"]
      }
    end

    if settings[:tools]
      body["tools"] = settings[:tools]
    end

    if role == "tool"
      body["tool_results"] = obj["tool_results"]
    elsif empty_tool_results
      body["tool_results"] = []
    end

    target_uri = "#{API_ENDPOINT}/chat"
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
