#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"

module GeminiHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1alpha"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120
  MAX_RETRIES = 5
  RETRY_DELAY = 1
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

  WEBSEARCH_TOOLS = [
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
    },
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
        required: ["query", "n"]
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
    if options["reasoning_effort"] || model =~ /2\.5.*preview/i
      is_thinking_model = true
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "GeminiHelper: Detected thinking model #{model} with reasoning_effort: #{options["reasoning_effort"]}"
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
      is_flash_model = model && model.include?("flash")
      user_max_tokens = options["max_tokens"] || 800
      
      case reasoning_effort
      when "low"
        if is_flash_model
          budget_tokens = [(user_max_tokens * 0.3).to_i, 8000].min
        else  # Pro model
          budget_tokens = [[(user_max_tokens * 0.3).to_i, 10000].max, 32768].min
          budget_tokens = [budget_tokens, 128].max
        end
      when "medium"
        if is_flash_model
          budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
        else  # Pro model
          budget_tokens = [[(user_max_tokens * 0.6).to_i, 20000].max, 32768].min
          budget_tokens = [budget_tokens, 128].max
        end
      when "high"
        if is_flash_model
          budget_tokens = [[(user_max_tokens * 0.8).to_i, 24000].min, 24576].min
        else  # Pro model
          budget_tokens = [[(user_max_tokens * 0.8).to_i, 28000].max, 32768].min
          budget_tokens = [budget_tokens, 128].max
        end
      else
        budget_tokens = is_flash_model ? 8000 : 10000
      end
      
      # Set thinking configuration
      body["generationConfig"]["thinkingConfig"] = {
        "thinkingBudget" => budget_tokens,
        "includeThoughts" => true
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
    if obj["ai_user"] == "true"
      max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || obj["max_tokens"]&.to_i
    else
      max_tokens = obj["max_tokens"]&.to_i
    end

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"
    
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
        res["content"]["images"] = obj["images"] if obj["images"]
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
        is_flash_model = model && model.include?("flash")
        
        # Calculate thinking budget based on reasoning_effort
        # Gemini 2.5 Flash: 0-24,576, Pro: 128-32,768
        user_max_tokens = max_tokens || 8192
        
        case reasoning_effort
        when "low"
          if is_flash_model
            budget_tokens = [(user_max_tokens * 0.3).to_i, 8000].min
          else  # Pro model
            budget_tokens = [[(user_max_tokens * 0.3).to_i, 10000].max, 32768].min
            budget_tokens = [budget_tokens, 128].max
          end
        when "medium"
          if is_flash_model
            budget_tokens = [(user_max_tokens * 0.6).to_i, 16000].min
          else  # Pro model
            budget_tokens = [[(user_max_tokens * 0.6).to_i, 20000].max, 32768].min
            budget_tokens = [budget_tokens, 128].max
          end
        when "high"
          if is_flash_model
            budget_tokens = [[(user_max_tokens * 0.8).to_i, 24000].min, 24576].min
          else  # Pro model
            budget_tokens = [[(user_max_tokens * 0.8).to_i, 28000].max, 32768].min
            budget_tokens = [budget_tokens, 128].max
          end
        else
          budget_tokens = is_flash_model ? 8000 : 10000
        end
        
        # Set thinking configuration using correct structure
        body["generationConfig"]["thinkingConfig"] = {
          "thinkingBudget" => budget_tokens,
          "includeThoughts" => true
        }
      end
    end

    websearch_suffixed = false
    body["contents"] = context.compact.map do |msg|
      if websearch && !websearch_suffixed
        text = "#{msg["text"]}\n\n#{WEBSEARCH_PROMPT}"
      else
        text = msg["text"]
      end
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => text }
        ]
      }
    end

    if body["contents"].last["role"] == "user"
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

    if settings["tools"]
      # Convert the tools format if it's an array (initialize_from_assistant apps)
      if settings["tools"].is_a?(Array)
        body["tools"] = {"function_declarations" => settings["tools"]}
      else
        body["tools"] = settings["tools"]
      end
      
      # Ensure function_declarations exists
      body["tools"]["function_declarations"] ||= []
      body["tools"]["function_declarations"].push(*WEBSEARCH_TOOLS) if websearch
      body["tools"]["function_declarations"].uniq!

      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "ANY"
        }
      }
    elsif websearch
      body["tools"] = {"function_declarations" => WEBSEARCH_TOOLS}
      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "ANY"
        }
      }
    else
      body.delete("tools")
      body.delete("tool_config")
    end

    if role == "tool"
      parts = obj["tool_results"].map { |result|
        { "text" => result.dig("functionResponse", "response", "content") }
      }.filter { |part| part["text"] }

      if parts.any?
        body["contents"] << {
          "role" => "model",
          "parts" => parts
        }
      end
      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "NONE"
        }
      }
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

    # Convert the HTTP::Response::Body to a string and then process line by line
    res.each_line do |chunk|
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
          end

          candidates = json_obj["candidates"]
          candidates.each do |candidate|

            finish_reason = candidate["finishReason"]
            case finish_reason
            when "MAX_TOKENS"
              finish_reason = "length"
            when "STOP"
              finish_reason = "stop"
            when "SAFETY"
              finish_reason = "safety"
            when "CITATION"
              finish_reason = "recitation"
            else
              finish_reason = nil
            end

            content = candidate["content"]
            next if (content.nil? || finish_reason == "recitation" || finish_reason == "safety")

            content["parts"]&.each do |part|
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
                
              elsif part["text"]
                fragment = part["text"]
                
                # Special processing for media generator app to strip code blocks
                # Extract HTML from code blocks - for both media generator and code interpreter apps
                if (is_media_generator || session[:parameters]["app_name"].to_s.include?("Code Interpreter") || 
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
                    fragment.scan(/<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im) do |match|
                      html_sections << match[0]
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
                    # Extract HTML between code markers
                    html_content = fragment.gsub(/```html\s+/, "").gsub(/\s+```/, "")
                    fragment = html_content
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
        new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
      rescue StandardError => e
        new_results = [{ "type" => "error", "content" => "ERROR: #{e.message}" }]
      end

      if result && new_results
        begin
          # More robust handling of different response structures
          if new_results.is_a?(Array) && new_results[0].is_a?(Hash) && new_results[0]["choices"]
            tool_result_content = new_results.dig(0, "choices", 0, "message", "content").to_s.strip
          else
            tool_result_content = new_results.to_s.strip
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
      
      response_data = {
        "choices" => [
          {
            "finish_reason" => finish_reason,
            "message" => { "content" => final_content }
          }
        ]
      }
      
      # Add thinking content if present (similar to Claude)
      if thinking_parts.any?
        response_data["choices"][0]["message"]["thinking"] = thinking_parts.join("\n")
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
    
    # Process each tool call
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        # Parse arguments from the tool call
        argument_hash = tool_call["args"] || {}
        
        # Convert string keys to symbols for method calling
        argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_sym] = v
          memo
        end

        # Add session parameter for functions that need access to uploaded images
        if function_name == "generate_video_with_veo" || function_name == "generate_image_with_gemini"
          argument_hash[:session] = session
        end
        
        # tavily_search already accepts n parameter directly, no need to convert
        
        # Call the function with the provided arguments
        function_return = send(function_name.to_sym, **argument_hash)
        
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
  def generate_video_with_veo(prompt:, image_path: nil, aspect_ratio: "16:9", number_of_videos: nil, person_generation: "allow_adult", duration_seconds: nil, session: nil)
    
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
    
    parts = []
    parts << "video_generator_veo.rb"
    parts << "-p"
    parts << prompt.to_s
    parts << "-a"
    parts << aspect_ratio if aspect_ratio
    parts << "-n"
    parts << "1"  # Always force number_of_videos to 1
    parts << "-g"
    parts << person_generation if person_generation
    if duration_seconds
      parts << "-d"
      parts << duration_seconds.to_s
    end
    
    # Add image path if available
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
      shared_folder = if defined?(IN_CONTAINER) && IN_CONTAINER
                       MonadicApp::SHARED_VOL
                      else
                       MonadicApp::LOCAL_SHARED_VOL
                      end
      
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
      shared_folder = if defined?(IN_CONTAINER) && IN_CONTAINER
                       MonadicApp::SHARED_VOL
                      else
                       MonadicApp::LOCAL_SHARED_VOL
                      end
      
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