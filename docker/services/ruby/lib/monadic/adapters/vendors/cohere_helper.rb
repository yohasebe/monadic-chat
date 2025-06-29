# frozen_string_literal: true
require_relative "../../utils/interaction_utils"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"

module CohereHelper
  include InteractionUtils
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  # API endpoint and configuration constants
  API_ENDPOINT = "https://api.cohere.ai/v2"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  VALID_ROLES = %w[user assistant system tool].freeze

  # websearch tools
  WEBSEARCH_TOOLS = [
    {
      type: "function",
      function: {
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
      function: {
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
          required: ["query", "n"]
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
      "Cohere"
    end

    # Fetches available models from Cohere API
    # Returns an array of model names, excluding embedding and reranking models
    def list_models
      # Return cached models if they exist
      return $MODELS[:cohere] if $MODELS[:cohere]

      api_key = CONFIG["COHERE_API_KEY"]
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
          # Cache the filtered models
          model_data = JSON.parse(res.body)
          $MODELS[:cohere] = model_data["models"].map do |model|
            model["name"]
          end.filter do |model|
            !model.include?("embed") && !model.include?("rerank")
          end
          $MODELS[:cohere]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:cohere] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "command-r-03-2025")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get the API key
    api_key = CONFIG["COHERE_API_KEY"]
    return "Error: COHERE_API_KEY not found" if api_key.nil?
    
    # Set the headers
    headers = {
      "accept" => "application/json",
      "content-type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Format messages for Cohere API
    messages = []
    
    # Process messages
    if options["messages"]
      # Add system message
      system_msg = options["messages"].find { |m| m["role"].to_s.downcase == "system" }
      if system_msg
        messages << {
          "role" => "user",
          "content" => "I want you to respond as if you were a user, not an assistant. " + system_msg["content"].to_s
        }
      end
      
      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)
        
        # Map standard roles to Cohere roles
        role = case msg["role"].to_s.downcase
               when "user" then "user"
               when "assistant" then "assistant"
               when "system" then "system"
               when "tool" then "tool"
               else "user" # Default to user for unknown roles
               end
        
        # Get content
        content = msg["content"] || msg["text"] || ""
        
        # Add to messages
        messages << {
          "role" => role,
          "content" => content.to_s
        }
      end
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 300,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages,
      "stream" => false
    }
    
    # Make request
    target_uri = "#{API_ENDPOINT}/chat"
    http = HTTP.headers(headers)
    response = nil
    
    # Simple retry logic
    MAX_RETRIES.times do |attempt|
      response = http.timeout(
        connect: OPEN_TIMEOUT,
        write: WRITE_TIMEOUT,
        read: READ_TIMEOUT
      ).post(target_uri, json: body)
      
      break if response&.status&.success?
      sleep RETRY_DELAY
    end

    # Process response
    if response&.status&.success?
      begin
        body_text = response.body.to_s
        result = JSON.parse(body_text)
        
        # Extract text from Cohere's specific response structure
        if result["message"] && result["message"]["content"] && result["message"]["content"].is_a?(Array)
          # Get text from content array (v2 API format)
          text_items = result["message"]["content"].select { |item| item["type"] == "text" }
          if text_items.any?
            return text_items.map { |item| item["text"] }.join("\n")
          end
        end
        
        # Fall back to standard fields
        return result["text"] || result["message"] || result["generated_text"] || "Error: No text in response"
      rescue => e
        return "Error parsing response: #{e.message}"
      end
    else
      begin
        error_body = response&.body.to_s
        error_data = JSON.parse(error_body)
        error = error_data["message"] || "Unknown error"
        return "Error: #{error}"
      rescue => e
        return "Error: API error response"
      end
    end
  rescue => e
    return "Error: #{e.message}"
  end
  
  # Helper method to format messages for Cohere's API format
  def format_messages_for_cohere(options, model)
    # Initialize messages array for API request
    messages = []
    
    # Check for custom system message from the AI User feature first
    custom_system_message = options["custom_system_message"]
    
    # If we have a specially formatted conversation string, use that
    if custom_system_message
      log_to_extra("Using formatted conversation approach for Cohere")
      
      # For Cohere, we use a minimal message structure:
      # 1. System message containing our formatted conversation with the AI User prompt
      # 2. A simple user message to get the response
      
      # System prompt containing the AI User instructions and formatted conversation
      messages << {
        "role" => "SYSTEM",
        "message" => custom_system_message
      }
      
      # Add a simple query message to get the next user response
      messages << {
        "role" => "CHATBOT",
        "message" => "Based on the conversation history, what would be a natural response from the user now?"
      }
      
      log_to_extra("Created message structure with formatted conversation")
      log_to_extra("System message length: #{custom_system_message.size}")
      
      return messages
    
    # Otherwise, use the standard message-based approach
    elsif options["messages"] && options["messages"].is_a?(Array)
      # Log for debugging
      log_to_extra("Processing #{options['messages'].size} messages")
      
      # Make a copy of the messages for manipulation
      conversation_messages = options["messages"].dup
      
      # If there's a system prompt, use it (otherwise use the default AI_USER_INITIAL_PROMPT)
      system_prompt = MonadicApp::AI_USER_INITIAL_PROMPT
      if options["initial_prompt"]
        system_prompt = options["initial_prompt"].to_s
        log_to_extra("Using custom initial prompt")
      end
      
      # Add system prompt first as USER role
      # NOTE: For Cohere API v2, we need to use USER role with the system prompt
      # This fixes the issue with the system role treatment in Cohere's API
      messages << {
        "role" => "USER",
        "message" => "I want you to respond as if you were a user, not an assistant. " + system_prompt
      }
      
      # Make sure we add at least one more message
      # Cohere needs a clear conversation flow to respond properly
      if conversation_messages.empty?
        # Add a minimal context message if none exists
        messages << {
          "role" => "CHATBOT",
          "message" => "Hello, I'm here to help. What would you like to talk about?"
        }
      else
        # Process existing messages (use maximum 4 for better reliability)
        # Process in reverse to ensure we have the most recent messages
        recent_messages = conversation_messages.last(4)
        
        recent_messages.each_with_index do |msg, idx|
          # Skip empty messages
          next if (msg["content"].to_s.strip.empty? && msg["text"].to_s.strip.empty?)
          
          # Extract the role and convert to Cohere format (uppercase)
          role = msg["role"].to_s.upcase
          # Map standard roles to Cohere roles
          cohere_role = case role
                        when "USER" then "USER"
                        when "ASSISTANT" then "CHATBOT"
                        when "SYSTEM" then "SYSTEM"
                        when "TOOL" then "TOOL"
                        else role # Keep as is if already uppercase
                        end
          
          # Extract message content, preferring "content" over "text"
          message_content = nil
          if msg["content"] && !msg["content"].to_s.strip.empty?
            message_content = msg["content"].to_s.strip
            log_to_extra("  Message #{idx+1}: Using content field")
          elsif msg["text"] && !msg["text"].to_s.strip.empty?
            message_content = msg["text"].to_s.strip
            log_to_extra("  Message #{idx+1}: Using text field")
          else
            log_to_extra("  Message #{idx+1}: No content found, skipping")
            next
          end
          
          # Add message to the array using Cohere format
          messages << {
            "role" => cohere_role,
            "message" => message_content
          }
          
          log_to_extra("  Added message: role=#{cohere_role}, message length=#{message_content.size}")
        end
      end
    else
      log_to_extra("No valid messages array found in options")
      return "Error: Invalid options format - no messages found"
    end
    
    # Ensure we have enough context (at least one message besides system prompt)
    if messages.size < 2
      log_to_extra("Not enough conversation context (messages size: #{messages.size})")
      return "Error: Not enough conversation context for Cohere AI User"
    end
    
    # Make sure we end with an assistant message for proper user response generation
    last_message = messages.last
    if last_message["role"] != "CHATBOT"
      log_to_extra("Last message is not from assistant, adding artificial assistant message")
      # Add a minimal assistant message to allow the AI to respond as a user
      messages << {
        "role" => "CHATBOT", 
        "message" => "I understand. How would you like to respond to that?"
      }
    end
    
    messages
  end
  
  # Process the Cohere API response to extract the text content
  def process_cohere_response(response)
    if response.nil?
      log_to_extra("No response received from Cohere API")
      return "Error: No response received from Cohere API"
    end
    
    if !response.status.success?
      # Handle error response
      error_message = "Unknown API error"
      
      if response && response.body
        begin
          error_data = JSON.parse(response.body)
          error_message = error_data["message"] || error_data["error"] || error_message
          log_to_extra("API error: #{error_message}")
        rescue JSON::ParserError
          log_to_extra("Failed to parse error response")
          log_to_extra("Raw error response: #{response.body}")
          error_message = "Failed to parse error response"
        end
      end
      
      return "Error: Cohere API returned error - #{error_message}"
    end
    
    # Response was successful, process it
    begin
      # Parse the response
      raw_body = response.body.to_s.strip
      log_to_extra("Raw response body: #{raw_body[0..500]}...")
      
      # If empty response, return error
      if raw_body.empty?
        log_to_extra("Empty response body")
        return "Error: Empty response from Cohere API"
      end
      
      # Parse JSON
      response_data = JSON.parse(raw_body)
      
      # Log full response data for debugging
      log_to_extra("Parsed response: #{response_data.inspect}")
      
      # Special case for Cohere responses - very specific to their format
      # According to Cohere API documentation, v2 responses use these fields:
      
      # PRIMARY FORMAT: Current Cohere Chat API format 
      if response_data["text"].is_a?(String) && !response_data["text"].strip.empty?
        result = response_data["text"].strip
        log_to_extra("Found response in primary 'text' field: #{result[0..100]}...")
        return result
      end
      
      # ALTERNATIVE FORMAT: For legacy or different response structures
      if response_data["generations"] && response_data["generations"].is_a?(Array) && !response_data["generations"].empty?
        generation = response_data["generations"][0]
        if generation.is_a?(Hash) && generation["text"].is_a?(String)
          result = generation["text"].strip
          log_to_extra("Found response in generations[0].text field: #{result[0..100]}...")
          return result
        end
      end
      
      # Try the other documented response formats:
      if response_data["message"] && response_data["message"]["text"].is_a?(String)
        result = response_data["message"]["text"].strip
        log_to_extra("Found response in message.text field: #{result[0..100]}...")
        return result
      end
      
      # Try the raw message field (sometimes Cohere returns this)
      if response_data["message"].is_a?(String) && !response_data["message"].empty?
        result = response_data["message"].strip
        log_to_extra("Found response in direct message field: #{result[0..100]}...")
        return result
      end
      
      # Even more comprehensive fallback search
      known_fields = ["text", "message", "response", "generation", "output", "answer", "content", "completion", "reply"]
      
      # Check top-level fields first
      known_fields.each do |field|
        if response_data[field].is_a?(String) && !response_data[field].strip.empty?
          result = response_data[field].strip
          log_to_extra("Found response in '#{field}' field: #{result[0..100]}...")
          return result
        end
      end
      
      # Deep search - look for nested fields
      result = extract_text_from_response(response_data)
      if result
        log_to_extra("Found response via deep search: #{result[0..100]}...")
        return result
      end
      
      # Last resort - use the first text field we can find
      if response_data.is_a?(Hash)
        response_data.each do |key, value|
          if value.is_a?(String) && !value.strip.empty?
            result = value.strip
            log_to_extra("Found response in '#{key}' field as last resort: #{result[0..100]}...")
            return result
          end
        end
      end
      
      # If we still can't find anything, return a useful message
      log_to_extra("Could not extract response content from Cohere API")
      "I couldn't generate a response to continue the conversation."
      
    rescue JSON::ParserError => e
      log_to_extra("Failed to parse JSON response: #{e.message}")
      log_to_extra("Raw response that failed parsing: #{response.body.to_s[0..500]}")
      return "Error parsing Cohere API response"
    end
  end
  
  # Helper for logging debug messages to the extra.log file
  def log_to_extra(message)
    begin
      extra_log = File.join(Dir.home, "monadic", "log", "extra.log")
      File.open(extra_log, "a") do |f|
        f.puts("[#{Time.now}] COHERE: #{message}")
      end
    rescue => e
      # Silent fail for logging
    end
  end

  # Helper for logging debug messages
  private def log_message(message)
    begin
      File.open(File.join(Dir.home, "monadic", "log", "cohere_helper_debug.log"), "a") do |f|
        f.puts("[#{Time.now}] #{message}")
      end
    rescue => e
      # Silent fail for logging
    end
  end

  # Helper for logging error messages
  private def log_error(message)
    begin
      File.open(File.join(Dir.home, "monadic", "log", "cohere_helper_debug.log"), "a") do |f|
        f.puts("[#{Time.now}] ERROR: #{message}")
      end
    rescue => e
      # Silent fail for logging
    end
  end
  
  # Helper method to extract text from complex response structures
  def extract_text_from_response(response, depth=0, max_depth=3)
    return nil if depth > max_depth || response.nil?
    
    # For string responses
    return response if response.is_a?(String) && !response.empty?
    
    # For hash responses
    if response.is_a?(Hash)
      # Try common text field names
      ["text", "content", "message", "response"].each do |key|
        if response[key].is_a?(String) && !response[key].empty?
          return response[key]
        elsif response[key].is_a?(Hash)
          # Look one level deeper
          result = extract_text_from_response(response[key], depth+1, max_depth)
          return result if result
        end
      end
      
      # Look for standard response structures
      if response["choices"].is_a?(Array) && !response["choices"].empty?
        choice = response["choices"].first
        if choice["message"].is_a?(Hash) && choice["message"]["content"].is_a?(String)
          return choice["message"]["content"]
        end
      end
      
      # Recursive search in all values
      response.each_value do |value|
        result = extract_text_from_response(value, depth+1, max_depth)
        return result if result
      end
    elsif response.is_a?(Array)
      # Try each array element
      response.each do |item|
        result = extract_text_from_response(item, depth+1, max_depth)
        return result if result
      end
    end
    
    nil
  end

  # Main API request handler
  def api_request(role, session, call_depth: 0, &block)
    empty_tool_results = role == "empty_tool_results"
    num_retrial = 0

    # Verify API key existence
    begin
      api_key = CONFIG["COHERE_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: COHERE_API_KEY not found. Please set the COHERE_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the initial system prompt from the session
    # Handle case where session[:messages] might be nil or empty
    session[:messages] ||= []
    initial_prompt = if session[:messages].empty? || session[:messages].first.nil?
                       obj["initial_prompt"] || ""
                     else
                       session[:messages].first&.dig("text").to_s
                     end

    # Parse numerical parameters
    temperature = obj["temperature"]&.to_f
    
    # Handle max_tokens, prioritizing AI_USER_MAX_TOKENS for AI User mode
    if obj["ai_user"] == "true"
      max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || obj["max_tokens"]&.to_i
    else
      max_tokens = obj["max_tokens"]&.to_i
    end
    
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"
    message = obj["message"]
    
    # Debug logging for websearch
    DebugHelper.debug("Cohere websearch enabled: #{websearch}", category: :api, level: :info) if websearch

    # Handle non-tool messages and update session
    if role != "tool"
      message ||= "Hi there!"
      
      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      if role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Initialize and manage message context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages][0...-1].last(context_size).each { |msg| msg["active"] = true }

    # Configure API request headers
    headers = {
      "accept" => "application/json",
      "content-type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Prepare messages array for v2 API format
    messages = []

    initial_prompt_with_suffix = if websearch
                                   initial_prompt.to_s + WEBSEARCH_PROMPT
                                 else
                                   initial_prompt.to_s
                                 end

    # Add system message (initial prompt)
    messages << {
      "role" => "system",
      "content" => initial_prompt_with_suffix
    }

    # Add context messages with appropriate roles
    context.each do |msg|
      next if msg["text"].to_s.strip.empty?  # Skip empty messages
      messages << {
        "role" => translate_role(msg["role"]),
        "content" => msg["text"].to_s.strip
      }
    end

    # Add current user message if not a tool call
    if role != "tool"
      current_message = "#{message}\n\n#{obj["prompt_suffix"]}".strip
      messages << {
        "role" => "user",
        "content" => current_message
      }
    end
    
    # Apply monadic transformation to the last user message if in monadic mode
    if obj["monadic"].to_s == "true" && messages.any? && 
       messages.last["role"] == "user" && role == "user"
      # Remove prompt suffix to get base message
      base_message = messages.last["content"].sub(/\n\n#{Regexp.escape(obj["prompt_suffix"] || "")}$/, "")
      # Apply monadic transformation using unified interface
      monadic_message = apply_monadic_transformation(base_message, app, "user")
      # Add prompt suffix back
      messages.last["content"] = "#{monadic_message}\n\n#{obj["prompt_suffix"]}".strip
    end

    # Construct request body with v2 API compatible parameters
    body = {
      "model" => obj["model"],
      "stream" => true,
    }

    # Add optional parameters with validation
    body["temperature"] = temperature if temperature && temperature.between?(0.0, 2.0)
    body["max_tokens"] = max_tokens if max_tokens && max_tokens.positive?

    # Configure monadic response format using unified interface
    body = configure_monadic_response(body, :cohere, app)

    # Handle tools differently for Cohere
    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
      body["tools"].push(*WEBSEARCH_TOOLS) if websearch
      body["tools"].uniq!
      DebugHelper.debug("Cohere tools with websearch: #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS
      DebugHelper.debug("Cohere tools (websearch only): #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
    else
      body.delete("tools")
      DebugHelper.debug("Cohere: No tools enabled", category: :api, level: :debug)
    end

    # Handle tool results in v2 format
    if role == "tool" && obj["tool_results"]
      body["messages"] = obj["tool_results"]
    else
      body["messages"] = messages
    end

    target_uri = "#{API_ENDPOINT}/chat"
    http = HTTP.headers(headers)

    res = nil
    MAX_RETRIES.times do |i|
      begin
        res = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)
        
        break if res.status.success?
        
        sleep RETRY_DELAY * (i + 1) # Exponential backoff
      rescue HTTP::Error, HTTP::TimeoutError => e
        next unless i == MAX_RETRIES - 1
        
        pp error_message = "Network error: #{e.message}"
        res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
        block&.call res
        return [res]
      end
    end

    # Handle API error responses
    unless res&.status&.success?
      error_report = begin
                      JSON.parse(res.body)
                    rescue StandardError
                      { "message" => "Unknown error occurred" }
                    end
      pp error_report
      formatted_error = format_api_error(error_report, "cohere")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
      block&.call res
      return [res]
    end

    # Process streaming response
    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
                      call_depth: call_depth, &block)
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
    block&.call res
    [res]
  end

  # Process streaming JSON response data
  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    # Store the request parameters for constructing the final response
    obj = session[:parameters]
    app_name = obj["app_name"]
    
    texts = []
    tool_calls = []
    finish_reason = nil
    buffer = String.new
    current_tool_call = nil
    accumulated_tool_calls = []

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      pattern = /(\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          begin
            json_data = matched.match(pattern)[1]
            json = JSON.parse(json_data)

            if CONFIG["EXTRA_LOGGING"]
              extra_log.puts(JSON.pretty_generate(json))
            end

            # Handle different event types from v2 streaming API
            case json["type"]
            when "message-start"
              buffer = ""
              accumulated_tool_calls = []
            when "content-start"
            when "content-delta"
              if content = json.dig("delta", "message", "content")
                if text = content["text"]
                  buffer += text
                  texts << text

                  unless text.strip.empty?
                    if text.length > 0
                      res = {
                        "type" => "fragment",
                        "content" => text,
                        "index" => texts.length - 1,
                        "timestamp" => Time.now.to_f,
                        "is_first" => texts.length == 1
                      }
                      block&.call res
                    end
                  end
                end
              end
            when "tool-plan-delta"
              if text = json.dig("delta", "message", "tool_plan")
                buffer += text
                texts << text

                unless text.strip.empty?
                  if text.length > 0
                    res = {
                      "type" => "fragment",
                      "content" => text,
                      "index" => texts.length - 1,
                      "timestamp" => Time.now.to_f,
                      "is_first" => texts.length == 1
                    }
                    block&.call res
                  end
                end
              end
            when "tool-call-start"
              tool_call_data = json.dig("delta", "message", "tool_calls")
              current_tool_call = tool_call_data.dup
              
              # Ensure there's a valid arguments field even if empty
              if current_tool_call && current_tool_call["function"] && !current_tool_call["function"]["arguments"]
                current_tool_call["function"]["arguments"] = "{}"
              end
            when "tool-call-delta"
              if current_tool_call && args = json.dig("delta", "message", "tool_calls", "function", "arguments")
                current_tool_call["function"]["arguments"] += args
              end
            when "tool-call-end"
              if current_tool_call
                # Ensure arguments is a valid JSON string
                if current_tool_call["function"] && current_tool_call["function"]["arguments"]
                  begin
                    # Try to parse to validate JSON and pretty print it
                    parsed = JSON.parse(current_tool_call["function"]["arguments"])
                    current_tool_call["function"]["arguments"] = JSON.generate(parsed)
                  rescue JSON::ParserError
                    # If not valid JSON, use an empty object
                    current_tool_call["function"]["arguments"] = "{}"
                  end
                end
                
                accumulated_tool_calls << current_tool_call
                current_tool_call = nil
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              end
            when "message-end"
              if json.dig("delta", "finish_reason")
                finish_reason = case json["delta"]["finish_reason"]
                                when "MAX_TOKENS"
                                  "length"
                                when "COMPLETE"
                                  "stop"
                                else
                                  json["delta"]["finish_reason"]
                                end
              end
            end
          rescue JSON::ParserError => e
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

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    # Prepare final result from accumulated text
    result = texts.empty? ? nil : texts.join("")

    # Process accumulated tool calls if any exist
    if accumulated_tool_calls.any?
      context = [
        {
          "role" => "assistant",
          "tool_calls" => accumulated_tool_calls,
          "tool_plan" => result
        }
      ]

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Maximum function call depth exceeded" }]
      end

      # Execute tool calls and get results
      new_results = process_functions(app, session, accumulated_tool_calls, context, call_depth, &block)

      # Handle different result scenarios
      if result.is_a?(Hash) && result["error"]
        # Handle error case
        res = { "type" => "error", "content" => result["error"] }
      elsif result && new_results
        # Combine text result with function results
        combined_result = "#{result}\n\n#{new_results.dig(0, "choices", 0, "message", "content")}"
        res = { "choices" => [{ "message" => { "content" => combined_result } }] }
      elsif new_results
        # Use only function results
        res = new_results
      elsif result
        # Use only text result
        res = { "choices" => [{ "message" => { "content" => result } }] }
      end
      
      # Send the result
      block&.call res
      
      # Send the DONE message to trigger HTML rendering
      done_msg = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call done_msg
      
      # Explicitly send a "wait" message to reset the UI status immediately 
      # This ensures the UI doesn't stay in the "RESPONDING" state
      ready_msg = { "type" => "wait", "content" => "<i class='fa-solid fa-circle-check text-success'></i> <span class='text-success'>Ready to Start</span>" }
      block&.call ready_msg
      
      # The "DONE" message tells the client to request HTML, which resets the status
      [res]
    elsif result
      # Return final text result exactly like the command_r_helper does
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      
      # Apply monadic transformation if enabled
      final_result = result
      if obj["monadic"] && final_result
        # Process through unified interface
        processed = process_monadic_response(final_result, app)
        # Validate the response
        validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
        final_result = validated.is_a?(Hash) ? JSON.generate(validated) : validated
      end
      
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason, 
              "message" => { "content" => final_result }
            }
          ]
        }
      ]
    else
      # Handle empty tool results
      api_request("empty_tool_results", session, call_depth: call_depth, &block)
    end
  end

  # Process function calls from the API response
  def process_functions(app, session, tool_calls, context, call_depth, &block)
    obj = session[:parameters]
    tool_results = []
    
    # First, tell the client that function processing is starting
    begin_msg = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> PROCESSING FUNCTION RESULTS" }
    block&.call begin_msg
    
    tool_calls.each do |tool_call|
      # Extract function name and validate
      function_name = tool_call.dig("function", "name")
      next if function_name.nil?

      # Important: Keep the original tool_call_id exactly as received
      tool_call_id = tool_call["id"]  # This ID must match exactly what the API sent

      # Parse and sanitize function arguments
      arguments = tool_call.dig("function", "arguments")
      argument_hash = if arguments.is_a?(String) && !arguments.empty?
        begin
          JSON.parse(arguments)
        rescue JSON::ParserError
          # If not valid JSON, use an empty hash
          {}
        end
      else
        {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      # Special handling for check_environment function
      if function_name == "check_environment" && argument_hash.empty?
        argument_hash = {}  # Ensure it's an empty hash, not nil
      end

      # Execute function and capture result
      begin
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      rescue StandardError => e
        pp "Function execution error: #{e.message}"  # Debug log
        function_return = "Error executing function: #{e.message}"
      end

      # Format tool results maintaining exact tool_call_id
      context << {
        "role" => "tool",
        "tool_call_id" => tool_call_id,
        "content" => [
          {
            "type" => "document", 
            "document" => {
              "id" => tool_call_id,
              "data" => {
                "results" => function_return.to_s
              }
            }
          }
        ]
      }
    end

    # Store the tool results in the session
    obj["tool_results"] = context

    # Tell the client we're done with function processing before making the recursive API request
    done_msg = { "type" => "wait", "content" => "<i class='fas fa-check-circle'></i> FUNCTION CALLS COMPLETE" }
    block&.call done_msg

    # Make recursive API request with tool results
    api_request("tool", session, call_depth: call_depth, &block)
  end

  # Translate role names to v2 API format
  def translate_role(role)
    role_lower = role.to_s.downcase
    VALID_ROLES.include?(role_lower) ? role_lower : "user"
  end
end
