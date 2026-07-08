# frozen_string_literal: true
require 'cgi'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/usage_normalizer"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../utils/system_prompt_injector"
require_relative "../../monadic_performance"
require_relative "../base_vendor_helper"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/extra_logger"
require_relative "../../shared_tools/tavily_definitions"

module CohereHelper
  include BaseVendorHelper
  include InteractionUtils
  include MonadicPerformance
  include FunctionCallErrorHandler
  MAX_FUNC_CALLS = 20
  # API endpoint and configuration constants
  API_ENDPOINT = "https://api.cohere.ai/v2"
  define_timeouts "COHERE", open: 10, read: 600, write: 120

  MAX_RETRIES = 5
  RETRY_DELAY = 1
  VALID_ROLES = %w[user assistant system tool].freeze
  # ENV key for emergency override
  COHERE_LEGACY_MODE_ENV = "COHERE_LEGACY_MODE"

  # Tavily-backed web search tools. SSOT is
  # `Monadic::SharedTools::TavilyDefinitions` (consolidated 2026-05-13);
  # local constants are aliases for backwards compat. Note: before
  # consolidation Cohere had `required: ["query", "n"]` here, forcing
  # the model to always pass a count; the canonical definition only
  # requires `query` (matching the other 3 helpers).
  WEBSEARCH_TOOLS = Monadic::SharedTools::TavilyDefinitions::TOOLS
  WEBSEARCH_PROMPT = Monadic::SharedTools::TavilyDefinitions::PROMPT

  # Helper method to check if a model is a thinking/reasoning model.
  # Prefer the SSOT (model_spec `supports_thinking` flag) so that new
  # Cohere thinking models whose name does not contain "thinking" or
  # "reasoning" (e.g. command-a-plus-05-2026) are still recognised.
  # Falls back to the legacy name heuristic when the SSOT has no entry.
  def self.is_thinking_model?(model_name)
    return false unless model_name
    if defined?(Monadic::Utils::ModelSpec) && Monadic::Utils::ModelSpec.respond_to?(:supports_thinking?)
      return true if Monadic::Utils::ModelSpec.supports_thinking?(model_name)
    end
    model_name.include?("thinking") || model_name.include?("reasoning")
  end

  class << self
    attr_reader :cached_models

    def vendor_name
      "Cohere"
    end

  end

  define_model_lister :cohere,
    api_key_config: "COHERE_API_KEY",
    endpoint_path: "/models" do |json|
      api_models = (json["models"] || [])
        .map { |m| m["name"] }
        .reject { |name| name.include?("embed") || name.include?("rerank") }

      # Enrich with non-deprecated Cohere models from model_spec
      begin
        model_spec_path = File.expand_path("../../../../public/js/monadic/model_spec.js", File.dirname(__FILE__))
        model_spec = ModelSpecLoader.load_merged_spec(model_spec_path) if defined?(ModelSpecLoader)
        if model_spec
          model_spec.each do |model_name, model_config|
            if model_name.match?(/^(command|c4ai|north)/) &&
               model_config["deprecated"] == false &&
               !api_models.include?(model_name)
              api_models << model_name
            end
          end
        end
      rescue => e
        Monadic::Utils::ExtraLogger.log { "[Cohere] Warning: Could not load model_spec: #{e.message}" }
      end

      api_models.sort
    end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    model = model.to_s.strip
    model = nil if model.empty?
    # Use default model from CONFIG if not specified
    model ||= SystemDefaults.get_default_model('cohere')
    
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

    # Special handling for AI User requests
    # Reframe as text completion to avoid role-play refusal
    if options["ai_user_system_message"]
      context = options["ai_user_system_message"]

      # Create a text completion task
      simple_messages = [
        {
          "role" => "user",
          "content" => [{ "type" => "text", "text" => "Complete this conversation by writing the next message from the human participant. Output ONLY the message text, nothing else.\n\nConversation:\n#{context}\n\nHuman's next message:" }]
        }
      ]

      # Prepare simple request body (omit temperature for thinking models)
      is_thinking_model = CohereHelper.is_thinking_model?(model) rescue false
      body = {
        "model" => model,
        "max_tokens" => options["max_tokens"] || 1000,
        "messages" => simple_messages,
        "stream" => false
      }
      body["temperature"] = options["temperature"] || 0.7 unless is_thinking_model

      # Make API request directly
      target_uri = "#{API_ENDPOINT}/chat"
      http = HTTP.headers(headers)

      response = post_json_with_retries(http, target_uri, body,
                                        max_retries: MAX_RETRIES, retry_delay: RETRY_DELAY,
                                        rescue_errors: [StandardError])

      # Process response
      if response && response.status && response.status.success?
        begin
          parsed_response = JSON.parse(response.body)
          # Extract text from Cohere v2 API response format
          if parsed_response["message"] && parsed_response["message"]["content"].is_a?(Array)
            text_items = parsed_response["message"]["content"].select { |item| item["type"] == "text" }
            if text_items.any?
              return text_items.map { |item| item["text"] }.join("\n")
            end
          end
          return Monadic::Utils::ErrorFormatter.parsing_error(
            provider: "Cohere",
            message: "No content in AI User response"
          )
        rescue => e
          return Monadic::Utils::ErrorFormatter.parsing_error(
            provider: "Cohere",
            message: e.message
          )
        end
      else
        begin
          error_data = response && response.body ? JSON.parse(response.body) : {}
          error_message = error_data["message"] || "Unknown error"
          return Monadic::Utils::ErrorFormatter.api_error(
            provider: "Cohere",
            message: error_message,
            code: response&.status&.code
          )
        rescue => e
          return Monadic::Utils::ErrorFormatter.parsing_error(
            provider: "Cohere",
            message: "Failed to parse error response"
          )
        end
      end
    end

    # Regular non-AI User conversation processing
    # Format messages for Cohere API
    messages = []
    
    # Process messages (Cohere v2 expects content as an array of typed parts)
    if options["messages"]
      raw_messages = options["messages"].map do |entry|
        if entry.respond_to?(:transform_keys)
          entry.transform_keys { |key| key.to_s }
        else
          entry
        end
      end

      # Add system message as a user preface to guide behaviour (Cohere doesn't have strict system role semantics)
      system_msg = raw_messages.find { |m| m["role"].to_s.downcase == "system" }
      if system_msg
        sys_text = system_msg["content"].to_s.strip
        sys_text = "You are a helpful assistant." if sys_text.empty?
        messages << {
          "role" => "user",
          "content" => [ { "type" => "text", "text" => sys_text } ]
        }
      end

      # Process conversation messages
      raw_messages.each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)

        # Map roles
        role = case msg["role"].to_s.downcase
               when "user" then "user"
               when "assistant" then "assistant"
               when "tool" then "tool"
               else "user"
               end

        # Build content parts
        parts = []
        text_segments = []
        content = msg["content"]

        if content.is_a?(Array)
          content.each do |item|
            case item
            when String
              text_segments << item
            when Hash
              str = item["text"] || item[:text]
              text_segments << str.to_s unless str.nil?
            end
          end
        elsif content
          text_segments << content.to_s
        end

        fallback_text = msg["text"] || msg[:text]
        text_segments << fallback_text.to_s if fallback_text

        text = text_segments.compact.join("\n").strip
        text = "(no content)" if text.empty?
        parts << { "type" => "text", "text" => text }

        # Add images if present
        if msg["images"] && msg["images"].any?
          msg["images"].each do |img|
            if img["data"].to_s.start_with?("data:")
              parts << { "type" => "image", "image" => img["data"] }
            else
              mime_type = img["type"] || "image/jpeg"
              parts << { "type" => "image", "image" => "data:#{mime_type};base64,#{img["data"]}" }
            end
          end
        end

        messages << { "role" => role, "content" => parts }
      end
    end
    
    # Prepare request body
    # For Cohere reasoning/thinking models, omit temperature to avoid unsupported sampling parameters
    is_thinking_model = false
    begin
      is_thinking_model = CohereHelper.is_thinking_model?(model)
    rescue StandardError
      is_thinking_model = false
    end

    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 300,
      "messages" => messages,
      "stream" => false
    }
    body["temperature"] = options["temperature"] || 0.7 unless is_thinking_model
    # Cohere's command models can fall into a repetition loop on longer
    # generations. frequency_penalty (Cohere's documented anti-repetition lever,
    # default 0.0, range 0.0–1.0) curbs it; omitted for thinking models, which
    # reject sampling params.
    body["frequency_penalty"] = options["frequency_penalty"] || 0.3 unless is_thinking_model

    # Add tool definitions if provided (for testing tool-calling apps)
    if options["tools"] && options["tools"].any?
      # Convert to Cohere format (similar to OpenAI)
      body["tools"] = options["tools"].map do |tool|
        if tool["type"] == "function" && tool["function"]
          # Already in OpenAI format - Cohere accepts this
          tool
        else
          # Convert from simple format to OpenAI/Cohere format
          {
            "type" => "function",
            "function" => {
              "name" => tool["name"] || tool[:name],
              "description" => tool["description"] || tool[:description] || "",
              "parameters" => tool["parameters"] || tool[:parameters] || { "type" => "object", "properties" => {} }
            }
          }
        end
      end
    end

    # Make request
    target_uri = "#{API_ENDPOINT}/chat"
    http = HTTP.headers(headers)
    response = post_json_with_retries(http, target_uri, body,
                                      max_retries: MAX_RETRIES, retry_delay: RETRY_DELAY)

    # Process response
    if response&.status&.success?
      begin
        body_text = response.body.to_s
        result = JSON.parse(body_text)
        # Real provider usage for the Conduit query path (thread-local; read+
        # cleared by Conduit#execute_query). Non-breaking; never raises.
        Thread.current[:conduit_provider_usage] =
          (Monadic::Utils::UsageNormalizer.extract("cohere", result) rescue nil)
        
        # Check for tool calls in the response (Cohere v2 API format)
        if result["message"] && result["message"]["tool_calls"] && result["message"]["tool_calls"].any?
          tool_calls = result["message"]["tool_calls"].map do |tc|
            {
              "name" => tc.dig("function", "name") || tc["name"],
              "args" => begin
                args = tc.dig("function", "arguments") || tc["parameters"] || "{}"
                args.is_a?(String) ? JSON.parse(args) : args
              rescue JSON::ParserError
                {}
              end
            }
          end
          # Get text content if any (including thinking content for reasoning models)
          text_content = ""
          if result["message"]["content"].is_a?(Array)
            # First try to get text items
            text_items = result["message"]["content"].select { |item| item["type"] == "text" }
            if text_items.any?
              text_content = text_items.map { |item| item["text"] }.join("\n")
            else
              # For reasoning models, thinking content may be the only content
              # Extract the actual thinking text as the response
              thinking_items = result["message"]["content"].select { |item| item["type"] == "thinking" }
              if thinking_items.any?
                # Extract the thinking text from reasoning models
                text_content = thinking_items.map { |item| item["thinking"] }.compact.join("\n")
              end
            end
          end
          return { text: text_content, tool_calls: tool_calls }
        end

        # Extract text from Cohere's specific response structure
        if result["message"] && result["message"]["content"] && result["message"]["content"].is_a?(Array)
          # Get text from content array (v2 API format)
          text_items = result["message"]["content"].select { |item| item["type"] == "text" }
          if text_items.any?
            return text_items.map { |item| item["text"] }.join("\n")
          end
          # Check for thinking-only responses (reasoning models)
          thinking_items = result["message"]["content"].select { |item| item["type"] == "thinking" }
          if thinking_items.any?
            return thinking_items.map { |item| item["thinking"] }.compact.join("\n")
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

  # Build the messages array from context, including image handling.
  # Returns [messages, messages_containing_img] on success, or an error Array to return immediately.
  private def build_cohere_messages(context, session, obj, role, message, initial_prompt, websearch, &block)
    messages = []
    messages_containing_img = false

    # Check if Progressive Tool Disclosure is enabled
    ptd_active = APPS[obj["app_name"]]&.respond_to?(:settings) && APPS[obj["app_name"]].settings.dig(:progressive_tools)

    # Use unified system prompt injector
    initial_prompt_with_suffix = Monadic::Utils::SystemPromptInjector.augment(
      base_prompt: initial_prompt.to_s,
      session: session,
      options: {
        websearch_enabled: websearch,
        reasoning_model: false,
        websearch_prompt: ptd_active ? nil : WEBSEARCH_PROMPT,
        system_prompt_suffix: obj["system_prompt_suffix"]
      },
      separator: "\n\n---\n\n"
    )

    # Check if any messages contain images
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

    # Add system message
    messages << { "role" => "system", "content" => initial_prompt_with_suffix }

    # Add context messages
    context.each do |msg|
      next if msg["text"].to_s.strip.empty?
      next if msg["role"] == "system"

      if CONFIG["EXTRA_LOGGING"]
        DebugHelper.debug("Adding context message - role: #{msg['role']}, text length: #{msg['text'].to_s.length}", category: :api, level: :debug)
      end

      if msg["images"] && msg["images"].any?
        result = build_cohere_image_message(msg, obj, translate_role(msg["role"]), &block)
        return result if result.is_a?(Array) # error response
        messages << result
      else
        messages << { "role" => translate_role(msg["role"]), "content" => msg["text"].to_s.strip }
      end
    end

    # Detect initiate_from_assistant initial greeting
    is_initial_greeting = messages.length == 1 && messages[0]["role"] == "system"

    # Add current user message if not a tool call
    if role != "tool"
      suffix_options = is_initial_greeting ? {} : { prompt_suffix: obj["prompt_suffix"] }
      current_message = Monadic::Utils::SystemPromptInjector.augment_user_message(
        base_message: message,
        session: session,
        options: suffix_options
      )

      latest_msg = session[:messages].last
      if latest_msg && latest_msg["images"] && latest_msg["images"].any? && role == "user"
        messages_containing_img = true
        result = build_cohere_image_message(latest_msg, obj, "user", text_override: current_message, &block)
        return result if result.is_a?(Array) # error response
        messages << result
      else
        messages << { "role" => "user", "content" => current_message }
      end
    end

    [messages, messages_containing_img]
  end

  # Build a single Cohere message with image content. Returns the message hash, or error Array.
  private def build_cohere_image_message(msg, obj, role, text_override: nil, &block)
    content = [{ "type" => "text", "text" => (text_override || msg["text"].to_s.strip) }]

    msg["images"].each do |img|
      begin
        spec_vision = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "vision_capability")
        vision_capable = spec_vision.nil? ? true : !!spec_vision
        spec_pdf = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_pdf")
        pdf_capable = spec_pdf.nil? ? false : !!spec_pdf
      rescue StandardError
        vision_capable = true
        pdf_capable = false
      end
      if ENV[COHERE_LEGACY_MODE_ENV] == "true"
        vision_capable = true
        pdf_capable = true
      end

      if img["type"] == "application/pdf"
        formatted_error = Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: "Cohere does not support PDF input. Please paste relevant text or use a provider that supports PDFs (e.g., Gemini, Claude, OpenAI).",
          code: 400
        )
        res = { "type" => "error", "content" => formatted_error }
        block&.call res
        return [res]
      end
      unless vision_capable
        formatted_error = Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: "This model does not support image input (vision).",
          code: 400
        )
        res = { "type" => "error", "content" => formatted_error }
        block&.call res
        return [res]
      end

      if img["data"].start_with?("data:")
        content << { "type" => "image", "image" => img["data"] }
      else
        mime_type = img["type"] || "image/jpeg"
        content << { "type" => "image", "image" => "data:#{mime_type};base64,#{img["data"]}" }
      end
    end

    { "role" => role, "content" => content }
  end

  # Configure reasoning (thinking) mode for Cohere command-a-reasoning models.
  # Modifies body in-place: sets body["thinking"] and potentially body["messages"] for single-text workaround.
  private def configure_cohere_reasoning(body, messages, obj, session)
    is_reasoning_model = CohereHelper.is_thinking_model?(obj["model"])
    valid_reasoning_values = %w[enabled disabled]
    if is_reasoning_model && !valid_reasoning_values.include?(obj["reasoning_effort"].to_s.strip.downcase)
      obj["reasoning_effort"] = "enabled"
    end

    return unless is_reasoning_model && obj["reasoning_effort"]

    has_assistant_messages = messages.any? { |m| m["role"] == "assistant" }

    Monadic::Utils::ExtraLogger.log { "Cohere reasoning check:\n  Model: #{obj["model"]}\n  Reasoning effort: #{obj["reasoning_effort"]}\n  Has assistant messages: #{has_assistant_messages}\n  Message count: #{messages.size}\n  Message roles: #{messages.map { |m| m["role"] }.join(", ")}" }

    # Models flagged `native_multiturn_reasoning` (e.g. North Mini Code) handle
    # the standard Cohere v2 multi-turn tool flow with reasoning on — verified
    # empirically — so they skip the single-text flattening below and keep the
    # native message array. Flattening is reserved for models like
    # command-a-reasoning that need it.
    native_multiturn = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "native_multiturn_reasoning") == true

    if obj["reasoning_effort"] == "enabled"
      if has_assistant_messages && !native_multiturn
        Monadic::Utils::ExtraLogger.log { "Cohere: Using single-text workaround for reasoning model with history" }

        conversation_text = format_conversation_as_single_text(messages)

        # Add language reminder at the end of flattened text
        lang = session[:runtime_settings]&.[](:language)
        if lang == "auto"
          conversation_text += "\n\nIMPORTANT: Respond in the same language as the user's latest message (after 'Now, the user asks:'). Default to English if unclear."
        elsif lang && lang != ""
          lang_info = Monadic::Utils::LanguageConfig::LANGUAGES[lang]
          if lang_info
            conversation_text += "\n\nIMPORTANT: You MUST respond in #{lang_info[:english]}."
          end
        end

        body["messages"] = [{ "role" => "user", "content" => conversation_text }]
        body["thinking"] = { "type" => "enabled" }

        Monadic::Utils::ExtraLogger.log { "  Single text format applied. New message count: #{body["messages"].size}\n  Thinking enabled: #{body["thinking"].inspect}\n  Message preview (first 500 chars):\n  #{body["messages"][0]["content"][0..500]}...\n  Total message length: #{body["messages"][0]["content"].length} chars" }
      else
        body["thinking"] = { "type" => "enabled" }
        DebugHelper.debug("Cohere: Reasoning enabled for #{obj["model"]} (no assistant messages)", category: :api, level: :info)
      end
    else
      body["thinking"] = { "type" => "disabled" }
      DebugHelper.debug("Cohere: Reasoning disabled for #{obj["model"]}", category: :api, level: :info)
    end
  end

  # Configure tools for the request: progressive disclosure, legacy tools, SSOT capability check.
  # Modifies body in-place.
  private def configure_cohere_tools(body, obj, app, session, role, websearch)
    # NOTE: tools must be configured on tool-round requests (role == "tool")
    # too. The conversation replays an assistant message carrying tool_calls,
    # and Cohere rejects that with INVALID_TOOL_GENERATION unless the matching
    # tools are also present. It is also required for multi-round tool use —
    # e.g. a skill unlocked via request_tool is only usable if the follow-up
    # request still carries the (now-expanded) tool set. Loop protection is
    # handled separately by MAX_FUNC_CALLS.
    app_settings = APPS[app]&.settings
    app_tools = app_settings&.[]("tools")
    progressive_settings = app_settings && (app_settings[:progressive_tools] || app_settings["progressive_tools"])
    progressive_enabled = !!progressive_settings

    Monadic::Utils::ExtraLogger.log { "\n=== COHERE TOOLS CONFIG ===\nApp: #{app}, Progressive: #{progressive_enabled}, Tools count: #{app_tools&.length || 0}" }

    if app_settings
      begin
        app_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
          app_name: app,
          session: session,
          app_settings: app_settings,
          default_tools: app_tools
        )
      rescue StandardError => e
        DebugHelper.debug("Cohere: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning)
      end

      begin
        app_tools = Monadic::Utils::ProgressiveToolManager.annotate_request_tool(
          tools: app_tools, app_settings: app_settings, session: session, app_name: app
        )
      rescue StandardError => e
        DebugHelper.debug("Cohere: Skill menu annotation skipped due to #{e.message}", category: :api, level: :warning)
      end
    end

    if progressive_enabled
      final_tools = Array(app_tools).flatten.compact.select { |tool| tool.is_a?(Hash) }
      # Web search is an explicit user toggle, so make the Tavily tools directly
      # available (not gated behind request_tool) even in progressive mode.
      # Without this a progressive app (e.g. Chat) with Web Search ON has no way
      # to actually search, and answers from stale training data instead.
      final_tools.push(*WEBSEARCH_TOOLS) if websearch
      final_tools.uniq! { |t| (t["function"] || t[:function] || t).values_at("name", :name).compact.first }
      if final_tools.empty?
        body.delete("tools")
      else
        body["tools"] = final_tools
      end
    else
      if obj["tools"] && !obj["tools"].empty?
        base_tools = Array(app_tools || []).select { |tool| tool.is_a?(Hash) }
        body["tools"] = base_tools
        body["tools"].push(*WEBSEARCH_TOOLS) if websearch && body["tools"]
        body["tools"].uniq! if body["tools"]
      elsif app_tools && !app_tools.empty?
        body["tools"] = Array(app_tools).select { |tool| tool.is_a?(Hash) }
        body["tools"].push(*WEBSEARCH_TOOLS) if websearch
        body["tools"].uniq!
      elsif websearch
        body["tools"] = WEBSEARCH_TOOLS.dup
      else
        body.delete("tools")
      end
    end

    # SSOT: If the model is not tool-capable, remove tools/tool_choice
    begin
      spec_tool = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "tool_capability")
      tool_capable = spec_tool.nil? ? true : !!spec_tool
    rescue StandardError
      tool_capable = true
    end
    if ENV[COHERE_LEGACY_MODE_ENV] == "true"
      tool_capable = true
    end
    unless tool_capable
      body.delete("tools")
      body.delete("tool_choice")
    end
  end

  # Execute the Cohere HTTP API call with retries, and route to streaming processing.
  private def execute_cohere_api_call(headers, body, app, session, call_depth, &block)
    target_uri = "#{API_ENDPOINT}/chat"
    http = HTTP.headers(headers)

    # Privacy Filter: mask user-message PII before sending to Cohere. No-op
    # when the app does not declare `privacy do; enabled true; end` in MDSL.
    # Cohere v2 uses messages with content as Array of typed parts ({type: "text",
    # text: ...}); image parts ({type: "image"}) pass through untouched.
    app_settings = (defined?(APPS) && APPS[app]) ? APPS[app].settings : nil
    if privacy_enabled_for?(app_settings, session) && body["messages"].is_a?(Array)
      body["messages"] = apply_privacy_to_messages(body["messages"], session, app_settings)
    end

    # Diagnostic: dump the exact tools and message roles sent to Cohere. The v2
    # API rejects malformed tool schemas (and model-generated calls to
    # non-existent tools) with a 422 "INVALID_TOOL_GENERATION"; this makes the
    # offending request visible without a live repro.
    if CONFIG["EXTRA_LOGGING"] && body.is_a?(Hash)
      Monadic::Utils::ExtraLogger.log do
        tool_names = Array(body["tools"]).map { |t| (t["function"] || t[:function] || t)["name"] || (t["function"] || t[:function] || t)[:name] }
        "[Cohere REQUEST] model=#{body["model"]} roles=#{Array(body["messages"]).map { |m| m["role"] }.join(",")} " \
          "tool_names=#{tool_names.inspect}"
      end
    end

    res = nil
    MAX_RETRIES.times do |i|
      begin
        res = http.timeout(
          connect: open_timeout,
          write: write_timeout,
          read: read_timeout
        ).post(target_uri, json: body)
        break if res.status.success?
        if CONFIG["EXTRA_LOGGING"]
          body_preview = begin
            res.body.to_s[0, 800]
          rescue StandardError
            "(unreadable)"
          end
          Monadic::Utils::ExtraLogger.log { "[Cohere RESPONSE ERROR] status=#{res.status} body=#{body_preview}" }
        end
        sleep RETRY_DELAY * (i + 1)
      rescue HTTP::Error, HTTP::TimeoutError => e
        next unless i == MAX_RETRIES - 1
        formatted_error = Monadic::Utils::ErrorFormatter.network_error(
          provider: "Cohere", message: "Network error: #{e.message}", timeout: true
        )
        res = { "type" => "error", "content" => formatted_error }
        block&.call res
        return [res]
      end
    end

    unless res&.status&.success?
      error_report = begin
                      JSON.parse(res.body)
                    rescue StandardError
                      { "message" => "Unknown error occurred" }
                    end
      Monadic::Utils::ExtraLogger.log { "[Cohere API Error] #{error_report}" }
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "Cohere",
        message: error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      return [res]
    end

    process_json_data(app: app, session: session, query: body, res: res.body, call_depth: call_depth, &block)
  end

  public

  # Main API request handler
  def api_request(role, session, call_depth: 0, &block)
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
      # Reset the cross-round tool_plan accumulator (see the tool branch and
      # build_cohere_text_response). Some reasoning models (e.g. command-a-plus)
      # emit their reasoning as tool_plan on tool rounds rather than as
      # content.thinking; accumulating it here lets it surface in the final
      # thinking panel instead of vanishing when tools are involved.
      session[:cohere_tool_plan_reasoning] = nil
    end

    current_call_depth = session[:call_depth_per_turn] || 0
    num_retrial = 0

    obj = session[:parameters]
    app = obj["app_name"]

    session[:messages] ||= []
    initial_prompt = if session[:messages].empty? || session[:messages].first.nil?
                       obj["initial_prompt"] || ""
                     else
                       session[:messages].first&.dig("text").to_s
                     end

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = Monadic::SharedTools::TavilyDefinitions.websearch_requested?(obj)
    message = obj["message"]

    # Handle non-tool messages and update session
    if role != "tool"
      message ||= "Hi there!"

      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      # Skip user card for initiate_from_assistant (obj["message"] is nil/empty)
      if role == "user" && obj["message"].to_s.strip != ""
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"]),
                  "app_name" => obj["app_name"]
                } }
        block&.call res

        # Check if this user message was already added by websocket.rb (for context extraction)
        # to avoid duplicate consecutive user messages that cause API errors
        existing_msg = session[:messages].find do |m|
          m["role"] == "user" && m["text"] == obj["message"]
        end

        if existing_msg
          # Update existing message with additional fields instead of adding new one
          existing_msg.merge!(res["content"])
        else
          session[:messages] << res["content"]
        end
      end
    end

    # After sending user card, validate API key and return explicit error if not set
    api_key = CONFIG["COHERE_API_KEY"]
    unless api_key && !api_key.to_s.strip.empty?
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Cohere",
        env_var: "COHERE_API_KEY"
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Initialize and manage message context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages][0...-1].last(context_size).each { |msg| msg["active"] = true }
    strip_inactive_image_data(session)

    # Build messages
    messages_result = build_cohere_messages(context, session, obj, role, message, initial_prompt, websearch, &block)
    return messages_result if messages_result.is_a?(Array) && messages_result.first.is_a?(Hash) && messages_result.first["type"] == "error"
    messages, messages_containing_img = messages_result

    # Resolve streaming capability
    begin
      spec_stream = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_streaming")
      supports_streaming = spec_stream.nil? ? true : !!spec_stream
    rescue StandardError
      supports_streaming = true
    end
    supports_streaming = true if ENV[COHERE_LEGACY_MODE_ENV] == "true"

    # Construct request body
    body = { "model" => obj["model"], "stream" => supports_streaming }
    body["temperature"] = temperature if temperature && temperature.between?(0.0, 2.0)
    body["max_tokens"] = max_tokens if max_tokens && max_tokens.positive?

    # Include tool results for tool responses
    if role == "tool" && obj["tool_results"]
      messages = messages + obj["tool_results"]
      Monadic::Utils::ExtraLogger.log { "Cohere: Added #{obj["tool_results"].size} tool result messages to conversation" }
    end

    # Configure reasoning mode
    configure_cohere_reasoning(body, messages, obj, session)

    # Switch to vision-capable model if needed
    if messages_containing_img
      begin
        vprop = Monadic::Utils::ModelSpec.get_model_property(body["model"], "vision_capability")
        current_vision = vprop == true
      rescue StandardError
        current_vision = true
      end
      unless current_vision
        original_model = body["model"]
        body["model"] = "command-a-vision-07-2025"
        if block && original_model != body["model"]
          block.call({ "type" => "system_info", "content" => "Model automatically switched from #{original_model} to #{body['model']} for image processing capability." })
        end
      end
    end

    # Configure tools
    configure_cohere_tools(body, obj, app, session, role, websearch)

    # Reconcile thinking-disabled with tools (see helper). Runs after tool
    # configuration because reasoning is configured before tools are known.
    drop_incompatible_thinking!(body)

    # Set messages if not already set by reasoning workaround
    body["messages"] ||= messages
    body["messages"] = Array(body["messages"]).compact
    body["messages"].map! { |msg| normalize_cohere_message(msg) }
    body["messages"].reject! { |msg| cohere_message_empty?(msg) }

    # Ensure at least one user message
    unless body["messages"].any? { |m| m.is_a?(Hash) && m["role"] == "user" && extract_cohere_text(m).to_s.strip != "" }
      fallback_text = obj["message"].to_s.strip
      fallback_text = "Hello" if fallback_text.empty?
      body["messages"] << normalize_cohere_message({ "role" => "user", "content" => [{ "type" => "text", "text" => fallback_text }] })
    end

    # Handle initiate_from_assistant
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      body["messages"] << { "role" => "user", "content" => "Please proceed according to your system instructions and introduce yourself." }
    end

    # Capability audit
    Monadic::Utils::ExtraLogger.log { "Cohere SSOT capabilities for #{obj['model']}: model=#{body['model']}, messages=#{body['messages']&.size}" }

    # Force text-only response when force-stop is active
    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Configure headers and execute API call
    headers = {
      "accept" => "application/json",
      "content-type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    execute_cohere_api_call(headers, body, app, session, call_depth, &block)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Cohere] Unexpected error: #{e.message}" }
    Monadic::Utils::ExtraLogger.log { "[Cohere] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(provider: "Cohere", message: "Unexpected error: #{e.message}")
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end

  # A Cohere reasoning model (e.g. command-a-plus) rejects a tool request sent
  # with thinking explicitly disabled: `thinking: {type: "disabled"}` together
  # with `tools` returns 422 "INVALID_TOOL_GENERATION". Verified against the
  # live API — omitting the thinking key (letting Cohere default) succeeds, as
  # does enabling it. Since body["thinking"] is only ever set for reasoning
  # models, drop the explicit disable whenever tools are present so an app that
  # pins reasoning_effort "disabled" (e.g. Chat) can still use tools.
  private def drop_incompatible_thinking!(body)
    return body unless body.is_a?(Hash)

    if body["tools"].is_a?(Array) && !body["tools"].empty? && body.dig("thinking", "type") == "disabled"
      body.delete("thinking")
      Monadic::Utils::ExtraLogger.log { "[Cohere] Dropped thinking:disabled because tools are present (avoids 422 INVALID_TOOL_GENERATION)" }
    end
    body
  end

  # Build the final text response from streaming results, including thinking and usage
  private def build_cohere_text_response(result:, obj:, finish_reason:, thinking_content:,
                                         fragment_sequence:, usage_input_tokens:,
                                         usage_output_tokens:, usage_total_tokens:,
                                         session: nil, &block)
    if result
      # Send DONE message to complete the stream
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => finish_reason })

      response = [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result }
            }
          ]
        }
      ]

      # Add thinking content if collected. Prefer content.thinking; when a
      # reasoning model emitted none (e.g. command-a-plus, which routes its
      # reasoning through tool_plan on tool rounds), fall back to the tool_plan
      # accumulated across rounds so the persistent thinking toggle still
      # reflects the model's reasoning instead of disappearing.
      thinking_text = if thinking_content && !thinking_content.empty?
                        thinking_content.join("")
                      elsif session
                        session[:cohere_tool_plan_reasoning].to_s
                      end
      if thinking_text && !thinking_text.strip.empty?
        response[0]["choices"][0]["message"]["thinking"] = thinking_text
      end

      # Attach usage if captured
      if usage_input_tokens || usage_output_tokens || usage_total_tokens
        response[0]["usage"] = {
          "input_tokens" => usage_input_tokens,
          "output_tokens" => usage_output_tokens,
          "total_tokens" => usage_total_tokens
        }.compact
      end
      response
    else
      # No text content — reasoning model fallback
      is_reasoning_model = obj["reasoning_model"] || CohereHelper.is_thinking_model?(obj["model"])
      reasoning_actually_enabled = obj["reasoning_effort"] == "enabled"

      if is_reasoning_model && reasoning_actually_enabled
        default_response = "I've processed your request. How can I help you further?"

        block&.call({
          "type" => "fragment", "content" => default_response,
          "sequence" => fragment_sequence, "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        })
        block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" })

        [{ "choices" => [{ "finish_reason" => finish_reason || "stop", "message" => { "content" => default_response } }] }]
      else
        if CONFIG["EXTRA_LOGGING"]
          DebugHelper.debug("Unexpected empty response for non-reasoning scenario", category: :api, level: :warn)
        end

        block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
        [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }]
      end
    end
  end

  public

  # Process streaming JSON response data
  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log { "Processing query (Call depth: #{call_depth})" }
    Monadic::Utils::ExtraLogger.log_json("Query", query)

    # Store the request parameters for constructing the final response
    obj = session[:parameters]
    app_name = obj["app_name"]

    texts = []
    fragment_sequence = 0  # Sequence number for fragments to ensure ordering
    tool_calls = []
    finish_reason = nil
    buffer = String.new
    current_tool_call = nil
    accumulated_tool_calls = []
    citations = []  # Store citation data
    thinking_content = []  # Store thinking content from reasoning models
    tool_plan_content = []  # Store tool_plan content separately (internal reasoning, not user-facing)
    # Track usage metrics if present in streaming deltas
    usage_input_tokens = nil
    usage_output_tokens = nil
    usage_total_tokens = nil

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      # Skip encoding cleanup - buffer.valid_encoding? check above is sufficient
      # Encoding cleanup with replace: "" can delete valid bytes from incomplete multibyte characters
      # that will become complete when the next chunk arrives
      # buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      # buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      pattern = /(\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          begin
            json_data = matched.match(pattern)[1]
            json = JSON.parse(json_data)

            Monadic::Utils::ExtraLogger.log_json("Cohere stream chunk", json)

            # Handle different event types from v2 streaming API
            case json["type"]
            when "message-start"
              buffer = ""
              accumulated_tool_calls = []
            when "content-start"
            when "content-delta"
              if content = json.dig("delta", "message", "content")
                # Handle thinking content for reasoning models (Command A Reasoning)
                if thinking = content["thinking"]
                  unless thinking.strip.empty?
                    # Store thinking content for final response
                    thinking_content << thinking

                    # Send thinking content to UI (like Claude/OpenAI/Mistral)
                    res = {
                      "type" => "thinking",
                      "content" => thinking
                    }
                    block&.call res

                    # Debug logging
                    DebugHelper.debug("Cohere thinking: #{thinking}", category: :api, level: :debug) if CONFIG["EXTRA_LOGGING"]
                  end
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
                        "sequence" => fragment_sequence,
                        "timestamp" => Time.now.to_f,
                        "is_first" => fragment_sequence == 0
                      }
                      fragment_sequence += 1
                      block&.call res
                    end
                  end
                end
              end
            when "tool-plan-delta"
              if text = json.dig("delta", "message", "tool_plan")
                # Store tool_plan separately - it's internal reasoning, not user-facing content
                # Do NOT add to buffer or texts as those are for user-facing response
                # Do NOT send to UI - tool_plan is internal and should never be displayed
                tool_plan_content << text

                # Debug logging only - do NOT send fragments to UI
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("Cohere tool_plan: #{text}", category: :api, level: :debug)
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
                if json["delta"]["finish_reason"] == "ERROR"
                  error_lines = ["\n=== COHERE API ERROR ===", "Finish reason: ERROR"]
                  error_lines << "Error message: #{json["delta"]["error"]}" if json["delta"]["error"]
                  error_lines << "Usage info: #{json["delta"]["usage"].inspect}" if json["delta"]["usage"]
                  error_lines << "Full delta: #{json["delta"].inspect}"
                  error_lines << "=== END ERROR ===\n"
                  Monadic::Utils::ExtraLogger.log { error_lines.join("\n") }
                end
                # Capture usage if present on message-end
                if json["delta"]["usage"].is_a?(Hash)
                  usage = json["delta"]["usage"]
                  usage_input_tokens = usage["prompt_tokens"] || usage["input_tokens"] || usage_input_tokens
                  usage_output_tokens = usage["completion_tokens"] || usage["output_tokens"] || usage_output_tokens
                  usage_total_tokens = usage["total_tokens"] || (usage_input_tokens.to_i + usage_output_tokens.to_i if usage_input_tokens && usage_output_tokens) || usage_total_tokens
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
      Monadic::Utils::ExtraLogger.log { "[Cohere Streaming] Error: #{e.message}" }
      Monadic::Utils::ExtraLogger.log { "[Cohere Streaming] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    end

    # Prepare final result from accumulated text
    result = texts.empty? ? nil : texts.join("")

    if CONFIG["EXTRA_LOGGING"]
      DebugHelper.debug("Cohere streaming complete - texts array size: #{texts.size}, result length: #{result.to_s.length}", category: :api, level: :info)
    end

    # Process citations if any were collected
    result = process_citations(result, citations) if result && citations.any?

    # Route to tool processing or build final text response
    if accumulated_tool_calls.any?
      tool_plan_text = tool_plan_content.empty? ? nil : tool_plan_content.join("")
      # Accumulate only genuine tool_plan reasoning for the thinking panel —
      # never the synthetic fallback below.
      if tool_plan_text && !tool_plan_text.strip.empty?
        acc = session[:cohere_tool_plan_reasoning].to_s
        acc += "\n\n" unless acc.empty?
        session[:cohere_tool_plan_reasoning] = acc + tool_plan_text
      end

      # Do NOT echo tool_plan back on the assistant tool-call turn. Verified
      # against the live API: command-a-plus and north-mini-code reject any
      # tool_plan on a replayed assistant message ("`tool plan` cannot be used
      # with this model", 400); command-a-reasoning tolerates it. Omitting it
      # is accepted by every model, so leave it out universally. (The streamed
      # tool_plan is still captured above for the thinking panel — that is a
      # display concern, separate from what we send back.)
      context = [
        {
          "role" => "assistant",
          "tool_calls" => accumulated_tool_calls
        }
      ]

      session[:call_depth_per_turn] += 1
      if session[:call_depth_per_turn] > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => Monadic::Utils::ErrorFormatter.api_error(
          provider: "Cohere",
          message: "Maximum function call depth exceeded"
        ) }]
      end

      return process_functions(app, session, accumulated_tool_calls, context, session[:call_depth_per_turn], &block)
    else
      build_cohere_text_response(
        result: result, obj: obj, finish_reason: finish_reason,
        thinking_content: thinking_content, fragment_sequence: fragment_sequence,
        usage_input_tokens: usage_input_tokens, usage_output_tokens: usage_output_tokens,
        usage_total_tokens: usage_total_tokens, session: session, &block
      )
    end
  end

  # Execute a single Cohere tool function: parse arguments, dispatch, handle errors
  # Returns [context_entry, error_stop] tuple
  private def invoke_cohere_tool_function(app, session, tool_call, function_name, &block)
    tool_call_id = tool_call["id"]

    # Parse and sanitize function arguments
    arguments = tool_call.dig("function", "arguments")
    argument_hash = if arguments.is_a?(String) && !arguments.empty?
      begin
        JSON.parse(arguments)
      rescue JSON::ParserError
        {}
      end
    else
      {}
    end

    argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
      next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

      memo[k.to_sym] = v
    end

    # Special handling for check_environment function
    argument_hash = {} if function_name == "check_environment" && argument_hash.empty?

    # request_tool (progressive disclosure) is handled group-aware in the execute
    # block below via ProgressiveToolManager.handle_request_tool.

    # Expand vocabulary ${TOKEN}s before the tool runs; before :session
    # injection so the session object is never walked. No-op without vocabulary.
    argument_hash = expand_tool_args_for_vocabulary(argument_hash, session, APPS[app]&.settings)

    # Inject session for tools that need it
    method_obj = APPS[app].method(function_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |_type, name| name == :session }
      argument_hash[:session] = session
    end

    # Execute function and capture result
    begin
      function_return = if function_name == "request_tool"
        Monadic::Utils::ProgressiveToolManager.handle_request_tool(
          session: session, app_name: app, app_settings: (APPS[app]&.settings || {}), argument_hash: argument_hash
        )
      else
        APPS[app].send(function_name.to_sym, **argument_hash)
      end
      send_verification_notification(session, &block) if function_name == "report_verification"
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Cohere Tools] Function execution error: #{e.message}" }
      function_return = Monadic::Utils::ErrorFormatter.tool_error(
        provider: "Cohere", tool_name: function_name, message: e.message
      )
    end

    # TTS extraction is a non-fatal side effect — isolate it so a failure here
    # cannot clobber a successful tool result (which previously surfaced as a
    # bogus "Tool Execution Error" and made the model re-call in a loop).
    begin
      Monadic::Utils::TtsTextExtractor.extract_tts_text(
        app: app, function_name: function_name,
        argument_hash: argument_hash, session: session
      )
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Cohere Tools] TTS extract (non-fatal): #{e.message}" }
    end

    # Check for repeated errors
    if handle_function_error(session, function_return, function_name, &block)
      error_entry = {
        "role" => "tool", "tool_call_id" => tool_call_id,
        "content" => [{ "type" => "text", "text" => function_return.to_s }]
      }
      return [error_entry, true]
    end

    # Store gallery_html for server-side injection
    if function_return.is_a?(Hash) && function_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << function_return[:gallery_html]
    end

    # Collect _image for visual self-verification and clean underscore keys
    pending_images = nil
    if function_return.is_a?(Hash) && function_return[:_image]
      pending_images = Array(function_return[:_image])
      clean_return = function_return.reject { |k, _| k.to_s.start_with?("_") }
      serialized_return = JSON.generate(clean_return)
    else
      serialized_return = nil
    end

    # Process function return to detect generated images
    processed_return = function_return.to_s
    if processed_return.include?("File(s) generated or modified:")
      file_matches = processed_return.scan(/\/data\/[^\s,]+(?:\.\w+)?/)
      image_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']
      image_files = file_matches.filter_map do |fp|
        clean_path = fp.gsub(/[,;.]$/, '')
        clean_path if image_extensions.any? { |ext| clean_path.downcase.end_with?(ext) }
      end

      if image_files.any?
        processed_return += "\n\nIMPORTANT: Display the generated image(s) using the following HTML:\n"
        image_files.each { |img_path| processed_return += "<div class=\"generated_image\"><img src=\"#{CGI.escapeHTML(img_path.to_s)}\" /></div>\n" }
        processed_return += "\nPlease include the above HTML in your response to show the image(s) to the user."
      end
    end

    # Determine content for the tool result document
    result_content = serialized_return || (function_return.is_a?(Hash) || function_return.is_a?(Array) ?
                      JSON.generate(function_return) : processed_return)

    tool_entry = {
      "role" => "tool", "tool_call_id" => tool_call_id,
      "content" => [
        {
          "type" => "document",
          "document" => {
            "id" => tool_call_id,
            # Cohere v2 requires document.data to be a JSON STRING, not a raw
            # object. Sending a Hash here made the model fail to register tool
            # results and re-call the same tool in a loop on multi-turn flows.
            "data" => JSON.generate({ "results" => result_content })
          }
        }
      ]
    }

    [tool_entry, false, pending_images]
  end

  public

  # Process function calls from the API response
  def process_functions(app, session, tool_calls, context, call_depth, &block)
    obj = session[:parameters]
    pending_tool_images = nil

    block&.call({ "type" => "wait", "content" => "<i class='fas fa-cogs'></i> PROCESSING FUNCTION RESULTS" })

    tool_calls.each do |tool_call|
      function_name = tool_call.dig("function", "name")
      next if function_name.nil?

      record_tool_call(session, function_name)
      block&.call({ "type" => "tool_executing", "content" => function_name })

      tool_entry, error_stop, images = invoke_cohere_tool_function(app, session, tool_call, function_name, &block)
      pending_tool_images = images if images&.any?

      if tool_entry
        context << tool_entry
        next if error_stop
      end
    end

    # Capture tool requests for progressive disclosure
    if APPS[app]&.respond_to?(:settings)
      begin
        assistant_msg = context.find { |msg| msg["role"] == "assistant" }
        assistant_text = assistant_msg&.dig("tool_plan") || ""
        Monadic::Utils::ProgressiveToolManager.capture_tool_requests(
          session: session, app_name: app,
          app_settings: APPS[app].settings, text: assistant_text
        )
      rescue StandardError => e
        DebugHelper.debug("Cohere progressive tools: failed to capture tool requests due to #{e.message}", category: :api, level: :warning)
      end
    end

    # Inject tool-generated images as user message for vision-capable models
    if pending_tool_images&.any?
      image_parts = pending_tool_images.filter_map do |img_filename|
        img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
        next unless img

        { "type" => "image", "image" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" }
      end
      if image_parts.any?
        context << {
          "role" => "user",
          "content" => [
            { "type" => "text", "text" => "[Tool-generated image. Verify the visual output before presenting results.]" },
            *image_parts
          ]
        }
      end
    end

    # Store tool results and check for error stopping
    obj["tool_results"] = context

    if should_stop_for_errors?(session)
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected. Stopping." } }] }]
    end

    block&.call({ "type" => "wait", "content" => "<i class='fas fa-check-circle'></i> FUNCTION CALLS COMPLETE" })
    block&.call({ "type" => "clear_fragments" })

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
      when "tool"
        # Include tool results in conversation history
        # Extract the tool result content from the document structure
        tool_content = extract_tool_result_text(msg)
        if tool_content && !tool_content.empty?
          conversation_messages << {
            "role" => "tool_result",
            "content" => tool_content
          }
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
        case msg["role"]
        when "user"
          result += "User: #{msg["content"]}\n\n"
        when "assistant"
          result += "Assistant: #{msg["content"]}\n\n"
        when "tool_result"
          # Format tool result as a system note showing the file was saved
          result += "[Tool Result]: #{msg["content"]}\n\n"
        end
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

  def extract_cohere_text(message)
    return "" unless message.is_a?(Hash)

    content = message["content"]
    case content
    when Array
      text_part = content.find do |part|
        part.is_a?(Hash) && part["type"].to_s.downcase == "text"
      end
      text_part ? text_part["text"].to_s : ""
    else
      content.to_s
    end
  end

  def normalize_cohere_message(message)
    return message unless message.is_a?(Hash)

    content = message["content"]
    if content.is_a?(String)
      message["content"] = [{ "type" => "text", "text" => content }]
    elsif content.is_a?(Array)
      content.each do |part|
        next unless part.is_a?(Hash)
        part["type"] = part["type"] ? part["type"].to_s.downcase : "text"
      end
    elsif content.nil?
      message["content"] = [{ "type" => "text", "text" => "" }]
    end

    message
  end

  def cohere_message_empty?(message)
    return false unless message.is_a?(Hash)

    # Never discard tool result messages or assistant messages with tool calls
    role = message["role"].to_s
    return false if role == "tool"
    return false if role == "assistant" && (message["tool_calls"] || message["tool_plan"])

    content = message["content"]
    case content
    when Array
      content.all? do |part|
        next true unless part.is_a?(Hash)
        type = part["type"].to_s.downcase
        # Preserve document-type content (used by Cohere tool results)
        if type == "image" || type == "document"
          false
        else
          part["text"].to_s.strip.empty?
        end
      end
    when String
      content.strip.empty?
    else
      content.to_s.strip.empty?
    end
  end

  # Extract text from tool result message for conversation formatting
  # Tool results have a complex structure with document/data/results format
  def extract_tool_result_text(msg)
    return "" unless msg.is_a?(Hash)

    content = msg["content"]
    return "" unless content.is_a?(Array)

    results = []
    content.each do |part|
      next unless part.is_a?(Hash)

      # Handle document format (Cohere v2 tool results). document.data is a
      # JSON string per the v2 spec; tolerate a legacy Hash too.
      if part["type"] == "document" && part["document"]
        doc = part["document"]
        data = doc["data"]
        if data.is_a?(String)
          parsed = (JSON.parse(data) rescue nil)
          results << (parsed.is_a?(Hash) && parsed["results"] ? parsed["results"].to_s : data)
        elsif data.is_a?(Hash) && data["results"]
          results << data["results"].to_s
        end
      # Handle text format
      elsif part["type"] == "text" && part["text"]
        results << part["text"].to_s
      end
    end

    results.join("\n")
  end
end
