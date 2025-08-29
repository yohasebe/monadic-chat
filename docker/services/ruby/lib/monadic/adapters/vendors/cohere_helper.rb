# frozen_string_literal: true
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"
require_relative "../../utils/model_spec_utils"

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

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from the web search results as possible to provide the user with the most up-to-date and relevant information.

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
  def send_query(options, model: nil)
    # Use default model from CONFIG if not specified
    model ||= CONFIG["COHERE_DEFAULT_MODEL"]
    
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get the API key
    api_key = CONFIG["COHERE_API_KEY"]
    return Monadic::Utils::ErrorFormatter.api_key_error(
      provider: "Cohere",
      env_var: "COHERE_API_KEY"
    ) if api_key.nil?
    
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
        
        # Check if message has images (for vision-capable models)
        if msg["images"] && msg["images"].any?
          content = []
          
          # Add text content
          text = msg["content"] || msg["text"] || ""
          content << {
            "type" => "text",
            "text" => text.to_s
          }
          
          # Add images
          msg["images"].each do |img|
            if img["data"].start_with?("data:")
              content << {
                "type" => "image",
                "image" => img["data"]
              }
            else
              mime_type = img["type"] || "image/jpeg"
              content << {
                "type" => "image",
                "image" => "data:#{mime_type};base64,#{img["data"]}"
              }
            end
          end
          
          messages << {
            "role" => role,
            "content" => content
          }
        else
          # Regular text-only message
          content = msg["content"] || msg["text"] || ""
          
          messages << {
            "role" => role,
            "content" => content.to_s
          }
        end
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
        return result["text"] || result["message"] || result["generated_text"] || Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Cohere",
          message: "No text found in response"
        )
      rescue => e
        return "Error parsing response: #{e.message}"
      end
    else
      begin
        error_body = response&.body.to_s
        error_data = JSON.parse(error_body)
        error = error_data["message"] || "Unknown error"
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: error
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: "API error response"
        )
      end
    end
  rescue => e
    return Monadic::Utils::ErrorFormatter.api_error(
      provider: "Cohere",
      message: e.message
    )
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
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: "Invalid options format - no messages found"
      )
    end
    
    # Ensure we have enough context (at least one message besides system prompt)
    if messages.size < 2
      log_to_extra("Not enough conversation context (messages size: #{messages.size})")
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: "Not enough conversation context for Cohere AI User"
      )
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
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: "No response received from Cohere API"
      )
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
      
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: "API returned error - #{error_message}",
        code: response_code
      )
    end
    
    # Response was successful, process it
    begin
      # Parse the response
      raw_body = response.body.to_s.strip
      log_to_extra("Raw response body: #{raw_body[0..500]}...")
      
      # If empty response, return error
      if raw_body.empty?
        log_to_extra("Empty response body")
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Cohere",
          message: "Empty response from API"
        )
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
      pp error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Cohere",
        env_var: "COHERE_API_KEY"
      )
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
    
    # Handle max_tokens
    max_tokens = obj["max_tokens"]&.to_i
    
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Handle both string and boolean values for websearch parameter
    websearch = CONFIG["TAVILY_API_KEY"] && (obj["websearch"] == "true" || obj["websearch"] == true)
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
    messages_containing_img = false

    initial_prompt_parts = [initial_prompt.to_s]
    
    # Add language preference if set
    if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
      language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
      initial_prompt_parts << language_prompt if !language_prompt.empty?
    end
    
    # Add websearch prompt if enabled
    initial_prompt_parts << WEBSEARCH_PROMPT if websearch
    
    initial_prompt_with_suffix = initial_prompt_parts.join("\n\n---\n\n")

    # Check if any messages contain images first
    context.each do |msg|
      if msg["images"] && msg["images"].any?
        messages_containing_img = true
        break
      end
    end
    
    # Also check current message for images
    if role == "user" && session[:messages].last && session[:messages].last["images"] && session[:messages].last["images"].any?
      messages_containing_img = true
    end

    # Add system message (initial prompt)
    messages << {
      "role" => "system",
      "content" => initial_prompt_with_suffix
    }

    # Add context messages with appropriate roles
    context.each do |msg|
      next if msg["text"].to_s.strip.empty?  # Skip empty messages
      
      # Debug logging for message construction
      if CONFIG["EXTRA_LOGGING"]
        DebugHelper.debug("Adding context message - role: #{msg['role']}, text length: #{msg['text'].to_s.length}", category: :api, level: :debug)
      end
      
      # Check if message contains images
      if msg["images"] && msg["images"].any?
        content = []
        
        # Add text content first
        content << {
          "type" => "text",
          "text" => msg["text"].to_s.strip
        }
        
        # Add images
        msg["images"].each do |img|
          # Cohere expects base64 images with proper formatting
          if img["data"].start_with?("data:")
            content << {
              "type" => "image",
              "image" => img["data"]
            }
          else
            # If it's already base64 without the data URL prefix
            mime_type = img["type"] || "image/jpeg"
            content << {
              "type" => "image", 
              "image" => "data:#{mime_type};base64,#{img["data"]}"
            }
          end
        end
        
        messages << {
          "role" => translate_role(msg["role"]),
          "content" => content
        }
      else
        # Regular text-only message
        messages << {
          "role" => translate_role(msg["role"]),
          "content" => msg["text"].to_s.strip
        }
      end
    end

    # Add current user message if not a tool call
    if role != "tool"
      current_message = "#{message}\n\n#{obj["prompt_suffix"]}".strip
      
      # Check if the current message has images
      latest_msg = session[:messages].last
      if latest_msg && latest_msg["images"] && latest_msg["images"].any? && role == "user"
        messages_containing_img = true
        content = []
        
        # Add text content
        content << {
          "type" => "text",
          "text" => current_message
        }
        
        # Add images from the latest message
        latest_msg["images"].each do |img|
          if img["data"].start_with?("data:")
            content << {
              "type" => "image",
              "image" => img["data"]
            }
          else
            mime_type = img["type"] || "image/jpeg"
            content << {
              "type" => "image",
              "image" => "data:#{mime_type};base64,#{img["data"]}"
            }
          end
        end
        
        messages << {
          "role" => "user",
          "content" => content
        }
      else
        # Regular text-only message
        messages << {
          "role" => "user",
          "content" => current_message
        }
      end
    end
    
    # Apply monadic transformation to the last user message if in monadic mode
    if obj["monadic"].to_s == "true" && messages.any? && 
       messages.last["role"] == "user" && role == "user"
      last_msg = messages.last
      if last_msg["content"].is_a?(Array)
        # Handle structured content with images
        text_content = last_msg["content"].find { |c| c["type"] == "text" }
        if text_content
          # Remove prompt suffix to get base message
          base_message = text_content["text"].sub(/\n\n#{Regexp.escape(obj["prompt_suffix"] || "")}$/, "")
          # Apply monadic transformation using unified interface
          monadic_message = apply_monadic_transformation(base_message, app, "user")
          # Add prompt suffix back
          text_content["text"] = "#{monadic_message}\n\n#{obj["prompt_suffix"]}".strip
        end
      else
        # Handle simple string content
        # Remove prompt suffix to get base message
        base_message = messages.last["content"].sub(/\n\n#{Regexp.escape(obj["prompt_suffix"] || "")}$/, "")
        # Apply monadic transformation using unified interface
        monadic_message = apply_monadic_transformation(base_message, app, "user")
        # Add prompt suffix back
        messages.last["content"] = "#{monadic_message}\n\n#{obj["prompt_suffix"]}".strip
      end
    end

    # Construct request body with v2 API compatible parameters
    body = {
      "model" => obj["model"],
      "stream" => true,
    }

    # Add optional parameters with validation
    body["temperature"] = temperature if temperature && temperature.between?(0.0, 2.0)
    body["max_tokens"] = max_tokens if max_tokens && max_tokens.positive?
    
    # Handle reasoning (thinking) parameter for command-a-reasoning models
    # Check if this is a reasoning model using ModelSpecUtils
    is_reasoning_model = ModelSpecUtils.is_thinking_model?(obj["model"])
    if is_reasoning_model && obj["reasoning_effort"]
      # Check if we have conversation history with assistant messages
      has_assistant_messages = messages.any? { |m| m["role"] == "assistant" }
      
      # Debug logging
      if CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
          f.puts "[#{Time.now}] Cohere reasoning check:"
          f.puts "  Model: #{obj["model"]}"
          f.puts "  Reasoning effort: #{obj["reasoning_effort"]}"
          f.puts "  Has assistant messages: #{has_assistant_messages}"
          f.puts "  Message count: #{messages.size}"
          f.puts "  Message roles: #{messages.map { |m| m["role"] }.join(", ")}"
        end
      end
      
      if obj["reasoning_effort"] == "enabled"
        if has_assistant_messages
          # Workaround for Cohere reasoning model issue:
          # When thinking is enabled and there are assistant messages in history,
          # we need to combine the conversation into a single user message
          # Always log this important information
          if CONFIG["EXTRA_LOGGING"]
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
              f.puts "[#{Time.now}] Cohere: Using single-text workaround for reasoning model with history"
            end
          end
          
          # Combine all messages into a single conversation context
          conversation_text = format_conversation_as_single_text(messages)
          
          # Replace messages with single user message containing the conversation
          body["messages"] = [
            {
              "role" => "user",
              "content" => conversation_text
            }
          ]
          
          # Enable thinking even with single-text workaround
          # This should work because Cohere sees it as a fresh conversation
          body["thinking"] = { "type" => "enabled" }
          
          # Log the final message structure
          if CONFIG["EXTRA_LOGGING"]
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
              f.puts "  Single text format applied. New message count: #{body["messages"].size}"
              f.puts "  Thinking enabled: #{body["thinking"].inspect}"
              f.puts "  Message preview (first 500 chars):"
              f.puts "  #{body["messages"][0]["content"][0..500]}..."
              f.puts "  Total message length: #{body["messages"][0]["content"].length} chars"
            end
          end
        else
          # First turn or no assistant messages - can use thinking normally
          body["thinking"] = { "type" => "enabled" }
          DebugHelper.debug("Cohere: Reasoning enabled for #{obj["model"]} (no assistant messages)", category: :api, level: :info)
        end
      else
        body["thinking"] = { "type" => "disabled" }
        DebugHelper.debug("Cohere: Reasoning disabled for #{obj["model"]}", category: :api, level: :info)
      end
    end

    # Configure monadic response format using unified interface
    body = configure_monadic_response(body, :cohere, app)

    # Check if we need to switch to vision-capable model
    if messages_containing_img
      # Check if the current model has vision capability from model_spec
      unless obj["vision_capability"]
        original_model = body["model"]
        body["model"] = "command-a-vision-07-2025"
        
        # Send system notification about model switch
        if block && original_model != body["model"]
          system_msg = {
            "type" => "system_info",
            "content" => "Model automatically switched from #{original_model} to #{body['model']} for image processing capability."
          }
          block.call system_msg
        end
      end
    end

    # Get tools from app settings
    app_tools = APPS[app]&.settings&.[]("tools")
    
    # Only include tools if this is not a tool response
    if role != "tool"
      # Handle tools differently for Cohere
      if obj["tools"] && !obj["tools"].empty?
        body["tools"] = app_tools || []
        body["tools"].push(*WEBSEARCH_TOOLS) if websearch && body["tools"]
        body["tools"].uniq! if body["tools"]
        DebugHelper.debug("Cohere tools with websearch: #{body["tools"]&.map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
      elsif app_tools && !app_tools.empty?
        # If no tools param but app has tools, use them
        body["tools"] = app_tools
        body["tools"].push(*WEBSEARCH_TOOLS) if websearch
        body["tools"].uniq!
        DebugHelper.debug("Cohere tools from app settings: #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
      elsif websearch
        body["tools"] = WEBSEARCH_TOOLS
        DebugHelper.debug("Cohere tools (websearch only): #{body["tools"].map { |t| t.dig(:function, :name) }.join(", ")}", category: :api, level: :debug)
      else
        body.delete("tools")
        DebugHelper.debug("Cohere: No tools enabled", category: :api, level: :debug)
      end
    end # end of role != "tool"

    # Handle tool results in v2 format
    # Only set messages if not already set by reasoning workaround
    if !body["messages"]
      if role == "tool" && obj["tool_results"]
        body["messages"] = obj["tool_results"]
      else
        body["messages"] = messages
      end
    end
    
    # Debug logging for message structure
    if CONFIG["EXTRA_LOGGING"]
      DebugHelper.debug("Sending #{body['messages'].length} messages to Cohere API", category: :api, level: :info)
      body["messages"].each_with_index do |msg, idx|
        DebugHelper.debug("Message #{idx}: role=#{msg['role']}, content_length=#{msg['content'].to_s.length}", category: :api, level: :debug)
        # Log first 100 chars of content for debugging
        if msg['content']
          content_preview = msg['content'].to_s[0..100]
          DebugHelper.debug("  Content preview: #{content_preview}...", category: :api, level: :debug)
        end
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

    # Log the complete API request for debugging
    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
        f.puts "\n[#{Time.now}] === COHERE API REQUEST ==="
        f.puts "Model: #{body["model"]}"
        f.puts "Thinking: #{body["thinking"].inspect}"
        f.puts "Stream: #{body["stream"]}"
        f.puts "Number of messages: #{body["messages"]&.size}"
        
        if body["messages"]
          body["messages"].each_with_index do |msg, idx|
            f.puts "\nMessage #{idx + 1}:"
            f.puts "  Role: #{msg["role"]}"
            if msg["content"]
              content_str = msg["content"].to_s
              f.puts "  Content length: #{content_str.length} chars"
              if content_str.length <= 1000
                f.puts "  Content: #{content_str}"
              else
                f.puts "  Content (first 500 chars): #{content_str[0..500]}..."
                f.puts "  Content (last 200 chars): ...#{content_str[-200..-1]}"
              end
            end
          end
        end
        
        f.puts "\n=== END API REQUEST ===\n"
      end
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
        formatted_error = Monadic::Utils::ErrorFormatter.network_error(
          provider: "Cohere",
          message: error_message,
          timeout: true
        )
        res = { "type" => "error", "content" => formatted_error }
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
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
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
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "Cohere",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
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
    citations = []  # Store citation data

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
                # Handle thinking content for reasoning models
                if thinking = content["thinking"]
                  # For now, we don't send thinking content to the UI
                  # It could be logged if needed
                  DebugHelper.debug("Cohere thinking: #{thinking}", category: :api, level: :debug) if CONFIG["EXTRA_LOGGING"]
                end
                
                # Also check for text content (both thinking and text can be present)
                if text = content["text"]
                  buffer += text
                  texts << text
                  
                  # Debug logging for text content
                  if CONFIG["EXTRA_LOGGING"]
                    DebugHelper.debug("Cohere text fragment received: #{text.length} chars", category: :api, level: :debug)
                  end

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
            when "citation-start"
              # Capture citation information
              if citation_data = json.dig("delta", "message", "citations")
                citations << citation_data
              end
            when "citation-end"
              # Citation end marker - no action needed
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
                
                # Log error details if finish_reason is ERROR
                if json["delta"]["finish_reason"] == "ERROR" && CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
                    f.puts "\n[#{Time.now}] === COHERE API ERROR ==="
                    f.puts "Finish reason: ERROR"
                    if json["delta"]["error"]
                      f.puts "Error message: #{json["delta"]["error"]}"
                    end
                    if json["delta"]["usage"]
                      f.puts "Usage info: #{json["delta"]["usage"].inspect}"
                    end
                    f.puts "Full delta: #{json["delta"].inspect}"
                    f.puts "=== END ERROR ===\n"
                  end
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
    
    # Debug logging for final result
    if CONFIG["EXTRA_LOGGING"]
      DebugHelper.debug("Cohere streaming complete - texts array size: #{texts.size}, result length: #{result.to_s.length}", category: :api, level: :info)
      if result.nil?
        DebugHelper.debug("Result is nil - checking reasoning model fallback", category: :api, level: :info)
        DebugHelper.debug("Session messages count: #{session[:messages]&.size || 0}", category: :api, level: :info)
        DebugHelper.debug("Is reasoning model: #{obj['reasoning_model']}, effort: #{obj['reasoning_effort']}", category: :api, level: :info)
      else
        DebugHelper.debug("Result has content: #{result[0..100]}...", category: :api, level: :debug)
      end
    end
    
    # Process citations if any were collected
    if result && citations.any?
      result = process_citations(result, citations)
    end

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
        return [{ "type" => "error", "content" => Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: "Maximum function call depth exceeded"
        ) }]
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
      ready_msg = { "type" => "wait", "content" => "<i class='fa-solid fa-circle-check' style='color: #22ad50;'></i> <span style='color: #22ad50;'>Ready to Start</span>" }
      block&.call ready_msg
      
      # The "DONE" message tells the client to request HTML, which resets the status
      [res]
    else
      # Handle regular text response or empty response (e.g., only thinking content)
      
      if result
        # Apply monadic transformation if enabled
        final_result = result
        if obj["monadic"] && final_result
          # Process through unified interface
          processed = process_monadic_response(final_result, app)
          # Validate the response
          validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
          final_result = validated.is_a?(Hash) ? JSON.generate(validated) : validated
        end
        
        # Send DONE message to complete the stream
        res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
        block&.call res
        
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
        # No text content (only thinking or genuinely empty response)
        # Check if this was a reasoning model with thinking content
        # Debug logging to understand the issue
        if CONFIG["EXTRA_LOGGING"]
          DebugHelper.debug("Empty response - checking reasoning model status", category: :api, level: :info)
          DebugHelper.debug("obj['reasoning_model']: #{obj['reasoning_model'].inspect}", category: :api, level: :info)
          DebugHelper.debug("obj['reasoning_effort']: #{obj['reasoning_effort'].inspect}", category: :api, level: :info)
          DebugHelper.debug("obj['model']: #{obj['model'].inspect}", category: :api, level: :info)
        end
        
        # For Cohere reasoning models, check using ModelSpecUtils
        is_reasoning_model = obj["reasoning_model"] || ModelSpecUtils.is_thinking_model?(obj["model"])
        
        # Check if reasoning was actually enabled for this request
        # With the new single-text workaround, thinking is always enabled when requested
        # So we only need to check if this is a reasoning model with thinking enabled
        reasoning_actually_enabled = obj["reasoning_effort"] == "enabled"
        
        if is_reasoning_model && reasoning_actually_enabled
          # For reasoning models with thinking enabled but no text output,
          # return a default message. This is normal behavior for Cohere reasoning models
          # when they complete their thinking but don't generate additional text.
          default_response = "I've processed your request. How can I help you further?"
          
          # Send the response as a fragment first
          res = {
            "type" => "fragment",
            "content" => default_response,
            "index" => 0,
            "timestamp" => Time.now.to_f,
            "is_first" => true
          }
          block&.call res
          
          # Send DONE message to complete the stream
          done_msg = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" }
          block&.call done_msg
          
          [
            {
              "choices" => [
                {
                  "finish_reason" => finish_reason || "stop",
                  "message" => { "content" => default_response }
                }
              ]
            }
          ]
        else
          # For non-reasoning models or when reasoning is disabled, return empty response
          # This should not happen in normal flow, but handle gracefully
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("Unexpected empty response for non-reasoning scenario", category: :api, level: :warn)
          end
          
          # Return a minimal response
          empty_response = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
          block&.call empty_response
          
          [
            {
              "choices" => [
                {
                  "finish_reason" => "stop",
                  "message" => { "content" => "" }
                }
              ]
            }
          ]
        end
      end
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

      # Process function return to detect generated images and enhance the response
      processed_return = function_return.to_s
      
      # Check if files were generated (especially images)
      if processed_return.include?("File(s) generated or modified:")
        # Extract file paths
        file_matches = processed_return.scan(/\/data\/[^\s,]+(?:\.\w+)?/)
        
        # For each file path, check if it's an image and enhance the response
        image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']
        image_files = []
        
        file_matches.each do |file_path|
          # Clean up the file path (remove trailing punctuation)
          clean_path = file_path.gsub(/[,;.]$/, '')
          
          # Check if it's an image file
          if image_extensions.any? { |ext| clean_path.downcase.end_with?(ext) }
            image_files << clean_path
          end
        end
        
        # If we found image files, add explicit instructions to the result
        if !image_files.empty?
          processed_return += "\n\nIMPORTANT: Display the generated image(s) using the following HTML:\n"
          image_files.each do |img_path|
            processed_return += "<div class=\"generated_image\"><img src=\"#{img_path}\" /></div>\n"
          end
          processed_return += "\nPlease include the above HTML in your response to show the image(s) to the user."
        end
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
                "results" => function_return.is_a?(Hash) || function_return.is_a?(Array) ? 
                            JSON.generate(function_return) : 
                            processed_return
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

  # Process citations to add HTML links
  def process_citations(text, citations)
    return text if citations.empty?
    
    # Sort citations by start position in reverse order to process from end to beginning
    # This prevents position shifts when inserting HTML
    sorted_citations = citations.sort_by { |c| -(c["start"] || 0) }
    
    result = text.dup
    
    sorted_citations.each do |citation|
      next unless citation["start"] && citation["end"] && citation["sources"]
      
      start_pos = citation["start"]
      end_pos = citation["end"]
      cited_text = citation["text"]
      
      # Extract URLs from the sources
      urls = []
      citation["sources"].each do |source|
        if source["tool_output"] && source["tool_output"]["results"]
          begin
            # Parse the JSON results
            results = JSON.parse(source["tool_output"]["results"])
            if results["results"] && results["results"].is_a?(Array)
              results["results"].each do |r|
                if r["url"] && r["title"]
                  urls << { url: r["url"], title: r["title"] }
                end
              end
            end
          rescue JSON::ParserError
            # Skip if can't parse
          end
        end
      end
      
      # Replace the cited text with linked version
      if urls.any?
        # Use the first URL as the main link
        first_url = urls.first
        linked_text = "<a href=\"#{first_url[:url]}\" target=\"_blank\" rel=\"noopener noreferrer\">#{cited_text}</a>"
        
        # Replace in the result string
        if result[start_pos...end_pos] == cited_text
          result[start_pos...end_pos] = linked_text
        end
      end
    end
    
    # Add references section at the end
    if citations.any?
      references = "\n\nReferences:\n"
      all_urls = []
      
      citations.each do |citation|
        next unless citation["sources"]
        
        citation["sources"].each do |source|
          if source["tool_output"] && source["tool_output"]["results"]
            begin
              results = JSON.parse(source["tool_output"]["results"])
              if results["results"] && results["results"].is_a?(Array)
                results["results"].each do |r|
                  if r["url"] && r["title"]
                    all_urls << { url: r["url"], title: r["title"] }
                  end
                end
              end
            rescue JSON::ParserError
              # Skip if can't parse
            end
          end
        end
      end
      
      # Remove duplicates and format
      all_urls.uniq! { |u| u[:url] }
      all_urls.each do |url_info|
        references += "- <a href=\"#{url_info[:url]}\" target=\"_blank\" rel=\"noopener noreferrer\">#{url_info[:title]}</a>\n"
      end
      
      result += references
    end
    
    result
  end
  
  # Format conversation history as a single text for reasoning model workaround
  def format_conversation_as_single_text(messages)
    # Estimate token count (rough estimate: 1 token ≈ 4 characters)
    max_context_chars = 200000  # Conservative limit (≈50K tokens)
    
    conversation_parts = []
    system_message = nil
    conversation_messages = []
    current_user_message = nil
    
    # Separate messages by type
    messages.each do |msg|
      case msg["role"]
      when "system"
        system_message = msg["content"]
      when "user", "assistant"
        if msg["role"] == "user" && msg == messages.last
          # The last user message is the current question
          current_user_message = msg["content"]
        else
          conversation_messages << msg
        end
      end
    end
    
    # Build the conversation text in a format that works with Cohere's reasoning
    result = ""
    
    # Start with a clear context that this is a continuation
    result += "You are continuing an ongoing conversation. Here is the context:\n\n"
    
    # Add system context if present
    if system_message
      result += "System Instructions:\n#{system_message}\n\n"
    end
    
    # Add conversation history if present
    if conversation_messages.any?
      result += "Previous Conversation:\n"
      result += "---\n"
      
      conversation_messages.each do |msg|
        role_label = msg["role"] == "user" ? "User" : "Assistant"
        result += "#{role_label}: #{msg["content"]}\n\n"
      end
      
      result += "---\n\n"
    end
    
    # Add current question with clear indication
    result += "Now, the user asks:\n"
    if current_user_message
      result += "#{current_user_message}\n\n"
    else
      # If no explicit current message, use the last message
      last_msg = messages.last
      if last_msg && last_msg["role"] == "user"
        result += "#{last_msg["content"]}\n\n"
      end
    end
    
    # Add instruction that encourages natural continuation
    result += "Please provide a thoughtful response to the user's question, taking into account the conversation history."
    
    # Truncate if too long (keep recent messages)
    if result.length > max_context_chars
      # Try to keep at least the system message and current question
      truncated_result = ""
      
      if system_message
        truncated_result += "<system_context>\n#{system_message}\n</system_context>\n\n"
      end
      
      # Add as many recent messages as possible
      truncated_result += "<conversation_history>\n"
      recent_messages = conversation_messages.last(10)  # Keep last 10 exchanges
      
      recent_messages.each do |msg|
        role_label = msg["role"] == "user" ? "User" : "Assistant"
        truncated_result += "#{role_label}: #{msg["content"]}\n"
      end
      
      truncated_result += "</conversation_history>\n\n"
      
      if current_user_message
        truncated_result += "<current_question>\n#{current_user_message}\n</current_question>\n\n"
      end
      
      truncated_result += "Based on the conversation history above, please continue the conversation naturally and answer the current question."
      
      result = truncated_result
      
      if CONFIG["EXTRA_LOGGING"]
        DebugHelper.debug("Cohere: Conversation truncated from #{result.length} to #{truncated_result.length} chars", category: :api, level: :info)
      end
    end
    
    result
  end
end
