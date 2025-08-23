# frozen_string_literal: false

require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"

module MistralHelper
  include InteractionUtils
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  API_ENDPOINT   = "https://api.mistral.ai/v1"
  OPEN_TIMEOUT   = 5
  READ_TIMEOUT   = 60
  WRITE_TIMEOUT  = 60
  MAX_RETRIES    = 5
  RETRY_DELAY    = 1

  EXCLUDED_MODELS = [
    "embed",
    "moderation",
    "open-mistral-7b",
    "mistral-tiny"
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

    IMPORTANT: You MUST use the tavily_search function to search for information about any topic, person, or subject that you don't have reliable information about. DO NOT make up or hallucinate information.

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    When asked about specific people, companies, or any factual information, ALWAYS use tavily_search first before responding.


    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from the web search results as possible to provide the user with the most up-to-date and relevant information.
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
    api_key = CONFIG["MISTRAL_API_KEY"]
    return Monadic::Utils::ErrorFormatter.api_key_error(
      provider: "Mistral",
      env_var: "MISTRAL_API_KEY"
    ) if api_key.nil?
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Get the requested model
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    
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
    
    # Check if this is a reasoning model (magistral models)
    is_reasoning_model = model && model.match?(/magistral/i)
    
    # Prepare request body
    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 1000,
      "messages" => messages,
      "safe_prompt" => false
    }
    
    # For reasoning models, use reasoning_effort instead of temperature
    if is_reasoning_model && options["reasoning_effort"]
      body["reasoning_effort"] = options["reasoning_effort"]
    else
      # For non-reasoning models, use temperature
      body["temperature"] = options["temperature"] || 0.7
    end
    
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
        
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Mistral",
          message: "Unexpected response format"
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Mistral",
          message: e.message
        )
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
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Mistral",
          message: error_message,
          code: res.status.code
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Mistral",
          message: "Failed to parse error response"
        )
      end
    end
  rescue => e
    return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Mistral",
          message: e.message
        )
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0
    begin
      api_key = CONFIG["MISTRAL_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Mistral",
        env_var: "MISTRAL_API_KEY"
      )
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

    # Handle both string and boolean values for websearch parameter
    websearch = obj["websearch"] == "true" || obj["websearch"] == true
    
    # Debug logging for websearch
    DebugHelper.debug("Mistral websearch enabled: #{websearch}", category: :api, level: :info) if websearch

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
          res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)

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

    # Check if this is a reasoning model (magistral models)
    is_reasoning_model = obj["model"] && obj["model"].match?(/magistral/i)
    
    # Set body for the API request
    body = {
      "model" => obj["model"],
      "messages" => []
    }
    
    # For reasoning models, use reasoning_effort instead of temperature
    if is_reasoning_model && obj["reasoning_effort"]
      body["reasoning_effort"] = obj["reasoning_effort"]
      # Log if extra logging is enabled
      DebugHelper.debug("Mistral: Using reasoning_effort '#{obj["reasoning_effort"]}' for model #{obj["model"]}", category: :api, level: :info)
    else
      # For non-reasoning models, use temperature
      body["temperature"] = temperature || 0.7
    end

    body["stream"] = true

    # Set the max tokens
    body["max_tokens"] = max_tokens || 4096

    # Configure monadic response format using unified interface
    body = configure_monadic_response(body, :mistral, app)

    # Skip tool setup if we're processing tool results
    if role != "tool"
      # Get tools from app settings
      app_tools = APPS[app]&.settings&.[]("tools")
      
      # Add tools if available
      if obj["tools"] && !obj["tools"].empty?
        body["tools"] = app_tools || []
        # Add websearch tools if websearch is enabled
        if websearch && body["tools"]
          body["tools"] = body["tools"] + WEBSEARCH_TOOLS
          body["tools"].uniq! { |tool| tool.dig(:function, :name) }
          
          # Add websearch prompt to system message (skip for Research Assistant which has its own prompt)
          unless app.to_s.include?("ResearchAssistant")
            system_msg = context.first
            if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
              system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
              system_msg["websearch_added"] = true
              DebugHelper.debug("Added WEBSEARCH_PROMPT to system message", category: :api, level: :debug)
            end
          end
          
        end
    elsif app_tools && !app_tools.empty?
      # If no tools param but app has tools, use them
      body["tools"] = app_tools
      # Add websearch tools if websearch is enabled
      if websearch
        body["tools"] = body["tools"] + WEBSEARCH_TOOLS
        body["tools"].uniq! { |tool| tool.dig(:function, :name) }
        
        # Add websearch prompt to system message (skip for Research Assistant which has its own prompt)
        unless app.to_s.include?("ResearchAssistant")
          system_msg = context.first
          if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
            system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
            system_msg["websearch_added"] = true
            DebugHelper.debug("Added WEBSEARCH_PROMPT to system message", category: :api, level: :debug)
          end
        end
      end
      DebugHelper.debug("Mistral tools: #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS
      DebugHelper.debug("Mistral websearch tools: #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)

      # Add websearch prompt to system message (skip for Research Assistant which has its own prompt)
      unless app.to_s.include?("ResearchAssistant")
        system_msg = context.first
        if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
          system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
          system_msg["websearch_added"] = true
          DebugHelper.debug("Added WEBSEARCH_PROMPT to system message", category: :api, level: :debug)
        end
      end
      
    end
    end  # end of role != "tool"

    # Add all messages to body
    system_message_modified = false
    body["messages"] = context.reject do |msg|
                         msg["role"] == "tool"
                       end.map do |msg|
      # Special handling for system messages with language injection
      if msg["role"] == "system" && !system_message_modified
        system_message_modified = true
        content_parts = [msg["text"]]
        
        # Add language preference if set
        if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
          language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
          content_parts << language_prompt if !language_prompt.empty?
        end
        
        { "role" => msg["role"], "content" => content_parts.join("\n\n---\n\n") }
      # Check if message contains images
      elsif msg["images"] && msg["role"] == "user"
        content = []
        
        # Add text content
        content << {
          "type" => "text",
          "text" => msg["text"]
        }
        
        # Add images
        msg["images"].each do |img|
          content << {
            "type" => "image_url", 
            "image_url" => img["data"]  # Mistral expects the URL/base64 string directly
          }
        end
        
        { "role" => msg["role"], "content" => content }
      else
        # Simple text-only format
        { "role" => msg["role"], "content" => msg["text"] }
      end
    end
    
    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      # Generic prompt that asks the assistant to follow system instructions
      initial_message = "Please proceed according to your system instructions and introduce yourself."
      
      body["messages"] << {
        "role" => "user",
        "content" => initial_message
      }
    end
    
    # Apply monadic transformation to the last user message if in monadic mode
    if obj["monadic"].to_s == "true" && body["messages"].any? && 
       body["messages"].last["role"] == "user" && role == "user"
      last_msg = body["messages"].last
      if last_msg["content"].is_a?(Array)
        # Handle structured content with images
        text_part = last_msg["content"].find { |part| part["type"] == "text" }
        if text_part
          monadic_message = apply_monadic_transformation(text_part["text"], app, "user")
          text_part["text"] = monadic_message
        end
      else
        # Handle simple text content
        monadic_message = apply_monadic_transformation(last_msg["content"], app, "user")
        last_msg["content"] = monadic_message
      end
    end

    if role == "tool"
      # For Mistral, we need to include the assistant message with tool calls
      # before adding tool responses
      if obj["tool_calls_message"]
        body["messages"] << obj["tool_calls_message"]
      end
      
      # Add the function response to the body
      body["messages"] += obj["function_returns"].map do |resp|
        # Ensure content is never nil
        content = resp[:content] || resp["content"] || "No result returned"
        { "role" => "tool",
          "content" => content.to_s,
          "tool_call_id" => resp[:tool_call_id] || resp["tool_call_id"],
          "name" => resp[:name] || resp["name"] }
      end
    end

    # Set up API endpoint
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    # Log extra information if enabled
    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("Processing Mistral query at #{Time.now} (Call depth: #{call_depth})")
        log.puts(JSON.pretty_generate(body))
      end
    end

    begin
      res = http.timeout(connect: OPEN_TIMEOUT,
                        write: WRITE_TIMEOUT,
                        read: READ_TIMEOUT).post(target_uri, json: body)

      unless res.status.success?
        err_json = JSON.parse(res.body)
        formatted_error = format_api_error(err_json, "mistral")
        error_message = Monadic::Utils::ErrorFormatter.api_error(
          provider: "Mistral",
          message: error_report["message"] || "Unknown API error",
          code: res.status.code
        )
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
        error_message = Monadic::Utils::ErrorFormatter.network_error(
          provider: "Mistral",
          message: "Request timed out",
          timeout: true
        )
        res = { "type" => "error", "content" => error_message }
        block&.call res
        return [res]
      end
    end

    # Log response status if extra logging is enabled
    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("Response status: #{res.status}")
        log.puts("Response headers: #{res.headers.to_h}")
        log.puts("About to process streaming response...")
      end
    end

    # Process the response line by line
    buffer = ""
    content_buffer = ""
    thinking_buffer = ""
    thinking = []
    tool_calls = []
    tool_use_content = nil
    last_tool_use_start_idx = nil
    error_buffer = []
    finish_reason = nil

    res.body.each do |chunk|
      # Handle encoding issues
      begin
        chunk = chunk.force_encoding("UTF-8")
        unless chunk.valid_encoding?
          chunk = chunk.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
        end
      rescue => e
        DebugHelper.debug("Encoding error in chunk: #{e.message}", category: :api, level: :error)
        next
      end

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
              
              
              # Check if this is a Magistral model and process thinking blocks
              # Updated pattern to match magistral-medium-latest
              if obj["model"] && obj["model"].match?(/magistral/i)
                # Debug logging for Magistral model detection
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("Mistral: Processing content for Magistral model: #{obj["model"]}", category: :api, level: :debug) if content_buffer.length == 0
                end
                # For Magistral models, collect all content and process thinking blocks later
                content_buffer += content
                
                # Don't send content to client yet - we'll process it after streaming is complete
                # This is necessary because <think> tags may be split across multiple chunks
              else
                # Non-Magistral models, process normally
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
        # Send notice fragment
        res = { "type" => "fragment", "content" => "\n\nNOTICE: Maximum function call depth exceeded" }
        block&.call res
        
        # Create a mock HTML response to properly end the conversation
        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
        return [{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }]
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
          function_return = Monadic::Utils::ErrorFormatter.tool_error(
            provider: "Mistral",
            tool_name: function_name,
            message: e.message
          )
        end

        # Add to function returns with proper encoding
        content = if function_return.is_a?(Hash) || function_return.is_a?(Array)
                    JSON.generate(function_return)
                  else
                    function_return.to_s
                  end
        # Ensure content is not nil or empty
        content = "No result returned" if content.nil? || content.empty?
        # Ensure UTF-8 encoding
        content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') unless content.valid_encoding?
        
        function_returns << {
          tool_call_id: tool_call["id"],
          role: "tool",
          name: function_name,
          content: content
        }
      end

      # Create assistant message with tool calls for Mistral's message ordering
      # Note: Mistral requires content field even if empty for tool calls
      tool_calls_message = {
        "role" => "assistant",
        "content" => content_buffer,
        "tool_calls" => tool_calls.map do |tc|
          {
            "id" => tc["id"],
            "type" => "function",
            "function" => tc["function"]
          }
        end
      }
      
      # Update session with function returns and tool calls message
      session[:parameters]["function_returns"] = function_returns
      session[:parameters]["tool_calls_message"] = tool_calls_message

      # Make recursive API call with tool responses
      return api_request("tool", session, call_depth: call_depth, &block)
    end

    # Finish up the standard response
    res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
    block&.call res

    # Clean content for Magistral models
    final_content = content_buffer
    if obj["model"] && obj["model"].match?(/magistral/i)
      # Extract thinking blocks from the complete content buffer
      if content_buffer.include?("<think>") || content_buffer.include?("<thinking>")
        # Extract all thinking blocks
        thinking_matches = content_buffer.scan(/<think>(.*?)<\/think>/m)
        thinking_matches += content_buffer.scan(/<thinking>(.*?)<\/thinking>/m)
        
        thinking_matches.each do |match|
          thinking_content = match[0].strip
          thinking << thinking_content
        end
        
        # Remove thinking blocks from final content
        final_content = content_buffer.gsub(/<think>.*?<\/think>/m, '')
        final_content = final_content.gsub(/<thinking>.*?<\/thinking>/m, '')
      end
      
      # Remove any remaining \boxed{} and \text{} formatting
      final_content = final_content.gsub(/\\boxed\{([^}]+)\}/, '\1')
      final_content = final_content.gsub(/\\text\{([^}]+)\}/, '\1')
    end
    
    # Prepare the result to return
    response = {
      "id" => SecureRandom.hex(12),
      "choices" => [
        {
          "message" => {
            "content" => final_content,
            "role" => "assistant"
          },
          "finish_reason" => finish_reason || "stop"
        }
      ]
    }

    # Add thinking if collected
    if thinking && !thinking.empty?
      response["choices"][0]["message"]["thinking"] = thinking.join("\n\n")
      # Debug logging for thinking content
      if CONFIG["EXTRA_LOGGING"]
        DebugHelper.debug("Mistral: Collected #{thinking.length} thinking block(s) for #{obj["model"]}", category: :api, level: :info)
      end
    end

    # Apply monadic transformation if enabled
    if obj["monadic"] && final_content
      # Process through unified interface
      processed = process_monadic_response(final_content, app)
      # Validate the response
      validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
      response["choices"][0]["message"]["content"] = validated.is_a?(Hash) ? JSON.generate(validated) : validated
    end

    [response]
  rescue StandardError => e
    # Log and return error
    error_message = Monadic::Utils::ErrorFormatter.api_error(
      provider: "Mistral",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => error_message }
    block&.call res
    [res]
  end
end
