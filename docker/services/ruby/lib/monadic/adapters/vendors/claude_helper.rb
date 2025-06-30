require 'fileutils'
require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/json_repair"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"

module ClaudeHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5 * 2
  READ_TIMEOUT = 60 * 5
  WRITE_TIMEOUT = 60 * 5
  MAX_RETRIES = 5
  RETRY_DELAY = 2

  MIN_PROMPT_CACHING = 1024
  MAX_PC_PROMPTS = 4


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
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01"
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
        else
          # Return fallback models if API call fails during testing
          fallback_models = [
            "claude-3-opus-20240229",
            "claude-3-5-sonnet-20241022",
            "claude-3-haiku-20240307"
          ]
          $MODELS[:anthropic] = fallback_models
          return fallback_models
        end
      rescue HTTP::Error, HTTP::TimeoutError, StandardError
        # Return fallback models if any error occurs
        fallback_models = [
          "claude-3-opus-20240229",
          "claude-3-5-sonnet-20241022",
          "claude-3-haiku-20240307"
        ]
        $MODELS[:anthropic] = fallback_models
        return fallback_models
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
    api_key = CONFIG["ANTHROPIC_API_KEY"]
    
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
    
    # Handle messages - check if custom messages are provided (e.g., from SecondOpinionAgent)
    if options["messages"]
      # Convert messages to Claude's expected format
      body["messages"] = options["messages"].map do |msg|
        content = msg["content"]
        # Ensure content is in the expected format for Claude API
        if content.is_a?(String)
          {
            "role" => msg["role"],
            "content" => [
              {
                "type" => "text",
                "text" => content
              }
            ]
          }
        else
          # Already in the correct format
          msg
        end
      end
    else
      # Default AI User message for backward compatibility
      body["messages"] = [{
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "What might the user say next in this conversation? Please respond as if you were the user."
          }
        ]
      }]
    end
    
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
    
    # Debug log at the very beginning
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] === Claude API Request Started ===")
      extra_log.puts("Role: #{role}")
      extra_log.puts("App: #{session[:parameters]["app_name"]}")
      extra_log.puts("Session parameters: #{session[:parameters].inspect}")
      extra_log.close
    end

    begin
      # First check CONFIG, then ENV for API key
      api_key = CONFIG["ANTHROPIC_API_KEY"]
      
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
    # Handle both string and boolean values for websearch parameter
    websearch = obj["websearch"] == "true" || obj["websearch"] == true
    
    # Debug log websearch parameter
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("[#{Time.now}] Claude websearch parameter check:")
      extra_log.puts("obj[\"websearch\"] = #{obj["websearch"].inspect} (type: #{obj["websearch"].class})")
      extra_log.puts("websearch enabled = #{websearch}")
      extra_log.close
    end
    
    # Determine which web search implementation to use
    # Models that support native web search: Claude 3.5/3.7 Sonnet, Claude 3.5 Haiku
    native_websearch_models = [
      "claude-opus-4",
      "claude-sonnet-4",
      "claude-3-7-sonnet", 
      "claude-3-5-sonnet", 
      "claude-3-5-haiku"
    ]
    
    # Check if model supports native web search and native is enabled
    use_native_websearch = websearch && 
                          native_websearch_models.any? { |m| model.to_s.include?(m) } &&
                          CONFIG["ANTHROPIC_NATIVE_WEBSEARCH"] != "false"
    
    # Claude only uses native web search
    
    # Store these variables in obj for later use in the method
    obj["use_native_websearch"] = use_native_websearch

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
      if system_prompts.empty? && use_native_websearch
        prompt_suffix = WEBSEARCH_PROMPT
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

    if message != "" && role == "user"
      @thinking = nil
      @signature = nil
      res = { "type" => "user",
              "content" => {
                "role" => role,
                "mid" => request_id,
                "text" => obj["message"],
                "html" => markdown_to_html(obj["message"]),
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
      "anthropic-beta" => "prompt-caching-2024-07-31,pdfs-2024-09-25,output-128k-2025-02-19,extended-cache-ttl-2025-04-11,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
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
    # Parse tools if they're sent as JSON string
    tools_param = obj["tools"]
    if tools_param.is_a?(String)
      begin
        tools_param = JSON.parse(tools_param)
      rescue JSON::ParserError
        tools_param = nil
      end
    end
    
    # Check for web search first, as it should be independent of other tools
    websearch_enabled = obj["websearch"] == "true" || obj["websearch"] == true
    
    if tools_param && !tools_param.empty?
      # Get tools from app settings, or use the parsed tools from request
      app_tools = APPS[app]&.settings&.[]("tools")
      if app_tools && !app_tools.empty?
        body["tools"] = app_tools
      elsif tools_param.is_a?(Array) && !tools_param.empty?
        # Use tools from request if app doesn't have them
        # Filter out any Tavily tools since Claude uses native web search
        body["tools"] = tools_param.reject do |tool|
          tool_name = tool.dig("name") || tool.dig("function", "name")
          ["tavily_search", "tavily_fetch"].include?(tool_name)
        end
      else
        body["tools"] = []
      end
    elsif websearch_enabled
      # Even if no other tools, we need to add web search tool
      body["tools"] = []
    end
    
    # Add web search tool if enabled
    if websearch_enabled
      DebugHelper.debug("Claude: Adding web_search_20250305 tool for web search", category: :api, level: :debug)
      # Claude's web search tool requires specific format per documentation
      # https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool
      web_search_tool = {
        "type" => "web_search_20250305",
        "name" => "web_search",
        # Optional: Limit the number of searches per request
        "max_uses" => 5
      }
      body["tools"] ||= []
      body["tools"] << web_search_tool
      
      # Log the tool for debugging
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] Claude: web_search_20250305 tool added to request")
        extra_log.puts("Tools array: #{body["tools"].inspect}")
        extra_log.close
      end
    end
    
    # Only clean up if we have tools
    if body["tools"] && !body["tools"].empty?
      body["tools"].uniq!
    else
      body.delete("tools")
      body.delete("tool_choice")
    end
    
    

    # Add the context to the body
    messages = context.compact.map do |msg|
      content = { "type" => "text", "text" => msg["text"] }
      { "role" => msg["role"], "content" => [content] }
    end
    
    # Apply monadic transformation to the last user message if in monadic mode
    if obj["monadic"].to_s == "true" && messages.any? && messages.last["role"] == "user" && role == "user" && message != ""
      monadic_message = apply_monadic_transformation(obj["message"], app, "user")
      messages.last["content"][0]["text"] = monadic_message
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

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 0 && initial_prompt.to_s != ""
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => "Let's start" }]
      }
      
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] Claude: Added dummy user message for initiate_from_assistant")
        extra_log.close
      end
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body["tool_choice"] = { "type" => "auto" }
    end

    # Configure monadic response format
    body = configure_monadic_response(body, :claude, app)

    # Debug final request body for web search
    if websearch_enabled
      DebugHelper.debug("Claude final request with web search - tools: #{body["tools"]&.map { |t| "#{t["type"]}:#{t["name"]}" }.join(", ")}", category: :api, level: :debug)
      
      # Additional logging for debugging
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] Claude final API request:")
        extra_log.puts("URL: #{API_ENDPOINT}/messages")
        extra_log.puts("Model: #{body["model"]}")
        extra_log.puts("Tools present: #{body["tools"] ? "Yes (#{body["tools"].length} tools)" : "No"}")
        if body["tools"]
          extra_log.puts("Tools: #{JSON.pretty_generate(body["tools"])}")
        end
        extra_log.close
      end
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
      formatted_error = format_api_error(error_report, "claude")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
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
        break if /\Rdata: \[DONE\]\R/ =~ buffer
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
                
                # Debug logging for tool input accumulation
                if CONFIG["EXTRA_LOGGING"] && extra_log
                  extra_log.puts "[Tool Input Fragment] Length: #{fragment.length}, Content: #{fragment[0..100].inspect}"
                  extra_log.puts "[Tool Input Total] Length: #{tool_calls.last["input"].length}"
                end
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
                
                if fragment.length > 0
                  texts << fragment

                  res = {
                    "type" => "fragment",
                    "content" => fragment,
                    "index" => texts.length - 1,
                    "timestamp" => Time.now.to_f,
                    "is_first" => texts.length == 1
                  }
                  block&.call res
                end
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
        rescue JSON::ParserError => e
          # Log the error for debugging
          debug_log = "[Claude Tool Call JSON Parse Error at #{Time.now}]\n"
          debug_log += "Tool: #{tool_call["name"]}\n"
          debug_log += "Raw input length: #{tool_call["input"].to_s.length}\n"
          debug_log += "Raw input (first 500 chars): #{tool_call["input"].to_s[0..500].inspect}\n"
          debug_log += "Raw input (last 100 chars): #{tool_call["input"].to_s[-100..-1].inspect}\n"
          debug_log += "Error: #{e.message}\n"
          
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
            f.puts debug_log
          end
          
          # Attempt to repair truncated JSON
          if tool_call["name"] == "run_script"
            input_hash = JSONRepair.extract_run_script_params(tool_call["input"])
            
            # Log repair attempt
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
              f.puts "Attempted JSON repair for run_script"
              f.puts "Extracted params: #{input_hash.inspect}"
              f.puts "-" * 50
            end
          elsif tool_call["name"] == "run_code"
            input_hash = JSONRepair.extract_run_code_params(tool_call["input"])
            
            # Log repair attempt
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
              f.puts "Attempted JSON repair for run_code"
              f.puts "Extracted params: #{input_hash.inspect}"
              f.puts "-" * 50
            end
          else
            # Try general repair for other tools
            input_hash = JSONRepair.attempt_repair(tool_call["input"])
          end
          
          # If repair failed completely, return empty hash
          input_hash = {} if input_hash["_json_repair_failed"]
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
        # Send notice fragment
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
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
        
        # Return immediately to end the conversation
        return [{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }]
      end

      # Apply monadic transformation if enabled
      if text_result && obj["monadic"]
        # Process through unified interface
        processed = process_monadic_response(text_result, app)
        # Validate the response
        validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
        text_result = validated.is_a?(Hash) ? JSON.generate(validated) : validated
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
