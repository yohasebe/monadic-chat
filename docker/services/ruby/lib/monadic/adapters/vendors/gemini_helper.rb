#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"

# GeminiHelper Module - Interface for Google's Gemini AI Models
#
# IMPORTANT NOTES ON GEMINI 2.5 MODELS:
# 
# 1. Function Calling vs Structured Output Trade-off:
#    - Gemini 2.5 models cannot simultaneously support function calling and structured JSON output
#    - For function calling: MUST use `reasoning_effort: minimal`
#    - For structured JSON (monadic mode): MUST NOT use reasoning_effort parameter
#    
# 2. Tool Management Strategy:
#    - Info-gathering tools (read-only) are separated from action tools
#    - Info tools: get_jupyter_cells_with_results, list_jupyter_notebooks (no call limits)
#    - Action tools: create_jupyter_notebook, run_jupyter, add_jupyter_cells (limited to 5 calls)
#    - This prevents exhausting tool call limits with read operations
#
# 3. Reasoning Effort Configuration:
#    - "minimal": Required for function calling with Gemini 2.5 models
#    - Omit parameter: Required for structured JSON output (monadic mode)
#    - Cannot have both: Choose based on app requirements
#
# 4. Known Issues and Solutions:
#    - JSON wrapped in markdown: Remove reasoning_effort and add explicit instructions
#    - Function calls not working: Add reasoning_effort: minimal
#    - Tool call limits: Separate info tools from action tools
#
module GeminiHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1alpha"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  
  # URL Context feature for web content retrieval
  # Supports up to 20 URLs per request
  MAX_URL_CONTEXT = 20
  
  # Supported content types for URL context
  URL_CONTEXT_TYPES = {
    text: ["html", "json", "txt", "xml", "css", "js"],
    image: ["png", "jpeg", "jpg", "bmp", "webp"],
    pdf: ["pdf"]
  }.freeze
  
  # URL Context prompt for better search integration
  URL_CONTEXT_PROMPT = <<~TEXT
    When web search is requested, I will analyze web content directly from URLs.
    This allows me to provide accurate, up-to-date information from reliable sources.
    I can process HTML pages, PDFs, images, and other content types directly.
    
    For search queries, I will:
    1. Identify relevant URLs to analyze
    2. Extract and synthesize information from multiple sources
    3. Provide comprehensive answers with proper citations
    
    **Important**: I will use HTML link tags with target="_blank" and rel="noopener noreferrer" 
    attributes to provide links to source URLs.
  TEXT
  
  SAFETY_SETTINGS = [
    {
      category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_HATE_SPEECH",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_HARASSMENT",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_DANGEROUS_CONTENT",
      threshold: "BLOCK_ONLY_HIGH"
    }
  ]



  attr_reader :models
  attr_reader :cached_models

  def self.vendor_name
    "Google"
  end

  def self.list_models
    # Return cached models if they exist
    return $MODELS[:gemini] if $MODELS[:gemini]

    api_key = CONFIG["GEMINI_API_KEY"]
    return [] if api_key.nil?

    headers = {
      "Content-Type": "application/json"
    }

    target_uri = "#{API_ENDPOINT}/models?key=#{api_key}"
      http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        models = []
        model_data["models"].each do |model|
          name = model["name"].split("/").last
          display_name = model["displayName"]
          models << name if name && /Legacy/ !~ display_name
        end
      end

      return [] if !models || models.empty?

      $MODELS[:gemini] = models.filter do |model|
        /(?:embedding|aqa|vision|imagen|learnlm|gemini-1)/ !~ model
      end.reverse

    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  # Method to manually clear the cache if needed
  def clear_models_cache
    $MODELS[:gemini] = nil
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "gemini-2.0-flash")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["GEMINI_API_KEY"]
    return "Error: GEMINI_API_KEY not found" if api_key.nil?

    # Check if this is a thinking model (Gemini 2.5) - moved before body creation
    is_thinking_model = false
    # Detect specific model type for proper thinking configuration
    is_25_pro = model =~ /gemini-2\.5-pro/i
    is_25_flash = model =~ /gemini-2\.5-flash(?!-lite)/i  # Match flash but not flash-lite
    is_25_flash_lite = model =~ /gemini-2\.5-flash-lite/i
    
    if options["reasoning_effort"] || model =~ /2\.5.*preview/i
      is_thinking_model = true
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "GeminiHelper: Detected thinking model #{model} with reasoning_effort: #{options["reasoning_effort"]}"
        puts "  Model type: Pro=#{is_25_pro}, Flash=#{is_25_flash}, Flash-Lite=#{is_25_flash_lite}"
      end
    end
    
    # Set headers
    headers = {
      "content-type" => "application/json"
    }

    # Basic request body
    body = {
      "safety_settings" => SAFETY_SETTINGS,
      "generationConfig" => {
        "maxOutputTokens" => options["max_tokens"] || 800
      }
    }
    
    # Only add temperature for non-thinking models
    if !is_thinking_model
      body["generationConfig"]["temperature"] = options["temperature"] || 0.7
    else
      # For thinking models, configure thinking budget
      reasoning_effort = options["reasoning_effort"] || "low"
      user_max_tokens = options["max_tokens"] || 800
      
      case reasoning_effort
      when "none"
        # Disable thinking completely for better function calling performance
        budget_tokens = 0
      when "minimal"
        # Set minimal thinking based on model capabilities:
        # - 2.5 Pro: minimum 128 (cannot disable)
        # - 2.5 Flash: can use 0 to disable
        # - 2.5 Flash Lite: doesn't think by default
        if is_25_pro
          budget_tokens = 128  # Minimum for Pro model
        elsif is_25_flash
          budget_tokens = 0  # Flash can disable thinking
        elsif is_25_flash_lite
          budget_tokens = 0  # Flash Lite doesn't think by default
        else
          budget_tokens = 0  # Default to 0 for unknown models
        end
      when "low"
        if is_25_pro
          budget_tokens = [(user_max_tokens * 0.2).to_i, 5000].min
          budget_tokens = [budget_tokens, 128].max  # Ensure minimum for Pro
        elsif is_25_flash
          budget_tokens = [(user_max_tokens * 0.2).to_i, 4000].min
        elsif is_25_flash_lite
          budget_tokens = 512  # Minimum for Flash Lite when it thinks
        else
          budget_tokens = [(user_max_tokens * 0.2).to_i, 4000].min
        end
      when "medium"
        if is_25_pro
          budget_tokens = [(user_max_tokens * 0.6).to_i, 20000].min
          budget_tokens = [budget_tokens, 128].max  # Ensure minimum for Pro
        elsif is_25_flash
          budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
        elsif is_25_flash_lite
          budget_tokens = [(user_max_tokens * 0.6).to_i, 8000].min
          budget_tokens = [budget_tokens, 512].max  # Ensure minimum for Flash Lite
        else
          budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
        end
      when "high"
        if is_25_pro
          budget_tokens = [(user_max_tokens * 0.8).to_i, 28000].min
          budget_tokens = [[budget_tokens, 128].max, 32768].min  # Max 32768 for Pro
        elsif is_25_flash
          budget_tokens = [(user_max_tokens * 0.8).to_i, 24000].min
          budget_tokens = [budget_tokens, 24576].min  # Max 24576 for Flash
        elsif is_25_flash_lite
          budget_tokens = [(user_max_tokens * 0.8).to_i, 20000].min
          budget_tokens = [[budget_tokens, 512].max, 24576].min  # Max 24576 for Flash Lite
        else
          budget_tokens = [(user_max_tokens * 0.8).to_i, 20000].min
        end
      else
        # Default values based on model type
        if is_25_pro
          budget_tokens = 10000
        elsif is_25_flash
          budget_tokens = 8000
        elsif is_25_flash_lite
          budget_tokens = 4000
        else
          budget_tokens = 8000
        end
      end
      
      # Set thinking configuration
      body["generationConfig"]["thinkingConfig"] = {
        "thinkingBudget" => budget_tokens,
        "includeThoughts" => false  # Don't include thoughts in the final output
      }
    end
    
    # Format messages for Gemini API
    formatted_messages = []
    
    # Process messages
    if options["messages"]
      # Look for system message
      system_msg = options["messages"].find { |m| m["role"] == "system" }
      if system_msg
        # Add system as user message (Gemini has no system role)
        formatted_messages << {
          "role" => "user",
          "parts" => [{ "text" => system_msg["content"].to_s }]
        }
      end
      
      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)
        
        # Map roles to Gemini format
        gemini_role = msg["role"] == "assistant" ? "model" : "user"
        content = msg["content"] || msg["text"] || ""
        
        # Add to formatted messages
        formatted_messages << {
          "role" => gemini_role,
          "parts" => [{ "text" => content.to_s }]
        }
      end
    end
    
    # Add messages to body
    body["contents"] = formatted_messages
    
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Set up API endpoint - use v1beta for thinking models, v1alpha for others
    endpoint = is_thinking_model ? "https://generativelanguage.googleapis.com/v1beta" : API_ENDPOINT
    target_uri = "#{endpoint}/models/#{model}:generateContent?key=#{api_key}"
    http = HTTP.headers(headers)
    
    # Make request
    response = nil
    
    # Simple retry logic
    begin
      MAX_RETRIES.times do |attempt|
        response = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)
        
        # Break if successful
        break if response && response.status && response.status.success?
        
        # Wait before retrying
        sleep RETRY_DELAY
      end

      # Check for valid response
      if !response || !response.status
        return "Error: No response from Gemini API"
      end
      
      # Process successful response
      if response.status.success?
        parsed_response = JSON.parse(response.body)
        
        # Debug logging for second opinion
        if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "GeminiHelper send_query: Full response structure:"
          puts JSON.pretty_generate(parsed_response)
        end
        
        # Extract text from standard response format
        if parsed_response["candidates"] && 
           parsed_response["candidates"][0] && 
           parsed_response["candidates"][0]["content"]
          
          content = parsed_response["candidates"][0]["content"]
          
          # 1. Check for parts array structure (Gemini 1.5 style)
          if content["parts"]
            text_parts = []
            content["parts"].each do |part|
              # Skip thinking parts for non-streaming response
              next if part["thought"] == true
              # Also skip modelThinking parts
              next if part["modelThinking"]
              
              # Handle both part["text"] and part itself being a hash with "text" key
              if part["text"]
                text_parts << part["text"]
              elsif part.is_a?(Hash) && part.key?("text")
                text_parts << part["text"]
              end
            end
            
            result = text_parts.join(" ").strip
            return result unless result.empty?
          end
          
          # 2. Check for direct text in content (some Gemini versions)
          if content["text"]
            return content["text"]
          end
          
          # 3. For backward compatibility, try accessing a potential text field 
          # that might be nested in another structure
          content.each do |key, value|
            if value.is_a?(Hash) && value["text"]
              return value["text"]
            end
          end
          
          # 4. Handle response functions (for function calling)
          if content["functionResponse"] && content["functionResponse"]["response"]
            return content["functionResponse"]["response"].to_s
          end
        end
        
        # Unable to extract text from response - log the structure
        if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "GeminiHelper send_query ERROR: Unable to extract text. Response structure:"
          puts "Candidates: #{parsed_response["candidates"]&.inspect}"
          if parsed_response["candidates"] && parsed_response["candidates"][0]
            puts "First candidate: #{parsed_response["candidates"][0].inspect}"
          end
        end
        return "Error: Unable to extract text from Gemini response"
      else
        # Handle error response
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "Unknown error"
        return "Error: #{error_message}"
      end
    rescue StandardError => e
      return "Error: #{e.message}"
    end
  end
  
  # Enhanced helper method to extract text from complex response structures
  def extract_text_from_response(response, depth=0, max_depth=3)
    return nil if depth > max_depth
    
    # For nil responses
    return nil if response.nil?
    
    # For string responses (direct text)
    return response if response.is_a?(String) && !response.empty?
    
    # Handle different response formats
    if response.is_a?(Hash)
      # Special handling for Gemini response format
      if response["candidates"].is_a?(Array) && !response["candidates"].empty?
        candidate = response["candidates"][0]
        
        # Process candidate structure for text extraction
        
        # Check for content.parts structure (common in Gemini responses)
        if candidate["content"].is_a?(Hash)
          content = candidate["content"]
          
          # 1. Check for parts array structure first (Gemini 1.5)
          if content["parts"].is_a?(Array)
            text_parts = []
            content["parts"].each do |part|
              # Handle both string and hash formats
              if part.is_a?(Hash) && part["text"].is_a?(String)
                text_parts << part["text"]
              elsif part.is_a?(String)
                text_parts << part
              end
            end
            
            return text_parts.join(" ") if text_parts.any?
          end
          
          # 2. Check for direct text in content (some versions)
          return content["text"] if content["text"].is_a?(String)
          
          # 3. Recurse into nested structures looking for text
          content.each do |key, value|
            if value.is_a?(Hash) && value["text"].is_a?(String)
              return value["text"]
            end
          end
          
          # 4. Handle Gemini 2.0 empty content case
          if content["role"] == "model" && (!content["parts"] || content["parts"].empty?) && !content["text"]
            # Special handling for AI User - returning nil here will let the main method handle the error
            return nil
          end
        end
        
        # 5. Check for direct text in candidate
        return candidate["text"] if candidate["text"].is_a?(String)
        
        # 6. Check for content as string
        return candidate["content"] if candidate["content"].is_a?(String)
        
        # Recursively check candidate object 
        result = extract_text_from_response(candidate, depth+1, max_depth)
        return result if result
      end
      
      # Try common text fields with several variations
      ["text", "content", "message", "output", "result", "answer"].each do |key|
        if response[key].is_a?(String) && !response[key].empty?
          return response[key]
        elsif response[key].is_a?(Hash)
          # Look one level deeper for text
          subresult = extract_text_from_response(response[key], depth+1, max_depth)
          return subresult if subresult
        end
      end
      
      # Recursive descent into all nested objects
      response.each_value do |value|
        result = extract_text_from_response(value, depth+1, max_depth)
        return result if result
      end
    elsif response.is_a?(Array)
      # Combine text from array elements if they're all strings
      if response.all? { |item| item.is_a?(String) }
        combined = response.join(" ").strip
        return combined unless combined.empty?
      end
      
      # Otherwise try each array element recursively
      response.each do |item|
        result = extract_text_from_response(item, depth+1, max_depth)
        return result if result
      end
    end
    
    # Nothing found
    nil
  end

  # Gemini-specific websearch implementation using URL Context
  def websearch_agent(query: "")
    DebugHelper.debug("Gemini websearch_agent called with query: #{query}", category: :web_search, level: :debug)
    
    # For Gemini, we'll return a message indicating that URL Context handles search
    # The actual URL processing happens in the api_request method
    <<~RESPONSE
      I'll search for information about: #{query}
      
      [Note: Gemini uses native URL Context feature for web search. 
       The search is integrated directly into the model's response generation.]
    RESPONSE
  end
  
  # Helper method to process URL context for web search
  def process_url_context(urls)
    return nil unless urls.is_a?(Array) && !urls.empty?
    
    # Limit to maximum allowed URLs
    urls = urls.first(MAX_URL_CONTEXT)
    
    # Convert URLs to Gemini's URL context format
    url_parts = urls.map do |url|
      { "url" => url }
    end
    
    DebugHelper.debug("Gemini URL Context: Processing #{url_parts.length} URLs", category: :api, level: :debug)
    url_parts
  end
  
  # Helper method to search for URLs based on query (placeholder for actual search logic)
  def search_urls_for_query(query)
    # This is a simplified version - in production, you might want to:
    # 1. Use a search API to find relevant URLs
    # 2. Parse existing search results from Google
    # 3. Use predefined URL patterns based on query type
    
    # For now, we'll construct Google search URLs as a fallback
    # This allows Gemini to at least attempt to process search-related content
    search_urls = []
    
    # Add Google search URL
    encoded_query = URI.encode_www_form_component(query)
    search_urls << "https://www.google.com/search?q=#{encoded_query}"
    
    # You could add more specialized URLs based on query patterns
    # For example, Wikipedia for general knowledge, news sites for current events, etc.
    
    DebugHelper.debug("Gemini URL Context: Generated search URLs for query: #{query}", category: :api, level: :debug)
    search_urls
  end
  
  # Helper method to determine which tools should be available next for thinking models
  def get_next_allowed_tools(completed_tools)
    # Define the expected sequence for Jupyter operations
    if completed_tools.empty?
      # First, we need to start Jupyter or create a notebook
      ["run_jupyter", "create_jupyter_notebook", "list_jupyter_notebooks"]
    elsif completed_tools.include?("run_jupyter") && !completed_tools.include?("create_jupyter_notebook")
      # After starting Jupyter, create a notebook
      ["create_jupyter_notebook", "list_jupyter_notebooks"]
    elsif completed_tools.include?("create_jupyter_notebook") && !completed_tools.include?("add_jupyter_cells")
      # After creating notebook, add cells
      ["add_jupyter_cells", "get_jupyter_cells_with_results"]
    else
      # Allow all tools if we're past the initial sequence
      nil  # This will allow all tools
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      # ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/config/env file.
      error_message = "ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    temperature = obj["temperature"]&.to_f
    
    # Handle max_tokens, prioritizing AI_USER_MAX_TOKENS for AI User mode
    if obj["ai_user"]
      max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || obj["max_tokens"]&.to_i
    else
      max_tokens = obj["max_tokens"]&.to_i
    end

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Use native Google search when websearch is enabled
    websearch = obj["websearch"]
    
    DebugHelper.debug("Gemini websearch enabled: #{websearch}", category: :api, level: :debug)
    
    # Handle thinking models based on reasoning_effort parameter presence
    reasoning_effort = obj["reasoning_effort"]
    is_thinking_model = !reasoning_effort.nil? && !reasoning_effort.empty?

    if role != "tool"
      message = obj["message"].to_s

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
                  "lang" => detect_language(message)
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
        session[:messages] << res["content"]
        block&.call res
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json"
    }

    body = {
      safety_settings: SAFETY_SETTINGS
    }

    if temperature || max_tokens || is_thinking_model
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
      
      # Configure thinking for Gemini 2.5 models with reasoning_effort
      if is_thinking_model && reasoning_effort
        model = obj["model"]
        # Detect specific model type for proper thinking configuration
        is_25_pro = model =~ /gemini-2\.5-pro/i
        is_25_flash = model =~ /gemini-2\.5-flash(?!-lite)/i  # Match flash but not flash-lite
        is_25_flash_lite = model =~ /gemini-2\.5-flash-lite/i
        
        if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "GeminiHelper api_request: Model type detection - Pro=#{is_25_pro}, Flash=#{is_25_flash}, Flash-Lite=#{is_25_flash_lite}"
        end
        
        # Calculate thinking budget based on reasoning_effort
        # 2.5 Pro: 128-32,768, 2.5 Flash: 0-24,576, 2.5 Flash Lite: 512-24,576 (doesn't think by default)
        user_max_tokens = max_tokens || 8192
        
        case reasoning_effort
        when "none"
          # Disable thinking completely for better function calling performance
          budget_tokens = 0
        when "minimal"
          # Set minimal thinking based on model capabilities:
          # - 2.5 Pro: minimum 128 (cannot disable)
          # - 2.5 Flash: can use 0 to disable
          # - 2.5 Flash Lite: doesn't think by default
          if is_25_pro
            budget_tokens = 128  # Minimum for Pro model
          elsif is_25_flash
            budget_tokens = 0  # Flash can disable thinking
          elsif is_25_flash_lite
            budget_tokens = 0  # Flash Lite doesn't think by default
          else
            budget_tokens = 0  # Default to 0 for unknown models
          end
        when "low"
          if is_25_pro
            budget_tokens = [(user_max_tokens * 0.3).to_i, 10000].min
            budget_tokens = [budget_tokens, 128].max  # Ensure minimum for Pro
          elsif is_25_flash
            budget_tokens = [(user_max_tokens * 0.3).to_i, 8000].min
          elsif is_25_flash_lite
            budget_tokens = 512  # Minimum for Flash Lite when it thinks
          else
            budget_tokens = [(user_max_tokens * 0.3).to_i, 8000].min
          end
        when "medium"
          if is_25_pro
            budget_tokens = [(user_max_tokens * 0.6).to_i, 20000].min
            budget_tokens = [budget_tokens, 128].max  # Ensure minimum for Pro
          elsif is_25_flash
            budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
          elsif is_25_flash_lite
            budget_tokens = [(user_max_tokens * 0.6).to_i, 8000].min
            budget_tokens = [budget_tokens, 512].max  # Ensure minimum for Flash Lite
          else
            budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
          end
        when "high"
          if is_25_pro
            budget_tokens = [(user_max_tokens * 0.8).to_i, 28000].min
            budget_tokens = [[budget_tokens, 128].max, 32768].min  # Max 32768 for Pro
          elsif is_25_flash
            budget_tokens = [(user_max_tokens * 0.8).to_i, 24000].min
            budget_tokens = [budget_tokens, 24576].min  # Max 24576 for Flash
          elsif is_25_flash_lite
            budget_tokens = [(user_max_tokens * 0.8).to_i, 20000].min
            budget_tokens = [[budget_tokens, 512].max, 24576].min  # Max 24576 for Flash Lite
          else
            budget_tokens = [(user_max_tokens * 0.8).to_i, 20000].min
          end
        else
          # Default values based on model type
          if is_25_pro
            budget_tokens = 10000
          elsif is_25_flash
            budget_tokens = 8000
          elsif is_25_flash_lite
            budget_tokens = 4000
          else
            budget_tokens = 8000
          end
        end
        
        # Set thinking configuration using correct structure
        body["generationConfig"]["thinkingConfig"] = {
          "thinkingBudget" => budget_tokens,
          "includeThoughts" => false  # Don't include thoughts in the final output
        }
      end
    end

    # Configure monadic response format using unified interface
    body = configure_monadic_response(body, :gemini, app)

    body["contents"] = context.compact.map do |msg|
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => msg["text"] }
        ]
      }
      message
    end

    if body["contents"].last["role"] == "user"
      # Apply monadic transformation if in monadic mode
      if obj["monadic"].to_s == "true" && role == "user"
        body["contents"].last["parts"].each do |part|
          if part["text"]
            # Extract the base message without prompt suffix
            base_message = part["text"].sub(/\n\n#{Regexp.escape(obj["prompt_suffix"] || "")}$/, "")
            # Apply monadic transformation using unified interface
            monadic_message = apply_monadic_transformation(base_message, app, "user")
            part["text"] = monadic_message
          end
        end
      end
      
      # append prompt suffix to the first item of parts with the key "text"
      body["contents"].last["parts"].each do |part|
        if part["text"]
          part["text"] = "#{part["text"]}\n\n#{obj["prompt_suffix"]}"
          break
        end
      end
      obj["images"]&.each do |img|
        body["contents"].last["parts"] << {
          "inlineData" => {
            "mimeType" => img["type"],
            "data" => img["data"].split(",")[1]
          }
        }
      end
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["contents"].empty? && initial_prompt.to_s != ""
      body["contents"] << {
        "role" => "user",
        "parts" => [{ "text" => "Please proceed according to your system instructions and introduce yourself." }]
      }
    end

    # Get tools from app settings (needed for both regular calls and tool result processing)
    app_tools = APPS[app] && APPS[app].settings["tools"] ? APPS[app].settings["tools"] : []
    
    # Skip tool setup if we're processing tool results
    if role != "tool"
      # Debug settings
      DebugHelper.debug("Gemini app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
      DebugHelper.debug("Gemini app_tools: #{app_tools.inspect}", category: :api, level: :debug)
      DebugHelper.debug("Gemini app_tools.empty?: #{app_tools.empty?}", category: :api, level: :debug)
      DebugHelper.debug("Gemini websearch: #{websearch}", category: :api, level: :debug)
      
      # Check if app_tools has actual function declarations
      has_function_declarations = false
      if app_tools
        if app_tools.is_a?(Hash) && app_tools["function_declarations"]
          has_function_declarations = !app_tools["function_declarations"].empty?
        elsif app_tools.is_a?(Array)
          has_function_declarations = !app_tools.empty?
        end
      end
      
      if has_function_declarations
        # Convert the tools format if it's an array (initialize_from_assistant apps)
        if app_tools.is_a?(Array)
          body["tools"] = [{"function_declarations" => app_tools}]
        else
          body["tools"] = [app_tools]
        end
        
        # Use AUTO mode to let model decide when to call tools
        # ANY mode can cause issues with Gemini
        body["tool_config"] = {
          "function_calling_config" => {
            "mode" => "AUTO"
          }
        }
      elsif websearch
        # Use URL Context instead of Google search for better control
        DebugHelper.debug("Gemini: URL Context enabled for web search", category: :api, level: :debug)
        
        # URL Context doesn't require tools configuration
        # URLs will be added to the content parts when processing messages
        body.delete("tools")
        body.delete("tool_config")
      else
        DebugHelper.debug("Gemini: No tools or websearch", category: :api, level: :debug)
        body.delete("tools")
        body.delete("tool_config")
      end
    end  # end of role != "tool"

    if role == "tool"
      # Add tool results as a user message to continue the conversation
      parts = obj["tool_results"].map { |result|
        { "text" => result.dig("functionResponse", "response", "content") }
      }.filter { |part| part["text"] }

      if parts.any?
        # Add tool results as a new user message to prompt the model for a response
        body["contents"] << {
          "role" => "user",
          "parts" => parts
        }
      end
      
      # For most apps, we want to stop tool calling after processing results
      # to prevent infinite loops. However, some apps may need multiple sequential calls.
      
      # Check if this is a thinking model (Gemini 2.5)
      is_thinking_model = obj["model"] && obj["model"].include?("2.5")
      
      # Check if this is a Jupyter app that needs multiple tool calls
      is_jupyter_app = app.to_s.include?("jupyter") || 
                       (session[:parameters]["app_name"] && session[:parameters]["app_name"].to_s.include?("Jupyter"))
      
      # Check what tools have been called so far
      tool_names = obj["tool_results"].map { |r| r.dig("functionResponse", "name") }.compact
      
      # For Gemini 2.5 thinking models, we now know they support function calling
      # according to the official documentation
      if is_jupyter_app
        # Separate information-gathering tools from action tools
        info_tools = ["get_jupyter_cells_with_results", "list_jupyter_notebooks"]
        action_tools = ["create_jupyter_notebook", "run_jupyter", "add_jupyter_cells", 
                       "update_jupyter_cell", "delete_jupyter_cell", 
                       "execute_and_fix_jupyter_cells", "run_code"]
        
        # Count only action tools (info tools don't count toward limits)
        action_tool_names = tool_names.reject { |name| info_tools.include?(name) }
        
        # Check what types of operations have been performed
        has_notebook_creation = action_tool_names.any? { |name| 
          ["create_jupyter_notebook", "run_jupyter"].include?(name)
        }
        
        has_cell_operations = action_tool_names.any? { |name| 
          ["add_jupyter_cells", "update_jupyter_cell", "delete_jupyter_cell"].include?(name)
        }
        
        has_execution = action_tool_names.any? { |name|
          ["execute_and_fix_jupyter_cells", "run_code"].include?(name)
        }
        
        # Count only action tool calls (not info gathering)
        action_tool_count = action_tool_names.length
        
        # Determine whether to allow more tool calls based on operation flow
        should_stop = false
        
        # Don't stop immediately after first cell operation
        # Allow multiple add_jupyter_cells calls
        
        # If we've done any execution, stop to show results
        if has_execution
          should_stop = true
        end
        
        # Stop if we've made too many ACTION calls (info calls don't count)
        if action_tool_count >= 5  # Allow enough calls for create + add cells + potential fixes
          should_stop = true
        end
        
        if should_stop
          # Disable tools completely to force text response
          body["tool_config"] = {
            "function_calling_config" => {
              "mode" => "NONE"
            }
          }
          body.delete("tools")
        else
          # Still need to call more tools
          if app_tools
            if app_tools.is_a?(Array)
              body["tools"] = [{"function_declarations" => app_tools}]
            else
              body["tools"] = [app_tools]
            end
            
            # Always use AUTO mode for Jupyter apps
            # Let the model decide when to call tools
            body["tool_config"] = {
              "function_calling_config" => {
                "mode" => "AUTO"
              }
            }
          end
        end
      else
        # For non-Jupyter apps, disable tools after any tool execution to prevent loops
        body["tool_config"] = {
          "function_calling_config" => {
            "mode" => "NONE"
          }
        }
        body.delete("tools")
      end
    end

    # Remove empty function_declarations to avoid API error
    if body["tools"] && body["tools"].is_a?(Array)
      body["tools"].each do |tool|
        if tool["function_declarations"] && tool["function_declarations"].empty?
          body.delete("tools")
          body.delete("tool_config")
          break
        end
      end
    end
    
    # Add URL Context for web search functionality
    if websearch && role == "user"
      DebugHelper.debug("Gemini: Adding URL Context for web search", category: :api, level: :debug)
      
      # Extract search query from the latest user message
      latest_message = body["contents"].last
      if latest_message && latest_message["role"] == "user" && latest_message["parts"]
        user_text = latest_message["parts"].find { |p| p["text"] }&.dig("text")
        
        if user_text
          # For now, we'll add a system instruction about URL Context capability
          # In a production environment, you might want to:
          # 1. Parse the user query to extract search terms
          # 2. Use a search API to find relevant URLs
          # 3. Add those URLs to the content
          
          # Add system instruction for URL Context if not already present
          if !body["systemInstruction"]
            body["systemInstruction"] = {
              "parts" => [
                { "text" => URL_CONTEXT_PROMPT }
              ]
            }
          else
            # Append URL Context prompt to existing system instruction
            existing_text = body["systemInstruction"]["parts"].find { |p| p["text"] }&.dig("text") || ""
            body["systemInstruction"]["parts"] = [
              { "text" => "#{existing_text}\n\n#{URL_CONTEXT_PROMPT}" }
            ]
          end
          
          # Add URLs to the message for URL Context processing
          # Check if the message contains a search-like query
          if user_text =~ /search|find|what is|who is|when|where|how|latest|recent|news|information about/i
            # Generate search URLs (simplified for now)
            urls = search_urls_for_query(user_text)
            url_parts = process_url_context(urls)
            
            if url_parts && !url_parts.empty?
              # Add URL parts to the message
              latest_message["parts"].concat(url_parts)
              DebugHelper.debug("Gemini: Added #{url_parts.length} URLs to context", category: :api, level: :debug)
            end
          end
          
          DebugHelper.debug("Gemini: URL Context system instruction added", category: :api, level: :debug)
        end
      end
    end
    
    # Debug logging
    if CONFIG["EXTRA_LOGGING"]  # Enable with EXTRA_LOGGING config setting
      puts "[DEBUG Gemini] app=#{app}, websearch=#{websearch}, app_tools=#{app_tools.inspect}"
      puts "[DEBUG Gemini] Final request body:"
      puts JSON.pretty_generate(body.dup.tap { |b| 
        # Truncate long system prompts for readability
        if b["system_instruction"] && b["system_instruction"]["parts"]
          b["system_instruction"]["parts"].each do |part|
            if part["text"] && part["text"].length > 200
              part["text"] = part["text"][0..200] + "... [truncated]"
            end
          end
        end
      })
    end
    
    # Use v1beta for thinking models, v1alpha for others
    endpoint = is_thinking_model ? "https://generativelanguage.googleapis.com/v1beta" : API_ENDPOINT
    target_uri = "#{endpoint}/models/#{obj["model"]}:streamGenerateContent?key=#{api_key}"


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
      formatted_error = format_api_error(error_report, "gemini")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
      block&.call res
      return [res]
    end

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body.to_s,
                      call_depth: call_depth, &block)
  rescue HTTP::Error, HTTP::TimeoutError, OpenSSL::SSL::SSLError => e
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY * num_retrial
      retry
    else
      error_message = e.is_a?(OpenSSL::SSL::SSLError) ? "SSL ERROR: #{e.message}" : "The request has timed out."
      res = { "type" => "error", "content" => "HTTP/SSL ERROR: #{error_message}" }
      block&.call res
      [res]
    end
  rescue StandardError => e
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
    
    # For media generator apps, we'll need special processing to remove code blocks
    is_media_generator = app.to_s.include?("image_generator") || 
                         app.to_s.include?("video_generator") || 
                         app.to_s.include?("gemini") && 
                         (session[:parameters]["app_name"].to_s.include?("Image Generator") || 
                          session[:parameters]["app_name"].to_s.include?("Video Generator"))

    buffer = String.new
    texts = []
    thinking_parts = []  # Store thinking content
    tool_calls = []
    finish_reason = nil
    @grounding_html = nil  # Store grounding metadata HTML to append to response

    # Convert the HTTP::Response::Body to a string and then process line by line
    res.each_line do |chunk|
      # Check if we should stop processing due to STOP finish reason
      break if finish_reason == "stop"
      
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      begin
        break if /\Rdata: [DONE]\R/ =~ buffer
      rescue
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      if /^\[?(\{\s*"candidates":.*^\})\n/m =~ buffer
        json = Regexp.last_match(1)
        begin
          json_obj = JSON.parse(json)

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts(JSON.pretty_generate(json_obj))
            
            # Specifically log if this is a web search response
            if session[:parameters]["websearch"] && json_obj["candidates"]
              json_obj["candidates"].each_with_index do |candidate, idx|
                if candidate["content"] && candidate["content"]["parts"]
                  candidate["content"]["parts"].each_with_index do |part, part_idx|
                    if part["text"] && (part["grounding_metadata"] || part["searchEntryPoint"])
                      puts "[DEBUG Gemini WebSearch] Candidate #{idx}, Part #{part_idx} contains search data"
                      puts "[DEBUG Gemini WebSearch] Text preview: #{part["text"][0..200]}..." if part["text"]
                    end
                  end
                end
              end
            end
          end

          candidates = json_obj["candidates"]
          
          # Debug: Log if no candidates
          if CONFIG["EXTRA_LOGGING"] && (candidates.nil? || candidates.empty?)
            puts "[DEBUG Gemini] No candidates in response: #{json_obj.inspect}"
          end
          
          candidates&.each do |candidate|
            
            # Check for grounding metadata at candidate level (skip empty objects)
            if candidate["groundingMetadata"] && 
               !candidate["groundingMetadata"].empty? && 
               @grounding_html.nil?
              grounding_data = candidate["groundingMetadata"]
              
              # Always log when grounding metadata is found
              if defined?(MonadicApp::EXTRA_LOG_FILE)
                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                  log.puts "[Gemini] Found grounding metadata at candidate level:"
                  log.puts "  - webSearchQueries: #{grounding_data["webSearchQueries"]&.inspect}"
                  log.puts "  - groundingChunks count: #{grounding_data["groundingChunks"]&.length}"
                  
                  if CONFIG["EXTRA_LOGGING"]
                    log.puts "[DEBUG Gemini] Full grounding data structure:"
                    log.puts JSON.pretty_generate(grounding_data)
                  end
                end
              end
              
              # Display search metadata
              if grounding_data["webSearchQueries"] && !grounding_data["webSearchQueries"].empty?
                search_info = "<div class='search-metadata' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>"
                search_info += "<details style='cursor: pointer;'>"
                # Escape search queries for HTML
                escaped_queries = grounding_data["webSearchQueries"].map do |q|
                  q.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                end
                search_info += "<summary style='font-weight: bold; color: #666;'>🔍 Web Search: #{escaped_queries.join(", ")}</summary>"
                
                if grounding_data["groundingChunks"] && !grounding_data["groundingChunks"].empty?
                  search_info += "<div style='margin-top: 10px;'>"
                  search_info += "<p style='margin: 5px 0; font-weight: bold;'>Sources:</p>"
                  search_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"
                  
                  grounding_data["groundingChunks"].each_with_index do |chunk, idx|
                    if chunk["web"]
                      url = chunk["web"]["uri"]
                      title = chunk["web"]["title"] || "Source #{idx + 1}"
                      title = title.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                      search_info += "<li style='margin: 3px 0;'><a href='#{url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{title}</a></li>"
                    end
                  end
                  
                  search_info += "</ul>"
                  search_info += "</div>"
                end
                
                search_info += "</details>"
                search_info += "</div>"
                
                # Store the HTML to append to final response
                @grounding_html = search_info
                
                if defined?(MonadicApp::EXTRA_LOG_FILE)
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts "[Gemini] Grounding metadata HTML stored for final response (candidate level)"
                    log.puts "[Gemini] HTML preview: #{search_info[0..200]}..."
                  end
                end
              end
            end

            finish_reason = candidate["finishReason"]
            case finish_reason
            when "MAX_TOKENS"
              finish_reason = "length"
            when "STOP"
              finish_reason = "stop"
              # For thinking models, we should stop processing after receiving STOP
              # to avoid infinite loops
            when "SAFETY"
              finish_reason = "safety"
            when "CITATION"
              finish_reason = "recitation"
            else
              finish_reason = nil
            end

            content = candidate["content"]
            
            # Debug: Log why content might be skipped
            if CONFIG["EXTRA_LOGGING"]
              if content.nil?
                puts "[DEBUG Gemini] Skipping candidate: content is nil"
              elsif finish_reason == "recitation"
                puts "[DEBUG Gemini] Skipping candidate: finish_reason is recitation"
              elsif finish_reason == "safety"
                puts "[DEBUG Gemini] Skipping candidate: finish_reason is safety"
                # For safety, try to provide more information
                safety_ratings = candidate["safetyRatings"]
                if safety_ratings
                  puts "[DEBUG Gemini] Safety ratings: #{safety_ratings.inspect}"
                end
              end
            end
            
            next if (content.nil? || finish_reason == "recitation" || finish_reason == "safety")

            content["parts"]&.each do |part|
              # Debug: Log all parts for Jupyter debugging
              if CONFIG["EXTRA_LOGGING"] && session[:parameters]["app_name"].to_s.include?("Jupyter")
                puts "[DEBUG Gemini Jupyter] Part keys: #{part.keys.inspect}"
                if part["functionCall"]
                  puts "[DEBUG Gemini Jupyter] Function call detected: #{part["functionCall"].inspect}"
                end
                if part["text"] && part["text"].length > 0
                  puts "[DEBUG Gemini Jupyter] Text fragment (first 100 chars): #{part["text"][0..100]}"
                end
              end
              
              # Process and display grounding metadata for web search results (part level)
              # Only process if we haven't already captured it at candidate level
              if @grounding_html.nil? && (part["grounding_metadata"] || json_obj["groundingMetadata"])
                grounding_data = part["grounding_metadata"] || json_obj["groundingMetadata"]
                
                # Log when found at part/json level
                if CONFIG["EXTRA_LOGGING"] && defined?(MonadicApp::EXTRA_LOG_FILE)
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts "[Gemini] Found grounding metadata at #{part["grounding_metadata"] ? "part" : "json"} level"
                    log.puts "  - webSearchQueries: #{grounding_data["webSearchQueries"]&.inspect}"
                    log.puts "  - groundingChunks count: #{grounding_data["groundingChunks"]&.length}"
                    log.puts "[DEBUG Gemini] Full grounding metadata structure:"
                    log.puts JSON.pretty_generate(grounding_data)
                    log.puts "  - searchEntryPoint exists: #{!grounding_data["searchEntryPoint"].nil?}"
                  end
                end
                
                # Build search metadata display if we have search queries and sources
                if grounding_data["webSearchQueries"] && !grounding_data["webSearchQueries"].empty?
                  search_info = "<div class='search-metadata' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>"
                  search_info += "<details style='cursor: pointer;'>"
                  # Escape search queries for HTML
                escaped_queries = grounding_data["webSearchQueries"].map do |q|
                  q.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                end
                search_info += "<summary style='font-weight: bold; color: #666;'>🔍 Web Search: #{escaped_queries.join(", ")}</summary>"
                  
                  # Display source citations if available
                  if grounding_data["groundingChunks"] && !grounding_data["groundingChunks"].empty?
                    search_info += "<div style='margin-top: 10px;'>"
                    search_info += "<p style='margin: 5px 0; font-weight: bold;'>Sources:</p>"
                    search_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"
                    
                    grounding_data["groundingChunks"].each_with_index do |chunk, idx|
                      if chunk["web"]
                        url = chunk["web"]["uri"]
                        title = chunk["web"]["title"] || "Source #{idx + 1}"
                        # Escape HTML in title to prevent XSS
                        title = title.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                        search_info += "<li style='margin: 3px 0;'><a href='#{url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{title}</a></li>"
                      end
                    end
                    
                    search_info += "</ul>"
                    search_info += "</div>"
                  end
                  
                  search_info += "</details>"
                  search_info += "</div>"
                  
                  # Store the HTML to append to final response
                  @grounding_html = search_info
                  
                  if CONFIG["EXTRA_LOGGING"] && defined?(MonadicApp::EXTRA_LOG_FILE)
                    File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                      log.puts "[Gemini] Grounding metadata HTML stored for final response (part level)"
                      log.puts "[Gemini] HTML preview: #{search_info[0..200]}..."
                    end
                  end
                  
                  # Clear the grounding data to avoid duplicate processing
                  json_obj.delete("groundingMetadata") if json_obj["groundingMetadata"]
                end
              end
              
              # Check if this part contains thinking content
              if part["thought"] == true && part["text"]
                thinking_fragment = part["text"]
                thinking_parts << thinking_fragment
                
                # Send thinking content as a special type (similar to Claude)
                res = {
                  "type" => "thinking",
                  "content" => thinking_fragment
                }
                block&.call res
                # Skip thinking content - it's internal reasoning, not output
                next
              end
              
              # Also check for modelThinking field (alternative format)
              if part["modelThinking"] && part["modelThinking"]["thought"]
                thinking_fragment = part["modelThinking"]["thought"]
                thinking_parts << thinking_fragment
                
                res = {
                  "type" => "thinking",
                  "content" => thinking_fragment
                }
                block&.call res
                # Skip this part
                next
              end
              
              if part["text"]
                fragment = part["text"]
                
                # Special handling for Math Tutor FIRST - needs priority
                # Debug: Log the actual app_name
                if CONFIG["EXTRA_LOGGING"] && fragment.include?("```")
                  puts "[DEBUG] App name: '#{session[:parameters]["app_name"]}'"
                  puts "[DEBUG] Display name: '#{session[:parameters]["display_name"]}'"
                end
                
                if session[:parameters]["app_name"].to_s.include?("MathTutor") || 
                   session[:parameters]["display_name"].to_s.include?("Math Tutor")
                  # For Math Tutor, only extract image HTML from code blocks
                  # Don't interfere with other content to avoid breaking MathJax
                  if fragment =~ /```(?:html)?\s*\n?(<div class="generated_image">.*?<\/div>)\s*\n?```/im
                    image_html = $1
                    # Replace just the code block containing the image with the raw HTML
                    fragment = fragment.gsub(/```(?:html)?\s*\n?(<div class="generated_image">.*?<\/div>)\s*\n?```/im, '\1')
                    
                    if CONFIG["EXTRA_LOGGING"]
                      puts "[DEBUG Math Tutor] Extracted image HTML from code block"
                    end
                  end
                # Special processing for media generator app to strip code blocks
                # Extract HTML from code blocks - for both media generator and code interpreter apps
                # Skip this processing for Jupyter Notebook as it needs different handling
                elsif !session[:parameters]["app_name"].to_s.include?("Jupyter") &&
                   (is_media_generator || session[:parameters]["app_name"].to_s.include?("Code Interpreter") || 
                    session[:parameters]["app_name"].to_s.include?("Video Generator")) && fragment.include?("```")
                  # Strip all code block markers for Video Generator app
                  if session[:parameters]["app_name"].to_s.include?("Video Generator")
                    # For video generator, we need to handle the entire fragment carefully
                    # First check if we have an HTML structure with video controls 
                    if fragment =~ /<div class="(?:prompt|generated_video)">.*?<\/div>/im
                      # Only keep the HTML content by first extracting all HTML elements
                      html_pattern = /<div.*?>.*?<\/div>|<p.*?>.*?<\/p>/im
                      html_elements = []
                      
                      # Extract all HTML elements (divs and paragraphs)
                      fragment.scan(html_pattern) do |match|
                        html_elements << match
                      end
                      
                      if html_elements.any?
                        # Join all found HTML elements with newlines
                        fragment = html_elements.join("\n")
                      end
                    else
                      # If no HTML structure found, try to extract from code blocks
                      content_inside_blocks = []
                      fragment.scan(/```(?:html|)\s*(.+?)\s*```/m) do |match|
                        content_inside_blocks << match[0]
                      end
                      
                      # If we found content inside code blocks, replace the fragment with just that content
                      if content_inside_blocks.any?
                        fragment = content_inside_blocks.join("\n\n")
                      else
                        # If no content found inside code blocks, just strip the markers
                        fragment = fragment.gsub(/```(?:html|\w*)?/, "").gsub(/```/, "")
                      end
                    end
                  # Standard processing for other media apps
                  elsif fragment =~ /<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im
                    # First try the clean approach - extract HTML content from any code block that contains visualization HTML
                    html_sections = []
                    code_sections = []
                    
                    # Extract HTML sections
                    fragment.scan(/<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im) do
                      html_sections << $&  # Use $& to get the entire matched string
                    end
                    
                    # Extract code blocks (without the HTML)
                    if fragment.match(/```(\w+)?.*?```/m)
                      fragment.scan(/```(\w+)?(.*?)```/m) do |lang, code|
                        # Skip if the code block contains HTML visualization
                        unless code =~ /<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im
                          code_sections << "```#{lang}#{code}```"
                        end
                      end
                    end
                    
                    # Rebuild the fragment with HTML outside of code blocks
                    if !html_sections.empty? || !code_sections.empty?
                      new_fragment = fragment.dup
                      
                      # Remove all code blocks and HTML sections first
                      new_fragment.gsub!(/```(\w+)?.*?```/m, '')
                      html_sections.each { |html| new_fragment.gsub!(html, '') }
                      
                      # Add back the code sections and HTML sections in the right order
                      new_fragment = new_fragment.strip
                      code_sections.each { |code| new_fragment += "\n\n#{code}" }
                      html_sections.each { |html| new_fragment += "\n\n#{html}" }
                      
                      fragment = new_fragment.strip
                    end
                  elsif fragment.include?("```html") && fragment.include?("```")
                    # Extract HTML between code markers - handle multiline properly
                    if fragment =~ /```html\s*(.*?)\s*```/m
                      html_content = $1
                      # Replace the entire code block with just the HTML content
                      fragment = fragment.gsub(/```html\s*.*?\s*```/m, html_content)
                    else
                      # Fallback to original simple replacement
                      html_content = fragment.gsub(/```html\s+/, "").gsub(/\s+```/, "")
                      fragment = html_content
                    end
                  elsif fragment.match(/```(\w+)?/)
                    # For media generator app only, remove any code block markers
                    if is_media_generator
                      fragment = fragment.gsub(/```(\w+)?/, "").gsub(/```/, "")
                    end
                  end
                end
                
                texts << fragment

                if fragment.length > 0
                  res = {
                    "type" => "fragment",
                    "content" => fragment,
                    "index" => texts.length - 1,
                    "timestamp" => Time.now.to_f,
                    "is_first" => texts.length == 1
                  }
                  block&.call res
                end

              elsif part["functionCall"]

                tool_calls << part["functionCall"]
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              end
            end
          end
        rescue JSON::ParserError
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
        buffer = String.new
      end
      
    rescue StandardError => e
      # Log error but continue processing
      STDERR.puts "Error processing JSON data chunk: #{e.message}"
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    result = []
    
    # Special handling for tool calls - don't show an error message yet if we have tool calls
    # because we might get a response after processing the function calls
    if texts.empty? && !tool_calls.any?
      # Only show error message when no text AND no tool calls
      result << "No response was received from the model. This might be due to a processing issue."
      res = { "type" => "fragment", "content" => "No response received from model" }
      block&.call res
      finish_reason = "error"
    else 
      result = texts
    end

    if tool_calls.any?
      context = []

      if result
        context << { "role" => "model", "text" => result.join("") }
      end

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      begin
        if CONFIG["EXTRA_LOGGING"] && session[:parameters]["app_name"].to_s.include?("Jupyter")
          puts "[DEBUG Gemini Jupyter] Processing #{tool_calls.length} function calls"
          tool_calls.each do |tc|
            puts "[DEBUG Gemini Jupyter] Function: #{tc["name"]}, Args keys: #{tc["args"]&.keys}"
          end
        end
        
        # Check if this is a Math Tutor run_code call
        is_math_tutor_code = (session[:parameters]["app_name"].to_s.include?("MathTutor") || 
                              session[:parameters]["display_name"].to_s.include?("Math Tutor")) && 
                             tool_calls.any? { |tc| tc["name"] == "run_code" }
        
        new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
        
        # For Math Tutor, inject HTML for generated images
        if is_math_tutor_code && new_results
          if CONFIG["EXTRA_LOGGING"]
            puts "[DEBUG Math Tutor] Checking tool results for image files"
          end
          
          # Check if any image files were generated
          result_text = new_results.to_s
          if result_text =~ /File\(s\) generated.*?(\/data\/[^,\s]+\.(?:svg|png|jpg|jpeg|gif))/i
            image_file = $1
            if CONFIG["EXTRA_LOGGING"]
              puts "[DEBUG Math Tutor] Found generated image: #{image_file}"
            end
            
            # Inject HTML for the image
            image_html = "\n\n<div class=\"generated_image\">\n  <img src=\"#{image_file}\" />\n</div>"
            
            # Send the HTML as a fragment
            res = {
              "type" => "fragment",
              "content" => image_html
            }
            block&.call res
          end
        end
        
        if CONFIG["EXTRA_LOGGING"] && session[:parameters]["app_name"].to_s.include?("Jupyter")
          puts "[DEBUG Gemini Jupyter] Function results received: #{new_results.class}"
        end
      rescue StandardError => e
        new_results = [{ "type" => "error", "content" => "ERROR: #{e.message}" }]
        if CONFIG["EXTRA_LOGGING"] && session[:parameters]["app_name"].to_s.include?("Jupyter")
          puts "[DEBUG Gemini Jupyter] Function call error: #{e.message}"
        end
      end

      if result && new_results
        begin
          # More robust handling of different response structures
          if new_results.is_a?(Array) && new_results[0].is_a?(Hash) && new_results[0]["choices"]
            tool_result_content = new_results.dig(0, "choices", 0, "message", "content").to_s.strip
          else
            tool_result_content = new_results.to_s.strip
          end
          
          # Special handling for Math Tutor run_code results
          if (session[:parameters]["app_name"].to_s.include?("MathTutor") || 
              session[:parameters]["display_name"].to_s.include?("Math Tutor")) && 
             tool_calls.any? { |tc| tc["name"] == "run_code" }
            if CONFIG["EXTRA_LOGGING"]
              puts "[DEBUG Math Tutor] Processing run_code result: #{tool_result_content[0..200]}"
            end
            
            # Check if image files were generated
            if tool_result_content =~ /File\(s\) generated.*?(\/data\/[^,\s;]+\.(?:svg|png|jpg|jpeg|gif))/i
              image_file = $1
              if CONFIG["EXTRA_LOGGING"]
                puts "[DEBUG Math Tutor] Appending HTML for image: #{image_file}"
              end
              # Append HTML directly to the tool result
              tool_result_content += "\n\n<div class=\"generated_image\">\n  <img src=\"#{image_file}\" />\n</div>"
            end
          end
          
          # Don't add generic content if tool_result_content is empty for video/image generation
          # This will let the actual result from the generate_video_with_veo function be displayed
          if tool_result_content.empty? && !tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" || tc["name"] == "generate_image_with_gemini" }
            tool_result_content = "[No additional content received from function call]"
          end
          
          # Clean up any "No response" messages that might be in the results
          if result.is_a?(Array) && result.length == 1 && 
             result[0].to_s.include?("No response was received")
            # Replace error message with actual content
            result = []
          end
          
          final_result = result.join("").strip
          
          # Special handling for video generation
          if tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" }
            # Extract video filename if available in tool result
            video_filename = nil
            video_success = false
            
            # Check if video generation succeeded based on content
            video_success = !tool_result_content.include?("Video generation failed") && tool_result_content.include?("saved video")
            
            if video_success
              # Simply return the original tool_result_content for LLM to process
              final_result = tool_result_content
            elsif tool_result_content.include?("Video generation failed")
              # If we have an explicit failure message, use it and ignore LLM content
              final_result = tool_result_content
            elsif !tool_result_content.empty?
              # Otherwise use the tool result content
              final_result = tool_result_content
            end
          # Special handling for new image generation with Gemini
          elsif tool_calls.any? { |tc| tc["name"] == "generate_image_with_gemini" }
            # For image generation, always pass the tool result back to LLM to process
            # The LLM will extract the filename and generate the appropriate HTML
            if !tool_result_content.empty?
              final_result = tool_result_content
            elsif !final_result.empty?
              # Use any initial result if tool result is empty
              final_result = final_result
            else
              # Fallback message
              final_result = "Image generation function was called but no result was returned."
            end
            
          else
            # Standard handling for non-video tools
            # If we have both initial text and function results, combine them
            if !final_result.empty? && !tool_result_content.empty?
              final_result += "\n\n" + tool_result_content
            # If we only have function results, use those
            elsif final_result.empty? && !tool_result_content.empty?
              final_result = tool_result_content
            # If we have nothing, provide a fallback message
            elsif final_result.empty? && tool_result_content.empty?
              final_result = "Function was called but no content was returned."
            end
          end
          
          # For Math Tutor, send the HTML image tag directly to frontend if present
          if (session[:parameters]["app_name"].to_s.include?("MathTutor") || 
              session[:parameters]["display_name"].to_s.include?("Math Tutor")) && 
             final_result.include?("<div class=\"generated_image\">")
            # Extract and send the HTML portion separately
            if final_result =~ /(<div class="generated_image">.*?<\/div>)/m
              image_html = $1
              # Send the image HTML as a fragment to the frontend
              res = {
                "type" => "fragment",
                "content" => image_html
              }
              block&.call res
              
              # Remove the HTML from the final result so it's not duplicated
              final_result = final_result.gsub(/<div class="generated_image">.*?<\/div>/m, '').strip
            end
          end
          
          # Return final result
          [{ "choices" => [{ "message" => { "content" => final_result } }] }]
        rescue StandardError => e
          # Log the error and send a more informative message
          result_text = result.join("").strip
          
          # Clean up any "No response" messages that might be in the results
          if result_text.include?("No response was received")
            result_text = ""
          end
          
          # Special handling for video generation even in error cases
          if tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" }
            # Check for successful video creation despite error
            video_success = false
            error_details = e.message.to_s
            
            # Extract filename using the same patterns as above
            if error_details =~ /Successfully saved video to: .*?\/(\d+_\d+_\d+x\d+\.mp4)/ ||
               error_details =~ /(\d{10}_\d+_\d+x\d+\.mp4)/ ||
               error_details =~ /Created placeholder video file at: .*?\/(\d+_\d+_\d+x\d+\.mp4)/
              video_filename = $1
              video_success = true
            end
            
            if video_success
              # We want to let LLM process the error message too
              # Just pass it the error message
              final_result = error_details
            else
              error_message = "[Error processing video generation results: #{e.message}]"
              final_result = result_text.empty? ? error_message : result_text + "\n\n" + error_message
            end
          else
            # Standard error handling for non-video functions
            error_message = "[Error processing function results: #{e.message}]"
            final_result = result_text.empty? ? error_message : result_text + "\n\n" + error_message
          end
          
          [{ "choices" => [{ "message" => { "content" => final_result } }] }]
        end
      elsif new_results
        # Notification of function call completion has been removed
        new_results
      elsif result
        # Don't return error messages if they were generated due to initial empty response
        # that was followed by function calls
        if result.is_a?(Array) && result.length == 1 && 
           result[0].to_s.include?("No response was received") && tool_calls.any?
          # Return empty result instead of error message
          [{ "choices" => [{ "message" => { "content" => "" } }] }]
        else
          [{ "choices" => [{ "message" => { "content" => result.join("") } }] }]
        end
      else
        # Ensure we always return something meaningful
        [{ "choices" => [{ "message" => { "content" => "No response was received from the model or function calls." } }] }]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      
      # Join the result and check if it needs unwrapping
      final_content = result.join("")
      
      # Check if the entire response is a single Markdown code block and unwrap it
      final_content = unwrap_single_markdown_code_block(final_content)
      
      # Append grounding metadata HTML if present
      if @grounding_html
        final_content += "\n\n" + @grounding_html
        if defined?(MonadicApp::EXTRA_LOG_FILE)
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts "[Gemini] Appended grounding metadata HTML to final response"
            log.puts "[Gemini] Final content length: #{final_content.length}"
          end
        end
      else
        if defined?(MonadicApp::EXTRA_LOG_FILE)
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts "[Gemini] No grounding HTML to append"
          end
        end
      end
      
      response_data = {
        "choices" => [
          {
            "finish_reason" => finish_reason,
            "message" => { "content" => final_content }
          }
        ]
      }
      
      # Don't add thinking content to final response 
      # (it's already been streamed to the user during processing)
      # This prevents duplicate display of thinking content
      # if thinking_parts.any?
      #   response_data["choices"][0]["message"]["thinking"] = thinking_parts.join("\n")
      # end
      
      # Apply monadic transformation if enabled
      obj = session[:parameters]
      if obj["monadic"] && final_content
        # Process through unified interface
        processed = process_monadic_response(final_content, app)
        # Validate the response
        validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
        response_data["choices"][0]["message"]["content"] = validated.is_a?(Hash) ? JSON.generate(validated) : validated
      end
      
      [response_data]
    end
  end

  def process_functions(app, session, tool_calls, context, call_depth, &block)
    return false if tool_calls.empty?

    # Get parameters from the session
    session_params = session[:parameters]
    
    # Initialize tool_results array in session parameters if it doesn't exist
    session_params["tool_results"] ||= []
    
    # Log tool calls for debugging
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Tools] Processing #{tool_calls.length} tool calls:"
      tool_calls.each { |tc| puts "  - #{tc['name']} with args: #{tc['args'].inspect[0..200]}" }
    end
    
    # Process each tool call
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        # Parse arguments from the tool call
        argument_hash = tool_call["args"] || {}
        
        # Debug logging for Jupyter add_jupyter_cells
        if CONFIG["EXTRA_LOGGING"] && function_name == "add_jupyter_cells"
          puts "[DEBUG Gemini Jupyter] add_jupyter_cells arguments before conversion:"
          puts "  - Raw args: #{argument_hash.inspect}"
          puts "  - cells type: #{argument_hash["cells"]&.class}"
          puts "  - cells value: #{argument_hash["cells"]&.inspect[0..500]}"
        end
        
        # Convert string keys to symbols for method calling
        argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_sym] = v
          memo
        end
        
        # Check if Gemini wrapped arguments in an "options" key and unwrap them
        if argument_hash.keys == [:options] && argument_hash[:options].is_a?(Hash)
          argument_hash = argument_hash[:options]
          # Convert the unwrapped hash keys to symbols as well
          argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
            memo[k.to_sym] = v
            memo
          end
        end

        # Add session parameter for functions that need access to uploaded images
        if function_name == "generate_video_with_veo" || function_name == "generate_image_with_gemini"
          argument_hash[:session] = session
        end
        
        # tavily_search already accepts n parameter directly, no need to convert
        
        # Special handling for tavily_search to ensure proper parameter mapping
        if function_name == "tavily_search"
          # Ensure we only pass the parameters tavily_search expects
          clean_args = {}
          clean_args[:query] = argument_hash[:query] || argument_hash[:q] if argument_hash[:query] || argument_hash[:q]
          clean_args[:n] = argument_hash[:n] || argument_hash[:max_results] || 3
          argument_hash = clean_args
        end
        
        # Call the function with the provided arguments
        function_return = send(function_name.to_sym, **argument_hash)
        
        # Log the result for debugging
        if CONFIG["EXTRA_LOGGING"]
          puts "[DEBUG Tools] #{function_name} returned: #{function_return.to_s[0..500]}"
        end
        
        # Process the returned content
        if function_return
          # Special handling for video generator and image generator
          if function_name == "generate_video_with_veo"
            video_filename = nil
            video_success = false
            error_message = nil
            
            # Check if there were any errors in the JSON
            begin
              if function_return.is_a?(String)
                parsed_json = JSON.parse(function_return)
                
                # Check if we have videos array with filenames (success indicator)
                if parsed_json["videos"] && !parsed_json["videos"].empty?
                  video_success = true
                elsif !parsed_json["success"]
                  # Extract error message if available
                  error_message = parsed_json["message"]
                  video_success = false
                end
              end
            rescue JSON::ParserError => e
              # Just check for success/failure based on text
              if function_return.to_s.include?("saved video") || 
                 function_return.to_s.include?("Successfully") ||
                 function_return.to_s =~ /\d{10}_\d+_\d+x\d+\.mp4/
                video_success = true
              end
            end
            
            # Prepare final content for response
            if video_success
              # Simply pass the raw response to LLM for processing
              content = function_return.is_a?(String) ? function_return : function_return.to_json
            elsif error_message
              # If we have a specific error message, use it
              content = "Video generation failed: #{error_message}"
            else
              # Fallback to the raw response
              content = function_return.is_a?(String) ? function_return : function_return.to_json
            end
          elsif function_name == "generate_image_with_gemini"
            # Special handling for image generator
            image_success = false
            error_message = nil
            
            # Check if there were any errors in the JSON
            begin
              if function_return.is_a?(String)
                parsed_json = JSON.parse(function_return)
                
                # Check if we have success indicator
                if parsed_json["success"]
                  image_success = true
                else
                  # Extract error message if available
                  error_message = parsed_json["error"]
                  image_success = false
                end
              end
            rescue JSON::ParserError => e
              # If JSON parsing fails, check for text indicators
              if function_return.to_s.include?("success") && function_return.to_s.include?("filename")
                image_success = true
              end
            end
            
            # Prepare final content for response
            if image_success
              # Simply pass the raw response to LLM for processing
              content = function_return.is_a?(String) ? function_return : function_return.to_json
            elsif error_message
              # If we have a specific error message, use it
              content = "Image generation failed: #{error_message}"
            else
              # Fallback to the raw response
              content = function_return.is_a?(String) ? function_return : function_return.to_json
            end
          else
            # Standard handling for other functions
            content = function_return.is_a?(String) ? function_return : function_return.to_json
          end

          # Add to tool results and debug
          session_params["tool_results"] << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => content
              }
            }
          }
          
          # Tool result added (debug logging removed)
        end
      rescue StandardError => e
        # Error handling for function invocation
        error_message = "ERROR: Function call failed: #{function_name}. #{e.message}"
        STDERR.puts error_message
        
        # If this is a video generation function error, provide a more informative message
        if function_name == "generate_video_with_veo"
          # Check for successful video creation despite error
          video_success = false
          video_filename = nil
          
          # Extract filename from error message if it exists
          if e.message =~ /Successfully saved video to: .*?\/(\d+_\d+_\d+x\d+\.mp4)/ ||
             e.message =~ /(\d{10}_\d+_\d+x\d+\.mp4)/ ||
             e.message =~ /Created placeholder video file at: .*?\/(\d+_\d+_\d+x\d+\.mp4)/
            video_filename = $1
            video_success = true
          end
          
          if video_filename && video_success
            # If we have a filename, consider it successful despite errors
            STDERR.puts "Found video filename in error: #{video_filename}"
            
            # Try to extract original prompt from arguments
            original_prompt = ""
            begin
              original_prompt = argument_hash[:prompt].to_s if argument_hash && argument_hash[:prompt]
            rescue
              original_prompt = "Video generation"
            end
            
            # Let LLM handle HTML generation - just pass filename information
            success_content = "Successfully saved video to: /data/#{video_filename}\nOriginal prompt: #{original_prompt}"
            
            session_params["tool_results"] << {
              "functionResponse" => {
                "name" => function_name,
                "response" => {
                  "name" => function_name,
                  "content" => success_content
                }
              }
            }
          else
            # Try to extract more useful error message information
            error_details = e.message.to_s
            # Look for common error patterns
            if error_details =~ /content\s+policy\s+violation/i || error_details =~ /responsible\s+AI/i || error_details =~ /safety/i
              custom_error_message = "Video generation failed: The prompt appears to violate content policy guidelines. Please try a different prompt with less sensitive content."
              session_params["tool_results"] << {
                "functionResponse" => {
                  "name" => function_name,
                  "response" => {
                    "name" => function_name,
                    "content" => custom_error_message
                  }
                }
              }
            else
              # Standard error handling
              session_params["tool_results"] << {
                "functionResponse" => {
                  "name" => function_name,
                  "response" => {
                    "name" => function_name,
                    "content" => error_message
                  }
                }
              }
            end
          end
        else
          # For non-video function errors
          session_params["tool_results"] << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => error_message
              }
            }
          }
        end
        
        # Send error message to client for better visibility
        res = { "type" => "fragment", "content" => "<span class='text-danger'>#{error_message}</span>" }
        block&.call res
      end
    end
    
    # Make the API request with the tool results
    # Log the call depth for debugging
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Gemini] Tool call depth: #{call_depth}, making API request with tool results"
    end
    
    # Remove the artificial limit - let MAX_FUNC_CALLS handle it
    # The real issue might be elsewhere
    
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def translate_role(role)
    case role
    when "user"
      "user"
    when "assistant"
      "model"
    when "system"
      "user"
    else
      role.downcase
    end
  end
  
  # Helper method to unwrap content from a single Markdown code block
  def unwrap_single_markdown_code_block(content)
    return content unless content.is_a?(String)
    
    # Strip leading/trailing whitespace to normalize
    trimmed = content.strip
    
    # Check if the entire content is wrapped in a single code block
    # Pattern: starts with ``` (optionally with language), ends with ```
    # and has no other ``` in between
    if trimmed =~ /\A```(?:html|HTML|xml|XML|markdown|md|)?\s*\n(.*)\n```\z/m
      inner_content = $1
      
      # Verify there are no nested code blocks
      if !inner_content.include?('```')
        return inner_content
      end
    end
    
    # Return original content if not a single code block
    content
  end
  
  # Helper function to generate video with Veo model
  def generate_video_with_veo(prompt:, image_path: nil, aspect_ratio: "16:9", number_of_videos: nil, person_generation: nil, negative_prompt: nil, duration_seconds: nil, session: nil)
    
    # Try to get image data from session and create temporary file
    actual_image_path = nil
    temp_file_path = nil
    
    if session && session[:messages]
      # Look for the most recent user message with images
      user_messages_with_images = session[:messages].select { |msg| msg["role"] == "user" && msg["images"] }
      
      if user_messages_with_images.any?
        latest_message = user_messages_with_images.last
        
        if latest_message["images"] && latest_message["images"].first
          # Extract image data from the first image
          first_image = latest_message["images"].first
          
          # Get the base64 data from the session
          if first_image["data"] && first_image["data"].start_with?("data:image/")
            # Create a temporary file from the base64 data
            require 'tempfile'
            require 'base64'
            
            # Extract the base64 data
            data_url = first_image["data"]
            # Split the data URL to get the base64 part
            base64_data = data_url.split(',').last
            # Decode the base64 data
            image_binary = Base64.decode64(base64_data)
            
            # Determine file extension and mime type from data URL or session data
            detected_mime_type = nil
            if first_image["type"]
              detected_mime_type = first_image["type"]
            elsif data_url.include?('image/')
              detected_mime_type = data_url.split(';').first.split(':').last
            end
            
            extension = case detected_mime_type
                       when 'image/jpeg', 'image/jpg' then '.jpg'
                       when 'image/png' then '.png'
                       when 'image/gif' then '.gif'
                       when 'image/webp' then '.webp'
                       else
                         # Try to detect from data URL if mime type is not available
                         if data_url.include?('image/jpeg')
                           '.jpg'
                         elsif data_url.include?('image/png')
                           '.png'
                         elsif data_url.include?('image/gif')
                           '.gif'
                         elsif data_url.include?('image/webp')
                           '.webp'
                         else
                           '.jpg' # default
                         end
                       end
            
            
            # Create temporary file in shared data directory
            # This ensures the file is accessible both locally and in Docker container
            data_paths = ["/monadic/data/", "#{Dir.home}/monadic/data/"]
            temp_dir = nil
            
            # Find or create the data directory
            data_paths.each do |path|
              if Dir.exist?(path)
                temp_dir = path
                break
              else
                begin
                  FileUtils.mkdir_p(path)
                  temp_dir = path
                  break
                rescue
                  next
                end
              end
            end
            
            if temp_dir
              # Create a unique filename with timestamp and mime type info
              timestamp = Time.now.to_i
              temp_filename = "video_gen_temp_#{timestamp}_#{rand(1000)}#{extension}"
              temp_file_path = File.join(temp_dir, temp_filename)
              
              # Store mime type information in a companion file for reference
              mime_info_path = temp_file_path + ".mime"
              
              # Check and potentially resize image before writing
              begin
                # Check image size
                image_size = image_binary.size
                
                # Check image size against Vertex AI limits (20MB)
                if image_size > 20 * 1024 * 1024
                  STDERR.puts "ERROR: Image is too large (#{image_size} bytes). Maximum supported size is 20MB."
                  actual_image_path = nil
                elsif image_size > 10 * 1024 * 1024
                  STDERR.puts "WARNING: Image is large (#{image_size} bytes). This may take longer to process."
                end
                
                # Write the image file and mime type info
                File.open(temp_file_path, 'wb') do |f|
                  f.write(image_binary)
                end
                
                # Write mime type info to companion file
                if detected_mime_type
                  File.write(mime_info_path, detected_mime_type)
                end
                
                actual_image_path = temp_filename  # Use just the filename, not full path
              rescue StandardError => e
                STDERR.puts "ERROR: Failed to process image: #{e.message}"
                actual_image_path = nil
              end
            else
              STDERR.puts "ERROR: Could not create temporary file - no accessible data directory"
            end
            
          elsif first_image["filename"]
            actual_image_path = first_image["filename"]
          elsif first_image["title"]
            actual_image_path = first_image["title"]
          else
          end
        else
        end
      else
      end
    else
    end
    
    # Use session image path if available, otherwise use provided image_path (but ignore "image_path" literal)
    final_image_path = actual_image_path
    if !final_image_path && image_path && image_path != "image_path"
      final_image_path = image_path
    else
    end
    
    # Construct the command
    # Use shellwords to properly escape all parameters
    require 'shellwords'
    
    # Veo 3 specifications (fixed values)
    # - Resolution: 720p
    # - Frame Rate: 24 fps
    # - Duration: 8 seconds
    # - Aspect Ratio: 16:9 only
    # - Videos per request: 1
    
    parts = []
    parts << "video_generator_veo.rb"
    parts << "-p"
    parts << prompt.to_s
    parts << "-a"
    parts << "16:9"  # Always use 16:9 for Veo 3
    parts << "-n"
    parts << "1"  # Always force number_of_videos to 1
    
    # Add negative prompt if provided
    if negative_prompt && !negative_prompt.to_s.empty?
      parts << "--negative-prompt"
      parts << negative_prompt.to_s
    end
    
    # Person generation is auto-selected based on image presence
    # Don't specify it manually - let the script handle it
    
    # Add image path if available (should be filename only from ~/monadic/data/)
    if final_image_path && !final_image_path.empty?
      parts << "-i"
      parts << final_image_path
    else
    end
    
    # Create the bash command using Shellwords.join for proper escaping
    cmd = "bash -c #{Shellwords.escape(Shellwords.join(parts))}"
    
    begin
      # Send command and get raw output
      result = send_command(command: cmd, container: "ruby")
      
      # Clean up temporary files if we created them
      if temp_file_path && File.exist?(temp_file_path)
        File.unlink(temp_file_path)
        # Also clean up mime info file if it exists
        mime_info_path = temp_file_path + ".mime"
        if File.exist?(mime_info_path)
          File.unlink(mime_info_path)
        end
      end
      
      return result
    rescue => e
      STDERR.puts "Error executing command: #{e.message}"
      
      # Clean up temporary files even if there was an error
      if temp_file_path && File.exist?(temp_file_path)
        File.unlink(temp_file_path)
        # Also clean up mime info file if it exists
        mime_info_path = temp_file_path + ".mime"
        if File.exist?(mime_info_path)
          File.unlink(mime_info_path)
        end
      end
      return { 
        "success" => false, 
        "message" => "Error executing video generation command: #{e.message}", 
        "original_prompt" => prompt 
      }.to_json
    end
  end
  
  # Helper method to get standard function handling instructions for Gemini models
  # Particularly important for "thinking" models but beneficial for all Gemini integrations
  def self.function_usage_instructions
    <<~INSTRUCTIONS
      IMPORTANT FUNCTION HANDLING GUIDELINES:
      
      1. For internal functions (like check_environment), execute them silently and don't mention them in your response to users.
         Never show these function calls in your response or include them in code blocks.
      
      2. For execution functions (like run_script), call them directly without printing them or storing their results:
         run_script(command="python", code="print('Hello world')", extension="py")
      
      3. When showing code examples to users, display the actual code they should run (e.g., Python code),
         not the function calls you use to execute that code.
      
      4. Begin your conversations with a simple greeting, not with function calls or outputs.
      
      5. All function calls should be made directly without print statements or variable assignments
         for their results. The system automatically handles displaying function results.
         
      6. CRITICAL: HTML elements (img, div, video, audio tags) MUST NEVER be enclosed in code blocks (```).
         When displaying images, plots, or visualizations, place the HTML directly in your response like this:
         
         <div class="generated_image">
           <img src="/data/image_filename.png" />
         </div>
         
         When displaying videos, place the HTML directly in your response like this:
         
         <div class="generated_video">
           <video controls width="100%">
             <source src="/data/video_filename.mp4" type="video/mp4">
             Your browser does not support the video tag.
           </video>
         </div>
         
         Do NOT place this HTML inside a code block. The media will only display if the HTML is outside of code blocks.
         Users will not see visualizations if you wrap HTML in code blocks.
    INSTRUCTIONS
  end

  def generate_image_with_gemini(prompt:, operation: "generate", model: "gemini", session: nil)
    require 'net/http'
    require 'json'
    require 'base64'
    require 'tempfile'
    
    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      return { success: false, error: "GEMINI_API_KEY not configured" }.to_json unless api_key
      
      # For editing operations, force use of Gemini model
      if operation == "edit"
        model = "gemini"
      end
      
      # If Imagen 3 is selected for generation, use direct API implementation
      if model == "imagen3" && operation == "generate"
        return generate_image_with_imagen_direct(prompt: prompt)
      end
      
      # Set up shared folder path
      shared_folder = Monadic::Utils::Environment.shared_volume
      
      # Prepare the request body with corrected structure
      request_body = {
        contents: [{
          parts: []
        }],
        generationConfig: {
          responseModalities: ["TEXT", "IMAGE"],
          temperature: 0.8,
          topK: 40,
          topP: 0.95
        }
      }
      
      # For edit operation, add the uploaded image to the request
      if operation == "edit" && session && session[:messages]
        # Look for the most recent user message with images
        user_messages_with_images = session[:messages].select { |msg| msg["role"] == "user" && msg["images"] }
        
        if user_messages_with_images.empty?
          return { success: false, error: "No image found for editing. Please upload an image first." }.to_json
        end
        
        latest_message = user_messages_with_images.last
        first_image = latest_message["images"].first
        
        if first_image && first_image["data"] && first_image["data"].start_with?("data:image/")
          # Extract base64 data from data URL
          data_url = first_image["data"]
          base64_data = data_url.split(',').last
          
          # Determine mime type
          mime_type = if first_image["type"]
                       first_image["type"]
                     elsif data_url.include?('image/')
                       data_url.split(';').first.split(':').last
                     else
                       "image/jpeg"
                     end
          
          # Add image to request parts
          request_body[:contents][0][:parts] << {
            inline_data: {
              mime_type: mime_type,
              data: base64_data
            }
          }
          
          # Add editing instruction
          request_body[:contents][0][:parts] << {
            text: prompt
          }
        else
          return { success: false, error: "Invalid image data format" }.to_json
        end
      else
        # For generate operation, just add the text prompt
        request_body[:contents][0][:parts] << {
          text: prompt
        }
      end
      
      # Make API request
      # Use the correct model for image generation
      model_name = "gemini-2.0-flash-preview-image-generation"
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{api_key}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 300 # 5 minutes timeout
      
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      response = http.request(request)
      
      if response.code == '200'
        result = JSON.parse(response.body)
        
        
        # Extract generated image from response
        if result["candidates"] && result["candidates"][0]
          candidate = result["candidates"][0]
          
          if candidate["content"] && candidate["content"]["parts"]
            parts = candidate["content"]["parts"]
            
            # Look for image data in parts
            image_found = false
            parts.each_with_index do |part, index|
              
              if part["inlineData"] && part["inlineData"]["mimeType"] && part["inlineData"]["mimeType"].start_with?("image/")
                # Found image data
                image_found = true
                image_data = Base64.decode64(part["inlineData"]["data"])
                timestamp = Time.now.to_i
                
                # Determine file extension from mime type
                extension = case part["inlineData"]["mimeType"]
                           when "image/png" then "png"
                           when "image/jpeg", "image/jpg" then "jpg"
                           when "image/webp" then "webp"
                           else "png"
                           end
                
                filename = "gemini_#{operation}_#{timestamp}.#{extension}"
                filepath = File.join(shared_folder, filename)
                
                File.open(filepath, 'wb') do |f|
                  f.write(image_data)
                end
                
                
                return { 
                  success: true, 
                  filename: filename,
                  operation: operation,
                  prompt: prompt,
                  model: "gemini"
                }.to_json
              elsif part["inline_data"] && part["inline_data"]["mime_type"] && part["inline_data"]["mime_type"].start_with?("image/")
                # Alternative key naming (inline_data vs inlineData)
                image_found = true
                image_data = Base64.decode64(part["inline_data"]["data"])
                timestamp = Time.now.to_i
                
                extension = case part["inline_data"]["mime_type"]
                           when "image/png" then "png"
                           when "image/jpeg", "image/jpg" then "jpg"
                           when "image/webp" then "webp"
                           else "png"
                           end
                
                filename = "gemini_#{operation}_#{timestamp}.#{extension}"
                filepath = File.join(shared_folder, filename)
                
                File.open(filepath, 'wb') do |f|
                  f.write(image_data)
                end
                
                
                return { 
                  success: true, 
                  filename: filename,
                  operation: operation,
                  prompt: prompt,
                  model: "gemini"
                }.to_json
              end
            end
            
          end
        end
        
        # If no image was found in response
        return { 
          success: false, 
          error: "No image was generated. Response parts: #{result["candidates"]&.first&.dig("content", "parts")&.map { |p| p.keys }}"
        }.to_json
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "API request failed with status #{response.code}"
        return { success: false, error: error_message }.to_json
      end
      
    rescue StandardError => e
      return { success: false, error: "Error: #{e.message}" }.to_json
    end
  end


  # Direct Imagen 3 API implementation
  def generate_image_with_imagen_direct(prompt:, aspect_ratio: "1:1", sample_count: 1, person_generation: "ALLOW_ADULT")
    require 'net/http'
    require 'json'
    require 'base64'
    
    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      return { success: false, error: "GEMINI_API_KEY not configured" }.to_json unless api_key
      
      
      # Set up shared folder path
      shared_folder = Monadic::Utils::Environment.shared_volume
      
      # Prepare the request body for Imagen 3
      request_body = {
        instances: [{
          prompt: prompt
        }],
        parameters: {
          sampleCount: sample_count,
          aspectRatio: aspect_ratio,
          personGeneration: person_generation
        }
      }
      
      # Make API request to Imagen 3
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=#{api_key}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 300 # 5 minutes timeout
      
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      response = http.request(request)
      
      if response.code == '200'
        result = JSON.parse(response.body)
        
        # Process Imagen 3 response
        if result["predictions"] && !result["predictions"].empty?
          prediction = result["predictions"].first
          
          if prediction["bytesBase64Encoded"]
            # Save the generated image
            image_data = Base64.decode64(prediction["bytesBase64Encoded"])
            timestamp = Time.now.to_i
            filename = "imagen3_#{timestamp}_0_#{aspect_ratio.gsub(':', 'x')}.png"
            filepath = File.join(shared_folder, filename)
            
            File.open(filepath, 'wb') do |f|
              f.write(image_data)
            end
            
            result = {
              success: true,
              filename: filename,
              operation: "generate",
              prompt: prompt,
              model: "imagen3"
            }.to_json
            return result
          end
        end
        
        # If no image was found in response
        error_result = {
          success: false,
          error: "No image was generated by Imagen 3. Response: #{result}"
        }.to_json
        return error_result
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "API request failed with status #{response.code}"
        return { success: false, error: error_message }.to_json
      end
      
    rescue StandardError => e
      return { success: false, error: "Error with Imagen 3: #{e.message}" }.to_json
    end
  end
end