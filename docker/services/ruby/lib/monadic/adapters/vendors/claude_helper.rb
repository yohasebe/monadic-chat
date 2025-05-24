require 'fileutils'

module ClaudeHelper
  MAX_FUNC_CALLS = 8
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5 * 2
  READ_TIMEOUT = 60 * 5
  WRITE_TIMEOUT = 60 * 5
  MAX_RETRIES = 5
  RETRY_DELAY = 2

  MIN_PROMPT_CACHING = 1024
  MAX_PC_PROMPTS = 4

  # Tavily-based websearch tools
  TAVILY_WEBSEARCH_TOOLS = [
    {
      name: "tavily_fetch",
      description: "fetch the content of the web page of the given url and return its content.",
      input_schema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "url of the web page."
          }
        },
        required: ["url"],
      }
    },
    {
      name: "tavily_search",
      description: "search the web for the given query and return the result. the result contains the answer to the query, the source url, and the content of the web page.",
      input_schema: {
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
  ]

  # Native Anthropic web search tool
  NATIVE_WEBSEARCH_TOOL = {
    type: "web_search_20250305",
    name: "web_search",
    max_uses: 10
  }

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT

  TAVILY_WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT


  attr_accessor :thinking, :signature

  class << self
    attr_reader :cached_models

    def vendor_name
      "Anthropic"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:anthropic] if $MODELS[:anthropic]

      api_key = CONFIG["ANTHROPIC_API_KEY"]
      return [] if api_key.nil?

      headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01"
      }

      target_uri = "#{API_ENDPOINT}/models"
      http = HTTP.headers(headers)

      begin
        res = http.get(target_uri)

        if res.status.success?
          # Cache the model list
          model_data = JSON.parse(res.body)
          models = model_data["data"].map do |model|
            model["id"]
          end.select do |model|
            !model.include?("claude-2")
          end
          
          # Store in $MODELS with indifferent access
          $MODELS[:anthropic] = models
          
          return models
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:anthropic] = nil
    end
  end

  def initialize
    @thinking = nil
    @signature = nil
    super
  end

  # Function to write logs to file - enabled for debugging AI User issues
  def log_to_file(message, type="general")
    return unless CONFIG["DEBUG_AI_USER"]
    
    begin
      log_dir = File.join(Dir.home, "monadic", "log")
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
      
      file_name = case type
                  when "ai_user"
                    "claude_ai_user_debug.log"
                  else
                    "claude_debug.log"
                  end
      
      File.open(File.join(log_dir, file_name), "a") do |f|
        f.puts("[#{Time.now}] #{message}")
      end
    rescue => e
      # Silent fail for logging
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "claude-3-5-sonnet-20241022")
    # First try CONFIG, then fall back to ENV for the API key
    api_key = CONFIG["ANTHROPIC_API_KEY"] || ENV["ANTHROPIC_API_KEY"]
    
    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "x-api-key" => api_key
    }

    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Model details are logged to dedicated log files
    
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Basic request body
    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7
    }
    
    # Extract system message - Claude API expects this as a top-level parameter
    if options["system"]
      body["system"] = options["system"]
    elsif options["ai_user_system_message"]
      body["system"] = options["ai_user_system_message"]
    end
    
    # Simple AI User message for more reliable responses
    body["messages"] = [{
      "role" => "user",
      "content" => [
        {
          "type" => "text",
          "text" => "What might the user say next in this conversation? Please respond as if you were the user."
        }
      ]
    }]
    
    # Set API endpoint
    target_uri = "#{API_ENDPOINT}/messages"

    # Make the request
    http = HTTP.headers(headers)
    
    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                       write: WRITE_TIMEOUT,
                       read: READ_TIMEOUT).post(target_uri, json: body)
      break if res && res.status && res.status.success?
      sleep RETRY_DELAY
    end

    # Process response
    if res && res.status && res.status.success?
      begin
        parsed_response = JSON.parse(res.body)
        
        # Extract content from response - try all known formats
        
        # Format 1: Direct content array in response root
        if parsed_response["content"] && parsed_response["content"].is_a?(Array)
          text_blocks = parsed_response["content"].select { |item| item["type"] == "text" }
          return text_blocks.map { |block| block["text"] }.join("\n") if text_blocks.any?
        end
        
        # Format 2: Content in message.content
        if parsed_response["message"] && parsed_response["message"]["content"].is_a?(Array)
          text_blocks = parsed_response["message"]["content"].select { |item| item["type"] == "text" }
          return text_blocks.map { |block| block["text"] }.join("\n") if text_blocks.any?
        end
        
        # Format 3: Direct completion in response
        if parsed_response["completion"]
          return parsed_response["completion"]
        end
        
        # Format 4: Text in response
        if parsed_response["text"]
          return parsed_response["text"]
        end
        
        # Extract any content from anywhere in the response
        def extract_text_from_hash(hash, depth=0)
          return nil if depth > 3 || !hash.is_a?(Hash)
          
          hash.each do |key, value|
            if key == "text" && value.is_a?(String)
              return value
            elsif value.is_a?(Hash)
              result = extract_text_from_hash(value, depth+1)
              return result if result
            elsif value.is_a?(Array)
              value.each do |item|
                if item.is_a?(Hash)
                  if item["type"] == "text" && item["text"]
                    return item["text"]
                  end
                  
                  result = extract_text_from_hash(item, depth+1)
                  return result if result
                end
              end
            end
          end
          nil
        end
        
        # Try recursive extraction
        text = extract_text_from_hash(parsed_response)
        return text if text
        
        # If all else fails, return the entire response for debugging
        return "ERROR: Could not extract text content from Claude API response. Full response: #{parsed_response.inspect[0..200]}..."
      rescue => e
        return "ERROR: Failed to process Claude API response: #{e.message}"
      end
    else
      error_response = (res && res.body) ? JSON.parse(res.body) : { "error" => "No response received" }
      return "ERROR: #{error_response.dig("error", "message") || error_response["error"]}"
    end
  rescue StandardError => e
    return "Error: #{e.message}"
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      # First check CONFIG, then ENV for API key
      api_key = CONFIG["ANTHROPIC_API_KEY"] || ENV["ANTHROPIC_API_KEY"]
      
      raise if api_key.nil?
    rescue StandardError => e
      error_message = "ERROR: ANTHROPIC_API_KEY not found. Please set the ANTHROPIC_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    model = obj["model"]
    
    # Check if web search is enabled
    websearch = obj["websearch"] == "true"
    
    # Determine which web search implementation to use
    # Models that support native web search: Claude 3.5/3.7 Sonnet, Claude 3.5 Haiku
    native_websearch_models = [
      "claude-3-5-sonnet", 
      "claude-3-7-sonnet", 
      "claude-3-5-haiku",
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022"
    ]
    
    # Check if model supports native web search and native is enabled
    use_native_websearch = websearch && 
                          native_websearch_models.any? { |m| model.to_s.include?(m) } &&
                          CONFIG["ANTHROPIC_NATIVE_WEBSEARCH"] != "false"
    
    # Use Tavily if API key is available and native is not being used
    use_tavily_websearch = websearch && 
                          CONFIG["TAVILY_API_KEY"] && 
                          !use_native_websearch
    
    # Store these variables in obj for later use in the method
    obj["use_native_websearch"] = use_native_websearch
    obj["use_tavily_websearch"] = use_tavily_websearch

    system_prompts = []
    system_prompt_count = 0
    
    session[:messages].each do |msg|
      next unless msg["role"] == "system"
      
      # Count system prompts
      system_prompt_count += 1

      # Check tokens only for the first MAX_PC_PROMPTS system prompts
      if obj["prompt_caching"] && system_prompt_count <= MAX_PC_PROMPTS
        check_num_tokens(msg)
      end

      # Add appropriate websearch prompt based on implementation
      if system_prompts.empty? && (use_native_websearch || use_tavily_websearch)
        prompt_suffix = use_tavily_websearch ? TAVILY_WEBSEARCH_PROMPT : WEBSEARCH_PROMPT
        text = msg["text"] + "\n---\n" + prompt_suffix
      else
        text = msg["text"]
      end

      sp = { type: "text", text: text }
      
      # Add cache_control only for the first MAX_PC_PROMPTS system prompts with sufficient tokens
      if obj["prompt_caching"] && system_prompt_count <= MAX_PC_PROMPTS && msg["tokens"] && msg["tokens"] > MIN_PROMPT_CACHING
        sp["cache_control"] = {
          "type" => "ephemeral",
          "ttl" => "1h"
        }
      end

      system_prompts << sp
    end

    temperature = obj["temperature"]&.to_f
    
    # Handle max_tokens, prioritizing AI_USER_MAX_TOKENS for AI User mode
    if obj["ai_user"] == "true"
      max_tokens = (CONFIG["AI_USER_MAX_TOKENS"] || obj["max_tokens"])&.to_i
    else
      max_tokens = obj["max_tokens"]&.to_i
    end

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    # Store the original max_tokens value
    user_max_tokens = max_tokens
    
    case obj["reasoning_effort"]
    when "low"
      # Use proportional approach based on user's max_tokens
      budget_tokens = [(user_max_tokens * 0.5).to_i, 16000].min
      max_tokens = user_max_tokens  # Keep original value
    when "medium"
      budget_tokens = [(user_max_tokens * 0.7).to_i, 32000].min
      max_tokens = user_max_tokens
    when "high"
      budget_tokens = [(user_max_tokens * 0.8).to_i, 48000].min
      max_tokens = user_max_tokens
    else
      budget_tokens = nil
    end
    
    # Ensure budget_tokens is less than max_tokens
    if budget_tokens && budget_tokens >= max_tokens
      # Adjust budget_tokens to be at most 80% of max_tokens
      budget_tokens = (max_tokens * 0.8).to_i
    end

    if role != "tool"
      # Apply monadic transformation if monadic mode is enabled
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end
    end

    if message != "" && role == "user"
      @thinking = nil
      @signature = nil
      res = { "type" => "user",
              "content" => {
                "role" => role,
                "mid" => request_id,
                "text" => obj["message"],
                "html" => markdown_to_html(message),
                "lang" => detect_language(obj["message"]),
                "active" => true
              } }

      res["content"]["images"] = obj["images"] if obj["images"]
      block&.call res
      session[:messages] << res["content"]
    end

    # Set old messages in the session to inactive
    # and add active messages to the context
    begin
      session[:messages].each { |msg| msg["active"] = false }

      context = session[:messages].filter do |msg|
        msg["role"] == "user" || msg["role"] == "assistant"
      end.last(context_size).each { |msg| msg["active"] = true }

      session[:messages].filter do |msg|
        msg["role"] == "system"
      end.each { |msg| msg["active"] = true }
    rescue StandardError
      context = []
    end

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "anthropic-beta" => "prompt-caching-2024-07-31,pdfs-2024-09-25,output-128k-2025-02-19;extended-cache-ttl-2025-04-11",
      "anthropic-dangerous-direct-browser-access": "true",
      "x-api-key" => api_key,
    }

    # Set the body for the API request
    body = {
      "system" => system_prompts,
      "model" => obj["model"],
      "stream" => true,
      "tool_choice" => {
        "type": "any"
      }
    }

    if budget_tokens
      body["max_tokens"] = max_tokens
      body["temperature"] = 1
      body["tool_choice"] = { "type" => "auto" }
      body["thinking"] = {
        "type": "enabled",
        "budget_tokens": budget_tokens
      }
    else
      body["temperature"] = temperature if temperature
      body["max_tokens"] = max_tokens if max_tokens
    end

    # Configure tools based on app settings and web search type
    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
      
      # Add appropriate web search tools
      if obj["use_native_websearch"]
        body["tools"] ||= []
        body["tools"] << NATIVE_WEBSEARCH_TOOL
      elsif obj["use_tavily_websearch"]
        body["tools"] ||= []
        body["tools"].push(*TAVILY_WEBSEARCH_TOOLS)
      end
      
      body["tools"].uniq!
    elsif obj["use_native_websearch"]
      body["tools"] = [NATIVE_WEBSEARCH_TOOL]
    elsif obj["use_tavily_websearch"]
      body["tools"] = TAVILY_WEBSEARCH_TOOLS
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Add the context to the body
    messages = context.compact.map do |msg|
      content = { "type" => "text", "text" => msg["text"] }
      { "role" => msg["role"], "content" => [content] }
    end

    # Only add a default message for regular chat mode, not for AI User mode
    # This ensures AI User can work with the conversation history properly
    if messages.empty? && obj["ai_user"] != "true"
      messages << {
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "Hello."
          }
        ]
      }
    end

    if !messages.empty? && messages.last["role"] == "user"
      content = messages.last["content"]

      # Handle PDFs and images if present
      if obj["images"]
        obj["images"].each do |file|
          if file["type"] == "application/pdf"
            doc = {
              "type" => "document",
              "source" => {
                "type" => "base64",
                "media_type" => "application/pdf",
                "data" => file["data"].split(",")[1]
              }
            }
            doc["cache_control"] = {
              "type" => "ephemeral",
              "ttl" => "1h"
            } if obj["prompt_caching"]
            # PDF is better inserted before the text 
            # https://docs.anthropic.com/en/docs/build-with-claude/pdf-support#optimize-pdf-processing
            content.unshift(doc)
          else
            # Handle images
            img = {
              "type" => "image",
              "source" => {
                "type" => "base64",
                "media_type" => file["type"],
                "data" => file["data"].split(",")[1]
              }
            }
            img["cache_control"] = {
              "type" => "ephemeral",
              "ttl" => "1h"
            } if obj["prompt_caching"]
            content << img
          end
        end
      end
    end

    body["messages"] = messages

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body["tool_choice"] = { "type" => "auto" }
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/messages"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
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
    buffer = String.new
    texts = []
    thinking = []
    redacted_thinking = []
    thinking_signature = nil
    tool_calls = []
    finish_reason = nil

    content_type = "text"

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

      scanner = StringScanner.new(buffer)
      pattern = /data: (\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            if CONFIG["EXTRA_LOGGING"]
              extra_log.puts(JSON.pretty_generate(json))
            end

            if json.dig("type") == "content_block_stop"
              res = { "type" => "fragment", "content" => "\n\n" }
              block&.call res
            end

            # Handle content type changes
            new_content_type = json.dig("content_block", "type")
            if new_content_type == "tool_use"
              json["content_block"]["input"] = ""
              tool_calls << json["content_block"]
            end
            content_type = new_content_type if new_content_type

            if content_type == "tool_use"
              if json.dig("delta", "partial_json")

                fragment = json.dig("delta", "partial_json").to_s

                tool_calls.last["input"] << fragment
              end
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "tool_use"
                  finish_reason = "tool_use"
                  res1 = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res1
                end
              end
            else
              # Handle text content
              if json.dig("delta", "text")
                fragment = json.dig("delta", "text").to_s
                texts << fragment

                res = {
                  "type" => "fragment",
                  "content" => fragment
                }
                block&.call res
              elsif json.dig("delta", "thinking")
                fragment = json.dig("delta", "thinking").to_s
                thinking << fragment

                res = {
                  "type" => "thinking",
                  "content" => fragment
                }
                block&.call res
              elsif json.dig("delta", "signature")
                fragment = json.dig("delta", "signature").to_s
                thinking_signature = fragment
              elsif json.dig("delta", "redacted_thinking")
                fragment = json.dig("delta", "redacted_thinking").to_s
                redacted_thinking << fragment
              end

              # Handle stop reasons
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "max_tokens"
                  finish_reason = "length"
                when "end_turn"
                  finish_reason = "stop"
                end
              end
            end
          rescue JSON::ParserError
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

    thinking_result = if thinking.empty?
                        nil
                      else
                        thinking.join("")
                      end

    redacted_thinking_result = if redacted_thinking.empty?
                                 nil
                               else
                                 redacted_thinking.join("")
                               end

    @thinking = @thinking.to_s + thinking_result if thinking_result
    @signature = thinking_signature if thinking_signature

    text_result = if texts.empty?
               nil
             else
               texts.join("")
             end

    # Process tool calls if any exist
    if tool_calls.any? && call_depth <= MAX_FUNC_CALLS
      call_depth += 1
      # Process each tool call individually
      responses = tool_calls.map do |tool_call|
        context = []
        context << {
          "role" => "assistant",
          "content" => []
        }

        if thinking_result || @thinking.to_s != ""
          thinking = thinking_result || @thinking.to_s
          signature = thinking_signature || @signature
          thinking_block = {
            "type" => "thinking",
            "thinking" => thinking,
            "signature" => signature
          }
          context.last["content"] << thinking_block
        end

        if redacted_thinking_result
          context.last["content"] << {
            "type" => "redacted_thinking",
            "data" => redacted_thinking_result
          }
        end

        if text_result
          content ={
            "type" => "text",
            "text" => text_result
          }
          context.last["content"] << content
        end

        # Parse tool call input
        begin
          input_hash = JSON.parse(tool_call["input"])
        rescue JSON::ParserError
          input_hash = {}
        end

        tool_call["input"] = input_hash

        context.last["content"] << {
          "type" => "tool_use",
          "id" => tool_call["id"],
          "name" => tool_call["name"],
          "input" => tool_call["input"]
        }

        # Process single tool call
        process_functions(app, session, [tool_call], context, call_depth, &block)
      end

      return responses.last

      # Process regular text response
    elsif text_result

      if call_depth > MAX_FUNC_CALLS
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
        block&.call res
      end

      # Apply monadic transformation if enabled
      if text_result && obj["monadic"]
        begin
          # Check if result is valid JSON
          JSON.parse(text_result)
          # If it's already JSON, apply monadic_map directly
          text_result = APPS[app].monadic_map(text_result)
        rescue JSON::ParserError
          # If not JSON, wrap it in the proper format before applying monadic_map
          wrapped = JSON.pretty_generate({
            "message" => text_result,
            "context" => {}
          })
          text_result = APPS[app].monadic_map(wrapped)
        end
      end

      # Send completion message
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res

      # Return final response
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => {
                "thinking" => @thinking,
                "content" => text_result
              }
            }
          ]
        }
      ]
    end
  end

  def check_num_tokens(msg)
    t = msg["tokens"]
    if t
      new_t = t.to_i
    else
      new_t = MonadicApp::TOKENIZER.count_tokens(msg["text"]).to_i
      msg["tokens"] = new_t
    end
    new_t > MIN_PROMPT_CACHING
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]
    tools.each do |tool_call|
      tool_name = tool_call["name"]

      begin
        argument_hash = tool_call["input"]
      rescue StandardError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      # wait for the app instance is ready up to 10 seconds
      app_instance = APPS[app]

      if argument_hash.empty?
        tool_return = app_instance.send(tool_name.to_sym)
      else
        tool_return = app_instance.send(tool_name.to_sym, **argument_hash)
      end

      unless tool_return
        tool_return = "Empty result"
      end

      content << {
        type: "tool_result",
        tool_use_id: tool_call["id"],
        content: tool_return.to_s
      }
    end

    context << {
      role: "user",
      content: content
    }

    obj["function_returns"] = context

    # Return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def monadic_unit(message)
    begin
      # If message is already JSON, parse and reconstruct
      json = JSON.parse(message)
      res = {
        "message" => json["message"] || message,
        "context" => json["context"] || @context
      }
    rescue JSON::ParserError
      # If not JSON, create the structure
      res = {
        "message" => message,
        "context" => @context
      }
    end
    res.to_json
  end

  def monadic_map(monad)
    begin
      obj = monadic_unwrap(monad)
      # Process the message part
      message = obj["message"].is_a?(String) ? obj["message"] : obj["message"].to_s
      # Update context if block is given
      @context = block_given? ? yield(obj["context"]) : obj["context"]
      # Create the result structure
      result = {
        "message" => message,
        "context" => @context
      }
      JSON.pretty_generate(sanitize_data(result))
    rescue JSON::ParserError
      # Handle invalid JSON input
      result = {
        "message" => monad.to_s,
        "context" => @context
      }
      JSON.pretty_generate(sanitize_data(result))
    end
  end

  def monadic_unwrap(monad)
    JSON.parse(monad)
  rescue JSON::ParserError
    { "message" => monad.to_s, "context" => @context }
  end

  def sanitize_data(data)
    if data.is_a? String
      return data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    if data.is_a? Hash
      data.each do |key, value|
        data[key] = sanitize_data(value)
      end
    elsif data.is_a? Array
      data.map! do |value|
        sanitize_data(value)
      end
    end

    data
  end
end
