# frozen_string_literal: false

module DeepSeekHelper
  MAX_FUNC_CALLS = 8
  API_ENDPOINT = "https://api.deepseek.com"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  # websearch tools
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
          required: ["url"],
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
          required: ["query"],
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
      "DeepSeek"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:deepseek] if $MODELS[:deepseek]

      api_key = CONFIG["DEEPSEEK_API_KEY"]
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
          # Cache the filtered and sorted models
          model_data = JSON.parse(res.body)
          $MODELS[:deepseek] = model_data["data"].sort_by do |model|
            model["created"]
          end.reverse.map do |model|
            model["id"]
          end.filter do |model|
            !model.include?("embed")
          end
          $MODELS[:deepseek]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:deepseek] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "deepseek-chat")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["DEEPSEEK_API_KEY"] || ENV["DEEPSEEK_API_KEY"]
    return "Error: DEEPSEEK_API_KEY not found" if api_key.nil?
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Format messages
    messages = []
    
    if options["messages"]
      # Look for system message
      system_msg = options["messages"].find { |m| m["role"] == "system" }
      if system_msg
        messages << {
          "role" => "system",
          "content" => system_msg["content"].to_s
        }
      end
      
      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)
        
        content = msg["content"] || msg["text"] || ""
        messages << {
          "role" => msg["role"],
          "content" => content.to_s
        }
      end
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "stream" => false,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages
    }
    
    # Make request
    target_uri = "#{API_ENDPOINT}/chat/completions"
    http = HTTP.headers(headers)
    
    # Simple retry logic
    response = nil
    MAX_RETRIES.times do
      begin
        response = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)
        
        break if response && response.status && response.status.success?
      rescue HTTP::Error, HTTP::TimeoutError
        # Continue to next retry
      end
      
      sleep RETRY_DELAY
    end
    
    # Process response
    if response && response.status && response.status.success?
      begin
        parsed_response = JSON.parse(response.body)
        return parsed_response.dig("choices", 0, "message", "content") || "Error: No content in response"
      rescue => e
        return "Error: #{e.message}"
      end
    else
      begin
        error_data = response && response.body ? JSON.parse(response.body) : {}
        error_message = error_data["error"] || "Unknown error"
        return "Error: #{error_message}"
      rescue => e
        return "Error: Failed to parse error response"
      end
    end
  rescue => e
    return "Error: #{e.message}"
  end

  def api_request(role, session, call_depth: 0, &block)

    num_retrial = 0

    begin
      api_key = CONFIG["DEEPSEEK_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: DEEPSEEK_API_KEY not found. Please set the DEEPSEEK_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"

    if role != "tool"
      message = obj["message"].to_s

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => message,
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
        session[:messages] << res["content"]
      end
    end

    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size + 1)
    end

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => model,
      "stream" => true
    }

    body["max_tokens"] = max_tokens if max_tokens

    body["temperature"] = temperature

    system_message_modified = false
    body["messages"] = context.compact.map do |msg|
      if websearch && !system_message_modified && msg["role"] == "system" 
        system_message_modified = true
        { "role" => msg["role"], "content" => msg["text"] + "\n\n---\n\n" + WEBSEARCH_PROMPT }
      else
        { "role" => msg["role"], "content" => msg["text"] }
      end
    end

    if settings["tools"]
      body["tools"] = settings["tools"] || []
      if websearch
        websearch_tools = WEBSEARCH_TOOLS.dup
        body["tools"].concat(websearch_tools)
        body["tools"].uniq!
      end
      body["tool_choice"] = "auto"
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      body["messages"].last["content"] += "\n\n" + settings["prompt_suffix"] if settings["prompt_suffix"]
    end

    if obj["model"].include?("reasoner")
      body.delete("temperature")
      body.delete("tool_choice")
      body.delete("tools")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].map do |msg|
        msg["content"] = msg["content"].sub(/---\n\n/, "")
        msg
      end
    else
      if obj["monadic"] || obj["json"]
        body["response_format"] ||= { "type" => "json_object" }
      end
    end

    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      if res.status.success?
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

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
                      call_depth: call_depth, &block)
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

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]

    buffer = String.new.force_encoding("UTF-8")
    texts = {}
    tools = {}
    finish_reason = nil
    partial_json = nil
    first_message = true

    res.each do |chunk|
      begin
        chunk = chunk.force_encoding("UTF-8")
        if buffer.valid_encoding? == false
          buffer << chunk
          next
        end

        if !chunk.force_encoding("UTF-8").valid_encoding?
          chunk = chunk.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace)
        end

        # Process partial JSON if exists
        if partial_json
          buffer = partial_json + chunk
        else
          buffer << chunk
        end

        # Try to extract complete JSON messages
        messages = extract_complete_messages(buffer)
        
        if messages.empty?
          # If no complete messages found, retain buffer and wait for next chunk
          partial_json = buffer
          next
        else
          # If the last message is incomplete, keep it for next processing
          last_message = messages.pop if !is_complete_json(messages.last)
          partial_json = last_message
          
          messages.each do |msg|
            begin
              data_content = msg.match(/data: (\{.*\})/m)
              return unless data_content && data_content[1]

              json = JSON.parse(data_content[1])

              if CONFIG["EXTRA_LOGGING"]
                extra_log.puts(JSON.pretty_generate(json))
              end

              # Process finish reason
              finish_reason = json.dig("choices", 0, "finish_reason")
              case finish_reason
              when "length"
                finish_reason = "length"
              when "stop"
                finish_reason = "stop"
              when "tool_calls"
                finish_reason = "function_call"
              else
                finish_reason = nil
              end

              # Process text content
              if json.dig("choices", 0, "delta")
                delta = json["choices"][0]["delta"]
                
                if delta["reasoning_content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["reasoning_content"] ||= ""
                  choice["message"]["content"] ||= ""

                  fragment = delta["reasoning_content"].to_s
                  choice["message"]["reasoning_content"] << fragment

                  res = {
                    "type" => "thinking",
                    "content" => fragment
                  }
                  block&.call res

                  texts[id]["choices"][0].delete("delta")
                elsif delta["content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["content"] ||= ""

                  fragment = delta["content"].to_s
                  choice["message"]["content"] << fragment

                  if fragment.length > 0
                    res = {
                      "type" => "fragment",
                      "content" => fragment,
                      "index" => choice["message"]["content"].length - fragment.length,
                      "timestamp" => Time.now.to_f,
                      "is_first" => choice["message"]["content"].length == fragment.length
                    }
                    block&.call res
                  end

                  texts[id]["choices"][0].delete("delta")
                end

                # Process tool calls
                if delta["tool_calls"]
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
              end
            rescue JSON::ParserError => e
              pp "JSON parse error in message: #{e.message}"
            end
          end
        end

        buffer = String.new

      rescue StandardError => e
        pp e.message
        pp e.backtrace
        next
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

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
      # Handle tool/function calls
      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")
      context = []
      res = {
        "role" => "assistant",
        "content" => "The AI model is calling functions to process the data."
      }
      res["tool_calls"] = tools.map do |tool|
        {
          "id" => tool["id"],
          "type" => "function",
          "function" => tool["function"]
        }
      end
      context << res

      # Check for maximum function call depth
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      # Process function calls and get new results
      new_results = process_functions(app, session, tools, context, call_depth, &block)

      if new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      # Return final result with finish reason
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      text_result["choices"][0]["finish_reason"] = finish_reason
      [text_result]
    else
      # Return done message if no result
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  private

  def extract_complete_messages(buffer)
    # Split by data message boundary pattern
    messages = buffer.split(/(?<=\n\n)(?=data: )/)
    messages.select { |msg| msg.start_with?('data: ') }
  end

  def is_complete_json(message)
    return false unless message.start_with?('data: ')
    
    begin
      data_content = message.match(/data: (\{.*\})/m)
      return false unless data_content && data_content[1]
      
      json = JSON.parse(data_content[1])
      
      # Check if JSON structure meets expectations
      return false unless json["choices"]&.first&.key?("delta")
      
      true
    rescue JSON::ParserError
      false
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
      if converted.empty?
        function_return = APPS[app].send(function_name.to_sym)
      else
        function_return = APPS[app].send(function_name.to_sym, **converted)
      end
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
end
