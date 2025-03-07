# frozen_string_literal: false

module MistralHelper
  MAX_FUNC_CALLS = 8
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

  WEBSEARCH_TOOLS = [
    {
      type: "function",
      function:
      {
        name: "tavily_fetch",
        description: "fetch the content of the web page of the given url and return its content.",
        parameters: {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "url of the web page."
            }
          },
          required: ["url"]
        }
      }
    },
    {
      type: "function",
      function:
      {
        name: "tavily_search",
        description: "search the web for the given query and return the result. the result contains the answer to the query, the source url, and the content of the web page.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "query to search for."
            },
            n: {
              type: "integer",
              description: "number of results to return (default: 3)."
            }
          },
          required: ["query"]
        }
      }
    }
  ]

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT

  class << self
    attr_reader :cached_models

    def vendor_name
      "Mistral"
    end

    def list_models
      # Return cached models if available

      return $MODELS[:mistral] if $MODELS[:mistral]

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
          $MODELS[:mistral] = model_data["data"]
            .sort_by { |model| model["created"] }
            .reverse
            .map { |model| model["id"] }
            .reject do |model|
              EXCLUDED_MODELS.any? do |excluded|
                /\b#{excluded}\b/ =~ model ||
                  /[\d\-]+(?:rc\d+)?\z/ =~ model
              end
            end
          $MODELS[:mistral]
        else
          []
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear cache if needed

    def clear_models_cache
      $MODELS[:mistral] = nil
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

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"

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
        res["content"]["images"] = obj["images"] if obj["images"]
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

    websearch_prompto_added = false
    messages = context.compact.map do |msg|
      if websearch && !websearch_prompto_added && msg["role"] == "system"
        text = msg["text"] + "\n\n" + WEBSEARCH_PROMPT
        websearch_prompto_added = true
      else
        text = msg["text"]
      end
      { "role" => msg["role"], "content" => text }
    end

    body = {
      "model"       => obj["model"],
      "temperature" => temperature,
      "safe_prompt" => false,
      "stream"      => true,
      "messages"    => messages
    }
    body["max_tokens"] = max_tokens if max_tokens

    # Add tool settings if available
    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = settings["tools"]
      body["tools"].push(*WEBSEARCH_TOOLS) if websearch
      body["tools"].uniq!
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS
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
          # if /\.pdf\z/ =~ img["title"]
          #   message["content"] << {
          #     "type" => "document_url",
          #     "document_url" => img["data"]
          #   }
          # else
            message["content"] << {
              "type" => "image_url",
              "image_url" => {
                "url" => img["data"],
                "detail" => "high"
              }
            }
          # end
        end
      end
      message
    end

    body["model"] = /pixtral/ =~ obj["model"] ? obj["model"] : "pixtral-large-latest"

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user" && settings["prompt_suffix"]
      prompt_suffix_added = false
      body["messages"].reverse_each do |msg|
        msg["content"].each do |content|
          if content["type"] == "text"
            content["text"] += "\n\n" + settings["prompt_suffix"]
            prompt_suffix_added = true
            break
          end
        end
        break if prompt_suffix_added
      end
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

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: response.body,
                      call_depth: call_depth, &block)

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

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    buffer = ""
    texts  = {}
    tools  = {}
    finish_reason = nil

    # Process each chunk from the streaming response

    res.each do |chunk|
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

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts(JSON.pretty_generate(json))
          end

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

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

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

  def replace_references(text)
    text.gsub(/\[\{"type"=>"reference", "reference_ids"=>\[(.*?)\]\}\]/) do
      ids_str = $1
      ids = ids_str.split(',').map(&:strip)
      "[#{ids.join(', ')}]"
    end
  end

end
