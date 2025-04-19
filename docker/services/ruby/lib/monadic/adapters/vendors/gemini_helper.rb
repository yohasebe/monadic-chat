# frozen_string_literal: true

module GeminiHelper
  MAX_FUNC_CALLS = 12
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
    "Gemini"
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
    api_key = CONFIG["GEMINI_API_KEY"] || ENV["GEMINI_API_KEY"]
    return "Error: GEMINI_API_KEY not found" if api_key.nil?

    # Set headers
    headers = {
      "content-type" => "application/json"
    }

    # Basic request body
    body = {
      "safety_settings" => SAFETY_SETTINGS,
      "generationConfig" => {
        "maxOutputTokens" => options["max_tokens"] || 800,
        "temperature" => options["temperature"] || 0.7
      }
    }
    
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
    
    # Set up API endpoint
    target_uri = "#{API_ENDPOINT}/models/#{model}:generateContent?key=#{api_key}"
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
        
        # Extract text from standard response format
        if parsed_response["candidates"] && 
           parsed_response["candidates"][0] && 
           parsed_response["candidates"][0]["content"]
          
          content = parsed_response["candidates"][0]["content"]
          
          # 1. Check for parts array structure (Gemini 1.5 style)
          if content["parts"]
            text_parts = []
            content["parts"].each do |part|
              text_parts << part["text"] if part["text"]
            end
            
            return text_parts.join(" ") if text_parts.any?
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
        
        # Unable to extract text from response
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

    if temperature || max_tokens
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
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

    target_uri = "#{API_ENDPOINT}/models/#{obj["model"]}:streamGenerateContent?key=#{api_key}"

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
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
        block&.call res
      return [res]
    end

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
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
    
    # For image generator app, we'll need special processing to remove code blocks
    is_image_generator = app.to_s.include?("image_generator") || app.to_s.include?("gemini") && session[:parameters]["app_name"].to_s.include?("Image Generator")

    buffer = String.new
    texts = []
    tool_calls = []
    finish_reason = nil

    res.each do |chunk|
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
              if part["text"]
                fragment = part["text"]
                
                # Special processing for image generator app to strip code blocks
                # Extract HTML from code blocks - for both image generator and code interpreter apps
    if (is_image_generator || session[:parameters]["app_name"].to_s.include?("Code Interpreter")) && fragment.include?("```")
      # Check for HTML tags enclosed in code blocks
      if fragment =~ /<div class="generated_image">.*?<img src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg)".*?>.*?<\/div>/im
        # First try the clean approach - extract HTML content from any code block that contains visualization HTML
        html_sections = []
        code_sections = []
        
        # Extract HTML sections
        fragment.scan(/<div class="generated_image">.*?<img src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg)".*?>.*?<\/div>/im) do |match|
          html_sections << match
        end
        
        # Extract code blocks (without the HTML)
        if fragment.match(/```(\w+)?.*?```/m)
          fragment.scan(/```(\w+)?(.*?)```/m) do |lang, code|
            # Skip if the code block contains HTML visualization
            unless code =~ /<div class="generated_image">.*?<img src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg)".*?>.*?<\/div>/im
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
        # For image generator app only, remove any code block markers
        if is_image_generator
          fragment = fragment.gsub(/```(\w+)?/, "").gsub(/```/, "")
        end
      end
    end
                
                texts << fragment

                res = {
                  "type" => "fragment",
                  "content" => fragment
                }
                block&.call res

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
          
          # If no actual content was returned from the function call, add a notice
          if tool_result_content.empty?
            tool_result_content = "[No additional content received from function call]"
          end
          
          # Clean up any "No response" messages that might be in the results
          if result.is_a?(Array) && result.length == 1 && 
             result[0].to_s.include?("No response was received")
            # Replace error message with actual content
            result = []
          end
          
          final_result = result.join("").strip
          
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
          
          # Notification of function call completion has been removed
          
          [{ "choices" => [{ "message" => { "content" => final_result } }] }]
        rescue StandardError => e
          # Log the error and send a more informative message
          result_text = result.join("").strip
          
          # Clean up any "No response" messages that might be in the results
          if result_text.include?("No response was received")
            result_text = ""
          end
          
          error_message = "[Error processing function results: #{e.message}]"
          final_result = result_text.empty? ? error_message : result_text + "\n\n" + error_message
          
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
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result.join("") }
            }
          ]
        }
      ]
    end
  end

  def process_functions(_app, session, tool_calls, context, call_depth, &block)
    return false if tool_calls.empty?

    obj = session[:parameters]
    # MODIFICATION: Changed the structure of tool_results to only include functionResponse
    tool_results = []
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        argument_hash = tool_call["args"]
      rescue StandardError
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = send(function_name.to_sym, **argument_hash)
        # MODIFICATION: Improved error handling and unified the return value format
        if function_return
          content = if function_return.is_a?(String)
                      function_return
                    else
                      function_return.to_json
                    end

          tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => content
              }
            }
          }
        else
          # Error handling
          error_message = "ERROR: Function (#{function_name}) called with #{argument_hash} returned nil."
        tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => error_message
              }
            }
          }
        # Send error message to client for better visibility
        res = { "type" => "fragment", "content" => "<span class='text-danger'>#{error_message}</span>" }
        block&.call res
        end
      rescue StandardError => e
        
        error_message = "ERROR: Function call failed: #{function_name}. #{e.message}"
        
        # Add error to tool_results (not context) to ensure it's properly processed
        tool_results << {
          "functionResponse" => {
            "name" => function_name,
            "response" => {
              "name" => function_name,
              "content" => error_message
            }
          }
        }
        
        # Send error message to client for better visibility
        res = { "type" => "fragment", "content" => "<span class='text-danger'>#{error_message}</span>" }
        block&.call res
      end
    end

    # MODIFICATION: Clear tool_results after processing
    obj["tool_results"] = tool_results
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
         
         Do NOT place this HTML inside a code block. The image will only display if the HTML is outside of code blocks.
         Users will not see visualizations if you wrap HTML in code blocks.
    INSTRUCTIONS
  end
end
