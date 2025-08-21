# frozen_string_literal: true

require_relative "../../utils/interaction_utils"

module GrokHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20  # Balanced for Grok-4
  API_ENDPOINT = "https://api.x.ai/v1"

  OPEN_TIMEOUT = 60
  READ_TIMEOUT = 300
  WRITE_TIMEOUT = 300

  MAX_RETRIES = 5
  RETRY_DELAY = 1


  class << self
    attr_reader :cached_models

    def vendor_name
      "xAI"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:grok] if $MODELS[:grok]

      api_key = CONFIG["XAI_API_KEY"]
      return [] if api_key.nil?

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      target_uri = "#{API_ENDPOINT}/language-models"
      http = HTTP.headers(headers)

      begin
        res = http.get(target_uri)

        if res.status.success?
          # Cache the model list
          model_data = JSON.parse(res.body)
          $MODELS[:grok] = model_data["models"].map do |model|
            model["id"]
          end
          $MODELS[:grok]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:grok] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "grok-3-mini")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["XAI_API_KEY"]
    if api_key.nil?
      require_relative '../../utils/error_handler'
      return ErrorHandler.format_error(
        category: :configuration,
        message: "XAI_API_KEY not found",
        suggestion: "Please set your xAI API key in the configuration"
      )
    end
    
    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Get the requested model
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Basic request body
    body = {
      "model" => model,
      "stream" => false,
      "temperature" => options["temperature"] || 0.7,
      "messages" => []
    }
    
    # Add parameters if specified
    body["max_tokens"] = options["max_tokens"] if options["max_tokens"]
    body["frequency_penalty"] = options["frequency_penalty"] if options["frequency_penalty"]
    body["presence_penalty"] = options["presence_penalty"] if options["presence_penalty"]

    # Grok-4 does not support reasoning_effort
    # (Grok-3 did support it, but current model is Grok-4)
    # case options["reasoning_effort"]
    # when "low"
    #   body["reasoning_effort"] = "low"
    # when "medium", "high"
    #   body["reasoning_effort"] = "high"
    # end
    
    # Add search_parameters if requested
    if options["search_parameters"]
      body["search_parameters"] = options["search_parameters"]
    end
    
    # Handle system message
    if options["system"]
      body["messages"] << {
        "role" => "system",
        "content" => options["system"]
      }
    elsif options["custom_system_message"]
      body["messages"] << {
        "role" => "system",
        "content" => options["custom_system_message"]
      }
    elsif options["initial_prompt"]
      body["messages"] << {
        "role" => "system",
        "content" => options["initial_prompt"]
      }
    end
    
    # Add messages from options
    if options["messages"]
      options["messages"].each do |msg|
        # Extract content with fallback to text
        content = msg["content"] || msg["text"] || ""
        
        # Only add non-empty messages
        if content.to_s.strip.length > 0
          body["messages"] << {
            "role" => msg["role"],
            "content" => content
          }
        end
      end
    elsif options["message"]
      body["messages"] << {
        "role" => "user",
        "content" => options["message"]
      }
    end
   
    # Set API endpoint
    target_uri = API_ENDPOINT + "/chat/completions"

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
      parsed_response = JSON.parse(res.body)
      return parsed_response.dig("choices", 0, "message", "content")
    else
      error_response = (res && res.body) ? JSON.parse(res.body) : { "error" => "No response received" }
      return "ERROR: #{error_response.dig("error", "message") || error_response["error"]}"
    end
  rescue StandardError => e
    require_relative '../../utils/error_handler'
    return ErrorHandler.format_provider_error(
      provider: "xAI Grok",
      error: e
    )
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, disable_streaming: false, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    api_key = CONFIG["XAI_API_KEY"]

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    presence_penalty = obj["presence_penalty"] ? obj["presence_penalty"].to_f : nil
    frequency_penalty = obj["frequency_penalty"] ? obj["frequency_penalty"].to_f : nil
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    # Check for websearch configuration
    # Handle both string and boolean values for websearch parameter
    websearch = obj["websearch"] == "true" || obj["websearch"] == true
    websearch_native = websearch
    
    # Debug log websearch parameter
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] === Grok websearch parameter check ===")
      extra_log.puts("obj[\"websearch\"] = #{obj["websearch"].inspect} (type: #{obj["websearch"].class})")
      extra_log.puts("websearch enabled = #{websearch}")
      extra_log.close
    end

    message = nil
    data = nil

    # Skip message processing for tool role (but still process context)
    if role != "tool"
      message = obj["message"].to_s
      
      # Reset model switch notification flag for new user messages
      if role == "user"
        session.delete(:model_switch_notified)
      end

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

      html = markdown_to_html(obj["message"], mathjax: obj["mathjax"])

      if message != "" && role == "user"

        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "role" => role,
                  "lang" => detect_language(message)
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
        block&.call res
        session[:messages] << res["content"]
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

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
    }
    
    # Store the original model for comparison later
    original_user_model = model

    # Disable streaming when processing tool results to avoid hanging
    body["stream"] = !disable_streaming
    body["n"] = 1
    body["temperature"] = temperature if temperature
    body["presence_penalty"] = presence_penalty if presence_penalty
    body["frequency_penalty"] = frequency_penalty if frequency_penalty
    body["max_tokens"] = max_tokens if max_tokens

    if obj["response_format"]
      body["response_format"] = APPS[app].settings["response_format"]
    end

    # Grok cannot execute tools with structured output enabled
    # Keep simple json_object format for compatibility
    if obj["monadic"] || obj["json"]
      body["response_format"] ||= { "type" => "json_object" }
    end

    # Get tools from app settings
    app_tools = APPS[app]&.settings&.[]("tools")
    
    # Include tools based on role and availability
    # When role is "tool" (sending tool results back), don't include tools to prevent infinite loops
    if role == "tool"
      body.delete("tools")
      body.delete("tool_choice")
    elsif obj["tools"] && !obj["tools"].empty?
      # Use app tools if available, otherwise fallback to empty array
      body["tools"] = app_tools || []
      
      # Special handling for Code Interpreter apps with Grok
      if app && app.include?("CodeInterpreter") && body["tools"] && !body["tools"].empty?
        # Determine tool_choice based on context
        if body["messages"].is_a?(Array) && body["messages"].length > 1
          # Check if the last assistant message contains code execution results
          last_assistant_msg = body["messages"].reverse.find { |m| m["role"] == "assistant" }
          
          if last_assistant_msg
            # Extract content text
            assistant_content = if last_assistant_msg["content"].is_a?(Array)
                                 last_assistant_msg["content"].map { |c| c["text"] if c["type"] == "text" }.compact.join(" ")
                               else
                                 last_assistant_msg["content"].to_s
                               end
            
            # If last response was a code execution, next message is likely a follow-up
            # Use "auto" to allow natural conversation
            if assistant_content =~ /File\(s\) generated|Output:|<div class="generated_image">|✓ File created/
              body["tool_choice"] = obj["tool_choice"] || "auto"
            else
              # Otherwise, for Code Interpreter, prefer tool usage
              # But only after initial greeting (more than 2 messages total)
              body["tool_choice"] = obj["tool_choice"] || (body["messages"].length > 2 ? "required" : "auto")
            end
          else
            # No assistant message yet, use auto
            body["tool_choice"] = obj["tool_choice"] || "auto"
          end
        else
          # Initial state, use auto
          body["tool_choice"] = obj["tool_choice"] || "auto"
        end
      else
        # Use tool_choice from settings or default
        body["tool_choice"] = obj["tool_choice"] || "auto"
      end
      
      # Remove tool_choice if no tools
      body.delete("tool_choice") if body["tools"].nil? || body["tools"].empty?
    elsif app_tools && !app_tools.empty?
      # If no tools param but app has tools, use them
      body["tools"] = app_tools
      
      # Same logic for Code Interpreter
      if app && app.include?("CodeInterpreter")
        if body["messages"].is_a?(Array) && body["messages"].length > 1
          last_assistant_msg = body["messages"].reverse.find { |m| m["role"] == "assistant" }
          
          if last_assistant_msg
            assistant_content = if last_assistant_msg["content"].is_a?(Array)
                                 last_assistant_msg["content"].map { |c| c["text"] if c["type"] == "text" }.compact.join(" ")
                               else
                                 last_assistant_msg["content"].to_s
                               end
            
            if assistant_content =~ /File\(s\) generated|Output:|<div class="generated_image">|✓ File created/
              body["tool_choice"] = obj["tool_choice"] || "auto"
            else
              body["tool_choice"] = obj["tool_choice"] || (body["messages"].length > 2 ? "required" : "auto")
            end
          else
            body["tool_choice"] = obj["tool_choice"] || "auto"
          end
        else
          body["tool_choice"] = obj["tool_choice"] || "auto"
        end
      else
        body["tool_choice"] = obj["tool_choice"] || "auto"
      end
    else
      body.delete("tools")
      body.delete("tool_choice")
    end
    
    # Add parallel_function_calling if specified (default is true for Grok)
    if body["tools"] && !body["tools"].empty? && obj["parallel_function_calling"] == false
      body["parallel_function_calling"] = false
    end
    
    # Debug log final tools being sent
    if CONFIG["EXTRA_LOGGING"] && body["tools"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] === Grok Final Tools (role: #{role}) ===")
      extra_log.puts("Number of tools: #{body['tools'].length}")
      extra_log.puts("Tool names: #{body['tools'].map { |t| t.dig('function', 'name') || t['name'] }.inspect}")
      if role == "tool"
        extra_log.puts("Including tools in tool response for continued function calling")
      end
      extra_log.close
    end
    
    # Add search_parameters for native Grok Live Search
    if websearch_native
      # Build search parameters with support for all documented options
      search_params = {
        "mode" => "on",  # "on" forces live search, "auto" lets model decide
        "return_citations" => true
      }
      
      # Configure data sources with their supported parameters
      sources = []
      
      # Web source with optional parameters
      web_source = { "type" => "web" }
      web_source["country"] = obj["web_country"] if obj["web_country"]
      web_source["excluded_websites"] = obj["excluded_websites"] if obj["excluded_websites"]
      web_source["allowed_websites"] = obj["allowed_websites"] if obj["allowed_websites"]
      web_source["safe_search"] = obj["safe_search"] if obj["safe_search"]
      sources << web_source
      
      # X (Twitter) source with optional parameters
      if obj.fetch("enable_x_search", true) # Default to enabled for backward compatibility
        x_source = { "type" => "x" }
        x_source["included_x_handles"] = obj["included_x_handles"] if obj["included_x_handles"]
        x_source["excluded_x_handles"] = obj["excluded_x_handles"] if obj["excluded_x_handles"]
        x_source["post_favorite_count"] = obj["post_favorite_count"] if obj["post_favorite_count"]
        x_source["post_view_count"] = obj["post_view_count"] if obj["post_view_count"]
        sources << x_source
      end
      
      # News source with optional parameters
      if obj.fetch("enable_news_search", true) # Default to enabled for backward compatibility
        news_source = { "type" => "news" }
        news_source["country"] = obj["news_country"] || obj["web_country"] if obj["news_country"] || obj["web_country"]
        news_source["excluded_websites"] = obj["news_excluded_websites"] || obj["excluded_websites"] if obj["news_excluded_websites"] || obj["excluded_websites"]
        news_source["safe_search"] = obj["news_safe_search"] || obj["safe_search"] if obj["news_safe_search"] || obj["safe_search"]
        sources << news_source
      end
      
      # RSS source with links parameter
      if obj["rss_links"] && !obj["rss_links"].empty?
        rss_source = {
          "type" => "rss",
          "links" => obj["rss_links"]
        }
        sources << rss_source
      end
      
      # Add configured sources to search parameters
      search_params["sources"] = sources unless sources.empty?
      
      # Add date range if specified
      search_params["date_from"] = obj["date_from"] if obj["date_from"]
      search_params["date_to"] = obj["date_to"] if obj["date_to"]
      
      body["search_parameters"] = search_params
      
      # Debug logging for web search
      DebugHelper.debug("Grok: Native Live Search enabled with search_parameters", category: :api, level: :debug)
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] === Grok API Request Started ===")
        extra_log.puts("App: #{app}")
        extra_log.puts("Websearch enabled: #{websearch}")
        extra_log.puts("Search parameters: #{JSON.pretty_generate(body["search_parameters"])}")
        extra_log.puts("Number of sources configured: #{sources.length}")
        extra_log.close
      end
      
      # Debug logging
      if DebugHelper.extra_logging?
        DebugHelper.debug("Grok Live Search enabled with #{sources.length} data sources:\n#{JSON.pretty_generate(body["search_parameters"])}", category: :api, level: :info)
      end
    end

    # The context is added to the body

    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user"
        msg["images"].each do |img|
          messages_containing_img = true
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
        end
      end
      message
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      # For Code Interpreter apps, use a more specific initial message that encourages tool usage
      if app && (app.include?("CodeInterpreter") || app.include?("code_interpreter"))
        initial_message = "Use the check_environment function to verify the Python environment, then introduce yourself and explain what you can do."
      else
        initial_message = "Please proceed according to your system instructions and introduce yourself."
      end
      
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] Grok initiate_from_assistant triggered")
        extra_log.puts("App: #{app}")
        extra_log.puts("Adding initial user message: #{initial_message}")
        extra_log.puts("Tools available: #{body['tools']&.length || 0}")
        extra_log.close
      end
      
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => initial_message }]
      }
    end

    # Handle tool role - send tool results back to Grok
    if role == "tool" && obj["function_returns"]
      # First, add the assistant message with tool_calls if it exists
      if obj["assistant_tool_calls"]
        assistant_message = {
          "role" => "assistant",
          "content" => [{"type" => "text", "text" => ""}],  # Empty content for tool calls
          "tool_calls" => obj["assistant_tool_calls"]
        }
        body["messages"] << assistant_message
      end
      
      # Then add tool results to the message history with proper format
      # According to Grok docs, tool results must have role="tool", content, and tool_call_id
      obj["function_returns"].each do |result|
        tool_message = {
          "role" => "tool",
          "content" => result["content"],
          "tool_call_id" => result["tool_call_id"]
        }
        body["messages"] << tool_message
      end
      
      # Log the tool results being added
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] Adding tool results to messages for Grok")
        if obj["assistant_tool_calls"]
          extra_log.puts("Assistant tool calls: #{obj['assistant_tool_calls'].length} calls")
        end
        extra_log.puts("Number of tool results: #{obj["function_returns"].length}")
        obj["function_returns"].each do |result|
          extra_log.puts("  - #{result['name']}: tool_call_id=#{result['tool_call_id']}, content_preview=#{result['content'].to_s[0..100]}...")
        end
        extra_log.puts("Total messages being sent: #{body['messages'].length}")
        extra_log.close
      end
    end

    last_text = context.last["text"]

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    if last_text != "" && prompt_suffix.to_s != ""
      new_text = last_text + "\n\n" + prompt_suffix.strip if prompt_suffix.to_s != ""
      if body.dig("messages", -1, "content")
        last_content = body["messages"].last["content"]
        # Check if content is an array (normal case) or string (tool result case)
        if last_content.is_a?(Array)
          last_content.each do |content_item|
            if content_item["type"] == "text"
              content_item["text"] = new_text
            end
          end
        elsif last_content.is_a?(String)
          # For tool results, content is just a string, so replace it directly
          body["messages"].last["content"] = new_text
        end
      end
    end

    if data
      body["messages"] << {
        "role" => "user",
        "content" => data.strip
      }
      body["prediction"] = {
        "type" => "content",
        "content" => data.strip
      }
    end

    if initial_prompt != "" && obj["system_prompt_suffix"].to_s != ""
      new_text = initial_prompt + "\n\n" + obj["system_prompt_suffix"].strip
      first_content = body["messages"].first["content"]
      # Check if content is an array (normal case) or string
      if first_content.is_a?(Array)
        first_content.each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = new_text
          end
        end
      elsif first_content.is_a?(String)
        body["messages"].first["content"] = new_text
      end
    end

    if messages_containing_img
      original_model = body["model"]
      body["model"] = "grok-2-vision-1212"
      body.delete("stop")
      
      # Send system notification about model switch
      if block && original_model != body["model"]
        system_msg = {
          "type" => "system_info",
          "content" => "Model automatically switched from #{original_model} to #{body['model']} for image processing capability."
        }
        block.call system_msg
      end
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)
    
    
    # Debug final request for web search
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] Grok final API request:")
      extra_log.puts("App: #{app}")
      extra_log.puts("URL: #{target_uri}")
      extra_log.puts("Model: #{body['model']}")
      extra_log.puts("Tool choice: #{body['tool_choice'].inspect}")
      extra_log.puts("Number of tools: #{body['tools']&.length || 0}")
      extra_log.puts("Number of messages: #{body['messages']&.length || 0}")
      # Log last user message for debugging
      last_user_msg = body["messages"].reverse.find { |m| m["role"] == "user" }
      if last_user_msg
        content_preview = last_user_msg["content"].to_s[0..100]
        extra_log.puts("Last user message preview: #{content_preview}")
      end
      if body['tools'] && body['tools'].any?
        extra_log.puts("Tool signatures:")
        body['tools'].each do |tool|
          extra_log.puts("  - #{tool.dig('function', 'name')}: #{tool.dig('function', 'parameters', 'properties')&.keys&.inspect}")
        end
      end
      extra_log.puts("Full request body:")
      extra_log.puts(JSON.pretty_generate(body))
      extra_log.close
    end


    # Process tool calls if any
    if body["messages"].is_a?(Array)
      body["messages"].each do |msg|
        next unless msg["tool_calls"] || msg[:tool_call]

        if !msg["role"] && !msg[:role]
          msg["role"] = "assistant"
        end
        tool_calls = msg["tool_calls"] || msg[:tool_call]
        tool_calls.each do |tool_call|
          tool_call.delete("index")
        end
      end
    end

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      begin
        error_data = JSON.parse(res.body) rescue { "message" => res.body.to_s, "status" => res.status }
        
        
        formatted_error = format_api_error(error_data, "grok")
        res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
        block&.call res
        return [res]
      rescue StandardError => e
        DebugHelper.debug("Error parsing API error response: #{e.message}", category: :api, level: :error)
        DebugHelper.debug("Raw response body: #{res.body.to_s[0..500]}", category: :api, level: :debug)
        DebugHelper.debug("Response status: #{res.status}", category: :api, level: :debug)
        res = { "type" => "error", "content" => "API ERROR: Unknown error occurred (#{res.status})" }
        block&.call res
        return [res]
      end
    end

    # return Array
    if !body["stream"]
      obj = JSON.parse(res.body)
      frag = obj.dig("choices", 0, "message", "content")
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      [obj]
    else
      # Include original model in the query for comparison
      body["original_user_model"] = original_user_model
      process_json_data(app: app,
                        session: session,
                        query: body,
                        res: res.body,
                        call_depth: call_depth, &block)
    end
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = "The request has timed out."
      DebugHelper.debug(error_message, category: :api, level: :error)
      res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
      block&.call res
      [res]
    end
  rescue StandardError => e
    DebugHelper.debug("API request error: #{e.message}", category: :api, level: :error)
    DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
    DebugHelper.debug("Error details: #{e.inspect}", category: :api, level: :debug)
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
    block&.call res
    [res]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      DebugHelper.debug("Processing query at #{Time.now} (Call depth: #{call_depth})", category: :api, level: :info)
      DebugHelper.debug("Query: #{JSON.pretty_generate(query)}", category: :api, level: :debug)
    end

    obj = session[:parameters]

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil
    started = false

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
              # Log first few response chunks in detail
              if texts.size < 5 || json.dig("choices", 0, "finish_reason")
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                if !started
                  extra_log.puts("\n[#{Time.now}] First Grok response chunk:")
                elsif json.dig("choices", 0, "finish_reason")
                  extra_log.puts("\n[#{Time.now}] Final Grok response chunk:")
                end
                extra_log.puts(JSON.pretty_generate(json))
                # Check for citations in various possible locations
                citations = json.dig("choices", 0, "delta", "citations") || 
                          json.dig("choices", 0, "message", "citations") ||
                          json.dig("citations") ||
                          json.dig("search_results")
                if citations
                  extra_log.puts("CITATIONS FOUND: #{citations.inspect}")
                else
                  extra_log.puts("NO CITATIONS in this chunk")
                end
                extra_log.close
              end
            end
            
            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            finish_reason = json.dig("choices", 0, "finish_reason")
            case finish_reason
            when "length"
              finish_reason = "length"
            when "stop"
              finish_reason = "stop"
            else
              finish_reason = nil
            end

            # Check if the delta contains 'content' (indicating a text fragment) or 'tool_calls'
            # Also handle the case where finish_reason is "tool_calls" with empty delta
            if json.dig("choices", 0, "delta", "tool_calls") || finish_reason == "tool_calls"
              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts("\n[#{Time.now}] Grok tool call detected in streaming response:")
                extra_log.puts("Tool call delta: #{json.dig('choices', 0, 'delta', 'tool_calls').inspect}")
                extra_log.puts("Finish reason: #{finish_reason}")
                extra_log.puts("Empty delta with tool_calls finish_reason") if finish_reason == "tool_calls" && !json.dig("choices", 0, "delta", "tool_calls")
                extra_log.close
              end
              
              # IMPORTANT: Grok returns tool_calls in chunks, then sends finish_reason="tool_calls" with empty delta
              if json.dig("choices", 0, "delta", "tool_calls")
                # This chunk contains the actual tool_calls
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
                
                # Store the complete tool call
                tid = json["id"] || "default"
                tools[tid] = json
                
                # Mark as complete tool call for Grok
                tools[tid]["grok_complete_tool_call"] = true
              elsif finish_reason == "tool_calls" && tools.any?
                # This is the final chunk with finish_reason but no delta
                # The tool_calls were already stored in previous chunks
                # Just mark that we should process them
                if CONFIG["EXTRA_LOGGING"]
                  extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                  extra_log.puts("\n[#{Time.now}] Final tool_calls chunk received, tools stored: #{tools.keys.inspect}")
                  extra_log.close
                end
              else
                # Handle partial tool calls (should be rare for Grok)
                tid = json.dig("choices", 0, "delta", "tool_calls", 0, "id")

                if tid
                  tools[tid] = json
                  tools[tid]["choices"][0]["message"] ||= tools[tid]["choices"][0]["delta"].dup
                  tools[tid]["choices"][0].delete("delta")
                else
                  new_tool_call = json.dig("choices", 0, "delta", "tool_calls", 0)
                  existing_tool_call = tools.values.last.dig("choices", 0, "message")
                  existing_tool_call["tool_calls"][0]["function"]["arguments"] << new_tool_call["function"]["arguments"]
                end
              end
            elsif json.dig("choices", 0, "delta", "content")
              # Merge text fragments based on "id"
              id = json["id"]
              texts[id] ||= json
              choice = texts[id]["choices"][0]
              choice["message"] ||= choice["delta"].dup
              choice["message"]["content"] ||= ""
              fragment = json.dig("choices", 0, "delta", "content").to_s

              # Grok only treatment for the first chunk as metadata
              if !started
                started = true
                
                # For first Grok fragment, add an invisible zero-width space at the start
                # This will display correctly but have a different "signature" for TTS
                # Zero-width space won't be visible but will make the fragment unique
                # to avoid being played twice
                if fragment.length > 0
                  res = {
                    "type" => "fragment",
                    "content" => "\u200B" + fragment,
                    "index" => 0,
                    "timestamp" => Time.now.to_f,
                    "is_first" => true
                  }
                  block&.call res
                end
                
                # Store original fragment (without zero-width space) in message content
                choice["message"]["content"] = fragment
                next
              end
              
              # Append to existing content
              choice["message"]["content"] << fragment
              
              if fragment.length > 0
                res = {
                  "type" => "fragment",
                  "content" => fragment,
                  "index" => choice["message"]["content"].length - fragment.length,
                  "timestamp" => Time.now.to_f,
                  "is_first" => false
                }
                block&.call res
              end
              next if !fragment || fragment == ""

              texts[id]["choices"][0].delete("delta")
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
      DebugHelper.debug("JSON parsing error: #{e.message}", category: :api, level: :error)
      DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
      DebugHelper.debug("Error details: #{e.inspect}", category: :api, level: :debug)
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    result = texts.empty? ? nil : texts.first[1]

    if result
      if obj["monadic"]
        choice = result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          # monadic_map returns JSON string, but we need the actual content
          modified = APPS[app].monadic_map(message)
          # Parse the JSON and extract the message field
          begin
            parsed = JSON.parse(modified)
            choice["message"]["content"] = parsed["message"] || modified
          rescue JSON::ParserError
            # If parsing fails, use the original modified value
            choice["message"]["content"] = modified
          end
        end
      end
    end

    if tools.any?
      context = []
      
      # Check if this is a Grok complete tool call
      is_grok_complete = tools.values.first["grok_complete_tool_call"] == true
      
      if is_grok_complete
        # Handle Grok's complete tool call
        tool_response = tools.values.first
        
        # Grok returns tool_calls at different levels depending on the response structure
        tool_calls = tool_response.dig("choices", 0, "delta", "tool_calls") || 
                     tool_response.dig("choices", 0, "message", "tool_calls") ||
                     tool_response.dig("choices", 0, "tool_calls")  # Check at choice level too
        
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("\n[#{Time.now}] Checking for tool_calls in Grok response:")
          extra_log.puts("  Tool response keys: #{tool_response.keys.inspect}")
          if tool_response["choices"]
            extra_log.puts("  Tool response choices: #{tool_response["choices"].inspect[0..500]}")
          end
          extra_log.puts("  - At delta level: #{tool_response.dig("choices", 0, "delta", "tool_calls").inspect[0..100]}")
          extra_log.puts("  - At message level: #{tool_response.dig("choices", 0, "message", "tool_calls").inspect[0..100]}")
          extra_log.puts("  - At choice level: #{tool_response.dig("choices", 0, "tool_calls").inspect[0..100]}")
          extra_log.puts("  Tool calls found: #{!tool_calls.nil?}")
          if tool_calls
            extra_log.puts("  Tool calls content: #{tool_calls.inspect[0..500]}")
          end
          extra_log.close
        end
        
        if tool_calls
          # Store the assistant message with tool_calls for the next API request
          # This will be added to messages in api_request when role == "tool"
          obj = session[:parameters]
          obj["assistant_tool_calls"] = tool_calls
          
          call_depth += 1
          if call_depth > MAX_FUNC_CALLS
            return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
          end
          
          # Process the tools and get results
          new_results = process_functions(app, session, tool_calls, call_depth, &block)
          # Return the results from Grok's response after tool execution
          return new_results || []
        end
      else
        # Handle partial tool calls (should be rare for Grok but keeping for compatibility)
        tool_calls = tools.first[1].dig("choices", 0, "message", "tool_calls")
        
        # Store assistant tool_calls for next request
        obj = session[:parameters]
        obj["assistant_tool_calls"] = tool_calls

        call_depth += 1
        if call_depth > MAX_FUNC_CALLS
          return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
        end

        new_results = process_functions(app, session, tool_calls, call_depth, &block)

        # Return results
        if result && new_results
          [result].concat new_results
        elsif new_results
          new_results
        elsif result
          [result]
        else
          []
        end
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result["choices"][0]["finish_reason"] = finish_reason
      [result]
    else
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  def build_tool_response(tool_results)
    response_parts = []
    
    tool_results.each do |result|
      case result["name"]
      when "create_jupyter_notebook"
        if result["content"].include?("created successfully")
          if result["content"] =~ /Notebook '([^']+)' created successfully/
            notebook_filename = $1
            response_parts << "✅ Created notebook: **#{notebook_filename}**"
            response_parts << "📎 <a href=\"http://localhost:8889/lab/tree/#{notebook_filename}\" target=\"_blank\">Open #{notebook_filename} in JupyterLab</a>"
          else
            response_parts << result["content"]
          end
        else
          response_parts << result["content"]
        end
        
      when "add_jupyter_cells"
        response_parts << "✅ Added cells to the notebook"
        
      when "run_jupyter"
        if result["content"].include?("started")
          response_parts << "✅ JupyterLab server started"
        elsif result["content"].include?("already running")
          response_parts << "ℹ️ JupyterLab was already running"
        else
          response_parts << result["content"]
        end
        
      when "run_code"
        output_content = result["content"]
        response_parts << "**Code Output:**\n```\n#{output_content}\n```"
        
        # Check if image files were generated (similar to Gemini's handling)
        if output_content =~ /✓ File created: ([^\s]+\.(svg|png|jpg|jpeg|gif)).*Full path: \/monadic\/data/i
          filename = $1
          # Add HTML for displaying the image
          response_parts << "<div class=\"generated_image\">\n  <img src=\"/data/#{filename}\" />\n</div>"
          
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts("\n[#{Time.now}] Grok auto-injected image HTML for: /data/#{filename}")
            extra_log.close
          end
        end
        
      when "generate_image_with_grok"
        # Parse the tool result to build proper HTML response
        begin
          if result["content"].is_a?(String)
            content_json = JSON.parse(result["content"])
            if content_json["success"] && content_json["filename"]
              # Build the HTML response as specified in the system prompt
              response_parts << "<div class=\"revised_prompt\">"
              response_parts << "  <b>Revised Prompt</b>: #{content_json["revised_prompt"]}"
              response_parts << "</div>"
              response_parts << "<div class=\"generated_image\">"
              response_parts << "  <img src=\"/data/#{content_json["filename"]}\">"
              response_parts << "</div>"
            else
              # Generation failed
              error_msg = content_json["message"] || "Image generation failed"
              response_parts << "❌ #{error_msg}"
            end
          else
            response_parts << result["content"]
          end
        rescue JSON::ParserError => e
          response_parts << "❌ Error processing image generation result: #{e.message}"
        end
        
      else
        response_parts << "✅ Executed: #{result["name"]}"
      end
    end
    
    response_parts.join("\n\n")
  end
  
  def process_functions(app, session, tools, call_depth, &block)
    obj = session[:parameters]
    tool_results = []
    
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        # Handle empty string arguments for tools with no parameters
        if function_call["arguments"].to_s.strip.empty?
          argument_hash = {}
        else
          argument_hash = JSON.parse(function_call["arguments"])
        end
      rescue JSON::ParserError
        argument_hash = {}
      end

      # CRITICAL FIX: Replace incorrect filenames with the stored correct one
      # This applies to any Jupyter function that takes a filename parameter
      if obj["current_notebook_filename"] && argument_hash["filename"]
        jupyter_functions = ["add_jupyter_cells", "delete_jupyter_cell", "update_jupyter_cell", 
                           "get_jupyter_cells_with_results", "execute_and_fix_jupyter_cells",
                           "restart_jupyter_kernel", "interrupt_jupyter_execution", 
                           "move_jupyter_cell", "insert_jupyter_cells"]
        
        if jupyter_functions.include?(function_name)
          provided_filename = argument_hash["filename"].to_s.gsub(/\.ipynb$/, '')
          stored_filename = obj["current_notebook_filename"].gsub(/\.ipynb$/, '')
          
          # Check if the provided file actually exists
          shared_volume = if Monadic::Utils::Environment.in_container?
                            MonadicApp::SHARED_VOL
                          else
                            MonadicApp::LOCAL_SHARED_VOL
                          end
          provided_path = File.join(shared_volume, "#{provided_filename}.ipynb")
          
          # If the provided file doesn't exist, use the stored filename
          if !File.exist?(provided_path) && obj["current_notebook_filename"]
            # Extract base names to check if they're related
            stored_base_name = stored_filename.gsub(/_\d{8}_\d{6}$/, '')
            provided_base_name = provided_filename.gsub(/_\d{8}_\d{6}$/, '')
            
            # Only replace if the base names match (same notebook, different timestamp)
            if stored_base_name == provided_base_name
              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts("\n[#{Time.now}] Replacing non-existent filename in #{function_name}:")
                extra_log.puts("  Original: #{argument_hash["filename"]} (file doesn't exist)")
                extra_log.puts("  Replaced with: #{stored_filename} (stored filename)")
                extra_log.close
              end
              argument_hash["filename"] = stored_filename
            end
          end
        end
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
        
        # GROK-SPECIFIC FIX: Check if SVG files were created with HTML escaping
        # This is a workaround for Grok's tendency to HTML-escape SVG content
        if function_name == "run_code" && function_return.to_s.include?("File(s) generated")
          # Extract file paths from the output
          if function_return =~ /File\(s\) generated.*?: ([^;]+)/
            file_list = $1
            files = file_list.split(",").map(&:strip)
            
            files.each do |file_path|
              if file_path.end_with?(".svg")
                # Convert /data/ path to actual file path
                actual_path = file_path.gsub("/data/", "")
                
                # Determine the full path based on environment
                full_path = if Monadic::Utils::Environment.in_container?
                              File.join("/monadic/data", actual_path)
                            else
                              File.join(File.expand_path("~/monadic/data"), actual_path)
                            end
                
                # Check and fix HTML-escaped SVG content
                begin
                  if File.exist?(full_path)
                    content = File.read(full_path)
                    if content.include?("&lt;svg") || content.include?("&gt;")
                      fixed_content = content.gsub("&lt;", "<")
                                            .gsub("&gt;", ">")
                                            .gsub("&quot;", '"')
                                            .gsub("&amp;", "&")
                      File.write(full_path, fixed_content)
                      
                      if CONFIG["EXTRA_LOGGING"]
                        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                        extra_log.puts("\n[#{Time.now}] Grok: Fixed HTML-escaped SVG file: #{actual_path}")
                        extra_log.close
                      end
                    end
                  end
                rescue => e
                  # Log error but don't fail the entire operation
                  if CONFIG["EXTRA_LOGGING"]
                    extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                    extra_log.puts("\n[#{Time.now}] Grok: Failed to fix SVG file #{actual_path}: #{e.message}")
                    extra_log.close
                  end
                end
              end
            end
          end
        end
        
        # CRITICAL: If this is create_jupyter_notebook, extract the actual filename with timestamp
        # and store it in session for subsequent tool calls AND for the LLM to use in its response
        if function_name == "create_jupyter_notebook" && function_return.include?("created successfully")
          # Extract actual notebook filename with timestamp
          if function_return =~ /Notebook '([^']+)' created successfully/
            actual_notebook_name = $1
            # Store in session for subsequent tool calls
            obj["current_notebook_filename"] = actual_notebook_name
            obj["current_notebook_link"] = "<a href='http://localhost:8889/lab/tree/#{actual_notebook_name}' target='_blank'>Open #{actual_notebook_name}</a>"
            
            
            if CONFIG["EXTRA_LOGGING"]
              extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
              extra_log.puts("\n[#{Time.now}] Stored notebook name: #{actual_notebook_name}")
              extra_log.puts("Stored notebook link: #{obj["current_notebook_link"]}")
              extra_log.close
            end
          end
        end
        
        # CRITICAL: If this is generate_image_with_grok, extract the actual filename
        # and store it in session for post-processing the LLM response
        if function_name == "generate_image_with_grok" && function_return.is_a?(String)
          begin
            # Parse the JSON response
            image_result = JSON.parse(function_return)
            if image_result["success"] && image_result["filename"]
              actual_image_filename = image_result["filename"]
              # Store in session for post-processing
              obj["current_image_filename"] = actual_image_filename
              
              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts("\n[#{Time.now}] Stored image filename: #{actual_image_filename}")
                extra_log.close
              end
            end
          rescue JSON::ParserError => e
            # Log error but don't fail
            if CONFIG["EXTRA_LOGGING"]
              extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
              extra_log.puts("\n[#{Time.now}] Failed to parse image generator response: #{e.message}")
              extra_log.close
            end
          end
        end
        
        # Log tool execution
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("\n[#{Time.now}] Tool executed: #{function_name}")
          extra_log.puts("Arguments: #{argument_hash.inspect}")
          extra_log.puts("Result: #{function_return.to_s[0..500]}...")
          extra_log.close
        end
      rescue StandardError => e
        DebugHelper.debug("Function call error in #{function_name}: #{e.message}", category: :api, level: :error)
        DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
        function_return = "ERROR: #{e.message}"
      end

      # Format tool result for Grok API
      tool_result = {
        "tool_call_id" => tool_call["id"],
        "role" => "tool",
        "name" => function_name,
        "content" => function_return.to_s
      }
      
      tool_results << tool_result
    end

    # Store tool results in session for API request
    obj["function_returns"] = tool_results
    
    # Check if we've reached max call depth
    if call_depth >= MAX_FUNC_CALLS
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] Max call depth reached (#{MAX_FUNC_CALLS})")
        extra_log.close
      end
      
      # Return a summary when max depth is reached
      summary = "Completed #{tool_results.length} tool execution(s):\n\n"
      tool_results.each do |result|
        summary += "• #{result['name']}: #{result['content'][0..100]}#{result['content'].length > 100 ? '...' : ''}\n"
      end
      
      return [{
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => summary
          },
          "finish_reason" => "stop"
        }]
      }]
    end
    
    # CORRECT FLOW: Send tool results back to Grok to get natural language response
    # According to documentation, we must send tool results with role="tool" back to Grok
    
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] Sending tool results back to Grok (depth: #{call_depth})")
      extra_log.puts("Number of tool results: #{tool_results.length}")
      tool_results.each do |result|
        extra_log.puts("  - #{result['name']}: tool_call_id=#{result['tool_call_id']}")
      end
      extra_log.close
    end
    
    # Build a helpful response that includes actual results
    response_content = build_tool_response(tool_results)
    
    # Make API request with tool results to get Grok's natural language response
    # Use "tool" as role to indicate we're sending tool results
    # IMPORTANT: Disable streaming for tool result processing to avoid hanging
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] About to make recursive API request with tool results")
      extra_log.puts("  Call depth: #{call_depth + 1}")
      extra_log.puts("  Streaming disabled for tool result processing")
      extra_log.close
    end
    
    new_results = api_request("tool", session, call_depth: call_depth + 1, disable_streaming: true, &block)
    
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] Returned from recursive API request")
      extra_log.puts("  Results type: #{new_results.class}")
      extra_log.puts("  Results empty?: #{new_results.nil? || (new_results.respond_to?(:empty?) && new_results.empty?)}")
      extra_log.close
    end
    
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("\n[#{Time.now}] Received response from Grok after tool execution")
      if new_results && new_results.is_a?(Array) && !new_results.empty?
        content = new_results.dig(0, "choices", 0, "message", "content")
        extra_log.puts("Response preview: #{content.to_s[0..200]}...") if content
      end
      extra_log.close
    end
    
    # CRITICAL FIX: Post-process Grok's response to replace incorrect filenames and fix image paths
    if new_results && new_results.is_a?(Array) && !new_results.empty?
      content = new_results.dig(0, "choices", 0, "message", "content")
      
      # Fix image paths for Code Interpreter
      if content && (obj["app_name"].to_s.include?("CodeInterpreter") || 
                     obj["display_name"].to_s.include?("Code Interpreter"))
        # Check if Grok is showing verification output but not proper image HTML
        if content =~ /✓ File created: ([^\s]+\.(svg|png|jpg|jpeg|gif)).*Full path: \/monadic\/data/i
          filename = $1
          # Check if the HTML is already there
          unless content.include?("<div class=\"generated_image\">")
            # Find where to inject the HTML (after the output section)
            if content =~ /(Output:.*?```[^`]*```)/m
              output_section = $1
              # Add the image HTML after the output section
              image_html = "\n\n<div class=\"generated_image\">\n  <img src=\"/data/#{filename}\" />\n</div>"
              content = content.sub(output_section, output_section + image_html)
              
              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts("\n[#{Time.now}] Grok auto-fixed image display for: /data/#{filename}")
                extra_log.close
              end
            end
          end
        end
      end
      
      if content && obj["current_notebook_filename"]
        actual_filename = obj["current_notebook_filename"]
        base_name = actual_filename.gsub(/_\d{8}_\d{6}\.ipynb$/, '')
        
        # Replace incorrect filename patterns with the actual filename
        # Pattern 1: Without timestamp
        content = content.gsub(/\b#{Regexp.escape(base_name)}\.ipynb\b/i, actual_filename)
        
        # Pattern 2: With ANY timestamp (catches all fake timestamps)
        content = content.gsub(/\b#{Regexp.escape(base_name)}_\d{8}_\d{6}\.ipynb\b/i, actual_filename)
        
        # Pattern 3: Fix URLs
        content = content.gsub(%r{http://localhost:8889/lab/tree/#{Regexp.escape(base_name)}_\d{8}_\d{6}\.ipynb}i,
                              "http://localhost:8889/lab/tree/#{actual_filename}")
        
        # Update the response with corrected content
        new_results[0]["choices"][0]["message"]["content"] = content
        
      end
      
      # Post-process image filenames if we have a stored image filename
      if content && obj["current_image_filename"]
        actual_image_filename = obj["current_image_filename"]
        
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("\n[#{Time.now}] Starting image filename post-processing")
          extra_log.puts("  Actual filename: #{actual_image_filename}")
          extra_log.puts("  Content preview before: #{content[0..200]}...")
          extra_log.close
        end
        
        # Replace various placeholder patterns with the actual filename
        # Pattern 1: Date-like placeholders (e.g., 20231012-123456.png)
        content = content.gsub(/\d{8}-\d{6}\.png/i, actual_image_filename)
        
        # Pattern 2: Timestamp-only placeholders (e.g., 123456789.png)
        content = content.gsub(/(?<!\d)\d{10}\.png/i, actual_image_filename)
        
        # Pattern 3: In image src attributes
        content = content.gsub(/src="\/data\/\d{8}-\d{6}\.png"/i, "src=\"/data/#{actual_image_filename}\"")
        content = content.gsub(/src="\/data\/\d{10}\.png"/i, "src=\"/data/#{actual_image_filename}\"")
        
        # Pattern 4: Any placeholder-looking filename
        content = content.gsub(/\/data\/[a-zA-Z0-9_-]+\.png/, "/data/#{actual_image_filename}")
        
        # Update the response with corrected content
        new_results[0]["choices"][0]["message"]["content"] = content
        
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("\n[#{Time.now}] Post-processed image filename: replaced placeholders with #{actual_image_filename}")
          extra_log.puts("  Content preview after: #{content[0..200]}...")
          extra_log.close
        end
      elsif CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] No image filename post-processing: current_image_filename not in session")
        extra_log.puts("  Session keys: #{obj.keys.inspect}")
        extra_log.close
      end
    end
    
    # If Grok returns empty or inadequate response after tool execution, provide a fallback
    content_check = new_results.dig(0, "choices", 0, "message", "content").to_s.strip if new_results
    is_inadequate = false
    
    # Check if response is empty or just echoing the prompt
    if new_results.nil? || new_results.empty? || !content_check || content_check.empty?
      is_inadequate = true
    elsif obj["current_image_filename"] && !content_check.include?("<img") && !content_check.include?("generated_image")
      # For image generation, if the response doesn't contain image HTML, it's inadequate
      is_inadequate = true
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] Grok response missing image HTML, using fallback")
        extra_log.close
      end
    end
    
    if is_inadequate
      
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("\n[#{Time.now}] Grok returned empty response after tool execution, using fallback")
        extra_log.close
      end
      
      # Build a fallback response based on tool results
      fallback_content = response_content || "Tools executed successfully."
      
      # Add information from session if available
      if obj["current_notebook_link"]
        fallback_content += "\n\n#{obj["current_notebook_link"]}"
      end
      
      return [{
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => fallback_content
          },
          "finish_reason" => "stop"
        }]
      }]
    end
    
    return new_results
  end
end
