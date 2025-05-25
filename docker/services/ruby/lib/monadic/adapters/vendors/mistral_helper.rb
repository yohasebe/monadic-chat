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

  # Simple non-streaming chat completion
  def send_query(options, model: "mistral-large-latest")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["MISTRAL_API_KEY"] || ENV["MISTRAL_API_KEY"]
    return "Error: MISTRAL_API_KEY not found" if api_key.nil?
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Get the requested model
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "MistralHelper.send_query: Using model: #{model}"
    end
    
    # Format messages with validation
    messages = []
    
    if options["messages"]
      # Debug logging is handled by dedicated log files
      
      # Validate and normalize messages
      options["messages"].each do |msg|
        content = msg["content"] || msg["text"] || ""
        next if content.to_s.strip.empty? # Skip empty messages
        
        # Normalize role to valid Mistral roles
        role = msg["role"].to_s.downcase
        
        # Mistral only supports user, assistant, and system roles
        unless ["user", "assistant", "system"].include?(role)
          role = "user" # Default unknown roles to user
        end
        
        messages << {
          "role" => role,
          "content" => content.to_s
        }
      end
      
      # Ensure we have at least one message and that the last message is from user
      if messages.empty?
        messages << {
          "role" => "user",
          "content" => "Hello, I'd like to have a conversation."
        }
      elsif messages.last["role"] != "user"
        # Add a user message if the last message is not from user
        messages << {
          "role" => "user",
          "content" => "Please continue with this conversation."
        }
      end
      
      # Detailed logs are maintained in dedicated log files
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages,
      "safe_prompt" => false
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
        
        # Standard OpenAI-compatible format
        if parsed_response["choices"] && 
           parsed_response["choices"][0] && 
           parsed_response["choices"][0]["message"]
          
          return parsed_response["choices"][0]["message"]["content"].to_s
        end
        
        return "Error: Unexpected response format"
      rescue => e
        return "Error: #{e.message}"
      end
    else
      begin
        # Error details are logged to dedicated log files
        
        error_data = response && response.body ? JSON.parse(response.body.to_s) : {}
        error_message = if error_data["error"] && error_data["error"].is_a?(Hash)
                         error_data["error"]["message"] || "Unknown error"
                       else
                         error_data["error"] || "Unknown error"
                       end
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
      api_key = CONFIG["MISTRAL_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      error_message = "ERROR: MISTRAL_API_KEY not found. Please set the MISTRAL_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get parameters from session
    obj = session[:parameters]
    app = obj["app_name"]

    # Handle max_tokens with AI_USER_MAX_TOKENS for AI User mode
    if obj["ai_user"] == "true"
      max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || obj["max_tokens"]&.to_i
    else
      max_tokens = obj["max_tokens"]&.to_i
    end

    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = obj["websearch"] == "true"

    if role != "tool"
      message = obj["message"].to_s

      if message != ""
        html = markdown_to_html(message)

        if message != "" && role == "user"
          res = { "type" => "user",
                  "content" => {
                    "mid" => request_id,
                    "role" => role,
                    "text" => message,
                    "html" => html,
                    "lang" => detect_language(message)
                  } }
          res["content"]["images"] = obj["images"] if obj["images"]

          block&.call res
          session[:messages] << res["content"]
        end
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

    # Set headers for API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set body for the API request
    body = {
      "model" => obj["model"],
      "temperature" => temperature || 0.7,
      "messages" => []
    }

    body["stream"] = true

    # Set the max tokens
    body["max_tokens"] = max_tokens || 4096

    # Add tools if available
    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS

      # Add websearch prompt to system message
      system_msg = context.first
      if system_msg && system_msg["role"] == "system"
        system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
      end
    end

    # Add all messages to body
    body["messages"] = context.reject do |msg|
                         msg["role"] == "tool"
                       end.map do |msg|
      { "role" => msg["role"],
        "content" => msg["text"] }
    end

    if role == "tool"
      # Add the function response to the body
      body["messages"] += obj["function_returns"].map do |resp|
        { "role" => "tool",
          "content" => resp["content"],
          "tool_call_id" => resp["tool_call_id"],
          "name" => resp["name"] }
      end
    end

    # Set up API endpoint
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    begin
      res = http.timeout(connect: OPEN_TIMEOUT,
                        write: WRITE_TIMEOUT,
                        read: READ_TIMEOUT).post(target_uri, json: body)

      unless res.status.success?
        err_json = JSON.parse(res.body)
        error_message = "API ERROR: #{err_json["error"]["message"]}" rescue "API ERROR: API call failed: #{res.status}"
        res = { "type" => "error", "content" => error_message }
        block&.call res
        return [res]
      end
    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        sleep RETRY_DELAY
        retry
      else
        error_message = "ERROR: The request has timed out."
        res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
        block&.call res
        return [res]
      end
    end

    # Process the response line by line
    buffer = ""
    content_buffer = ""
    thinking_buffer = ""
    tool_calls = []
    tool_use_content = nil
    last_tool_use_start_idx = nil
    error_buffer = []
    finish_reason = nil

    res.body.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")

      if /\A\s*data:\s+\[DONE\]\s*\z/ =~ chunk
        # Handle stream end
        break
      end

      # Skip empty data chunks
      next if /\A\s*data:\s*\z/ =~ chunk || chunk.strip.empty?

      # Remove data: prefix if present
      chunk.sub!(/\A\s*data:\s+/, "")

      buffer += chunk
      scanner = StringScanner.new(buffer)

      while scanner.scan_until(/\{.*?\}(?=\n|\z)/m)
        json_str = scanner.matched
        begin
          json = JSON.parse(json_str)

          # Extract id for future reference
          chunk_id = json["id"]

          # Check for errors
          if json["error"]
            error_buffer << json["error"]["message"] || "Unknown error"
            next
          end

          # Extract content from delta if present
          if json["choices"] && json["choices"][0] && json["choices"][0]["delta"]
            delta = json["choices"][0]["delta"]

            # Check if this delta contains content
            if delta["content"]
              content = delta["content"]
              content_buffer += content

              # Send content to the client
              if content.length > 0
                res = {
                  "type" => "fragment",
                  "content" => content,
                  "index" => content_buffer.length - content.length,
                  "timestamp" => Time.now.to_f,
                  "is_first" => content_buffer.length == content.length
                }
                block&.call res
              end
            end

            # Check for tool calls
            if delta["tool_calls"] && !delta["tool_calls"].empty?
              tool_call = delta["tool_calls"][0]

              # If this is a new tool call, create a new entry
              if tool_call["index"] && (tool_calls[tool_call["index"]].nil? || tool_call["id"])
                tool_calls[tool_call["index"]] = {
                  "id" => tool_call["id"],
                  "function" => {
                    "name" => tool_call.dig("function", "name"),
                    "arguments" => tool_call.dig("function", "arguments") || ""
                  }
                }
              # Otherwise append to existing tool call
              elsif tool_call["index"]
                index = tool_call["index"]
                if tool_call.dig("function", "arguments")
                  tool_calls[index]["function"]["arguments"] += tool_call.dig("function", "arguments")
                end
              end

              # If this is a new tool call, inform the client
              if tool_call["index"] && tool_call["id"]
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              end
            end

            # Check for finish reason
            if json["choices"] && json["choices"][0] && json["choices"][0]["finish_reason"]
              finish_reason = json["choices"][0]["finish_reason"]
            end
          end
        rescue JSON::ParserError
          # Skip malformed JSON
        end
      end

      # Keep any unprocessed content for next iteration
      buffer = scanner.rest
    end

    # Once done with the main content, process any tool calls
    if tool_calls && !tool_calls.empty?
      # Process each tool call
      call_depth += 1

      if call_depth > MAX_FUNC_CALLS
        # Avoid excessive function calls
        res = { "type" => "fragment", "content" => "\n\nMAXIMUM FUNCTION CALL DEPTH EXCEEDED" }
        block&.call res
        return []
      end

      # Process tool calls
      function_returns = []
      tool_calls.each do |tool_call|
        next unless tool_call # Skip nil entries

        # Extract function details
        function_name = tool_call.dig("function", "name")
        function_args = tool_call.dig("function", "arguments")

        # Parse arguments
        begin
          args = JSON.parse(function_args)
        rescue JSON::ParserError
          # Handle malformed JSON
          args = {}
        end

        # Convert to symbols
        args_hash = {}
        args.each do |k, v|
          args_hash[k.to_sym] = v
        end

        # Call the function
        begin
          if args_hash.empty?
            function_return = APPS[app].send(function_name.to_sym)
          else
            function_return = APPS[app].send(function_name.to_sym, **args_hash)
          end
        rescue StandardError => e
          # Function call failed
          function_return = "ERROR: #{e.message}"
        end

        # Add to function returns
        function_returns << {
          tool_call_id: tool_call["id"],
          role: "tool",
          name: function_name,
          content: function_return.to_s
        }
      end

      # Update session with function returns
      session[:parameters]["function_returns"] = function_returns

      # Make recursive API call with tool responses
      new_results = api_request("tool", session, call_depth: call_depth, &block)
      
      # Wrap up the call with "DONE" message
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      
      return new_results
    end

    # Finish up the standard response
    res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
    block&.call res

    # Prepare the result to return
    response = {
      "id" => SecureRandom.hex(12),
      "choices" => [
        {
          "message" => {
            "content" => content_buffer,
            "role" => "assistant"
          },
          "finish_reason" => finish_reason || "stop"
        }
      ]
    }

    # Add thinking if collected
    if thinking_buffer && !thinking_buffer.empty?
      response["choices"][0]["message"]["thinking"] = thinking_buffer
    end

    [response]
  rescue StandardError => e
    # Log and return error
    error_message = "ERROR: #{e.message}"
    res = { "type" => "error", "content" => error_message }
    block&.call res
    [res]
  end
end
