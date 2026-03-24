# frozen_string_literal: false

require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../utils/system_prompt_injector"
require_relative "../../monadic_performance"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require_relative "../base_vendor_helper"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/extra_logger"

module MistralHelper
  include BaseVendorHelper
  include InteractionUtils
  include MonadicPerformance
  include FunctionCallErrorHandler
  MAX_FUNC_CALLS = 30
  API_ENDPOINT   = "https://api.mistral.ai/v1"
  define_timeouts "MISTRAL", open: 5, read: 600, write: 120

  MAX_RETRIES    = 5
  RETRY_DELAY    = 1
  # ENV key for emergency override
  MISTRAL_LEGACY_MODE_ENV = "MISTRAL_LEGACY_MODE"

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

          model_data = begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            {"data" => []}
          end
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

  # Get default model
  def self.get_default_model
    "mistral-large-latest"
  end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    model = model.to_s.strip
    model = nil if model.empty?
    # Use default model from CONFIG if not specified
    model ||= SystemDefaults.get_default_model('mistral')
    
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
    
    # Check if this is a reasoning model via SSOT (magistral, mistral-small-4, etc.)
    is_reasoning_model = defined?(Monadic::Utils::ModelSpec) &&
                         Monadic::Utils::ModelSpec.supports_thinking?(model)
    
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

    # Add tool definitions if provided (for testing tool-calling apps)
    if options["tools"] && options["tools"].any?
      # Convert to Mistral/OpenAI format if needed
      body["tools"] = options["tools"].map do |tool|
        if tool["type"] == "function" && tool["function"]
          # Already in OpenAI format
          tool
        else
          # Convert from simple format to OpenAI format
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
      body["tool_choice"] = "auto"
    end

    # Make request
    target_uri = "#{API_ENDPOINT}/chat/completions"
    http = HTTP.headers(headers)
    
    # Simple retry logic
    response = nil
    MAX_RETRIES.times do
      begin
        response = http.timeout(
          connect: open_timeout,
          write: write_timeout,
          read: read_timeout
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
        parsed_response = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {"message" => response.body.to_s}
        end
        
        # Standard OpenAI-compatible format
        if parsed_response["choices"] &&
           parsed_response["choices"][0] &&
           parsed_response["choices"][0]["message"]

          message = parsed_response["choices"][0]["message"]

          # Check for tool calls in the response
          if message["tool_calls"] && message["tool_calls"].any?
            tool_calls = message["tool_calls"].map do |tc|
              {
                "name" => tc.dig("function", "name"),
                "args" => begin
                  JSON.parse(tc.dig("function", "arguments") || "{}")
                rescue JSON::ParserError
                  {}
                end
              }
            end
            text_content = message["content"] || ""
            return { text: text_content, tool_calls: tool_calls }
          end

          return message["content"].to_s
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
        
        error_data = if response && response.body
                       begin
                         JSON.parse(response.body.to_s)
                       rescue JSON::ParserError
                         {"message" => response.body.to_s}
                       end
                     else
                       {}
                     end
        error_message = if error_data["error"] && error_data["error"].is_a?(Hash)
                         error_data["error"]["message"] || "Unknown error"
                       else
                         error_data["error"] || "Unknown error"
                       end
        status_code = if response && response.respond_to?(:status) && response.status.respond_to?(:code)
                        response.status.code
                      end
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Mistral",
          message: error_message,
          code: status_code
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
    # Reset call_depth counter for each new user turn
    # This allows unlimited user iterations while preventing infinite loops within a single response
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
    end

    num_retrial = 0
    # API key validation is performed after user message is sent (for UX consistency)

    # Get parameters from session
    obj = session[:parameters]
    app = obj["app_name"]

    # Handle max_tokens
    max_tokens = obj["max_tokens"]&.to_i

    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Handle both string and boolean values for websearch parameter
    websearch = obj["websearch"] == "true" || obj["websearch"] == true
    if session[:parameters]["tavily_disabled"]
      websearch = false
    end
    
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
                    "lang" => detect_language(message),
                    "app_name" => obj["app_name"]
                  } }
          res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)

          block&.call res

          # Check if this user message was already added by websocket.rb (for context extraction)
          # to avoid duplicate consecutive user messages that cause API errors
          existing_msg = session[:messages].find do |m|
            m["role"] == "user" && m["text"] == message
          end

          if existing_msg
            # Update existing message with additional fields instead of adding new one
            existing_msg.merge!(res["content"])
          else
            session[:messages] << res["content"]
          end
        end
    end
    end

    # After sending user card, check API key. If not set, return error card and exit
    api_key = CONFIG["MISTRAL_API_KEY"]
    unless api_key && !api_key.to_s.strip.empty?
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Mistral",
        env_var: "MISTRAL_API_KEY"
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }
    strip_inactive_image_data(session)

    # Set headers for API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Check if this is a reasoning model via SSOT (magistral, mistral-small-4, etc.)
    is_reasoning_model = defined?(Monadic::Utils::ModelSpec) &&
                         Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
    
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

    # SSOT: supports_streaming gate (default true)
    begin
      spec_stream = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_streaming")
      supports_streaming = spec_stream.nil? ? true : !!spec_stream
    rescue StandardError
      supports_streaming = true
    end
    if ENV[MISTRAL_LEGACY_MODE_ENV] == "true"
      supports_streaming = true
    end
    body["stream"] = supports_streaming

    # Set the max tokens
    body["max_tokens"] = max_tokens || 4096

    configure_mistral_tools(body, obj, app, session, websearch, context)

    msg_result = build_mistral_messages(body, context, obj, session, role, &block)
    return msg_result if msg_result.is_a?(Array)

    # Set up API endpoint
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    # Force text-only response when force-stop is active (e.g., after parallel dispatch
    # or verification sets call_depth_per_turn = FORCE_STOP_DEPTH). Prevents the model from attempting
    # tool calls that would hit MAX_FUNC_CALLS and truncate the synthesis response.
    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Log extra information if enabled
    Monadic::Utils::ExtraLogger.log { "Processing Mistral query (Call depth: #{call_depth})\n#{JSON.pretty_generate(body)}" }

    begin
      res = http.timeout(connect: open_timeout,
                        write: write_timeout,
                        read: read_timeout).post(target_uri, json: body)

      unless res.status.success?
        Monadic::Utils::ExtraLogger.log { "[Mistral] HTTP #{res.status} body: #{res.body.to_s[0,500]}" }
        error_text = nil
        err_json = nil
        begin
          err_json = JSON.parse(res.body.to_s)
        rescue JSON::ParserError
          error_text = res.body.to_s
        end

        message = if err_json
                    err_json["message"] || err_json["error"] || err_json["detail"]
                  else
                    error_text
                  end
        message ||= "Unknown API error"

        if res.status.code.to_i == 401 && message.downcase.include?("api key")
          error_message = Monadic::Utils::ErrorFormatter.api_key_error(
            provider: "Mistral",
            env_var: "MISTRAL_API_KEY"
          )
        else
          error_message = Monadic::Utils::ErrorFormatter.api_error(
            provider: "Mistral",
            message: message,
            code: res.status.code
          )
        end
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
    Monadic::Utils::ExtraLogger.log { "Response status: #{res.status}\nResponse headers: #{res.headers.to_h}\nAbout to process streaming response..." }

    # Process the response line by line
    buffer = ""
    content_buffer = ""
    fragment_sequence = 0
    thinking = []
    tool_calls = []
    finish_reason = nil
    # Track usage if present (rare in streaming)
    usage_prompt_tokens = nil
    usage_completion_tokens = nil
    usage_total_tokens = nil

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

          # Check for errors
        if json["error"]
          Monadic::Utils::ExtraLogger.log { "[Mistral] streaming error chunk: #{json['error'].inspect}" }
          DebugHelper.debug("Mistral streaming error: #{json['error']['message'] || 'Unknown error'}", category: :api, level: :error)
          next
        end

          # Capture usage if present on this chunk
          if json["usage"].is_a?(Hash)
            usage_prompt_tokens = json.dig("usage", "prompt_tokens") || usage_prompt_tokens
            usage_completion_tokens = json.dig("usage", "completion_tokens") || usage_completion_tokens
            usage_total_tokens = json.dig("usage", "total_tokens") || usage_total_tokens
          end

          # Extract content from delta if present
          if json["choices"] && json["choices"][0] && json["choices"][0]["delta"]
            delta = json["choices"][0]["delta"]

            # Check for new format thinking chunks (Magistral 2507/2509+)
            if delta["type"] == "thinking" && delta["thinking"].is_a?(Array)
              # Extract thinking text from structured format
              thinking_text = delta["thinking"].filter_map do |chunk|
                if chunk.is_a?(Hash) && chunk["type"] == "text"
                  chunk["text"]
                end
              end.join

              unless thinking_text.empty?
                thinking << thinking_text

                # Send thinking content to frontend (like Claude/OpenAI)
                res = {
                  "type" => "thinking",
                  "content" => thinking_text
                }
                block&.call res
              end
            end

            # Check if this delta contains content
            if delta["content"]
              content = delta["content"]

              # Handle case where content might be an Array (some Mistral API responses)
              if content.is_a?(Array)
                content = content.map { |c| c.is_a?(Hash) ? (c["text"] || c["content"] || "") : c.to_s }.join
              end
              content = content.to_s unless content.is_a?(String)

              # Check if this is a reasoning model and process thinking blocks
              if is_reasoning_model
                # Debug logging for reasoning model detection
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("Mistral: Processing content for reasoning model: #{obj["model"]}", category: :api, level: :debug) if content_buffer.length == 0
                end
                # For reasoning models, collect all content and process thinking blocks later
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
                    "sequence" => fragment_sequence,
                    "timestamp" => Time.now.to_f,
                    "is_first" => fragment_sequence == 0
                  }
                  fragment_sequence += 1
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
      # Save the pre-tool content to session for later use
      # This prevents losing streamed content when tool calls trigger recursive api_request
      if content_buffer && !content_buffer.strip.empty?
        session[:mistral_pre_tool_content] ||= ""
        session[:mistral_pre_tool_content] += content_buffer
      end

      # Process each tool call
      session[:call_depth_per_turn] += 1

      if session[:call_depth_per_turn] > MAX_FUNC_CALLS
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
      pending_tool_images = nil
      tool_calls.each do |tool_call|
        next unless tool_call # Skip nil entries

        function_name = tool_call.dig("function", "name")
        next if function_name.nil?

        block&.call({ "type" => "tool_executing", "content" => function_name })

        tool_entry, error_stop, images = invoke_mistral_tool_function(app, session, tool_call, function_name, &block)
        function_returns << tool_entry if tool_entry
        pending_tool_images = images if images
        next if error_stop
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

      if APPS[app]&.respond_to?(:settings)
        begin
          Monadic::Utils::ProgressiveToolManager.capture_tool_requests(
            session: session,
            app_name: app,
            app_settings: APPS[app].settings,
            text: tool_calls_message["content"]
          )
        rescue StandardError => e
          DebugHelper.debug("Mistral progressive tools: failed to capture tool requests due to #{e.message}", category: :api, level: :warning)
        end
      end
      
      # Inject tool-generated images as user message for vision-capable models
      if pending_tool_images&.any?
        image_parts = pending_tool_images.filter_map do |img_filename|
          img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
          next unless img

          { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" } }
        end
        if image_parts.any?
          function_returns << {
            role: "user",
            content: [
              { "type" => "text", "text" => "[Tool-generated image. Verify the visual output before presenting results.]" },
              *image_parts
            ]
          }
        end
      end

      # Update session with function returns and tool calls message
      session[:parameters]["function_returns"] = function_returns
      session[:parameters]["tool_calls_message"] = tool_calls_message

      # Check if we should stop due to repeated errors
      if should_stop_for_errors?(session)
        res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
        block&.call res
        return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected. Stopping." } }] }]
      end

      # Make recursive API call with tool responses
      return api_request("tool", session, call_depth: call_depth, &block)
    end

    build_mistral_text_response(content_buffer, thinking, obj, session, finish_reason,
                               usage_prompt_tokens, usage_completion_tokens, usage_total_tokens, &block)
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

  private

  # Configure tools for the Mistral API request, including progressive tool
  # disclosure, websearch tools, and SSOT capability gates.
  def configure_mistral_tools(body, obj, app, session, websearch, context)
    app_settings = APPS[app]&.settings
    app_tools = app_settings&.[]("tools")
    progressive_settings = app_settings && (app_settings[:progressive_tools] || app_settings["progressive_tools"])
    progressive_enabled = !!progressive_settings

    state_debug = session.dig(:progressive_tools, app.to_s)
    Monadic::Utils::ExtraLogger.log { "[Mistral] progressive state before filter: #{state_debug.inspect}" }

    if app_settings
      begin
        app_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
          app_name: app,
          session: session,
          app_settings: app_settings,
          default_tools: app_tools
        )
      rescue StandardError => e
        DebugHelper.debug("Mistral: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning)
      end
    end

    unless websearch
      app_tools = Array(app_tools).select do |tool|
        next false unless tool.is_a?(Hash)
        name = tool.dig(:function, :name) || tool.dig("function", "name")
        name && !name.start_with?("tavily_")
      end
    end

    final_tools = nil
    if CONFIG["EXTRA_LOGGING"]
      unlocked = session.dig(:progressive_tools, app.to_s, :unlocked)
      DebugHelper.debug("Mistral progressive state: unlocked=#{unlocked.inspect}, app_tools_count=#{Array(app_tools).compact.size}", category: :api, level: :debug)
    end

    Monadic::Utils::ExtraLogger.log { "[Mistral] app_tools raw: #{app_tools.inspect}\n[Mistral] obj tools: #{obj['tools'].inspect}\n[Mistral] websearch flag: #{websearch.inspect}" }

    request_tools = obj["tools"]
    if request_tools.is_a?(String)
      begin
        request_tools = JSON.parse(request_tools)
      rescue JSON::ParserError
        request_tools = nil
      end
    end
    if request_tools && !websearch
      request_tools = Array(request_tools).select do |tool|
        next false unless tool.is_a?(Hash)
        name = tool.dig(:function, :name) || tool.dig("function", "name")
        name && !name.start_with?("tavily_")
      end
    end

    if progressive_enabled
      merged = []
      merged.concat(Array(request_tools)) if request_tools && !request_tools.empty?
      merged.concat(Array(app_tools)) if app_tools
      merged = merged.flatten.compact.select { |tool| tool.is_a?(Hash) }
      merged.uniq! { |tool| tool.dig(:function, :name) || tool.dig("function", "name") }

      if merged.empty?
        DebugHelper.debug("Mistral progressive tools: none unlocked", category: :api, level: :debug)
      else
        final_tools = merged
        DebugHelper.debug("Mistral progressive tools: #{final_tools.map { |t| t.dig(:function, :name) || t.dig('function', 'name') }.compact.join(', ')}", category: :api, level: :debug)

        if websearch && !app.to_s.include?("ResearchAssistant")
          has_tavily = final_tools.any? { |tool| (tool.dig(:function, :name) || tool.dig("function", "name"))&.start_with?("tavily_") }
          if has_tavily
            system_msg = context.first
            if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
              system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
              system_msg["websearch_added"] = true
              DebugHelper.debug("Added WEBSEARCH_PROMPT to system message", category: :api, level: :debug)
            end
          end
        end
      end
    else
      if request_tools && !request_tools.empty?
        base = Array(app_tools).select { |tool| tool.is_a?(Hash) } + Array(request_tools).select { |tool| tool.is_a?(Hash) }
        base = base.flatten.compact
        base.uniq! { |tool| tool.dig(:function, :name) || tool.dig("function", "name") }
        final_tools = base unless base.empty?
        DebugHelper.debug("Mistral tools with request merge: #{base.map { |t| t.dig(:function, :name) || t.dig('function', 'name') }.compact.join(', ')}", category: :api, level: :debug) if final_tools
      elsif app_tools && !app_tools.empty?
        base = Array(app_tools).select { |tool| tool.is_a?(Hash) }
        if websearch
          base += WEBSEARCH_TOOLS
        end
        base = base.flatten.compact.select { |tool| tool.is_a?(Hash) }
        base.uniq! { |tool| tool.dig(:function, :name) || tool.dig("function", "name") }
        final_tools = base unless base.empty?
        DebugHelper.debug("Mistral tools from app settings: #{base.map { |t| t.dig(:function, :name) || t.dig('function', 'name') }.compact.join(', ')}", category: :api, level: :debug) if final_tools
      elsif websearch
        final_tools = WEBSEARCH_TOOLS.dup
        DebugHelper.debug("Mistral websearch tools only", category: :api, level: :debug)
      end

      if final_tools && websearch && !app.to_s.include?("ResearchAssistant")
        system_msg = context.first
        if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
          system_msg["text"] += "\n\n#{WEBSEARCH_PROMPT}"
          system_msg["websearch_added"] = true
          DebugHelper.debug("Added WEBSEARCH_PROMPT to system message", category: :api, level: :debug)
        end
      end
    end

    if final_tools && !final_tools.empty?
      body["tools"] = final_tools
    else
      body.delete("tools")
      DebugHelper.debug("Mistral: No tools enabled", category: :api, level: :debug)
    end
    Monadic::Utils::ExtraLogger.log { "[Mistral] final tools for #{app}: #{Array(body['tools']).map { |t| t.dig(:function, :name) || t.dig('function', 'name') || t['name'] }.inspect}" }

    # SSOT: If the model is not tool-capable, remove tools/tool_choice
    begin
      spec_tool = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "tool_capability")
      tool_src = spec_tool.nil? ? "fallback" : "spec"
      tool_capable = spec_tool.nil? ? true : !!spec_tool
    rescue StandardError
      tool_src = "fallback"
      tool_capable = true
    end
    if ENV[MISTRAL_LEGACY_MODE_ENV] == "true"
      tool_capable = true
      tool_src = "legacy"
    end
    unless tool_capable
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Capability audit (optional)
    begin
      audit = []
      # Re-query streaming from SSOT for audit
      begin
        spec_stream = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_streaming")
        s_src = spec_stream.nil? ? "fallback" : "spec"
        audit << "streaming:#{spec_stream.nil? ? true : !!spec_stream}(#{s_src})"
      rescue StandardError
        audit << "streaming:true(fallback)"
      end
      audit << "tools:#{tool_capable}(#{tool_src})"
      begin
        vprop = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "vision_capability")
        vsrc = vprop.nil? ? "fallback" : "spec"
        pprop = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_pdf")
        psrc = pprop.nil? ? "fallback" : "spec"
        audit << "vision:#{!!vprop}(#{vsrc})"
        audit << "pdf:#{!!pprop}(#{psrc})"
      rescue StandardError
      end
      Monadic::Utils::ExtraLogger.log { "Mistral SSOT capabilities for #{obj['model']}: #{audit.join(', ')}" }
    rescue StandardError
    end
  end

  # Build the messages array for the Mistral API request body.
  # Returns true on success, or an Array (error response) for the orchestrator to propagate.
  def build_mistral_messages(body, context, obj, session, role, &block)
    system_message_modified = false
    body["messages"] = context.reject do |msg|
                         msg["role"] == "tool"
                       end.map do |msg|
      if msg["role"] == "system" && !system_message_modified
        system_message_modified = true

        augmented_content = Monadic::Utils::SystemPromptInjector.augment(
          base_prompt: msg["text"],
          session: session,
          options: {
            websearch_enabled: false,
            reasoning_model: false,
            websearch_prompt: nil,
            system_prompt_suffix: obj["system_prompt_suffix"]
          },
          separator: "\n\n---\n\n"
        )

        { "role" => msg["role"], "content" => augmented_content }
      elsif msg["images"] && msg["role"] == "user"
        content = []
        content << { "type" => "text", "text" => msg["text"] }

        msg["images"].each do |img|
          begin
            vprop = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "vision_capability")
            vision_capable = vprop.nil? ? true : !!vprop
            pprop = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "supports_pdf")
            pdf_capable = pprop.nil? ? false : !!pprop
          rescue StandardError
            vision_capable = true
            pdf_capable = false
          end
          if ENV[MISTRAL_LEGACY_MODE_ENV] == "true"
            vision_capable = true
            pdf_capable = true
          end
          if img["type"] == "application/pdf"
            unless pdf_capable
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Mistral",
                message: "This model does not support PDF input.",
                code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end
            formatted_error = Monadic::Utils::ErrorFormatter.api_error(
              provider: "Mistral",
              message: "Please provide a public PDF URL in your message.",
              code: 400
            )
            res = { "type" => "error", "content" => formatted_error }
            block&.call res
            return [res]
          end
          unless vision_capable
            formatted_error = Monadic::Utils::ErrorFormatter.api_error(
              provider: "Mistral",
              message: "This model does not support image input (vision).",
              code: 400
            )
            res = { "type" => "error", "content" => formatted_error }
            block&.call res
            return [res]
          end
          content << {
            "type" => "image_url",
            "image_url" => img["data"]
          }
        end

        { "role" => msg["role"], "content" => content }
      else
        { "role" => msg["role"], "content" => msg["text"] }
      end
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      body["messages"] << {
        "role" => "user",
        "content" => "Please proceed according to your system instructions and introduce yourself."
      }
    end

    if role == "tool"
      body["messages"] << obj["tool_calls_message"] if obj["tool_calls_message"]

      obj["function_returns"].each do |resp|
        resp_role = resp[:role] || resp["role"] || "tool"
        if resp_role == "user"
          body["messages"] << { "role" => "user", "content" => resp[:content] || resp["content"] }
        else
          content = resp[:content] || resp["content"] || "No result returned"
          body["messages"] << {
            "role" => "tool",
            "content" => content.to_s,
            "tool_call_id" => resp[:tool_call_id] || resp["tool_call_id"],
            "name" => resp[:name] || resp["name"]
          }
        end
      end
    end

    true
  end

  # Invoke a single tool function and return [entry, error_stop, images].
  def invoke_mistral_tool_function(app, session, tool_call, function_name, &block)
    if function_name && APPS[app]&.respond_to?(:settings)
      begin
        Monadic::Utils::ProgressiveToolManager.unlock_tool(
          session: session,
          app_name: app,
          tool_name: function_name
        )
      rescue StandardError => e
        DebugHelper.debug("Mistral progressive tools: unlock_tool failed for #{function_name} due to #{e.message}", category: :api, level: :warning)
      end
    end

    # Parse arguments
    function_args = tool_call.dig("function", "arguments")
    begin
      args = JSON.parse(function_args)
    rescue JSON::ParserError
      args = {}
    end

    args_hash = {}
    args.each { |k, v| args_hash[k.to_sym] = v }

    # Inject session for tools that need it
    method_obj = APPS[app].method(function_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |_type, name| name == :session }
      args_hash[:session] = session
    end

    # Call the function
    begin
      function_return = if args_hash.empty?
                          APPS[app].send(function_name.to_sym)
                        else
                          APPS[app].send(function_name.to_sym, **args_hash)
                        end
    rescue StandardError => e
      function_return = Monadic::Utils::ErrorFormatter.tool_error(
        provider: "Mistral",
        tool_name: function_name,
        message: e.message
      )
    end

    send_verification_notification(session, &block) if function_name == "report_verification"

    if function_name.to_s.start_with?("tavily_") && function_return.to_s.downcase.include?("bearer token not found")
      function_return = {
        error: "tavily_api_key_missing",
        message: "Tavily API call failed with 'Bearer token not found'. Please verify that TAVILY_API_KEY is configured, or continue the research without live web search."
      }
      session[:parameters]["tavily_disabled"] = true
      begin
        Monadic::Utils::ProgressiveToolManager.trigger_event(
          session: session,
          app_name: app,
          event: "tavily_missing"
        )
      rescue StandardError
      end
    end

    # Check for repeated errors
    if handle_function_error(session, function_return, function_name, &block)
      content = function_return.to_s
      content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') unless content.valid_encoding?

      entry = {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: content
      }
      return [entry, true, nil]
    end

    # Store gallery_html for server-side injection
    if function_return.is_a?(Hash) && function_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << function_return[:gallery_html]
    end

    # Collect _image for visual self-verification
    images = nil
    if function_return.is_a?(Hash) && function_return[:_image]
      images = Array(function_return[:_image])
      clean_return = function_return.reject { |k, _| k.to_s.start_with?("_") }
      content = JSON.generate(clean_return)
    else
      content = if function_return.is_a?(Hash) || function_return.is_a?(Array)
                  JSON.generate(function_return)
                else
                  function_return.to_s
                end
    end

    content = "No result returned" if content.nil? || content.empty?
    content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') unless content.valid_encoding?

    entry = {
      tool_call_id: tool_call["id"],
      role: "tool",
      name: function_name,
      content: content
    }
    [entry, false, images]
  end

  # Build the final text response, including thinking extraction for Magistral models.
  def build_mistral_text_response(content_buffer, thinking, obj, session, finish_reason,
                                  usage_prompt_tokens, usage_completion_tokens, usage_total_tokens, &block)
    res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
    block&.call res

    Monadic::Utils::ExtraLogger.log { "[Mistral] content_buffer length: #{content_buffer.length}\n[Mistral] content_buffer first 500 chars: #{content_buffer[0..500]}\n[Mistral] content_buffer last 500 chars: #{content_buffer[-500..-1]}" }

    # Prepend any saved pre-tool content from earlier in the conversation
    pre_tool_content = session[:mistral_pre_tool_content]
    if pre_tool_content && pre_tool_content.is_a?(String) && !pre_tool_content.strip.empty?
      content_buffer = pre_tool_content + "\n\n" + content_buffer.to_s
      session.delete(:mistral_pre_tool_content)
    end

    # Clean content for reasoning models (thinking blocks, LaTeX artifacts)
    final_content = content_buffer
    is_reasoning = defined?(Monadic::Utils::ModelSpec) &&
                   Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
    if is_reasoning
      if content_buffer.include?("<think>") || content_buffer.include?("<thinking>")
        thinking_matches = content_buffer.scan(/<think>(.*?)<\/think>/m)
        thinking_matches += content_buffer.scan(/<thinking>(.*?)<\/thinking>/m)

        thinking_matches.each do |match|
          thinking << match[0].strip
        end

        final_content = content_buffer.gsub(/<think>.*?<\/think>/m, '')
        final_content = final_content.gsub(/<thinking>.*?<\/thinking>/m, '')
      end

      final_content = final_content.gsub(/\\boxed\{([^}]+)\}/, '\1')
      final_content = final_content.gsub(/\\text\{([^}]+)\}/, '\1')
    end

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

    if usage_prompt_tokens || usage_completion_tokens || usage_total_tokens
      response["usage"] = {
        "prompt_tokens" => usage_prompt_tokens,
        "completion_tokens" => usage_completion_tokens,
        "total_tokens" => usage_total_tokens
      }.compact
    end

    if thinking && !thinking.empty?
      response["choices"][0]["message"]["thinking"] = thinking.join("\n\n")
      if CONFIG["EXTRA_LOGGING"]
        DebugHelper.debug("Mistral: Collected #{thinking.length} thinking block(s) for #{obj["model"]}", category: :api, level: :info)
      end
    end

    stored_content = response.dig("choices", 0, "message", "content")
    if stored_content && !stored_content.to_s.empty?
      begin
        session[:messages] << {
          "role" => "assistant",
          "text" => stored_content.to_s,
          "html" => markdown_to_html(stored_content.to_s),
          "lang" => detect_language(stored_content.to_s),
          "mid" => SecureRandom.hex(4),
          "active" => true
        }
      rescue StandardError
        session[:messages] << {
          "role" => "assistant",
          "text" => stored_content.to_s
        }
      end
    end

    [response]
  end

  public

end
