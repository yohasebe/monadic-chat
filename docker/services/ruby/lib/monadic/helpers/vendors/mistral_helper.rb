# frozen_string_literal: false

module MistralHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT   = "https://api.mistral.ai/v1"
  OPEN_TIMEOUT   = 5
  READ_TIMEOUT   = 60
  WRITE_TIMEOUT  = 60
  MAX_RETRIES    = 5
  RETRY_DELAY    = 1

  EXCLUDED_MODELS = [
    "embed",
    "moderation",
    "open",
    "medium",
    "small",
    "tiny",
    "pixtral-12b"
  ]

  class << self
    attr_reader :cached_models

    def vendor_name
      "Mistral"
    end

    def list_models
      # Return cached models if available

      return @cached_models if @cached_models

      api_key = CONFIG["MISTRAL_API_KEY"]
      return [] if api_key.nil?

      headers = {
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      target_uri = "#{API_ENDPOINT}/models"
      http = HTTP.headers(headers)

      begin
        response = http.get(target_uri)
        if response.status.success?
          # Cache filtered and sorted models

          model_data = JSON.parse(response.body)
          @cached_models = model_data["data"]
            .sort_by { |model| model["created"] }
            .reverse
            .map { |model| model["id"] }
            .reject do |model|
              EXCLUDED_MODELS.any? do |excluded|
                /\b#{excluded}\b/ =~ model ||
                  /[\d\-]+(?:rc\d+)?\z/ =~ model
              end
            end
          @cached_models
        else
          []
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear cache if needed

    def clear_models_cache
      @cached_models = nil
    end
  end

  # Non-streaming plain text completion/chat call

  def send_query(options, model: "mistral-large-latest")
    api_key = CONFIG["MISTRAL_API_KEY"]

    headers = {
      "Content-Type"  => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model"  => model,
      "stream" => false
    }.merge(options)

    target_uri = "#{API_ENDPOINT}/chat/completions"
    http = HTTP.headers(headers)

    response = nil
    MAX_RETRIES.times do
      response = http.timeout(connect: OPEN_TIMEOUT,
                              write: WRITE_TIMEOUT,
                              read: READ_TIMEOUT)
        .post(target_uri, json: body)
      break if response.status.success?

      sleep RETRY_DELAY
    end

    if response && response.status && response.status.success?
      begin
        parsed_response = JSON.parse(response.body)
        parsed_response.dig("choices", 0, "message", "content")
      rescue JSON::ParserError => e
        "ERROR: Failed to parse response JSON: #{e.message}"
      end
    else
      error_response = begin
                         response && response.body ? JSON.parse(response.body) : { "error" => "No response received" }
                       rescue JSON::ParserError => e
                         { "error" => "Failed to parse error response JSON: #{e.message}" }
                       end
      pp error_response
      "ERROR: #{error_response["error"]}"
    end
  rescue StandardError => e
    "Error: The request could not be completed. (#{e.message})"
  end

  def api_request(role, session, call_depth: 0, &block)
    # Validate API key presence

    begin
      api_key = CONFIG["MISTRAL_API_KEY"]
      raise "API key missing" if api_key.nil?
    rescue StandardError
      error_msg = "ERROR: MISTRAL_API_KEY not found. Please set the MISTRAL_API_KEY environment variable in the ~/monadic/config/env file."
      pp error_msg
      res = { "type" => "error", "content" => error_msg }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    max_tokens   = obj["max_tokens"]&.to_i
    temperature  = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id   = SecureRandom.hex(4)

    if role != "tool"
      message = obj["message"].to_s
      html = message.empty? ? message : markdown_to_html(message)
      if !message.empty? && role == "user"
        res = {
          "type"    => "user",
          "content" => {
            "mid"  => request_id,
            "role" => role,
            "text" => message,
            "html" => html,
            "lang" => detect_language(obj["message"])
          }
        }
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Mark all previous messages as inactive

    session[:messages].each { |msg| msg["active"] = false }
    # Build conversation context

    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size + 1)
    end
    context.each { |msg| msg["active"] = true }

    headers = {
      "Content-Type"  => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model"       => obj["model"],
      "temperature" => temperature,
      "safe_prompt" => false,
      "stream"      => true,
      "messages"    => context.compact.map { |msg| { "role" => msg["role"], "content" => msg["text"] } }
    }
    body["max_tokens"] = max_tokens if max_tokens

    # Add tool settings if available

    if settings["tools"]
      body["tools"] = settings["tools"]
      body["tool_choice"] = "auto"
    else
      body.delete("tool_choice")
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user" && settings["prompt_suffix"]
      body["messages"].last["content"] += "\n\n" + settings["prompt_suffix"]
    end

    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    response = nil
    MAX_RETRIES.times do
      response = http.timeout(connect: OPEN_TIMEOUT,
                              write: WRITE_TIMEOUT,
                              read: READ_TIMEOUT)
        .post(target_uri, json: body)
      break if response.status.success?

      sleep RETRY_DELAY
    end

    unless response.status.success?
      error_report = JSON.parse(response.body) rescue { "error" => "Invalid JSON error response" }
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
        block&.call res
      return [res]
    end

    process_json_data(app, session, response.body, call_depth, &block)
  rescue HTTP::Error, HTTP::TimeoutError
    @num_retrial ||= 0
    if @num_retrial < MAX_RETRIES
      @num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_msg = "The request has timed out."
      pp error_msg
      res = { "type" => "error", "content" => "HTTP ERROR: #{error_msg}" }
        block&.call res
      [res]
    end
  rescue StandardError => e
    pp e.message, e.backtrace, e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
      block&.call res
    [res]
  end

  def process_json_data(app, session, body, call_depth, &block)
    # Initialize buffer and result holders

    buffer = ""
    texts  = {}
    tools  = {}
    finish_reason = nil

    # Process each chunk from the streaming response

    body.each do |chunk|
      # Ensure valid UTF-8 encoding; replace invalid sequences if needed

      chunk = chunk.force_encoding("UTF-8")
      chunk = chunk.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace)
      buffer << chunk

      # Process complete SSE events (events are delimited with double newline)

      while buffer.include?("\n\n")
        # Extract one complete event from the buffer

        event_end_index = buffer.index("\n\n")
        event_data = buffer.slice!(0, event_end_index + 2)

        # Split lines and extract those starting with "data:"

        event_lines = event_data.split("\n").map(&:strip).reject(&:empty?)
        data_lines  = event_lines.select { |line| line.start_with?("data:") }
        # Concatenate the data payload from all "data:" fields

        data_payload = data_lines.map { |line| line.sub(/^data:\s*/, "") }.join

        # Skip if payload is empty

        next if data_payload.empty?

        # Attempt to parse JSON payload; if incomplete, re-append back to buffer

        begin
          json = JSON.parse(data_payload)
        rescue JSON::ParserError
          buffer = data_payload + buffer
          break
        end

        # Determine finish_reason from JSON payload if provided

        if json.dig("choices", 0, "finish_reason")
          case json["choices"][0]["finish_reason"]
          when "length"
            finish_reason = "length"
          when "stop"
            finish_reason = "stop"
          when "tool_calls"
            finish_reason = "function_call"
          end
        end

        # Process text fragment if available in delta content

        if json.dig("choices", 0, "delta", "content")
          id = json["id"]
          texts[id] ||= json
          choice = texts[id]["choices"][0]
          # Initialize message content if not already present

          choice["message"] ||= {}
          choice["message"]["content"] ||= ""
          fragment = json.dig("choices", 0, "delta", "content").to_s
          choice["message"]["content"] << fragment

          # Callback with the text fragment

          res = { "type" => "fragment", "content" => fragment }
          block&.call res

          # Remove the delta field after processing

          texts[id]["choices"][0].delete("delta")
        end

        # Process function call instructions if any are present

        if json.dig("choices", 0, "delta", "tool_calls")
          res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
          block&.call res
          id = json["id"]
          tools[id] ||= json
          # Optionally initialize tool message if needed

          tools[id]["choices"][0]["message"] ||= {}
        end
      end
    end

    # Use a regular if-elsif-else chain instead of 'unless' to allow elsif usage

    if !tools.empty?
      # Process tool/function calls if any exist
      tool_call_data = tools.values.first
      tool_calls = tool_call_data.dig("choices", 0, "delta", "tool_calls")
      if tool_calls
        context = []
        res = {
          "role"    => "assistant",
          "content" => "The AI model is calling functions to process the data."
        }
        res["tool_calls"] = tool_calls.map do |tool|
          {
            "id"       => tool["id"],
            "type"     => "function",
            "function" => tool["function"]
          }
        end
        context << res

        # Increase call depth and check against max allowed calls

        call_depth += 1
        if call_depth > MAX_FUNC_CALLS
          error_res = [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
          block&.call error_res.first
          return error_res
        end

        # Process the functions and get new results recursively

        new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
        return new_results if new_results
        return [texts.values.first] unless texts.empty?
      end
    elsif !texts.empty?
      # Return the final result if text fragments have been accumulated

      final_text = texts.values.first
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      final_text["choices"][0]["finish_reason"] = finish_reason
      return [final_text]
    else
      # If no data processed, return a done message

      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      return [res]
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    # Process each tool call

    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      # Safely parse function call arguments

      begin
        argument_hash = JSON.parse(function_call["arguments"])
      rescue JSON::ParserError
        argument_hash = {}
      end

      # Convert argument keys to symbols

      converted = {}
      argument_hash.each { |k, v| converted[k.to_sym] = v }

      # Call the corresponding function and rescue errors if any

      begin
        function_return = APPS[app].send(function_name.to_sym, **converted)
      rescue StandardError => e
        function_return = "ERROR: #{e.message}"
      end

      # Append the function result to the context

      context << {
        role:         "tool",
        tool_call_id: tool_call["id"],
        name:         function_name,
        content:      function_return.to_s
      }
    end

    # Add function returns to the session parameters

    obj["function_returns"] = context

    # Wait briefly before re-invoking the API request with updated context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
