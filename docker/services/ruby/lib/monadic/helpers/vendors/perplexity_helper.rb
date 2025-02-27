# frozen_string_literal: true

module PerplexityHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.perplexity.ai"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60 * 10
  WRITE_TIMEOUT = 60 * 10

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  attr_reader :models

  def self.vendor_name
    "Perplexity"
  end

  def self.list_models
    ["sonar",
     "sonar-pro",
     "sonar-reasoning",
     "sonar-reasoning-pro",
     "sonar-deep-research",
     "r1-1776"
    ]
  end

  # No streaming plain text completion/chat call
  def send_query(options, model: "sonar-chat")
    api_key = ENV["PERPLEXITY_API_KEY"]

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
      "stream" => false,
      "messages" => []
    }
    body.merge!(options)

    target_uri = "#{API_ENDPOINT}/chat/completions"
    http = HTTP.headers(headers)

    res = nil
    MAX_RETRIES.times do |i|
      begin
        res = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)

        # Check that res is not nil and has a successful status.
        break if res && res.status && res.status.success?

        sleep RETRY_DELAY * (i + 1)  # Exponential backoff
      rescue HTTP::Error, HTTP::TimeoutError => e
        next unless i == MAX_RETRIES - 1

        pp error_message = "Network error: #{e.message}"
          res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
          block&.call(res)
        return [res]
      end
    end

    if res && res.status && res.status.success?
      begin
        # Parse response JSON only once.
        parsed_response = JSON.parse(res.body)
        return parsed_response.dig("choices", 0, "message", "content")
      rescue JSON::ParserError => e
        return "ERROR: Failed to parse response JSON: #{e.message}"
      end
    else
      error_response = nil
      begin
        # Parse error JSON only once.
        error_response = (res && res.body) ? JSON.parse(res.body) : { "error" => "No response received" }
      rescue JSON::ParserError => e
        error_response = { "error" => "Failed to parse error response JSON: #{e.message}" }
      end
      pp error_response
      return "ERROR: #{error_response['error']}"
    end
  rescue StandardError => e
    return "Error: The request could not be completed. (#{e.message})"
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    api_key = CONFIG["PERPLEXITY_API_KEY"]

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i 
    temperature = obj["temperature"]&.to_f
    presence_penalty = obj["presence_penalty"]&.to_f
    frequency_penalty = obj["frequency_penalty"]&.to_f 
    frequency_penalty = 1.0 if frequency_penalty == 0.0

    context_size = obj["context_size"]&.to_i

    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    message = nil
    data = nil

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
        res["content"]["images"] = obj["images"] if obj["images"]
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
    }

    body["stream"] = true
    body["n"] = 1

    body["temperature"] = temperature if temperature
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
      body["tool_choice"] = "auto"
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # The context is added to the body
    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user"
        msg["images"].each do |img|
          messages_containing_img = true
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
        end
      end
      message
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body["tool_choice"] = "auto"
    end

    if obj["model"].include?("reasoning")
      body.delete("temperature")
      body.delete("tool_choice")
      body.delete("tools")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].each do |msg|
        msg["content"].each do |item|
          if item["type"] == "text"
            item["text"] = item["text"].sub(/---\n\n/, "")
          end
        end
      end
    else
      if obj["monadic"] || obj["json"]
        body["response_format"] ||= { "type" => "json_object" }
      end
    end

    last_text = context.last["text"]

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
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

    if data
      body["messages"] << {
        "role" => "user",
        "content" => data.strip
      }
      body["prediction"] = {
        "type" => "content",
        "content" => data.strip
      }
    end

    # initial prompt in the body is appended with the settings["system_prompt_suffix"
    if initial_prompt != "" && obj["system_prompt_suffix"].to_s != ""
      new_text = initial_prompt + "\n\n" + obj["system_prompt_suffix"].strip
      body["messages"].first["content"].each do |content_item|
        if content_item["type"] == "text"
          content_item["text"] = new_text
        end
      end
    end

    if messages_containing_img
      body["model"] = "grok-2-vision-1212"
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
      begin
        status = res.status
        error_message = res.body.to_s
        res = { "type" => "error", "content" => "API ERROR: #{status} - #{error_message}" }
        block&.call res
        return [res]
      rescue StandardError
        res = { "type" => "error", "content" => "API ERROR" }
        block&.call res
        return [res]
      end
    end

    # return Array
    if !body["stream"]
      obj = JSON.parse(res.body)
      frag = obj.dig("choices", 0, "message", "content")
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      [obj]
    else
      process_json_data(app: app,
                        session: session,
                        query: body,
                        res: res.body,
                        call_depth: call_depth, &block)
    end
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

  def check_citations(text, citations)
    used_citations = text.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq.sort

    citation_map = used_citations.each_with_index.to_h { |old_num, index| [old_num, index + 1] }

    newtext = text.gsub(/\[(\d+)\]/) do |match|
      "[#{citation_map[$1.to_i]}]"
    end

    new_citations = if used_citations
                      used_citations.compact.map { |i| citations[i - 1] }
                    else
                      []
                    end

    [newtext, new_citations]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]

    buffer = String.new
    texts = {}
    thinking = []
    tools = {}
    finish_reason = nil
    started = false
    current_json = nil
    stopped = false
    json = nil

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      first_iteration = true


      while (match = buffer.match(/^data: (\{.*?\})\r\n/m))
        json_str = match[1]
        buffer = buffer[match[0].length..-1]

        begin
          json = JSON.parse(json_str)

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts(JSON.pretty_generate(json))
          end

          finish_reason = json.dig("choices", 0, "finish_reason")
          delta = json.dig("choices", 0, "delta")

          if delta && delta["content"]
            id = json["id"]
            texts[id] ||= json
            choice = texts[id]["choices"][0]
            choice["message"] ||= delta.dup
            choice["message"]["content"] ||= ""

            fragment = delta["content"].to_s
            choice["message"]["content"] << fragment

            res = {
              "type" => "fragment",
              "content" => fragment
            }
            block&.call res

            texts[id]["choices"][0].delete("delta")
          elsif delta && delta["tool_calls"]
            res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
            block&.call res

            tid = delta["tool_calls"][0]["id"]
            if tid
              tools[tid] = json
              tools[tid]["choices"][0]["message"] ||= tools[tid]["choices"][0]["delta"].dup
              tools[tid]["choices"][0].delete("delta")
            end
          end

          # This comment-out is due to the lack of finish_reason in the JSON response from "sonar-pro"
          if json["choices"][0]["finish_reason"] == "stop"
            texts.first[1]["choices"][0]["message"]["content"] = json["choices"][0]["message"]["content"].gsub(/<think>(.*?)<\/think>\s+/m) do
              thinking << $1
              ""
            end

            citations = json["citations"] if json["citations"]
            new_text, new_citations = check_citations(texts.first[1]["choices"][0]["message"]["content"], citations)
            # add citations to the last message
            if citations && citations.any?
              citation_text = "\n\n<div data-title='Citations' class='toggle'><ol>" + new_citations.map.with_index do |citation, i|
                "<li><a href='#{citation}' target='_blank' rel='noopener noreferrer'>#{CGI.unescape(citation)}</a></li>"
              end.join("\n") + "</ol></div>"
              texts.first[1]["choices"][0]["message"]["content"] = new_text + citation_text
            end
            stopped = true
            break
          end

        rescue JSON::ParserError => e
          pp "JSON parse error: #{e.message}"
          buffer = "data: #{json_str}" + buffer
          break
        end
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    if json && !stopped
      stopped = true
      citations = json["citations"] if json["citations"]
      new_text, new_citations = check_citations(texts.first[1]["choices"][0]["message"]["content"], citations)
      # add citations to the last message
      if citations.any?
        citation_text = "\n\n<div data-title='Citations' class='toggle'><ol>" + new_citations.map.with_index do |citation, i|
          "<li><a href='#{citation}' target='_blank' rel='noopener noreferrer'>#{CGI.unescape(citation)}</a></li>"
        end.join("\n") + "</ol></div>"
        texts.first[1]["choices"][0]["message"]["content"] = new_text + citation_text
      end
    end

    thinking_result = thinking.empty? ? nil : thinking.join("\n\n")
    text_result = texts.empty? ? nil : texts.first[1]

    if text_result
      if obj["monadic"]
        choice = text_result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          modified = APPS[app].monadic_map(message)
          choice["text"] = modified
        end
      end
    end

    if tools.any?
      context = []
      if text_result
        merged = text_result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
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

      if text_result && new_results
        [text_result].concat new_results
      elsif new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      text_result["choices"][0]["finish_reason"] = finish_reason
      text_result["choices"][0]["thinking"] = thinking_result.strip if thinking_result
      [text_result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  rescue StandardError => e
    pp "Error in process_json_data: #{e.message}"
    pp e.backtrace
    res = { "type" => "error", "content" => "ERROR: #{e.message}" }
    block&.call res
    [res]
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
