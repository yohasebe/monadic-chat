# frozen_string_literal: false

require_relative "../../utils/interaction_utils"
require_relative "../../utils/extra_logger"
require_relative "../base_vendor_helper"
require 'strscan'
require 'securerandom'

module DeepSeekHelper
  include BaseVendorHelper
  include InteractionUtils
  include FunctionCallErrorHandler
  MAX_FUNC_CALLS = 20
  # Note: Beta API (/beta) with strict mode has schema validation issues
  # Keeping standard endpoint for now
  API_ENDPOINT = "https://api.deepseek.com"
  define_timeouts "DEEPSEEK", open: 10, read: 120, write: 120
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  # websearch tools
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

  # JSON format instruction for monadic mode (required by DeepSeek API)
  JSON_FORMAT_PROMPT = <<~TEXT

    IMPORTANT: You must respond in valid JSON format. Your response should be a properly formatted JSON object.
  TEXT

  WEBSEARCH_PROMPT = <<~TEXT

    IMPORTANT: You have access to web search functions. You MUST use these functions when users ask questions requiring current information or web research.

    Available functions:
    1. **tavily_search** - Search the web for information
       - Parameters: query (string), n (integer, default 3)
       - Example call: {"name": "tavily_search", "arguments": {"query": "latest AI developments 2025", "n": 5}}
       
    2. **tavily_fetch** - Fetch full content from a specific URL
       - Parameters: url (string)
       - Example call: {"name": "tavily_fetch", "arguments": {"url": "https://example.com/article"}}

    When to use these functions:
    - User asks about current events, news, or recent information
    - User asks about specific people, companies, or organizations  
    - User asks questions requiring factual, up-to-date information
    - You need to verify or update information

    Example function calling pattern:
    User: "What are the latest developments in quantum computing?"
    Assistant: I'll search for the latest information about quantum computing developments.
    [Call tavily_search with query "latest quantum computing developments 2025"]

    Always:
    - Use English in search queries for better results
    - Translate results back to user's language if needed
    - Cite sources using HTML links: <a href="URL" target="_blank" rel="noopener noreferrer">Source</a>
    - Use search results to provide accurate, well-supported responses
  TEXT

  class << self
    attr_reader :cached_models

    def vendor_name
      "DeepSeek"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:deepseek] if $MODELS[:deepseek]

      api_key = CONFIG["DEEPSEEK_API_KEY"]
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
          # Cache the filtered and sorted models
          model_data = JSON.parse(res.body)
          $MODELS[:deepseek] = model_data["data"].sort_by do |model|
            model["created"]
          end.reverse.map do |model|
            model["id"]
          end.filter do |model|
            !model.include?("embed")
          end
          $MODELS[:deepseek]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:deepseek] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "deepseek-chat")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["DEEPSEEK_API_KEY"]
    return "Error: DEEPSEEK_API_KEY not found" if api_key.nil?
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Format messages
    messages = []
    
    if options["messages"]
      # Look for system message
      system_msg = options["messages"].find { |m| m["role"] == "system" }
      if system_msg
        messages << {
          "role" => "system",
          "content" => system_msg["content"].to_s
        }
      end
      
      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)
        
        content = msg["content"] || msg["text"] || ""
        messages << {
          "role" => msg["role"],
          "content" => content.to_s
        }
      end
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "stream" => false,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages
    }
    
    # Make request
    target_uri = "#{API_ENDPOINT}/chat/completions"
    
    # Debug the full request body
    DebugHelper.debug("DeepSeek API request body: #{JSON.pretty_generate(body)}", category: :api, level: :debug)
    
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
        parsed_response = JSON.parse(response.body)
        return parsed_response.dig("choices", 0, "message", "content") || "Error: No content in response"
      rescue => e
        return "Error: #{e.message}"
      end
    else
      begin
        error_data = response && response.body ? JSON.parse(response.body) : {}
        error_message = error_data["error"] || "Unknown error"
        return "Error: #{error_message}"
      rescue => e
        return "Error: Failed to parse error response"
      end
    end
  rescue => e
    return "Error: #{e.message}"
  end

  def api_request(role, session, call_depth: 0, &block)
    Monadic::Utils::ExtraLogger.log { "[DeepSeek] api_request called: role=#{role}, call_depth=#{call_depth}" }

    # Reset parallel dispatch guard and call depth for new user turn
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
    end

    num_retrial = 0

    begin
      api_key = CONFIG["DEEPSEEK_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      error_message = "ERROR: DEEPSEEK_API_KEY not found. Please set the DEEPSEEK_API_KEY environment variable in the ~/monadic/config/env file."
      Monadic::Utils::ExtraLogger.log { "[DeepSeek] #{error_message}" }
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Handle both string and boolean values for websearch parameter
    websearch = CONFIG["TAVILY_API_KEY"] && (obj["websearch"] == "true" || obj["websearch"] == true)

    if role != "tool"
      message = obj["message"].to_s

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

      # HTML is generated from the original message, not the monadic version
      html = if obj["message"] != ""
               markdown_to_html(obj["message"])
             else
               obj["message"]
             end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => obj["message"],
                  "html" => markdown_to_html(obj["message"]),
                  "lang" => detect_language(obj["message"])
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

    session[:messages].each { |msg| msg["active"] = false }

    # Safer context building with nil checks
    context = []
    if session[:messages] && !session[:messages].empty?
      context = [session[:messages].first]
      if session[:messages].length > 1
        context += session[:messages][1..].last(context_size + 1)
      end
    end
    context.each { |msg| msg["active"] = true if msg }
    strip_inactive_image_data(session)

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => model,
      "stream" => true
    }

    body["max_tokens"] = max_tokens if max_tokens

    body["temperature"] = temperature

    # Determine if we need to add JSON format instruction
    # Handle both string "true" and boolean true values
    # Note: monadic mode does NOT require JSON format - it uses tools for state management
    # Only explicit json mode requires JSON format
    is_monadic = obj["monadic"].to_s == "true"
    is_json = obj["json"].to_s == "true"
    needs_json_prompt = is_json  # Only json mode needs JSON format, not monadic

    system_message_modified = false
    body["messages"] = context.compact.map do |msg|
      if !system_message_modified && msg["role"] == "system"
        system_message_modified = true
        content = msg["text"]
        # Add websearch prompt if enabled
        content += "\n\n---\n\n" + WEBSEARCH_PROMPT if websearch
        # Add JSON format prompt if monadic/json mode (required by DeepSeek API)
        content += "\n\n---\n\n" + JSON_FORMAT_PROMPT if needs_json_prompt
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

    configure_deepseek_tools(body, app, obj, websearch)

    # Detect initiate_from_assistant initial greeting (skip prompt_suffix)
    is_initial_greeting = body["messages"].length == 2 &&
                          body["messages"][0]["role"] == "system" &&
                          body["messages"][1]["role"] == "user" &&
                          session[:messages].length <= 2

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user" && !is_initial_greeting
      body["messages"].last["content"] += "\n\n" + APPS[app].settings["prompt_suffix"] if APPS[app].settings["prompt_suffix"]
    end

    configure_deepseek_reasoning(body, obj, is_json, role)

    execute_deepseek_api_call(headers, body, app, session, call_depth, &block)
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = "The request has timed out."
      Monadic::Utils::ExtraLogger.log { "[DeepSeek] #{error_message}" }
      formatted_error = Monadic::Utils::ErrorFormatter.network_error(
        provider: "DeepSeek",
        message: error_message,
        timeout: true
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      [res]
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[DeepSeek] Unknown error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "DeepSeek",
      message: e.message
    )
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log { "Processing query (Call depth: #{call_depth})\n#{JSON.pretty_generate(query)}" }

    obj = session[:parameters]

    # Define monadic/json mode flags for consistent checking
    is_monadic = obj["monadic"].to_s == "true"
    is_json = obj["json"].to_s == "true"

    buffer = String.new.force_encoding("UTF-8")
    texts = {}
    tools = {}
    finish_reason = nil
    fragment_sequence = 0
    @dsml_abort_streaming = false  # Flag for early abort on malformed DSML

    chunk_count = 0
    res.each do |chunk|
      # Check for early abort flag (set when malformed DSML detected)
      break if @dsml_abort_streaming

      begin
        chunk_count += 1
        chunk = chunk.force_encoding("UTF-8")
        buffer << chunk

        # Debug: Log first few chunks
        if chunk_count <= 3
          Monadic::Utils::ExtraLogger.log { "Chunk #{chunk_count}: #{chunk[0..100]}" }
        end

        if buffer.valid_encoding? == false
          next
        end

        # Check for [DONE] message
        begin
          break if /\Rdata: \[DONE\]\R/ =~ buffer
        rescue StandardError
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

              Monadic::Utils::ExtraLogger.log { JSON.pretty_generate(json) }

              # Process finish reason
              finish_reason = json.dig("choices", 0, "finish_reason")
              DebugHelper.debug("DeepSeek finish_reason: #{finish_reason}", category: :api, level: :verbose) if finish_reason
              
              case finish_reason
              when "length"
                finish_reason = "length"
              when "stop"
                finish_reason = "stop"
              when "tool_calls"
                finish_reason = "function_call"
                DebugHelper.debug("DeepSeek detected tool_calls finish reason", category: :api, level: :debug)
              else
                finish_reason = nil
              end

              # Process text content
              if json.dig("choices", 0, "delta")
                delta = json["choices"][0]["delta"]
                
                if delta["reasoning_content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["reasoning_content"] ||= ""
                  choice["message"]["content"] ||= ""

                  fragment = delta["reasoning_content"].to_s
                  choice["message"]["reasoning_content"] << fragment

                  res = {
                    "type" => "thinking",
                    "content" => fragment
                  }
                  block&.call res

                  texts[id]["choices"][0].delete("delta")
                elsif delta["content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["content"] ||= ""

                  fragment = delta["content"].to_s
                  choice["message"]["content"] << fragment

                  # Check if DeepSeek is outputting function calls as text (DSML or JSON format)
                  if choice["message"]["content"].include?("<｜DSML｜") || choice["message"]["content"].include?("<|DSML|")
                    # DeepSeek is outputting function calls in DSML format, don't send fragments
                    # We'll handle this after the full message is received

                    # Early detection of malformed DSML loop pattern
                    # If we see multiple function_calls blocks, the model is stuck in a loop
                    dsml_fc_count = choice["message"]["content"].scan(/<[｜|]DSML[｜|]function_calls>/).length
                    dsml_invoke_count = choice["message"]["content"].scan(/<[｜|]DSML[｜|]invoke/).length

                    # Abort early if we detect loop patterns:
                    # 1. More than 2 function_calls blocks (should only be 1)
                    # 2. More than 3 invoke tags without corresponding closing tags
                    content_so_far = choice["message"]["content"]
                    invoke_close_count = content_so_far.scan(/<[｜|]DSML[｜|]\/invoke>/).length +
                                        content_so_far.scan(/<\/[｜|]DSML[｜|]invoke>/).length

                    if dsml_fc_count > 2 || (dsml_invoke_count > 3 && invoke_close_count == 0)
                      # Abort streaming early - model is in infinite loop
                      Monadic::Utils::ExtraLogger.log { "!!! EARLY ABORT: Detected DSML infinite loop during streaming !!!\n  function_calls blocks: #{dsml_fc_count}, invoke tags: #{dsml_invoke_count}, close tags: #{invoke_close_count}\n  Aborting stream to prevent long wait" }
                      # Set a flag to break out of the streaming loop
                      @dsml_abort_streaming = true
                      break
                    end
                  elsif choice["message"]["content"] =~ /```json\s*\n?\s*\{.*"name"\s*:\s*"(tavily_search|tavily_fetch)"/m
                    # DeepSeek is outputting function calls as JSON text, don't send fragments
                    # We'll handle this after the full message is received
                  elsif is_json
                    # Suppress fragments for json mode only - content will be processed after completion
                    # The raw JSON fragments should not be shown to the user
                    # Note: monadic mode uses normal streaming since responses are natural language
                  elsif fragment.length > 0
                    res = {
                      "type" => "fragment",
                      "content" => fragment,
                      "sequence" => fragment_sequence,
                      "timestamp" => Time.now.to_f,
                      "is_first" => fragment_sequence == 0
                    }
                    fragment_sequence += 1
                    block&.call res
                  end

                  texts[id]["choices"][0].delete("delta")
                end

                # Process tool calls
                if delta["tool_calls"]
                  DebugHelper.debug("DeepSeek tool call detected: #{delta["tool_calls"].inspect}", category: :api, level: :debug)
                  DebugHelper.debug("Full JSON at tool call: #{json.inspect}", category: :api, level: :verbose)
                  
                  res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res

                  tid = json.dig("choices", 0, "delta", "tool_calls", 0, "id")

                  if tid
                    # Clone the json object
                    tools[tid] = JSON.parse(JSON.generate(json))
                    tools[tid]["choices"][0]["message"] ||= {}
                    tools[tid]["choices"][0]["message"]["role"] = "assistant"
                    tools[tid]["choices"][0]["message"]["content"] = ""
                    tools[tid]["choices"][0]["message"]["tool_calls"] ||= []
                    
                    # Copy the tool call info from delta
                    tool_call_delta = json.dig("choices", 0, "delta", "tool_calls", 0)
                    if tool_call_delta
                      new_tool_call = {
                        "id" => tool_call_delta["id"],
                        "type" => tool_call_delta["type"] || "function",
                        "function" => {
                          "name" => tool_call_delta.dig("function", "name") || "",
                          "arguments" => tool_call_delta.dig("function", "arguments") || ""
                        }
                      }
                      tools[tid]["choices"][0]["message"]["tool_calls"] << new_tool_call
                    end
                    
                    tools[tid]["choices"][0].delete("delta")
                  else
                    # Accumulate arguments for existing tool call
                    new_tool_call = json.dig("choices", 0, "delta", "tool_calls", 0)
                    if tools.values.any? && new_tool_call && new_tool_call.dig("function", "arguments")
                      last_tool = tools.values.last
                      if last_tool && last_tool.dig("choices", 0, "message", "tool_calls", 0)
                        last_tool["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"] += new_tool_call["function"]["arguments"]
                      end
                    end
                  end
                end
              end
            rescue JSON::ParserError => e
              Monadic::Utils::ExtraLogger.log { "[DeepSeek] JSON parse error: #{e.message}" }
            end
          else
            scanner.pos += 1
          end
        end

        buffer = scanner.rest

      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[DeepSeek] Streaming error: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}" }
        next
      end
    end

    Monadic::Utils::ExtraLogger.log do
      msg = "Total chunks received: #{chunk_count}"
      msg += "\n!!! Streaming was ABORTED due to malformed DSML loop !!!" if @dsml_abort_streaming
      msg
    end

    text_result = texts.empty? ? nil : texts.first[1]

    if text_result
      content = text_result.dig("choices", 0, "message", "content") || ""

      dsml_result = parse_deepseek_dsml_content(content, text_result, tools, obj, app, session, call_depth, &block)
      return dsml_result if dsml_result.is_a?(Array)

      parse_deepseek_json_function_call(content, text_result, tools) unless dsml_result
      
      # Process JSON responses only for explicit json mode (not monadic mode)
      # Monadic mode uses tools for state management and returns natural language
      if is_json
        choice = text_result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop" || choice["finish_reason"].nil?
          message = choice["message"]["content"]
          # Parse the JSON and extract the message/response field
          begin
            parsed = JSON.parse(message)
            # Check for common response field names
            extracted_content = parsed["message"] || parsed["response"] || parsed["text"] || message
            choice["message"]["content"] = extracted_content

            # Send the processed content as a single fragment to the UI
            # (since we suppressed streaming fragments for json mode)
            res = {
              "type" => "fragment",
              "content" => extracted_content,
              "sequence" => fragment_sequence,
              "timestamp" => Time.now.to_f,
              "is_first" => fragment_sequence == 0
            }
            fragment_sequence += 1
            block&.call res
          rescue JSON::ParserError
            # If parsing fails, use the original content
            # Send the raw content as fragment
            res = {
              "type" => "fragment",
              "content" => message,
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

    dispatch_deepseek_tool_results(tools, text_result, finish_reason, obj, session, app, call_depth, &block)
  end

  private

  def configure_deepseek_tools(body, app, obj, websearch)
    app_tools = APPS[app] && APPS[app].settings["tools"] ? APPS[app].settings["tools"] : []

    DebugHelper.debug("DeepSeek app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
    DebugHelper.debug("DeepSeek app_tools from settings: #{app_tools.inspect}", category: :api, level: :debug)
    DebugHelper.debug("DeepSeek websearch enabled: #{websearch}", category: :api, level: :debug)

    skip_tools = obj["_skip_tools_next_request"] == true
    if skip_tools
      obj.delete("_skip_tools_next_request")
      Monadic::Utils::ExtraLogger.log { "[DeepSeek] Skipping tools due to terminal tool in previous turn" }
    end

    unless skip_tools
      if websearch
        body["tools"] = WEBSEARCH_TOOLS.dup
        if app_tools && !app_tools.empty?
          body["tools"].concat(app_tools)
          body["tools"].uniq!
        end
        body["tool_choice"] = "auto"

        DebugHelper.debug("DeepSeek tools configured: #{body["tools"].map { |t| t.dig(:function, :name) || t.dig("function", "name") }.join(", ")}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tool_choice: #{body["tool_choice"]}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tools full: #{body["tools"].inspect}", category: :api, level: :verbose)
      elsif app_tools && !app_tools.empty?
        body["tools"] = app_tools
        body["tool_choice"] = "auto"
      else
        body.delete("tools")
        body.delete("tool_choice")
      end

      if body["tools"] && body["tools"].empty?
        DebugHelper.debug("DeepSeek: Removing empty tools array", category: :api, level: :debug)
        body.delete("tools")
        body.delete("tool_choice")
      end
    else
      body.delete("tools")
      body.delete("tool_choice")
    end
  end

  def configure_deepseek_reasoning(body, obj, is_json, role)
    is_reasoning_model = obj["model"].include?("reasoner") || obj["model"].include?("-r1")

    if is_reasoning_model
      body.delete("temperature")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      body["messages"] = body["messages"].map.with_index do |msg, idx|
        msg["content"] = msg["content"]&.sub(/---\n\n/, "") || msg["content"]
        if msg["role"] == "assistant" && idx < body["messages"].length - 1
          msg.delete("reasoning_content")
        end
        msg
      end
    else
      if is_json && role != "tool"
        body["response_format"] ||= { "type" => "json_object" }
      end
    end
  end

  # Parse DSML format tool calls from DeepSeek response content.
  # Returns nil if no DSML detected, :processed if DSML was handled,
  # or an Array result for early return (retry/error).
  # Modifies text_result and tools hash in-place.
  def parse_deepseek_dsml_content(content, text_result, tools, obj, app, session, call_depth, &block)
    return nil unless content.include?("<｜DSML｜") || content.include?("<|DSML|")

    DebugHelper.debug("DeepSeek: Detected DSML format in response (model should use native tool_calls)", category: :api, level: :warn)

    Monadic::Utils::ExtraLogger.log { "=== DeepSeek DSML Raw Content (first 500 chars) ===\n#{content[0..500]}\n=== End DSML Raw Content ===" }

    # Normalize DSML variations to a standard format
    normalized_content = content.dup
    normalized_content.gsub!("｜", "|")
    normalized_content.gsub!(/<\/\|DSML\|(\w+)>/, '<|DSML|/\1>')
    normalized_content.gsub!(/>\s+<\|DSML\|/, "><|DSML|")

    DebugHelper.debug("DeepSeek: Normalized DSML content", category: :api, level: :verbose)

    # Check for malformed DSML patterns
    dsml_invoke_count = normalized_content.scan(/<\|DSML\|invoke/).length
    dsml_close_invoke_count = normalized_content.scan(/<\|DSML\|\/invoke>/).length
    dsml_function_calls_count = normalized_content.scan(/<\|DSML\|function_calls>/).length
    alt_close_count = content.scan(/<\/[｜|]DSML[｜|]invoke>/).length
    total_close_count = dsml_close_invoke_count + alt_close_count

    Monadic::Utils::ExtraLogger.log { "=== DSML Tag Analysis ===\n  invoke open tags: #{dsml_invoke_count}\n  invoke close tags: #{total_close_count}\n  function_calls tags: #{dsml_function_calls_count}\n=========================" }

    is_malformed = (dsml_invoke_count > 3 && total_close_count == 0) ||
                   (dsml_function_calls_count > 2)

    if is_malformed
      return handle_deepseek_malformed_dsml(content, text_result, call_depth, session, &block)
    end

    # Parse DSML function calls from normalized content
    tool_calls = parse_deepseek_dsml_invocations(normalized_content)

    if tool_calls.any?
      # Validate function names against registered tools
      early_return = validate_deepseek_dsml_tool_calls(tool_calls, text_result, tools, obj, app, session, call_depth, &block)
      return early_return if early_return.is_a?(Array)
    else
      # DSML detected but no valid tool calls parsed - clean up the content
      DebugHelper.debug("DeepSeek: DSML detected but no valid tool calls could be parsed", category: :api, level: :warn)
      clean_content = content.gsub(/<[｜|]DSML[｜|][^>]*>/, "").gsub(/<\/[｜|]DSML[｜|][^>]*>/, "").strip
      text_result["choices"][0]["message"]["content"] = clean_content.empty? ? content : clean_content
    end

    :processed
  end

  def handle_deepseek_malformed_dsml(content, text_result, call_depth, session, &block)
    Monadic::Utils::ExtraLogger.log { "!!! MALFORMED DSML DETECTED !!!\n  Call depth: #{call_depth}" }

    max_dsml_retries = 4
    if call_depth < max_dsml_retries
      Monadic::Utils::ExtraLogger.log { "  Action: Auto-retrying request (attempt #{call_depth + 1} of #{max_dsml_retries})" }

      res = { "type" => "wait", "content" => "<i class='fas fa-redo'></i> RETRYING TOOL CALL (#{call_depth + 1}/#{max_dsml_retries})" }
      block&.call res

      sleep(call_depth + 1)

      return api_request("user", session, call_depth: call_depth + 1, &block)
    end

    Monadic::Utils::ExtraLogger.log { "  Action: All retries exhausted, returning error to user" }

    clean_content = content.gsub(/<[｜|]DSML[｜|][^>]*>/, "").gsub(/<\/[｜|]DSML[｜|][^>]*>/, "").strip
    error_notice = "⚠️ **Tool Call Issue**: The AI attempted to use a tool but encountered repeated formatting errors. Please try starting a new conversation.\n\n"

    if clean_content.empty?
      text_result["choices"][0]["message"]["content"] = error_notice + "I was trying to perform an action but encountered an issue."
    else
      text_result["choices"][0]["message"]["content"] = error_notice + clean_content
    end

    res = { "type" => "info", "content" => "DeepSeek tool call failed after multiple attempts. Please start a new conversation." }
    block&.call res

    :processed
  end

  def parse_deepseek_dsml_invocations(normalized_content)
    tool_calls = []

    invoke_pattern = /<\|DSML\|invoke\s+name="([^"]+)"(?:\s*\/>|>(.*?)<\|DSML\|\/invoke>)/m
    normalized_content.scan(invoke_pattern) do |name, params_block|
      arguments = {}

      if params_block && !params_block.strip.empty?
        param_pattern = /<\|DSML\|(?:param|invoke_arg)\s+name="([^"]+)"(?:\s*\/>|>(.*?)<\|DSML\|\/(?:param|invoke_arg)>)/m
        params_block.scan(param_pattern) do |param_name, param_value|
          param_value ||= ""
          cleaned_value = param_value.strip
          begin
            if cleaned_value.start_with?('"') && cleaned_value.end_with?('"')
              arguments[param_name] = JSON.parse(cleaned_value)
            elsif cleaned_value =~ /\A[\[\{]/
              arguments[param_name] = JSON.parse(cleaned_value)
            else
              arguments[param_name] = cleaned_value
            end
          rescue JSON::ParserError
            arguments[param_name] = cleaned_value
          end
        end
      end

      tool_calls << {
        "id" => "call_#{SecureRandom.hex(8)}",
        "type" => "function",
        "function" => {
          "name" => name,
          "arguments" => JSON.generate(arguments)
        }
      }

      DebugHelper.debug("DeepSeek: Parsed DSML invoke - name=#{name}, args=#{arguments.keys.join(',')}", category: :api, level: :debug)
    end

    # Fallback parsing for incomplete DSML
    if tool_calls.empty? && normalized_content.include?("<|DSML|invoke")
      DebugHelper.debug("DeepSeek: Standard DSML parsing found no calls, trying fallback recovery", category: :api, level: :debug)

      fallback_pattern = /<\|DSML\|invoke\s+name="([^"]+)"/
      potential_names = normalized_content.scan(fallback_pattern).flatten.uniq

      if potential_names.any?
        DebugHelper.debug("DeepSeek: Fallback found potential function names: #{potential_names.join(', ')}", category: :api, level: :debug)

        potential_names.each do |func_name|
          arguments = {}
          param_fallback = /<\|DSML\|(?:param|invoke_arg)\s+name="([^"]+)"[^>]*>([^<]*)/
          normalized_content.scan(param_fallback) do |param_name, param_value|
            cleaned = param_value.strip
            arguments[param_name] = cleaned unless cleaned.empty?
          end

          tool_calls << {
            "id" => "call_#{SecureRandom.hex(8)}",
            "type" => "function",
            "function" => {
              "name" => func_name,
              "arguments" => JSON.generate(arguments)
            }
          }

          DebugHelper.debug("DeepSeek: Fallback recovered invoke - name=#{func_name}, args=#{arguments.keys.join(',')}", category: :api, level: :debug)
        end
      end
    end

    tool_calls
  end

  def validate_deepseek_dsml_tool_calls(tool_calls, text_result, tools, obj, app, session, call_depth, &block)
    app_tools = APPS[app]&.settings&.[]("tools") || []
    all_tools = app_tools.dup

    websearch_enabled = CONFIG["TAVILY_API_KEY"] && (obj["websearch"].to_s == "true" || obj["websearch"] == true)
    all_tools.concat(WEBSEARCH_TOOLS) if websearch_enabled

    valid_tool_names = all_tools.map { |t|
      t.dig(:function, :name) || t.dig("function", "name")
    }.compact

    invalid_calls = tool_calls.select do |tc|
      !valid_tool_names.include?(tc.dig("function", "name"))
    end

    if invalid_calls.any? && call_depth < 1
      invalid_names = invalid_calls.map { |tc| tc.dig("function", "name") }.join(", ")
      DebugHelper.debug("DeepSeek: Invalid function name(s) detected: #{invalid_names}. Triggering retry.", category: :api, level: :warn)

      correction_message = "Error: The function name '#{invalid_names}' is not valid. " \
                           "You must use the exact function name from this list: #{valid_tool_names.join(', ')}. " \
                           "Please call the correct function with the proper name."

      session[:messages] << {
        "role" => "user",
        "text" => correction_message,
        "active" => true
      }

      return api_request("user", session, call_depth: call_depth + 1, &block)
    end

    text_result["choices"][0]["message"]["tool_calls"] = tool_calls

    # Remove DSML content from the response
    content = text_result.dig("choices", 0, "message", "content") || ""
    normalized_content = content.dup
    normalized_content.gsub!("｜", "|")
    normalized_content.gsub!(/<\/\|DSML\|(\w+)>/, '<|DSML|/\1>')
    clean_content = normalized_content.gsub(/<\|DSML\|function_calls>.*?<\|DSML\|\/function_calls>/m, "")
    clean_content = clean_content.gsub(/<\|DSML\|[^>]*>/, "").gsub(/<\/\|DSML\|[^>]*>/, "").strip
    text_result["choices"][0]["message"]["content"] = clean_content

    if clean_content && !clean_content.empty?
      request_id = SecureRandom.hex(4)
      app_name = session[:parameters]["app_name"] || obj["app_name"]
      assistant_message = {
        "role" => "assistant",
        "text" => clean_content,
        "html" => markdown_to_html(clean_content, mathjax: true),
        "lang" => detect_language(clean_content),
        "mid" => request_id,
        "active" => true,
        "app_name" => app_name
      }
      session[:messages] << assistant_message

      html_res = { "type" => "html", "content" => assistant_message, "more_coming" => true }
      block&.call html_res

      DebugHelper.debug("DeepSeek: Saved assistant message before DSML tool call (#{clean_content.length} chars)", category: :api, level: :debug)
    end

    text_result["choices"][0]["finish_reason"] = "function_call"

    tid = tool_calls.first["id"]
    tools[tid] = text_result

    DebugHelper.debug("DeepSeek: Converted #{tool_calls.length} DSML function call(s) to tool call format", category: :api, level: :debug)
    nil
  end

  def parse_deepseek_json_function_call(content, text_result, tools)
    return unless content =~ /```json\s*\n?\s*(\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\})\s*\n?\s*```/m

    json_match = $1
    begin
      func_call = JSON.parse(json_match)

      if func_call["name"] && func_call["arguments"]
        text_result["choices"][0]["message"]["tool_calls"] = [{
          "id" => "call_#{SecureRandom.hex(8)}",
          "type" => "function",
          "function" => {
            "name" => func_call["name"],
            "arguments" => func_call["arguments"].is_a?(String) ? func_call["arguments"] : JSON.generate(func_call["arguments"])
          }
        }]

        text_result["choices"][0]["message"]["content"] = content.gsub(/```json\s*\n?\s*\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\}\s*\n?\s*```/m, "").strip
        text_result["choices"][0]["finish_reason"] = "function_call"

        tid = text_result["choices"][0]["message"]["tool_calls"][0]["id"]
        tools[tid] = text_result

        DebugHelper.debug("DeepSeek: Converted JSON text function call to tool call format", category: :api, level: :debug)
      end
    rescue JSON::ParserError => e
      DebugHelper.debug("DeepSeek: Failed to parse function call from text: #{e.message}", category: :api, level: :debug)
    end
  end

  def dispatch_deepseek_tool_results(tools, text_result, finish_reason, obj, session, app, call_depth, &block)
    if tools.any?
      finish_reason = nil

      DebugHelper.debug("DeepSeek tools before processing: #{tools.inspect}", category: :api, level: :verbose)

      tools_data = tools.first[1].dig("choices", 0, "message", "tool_calls")
      tools_data = [tools_data] if tools_data && !tools_data.is_a?(Array)

      DebugHelper.debug("DeepSeek tools_data after processing: #{tools_data.inspect}", category: :api, level: :debug)

      # Save any content from text_result to session BEFORE processing tool calls
      if text_result
        content_before_tools = text_result.dig("choices", 0, "message", "content")
        if content_before_tools && !content_before_tools.to_s.strip.empty?
          request_id = SecureRandom.hex(4)
          app_name = session[:parameters]["app_name"] || obj["app_name"]
          assistant_message = {
            "role" => "assistant",
            "text" => content_before_tools.to_s,
            "html" => markdown_to_html(content_before_tools.to_s, mathjax: true),
            "lang" => detect_language(content_before_tools.to_s),
            "mid" => request_id,
            "active" => true,
            "app_name" => app_name
          }
          session[:messages] << assistant_message

          Monadic::Utils::ExtraLogger.log { "[DeepSeek] Saved assistant message before tool call: #{content_before_tools.length} chars, mid=#{request_id}, app_name=#{app_name}\n[DeepSeek] session[:messages] now has #{session[:messages].size} messages" }

          html_res = { "type" => "html", "content" => assistant_message, "more_coming" => true }

          Monadic::Utils::ExtraLogger.log { "[DeepSeek] Sending html message with more_coming=true, content length=#{content_before_tools.length}" }

          block&.call html_res

          DebugHelper.debug("DeepSeek: Saved assistant message before native tool call (#{content_before_tools.length} chars)", category: :api, level: :debug)
        end
      end

      context = []
      assistant_msg = {
        "role" => "assistant",
        "content" => nil,
        "tool_calls" => tools_data.map do |tool|
          {
            "id" => tool["id"],
            "type" => "function",
            "function" => tool["function"]
          }
        end
      }

      model_name = obj["model"] || ""
      is_reasoning_model = model_name.include?("reasoner") || model_name.include?("-r1")
      if is_reasoning_model
        reasoning_content = text_result&.dig("choices", 0, "message", "reasoning_content")
        if reasoning_content && !reasoning_content.empty?
          assistant_msg["reasoning_content"] = reasoning_content
          DebugHelper.debug("DeepSeek: Including reasoning_content in tool call context (#{reasoning_content.length} chars)", category: :api, level: :debug)
        end
      end

      context << assistant_msg

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tools_data, context, call_depth, &block)

      if new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      text_result["choices"][0]["finish_reason"] = finish_reason
      [text_result]
    else
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  def execute_deepseek_api_call(headers, body, app, session, call_depth, &block)
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"

    DebugHelper.debug("DeepSeek streaming API final body: #{JSON.pretty_generate(body)}", category: :api, level: :debug)

    res = { "type" => "wait", "content" => "<i class='fas fa-spinner fa-pulse'></i> THINKING" }
    block&.call res

    http = HTTP.headers(headers)

    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      body.delete("tools")
      body.delete("tool_choice")
    end

    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout,
                         write: write_timeout,
                         read: read_timeout).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)
      Monadic::Utils::ExtraLogger.log { "[DeepSeek] API error: #{error_report}" }
      formatted_error = format_api_error(error_report, "deepseek")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
      block&.call res
      return [res]
    end

    Monadic::Utils::ExtraLogger.log { "Response status: #{res.status}\nResponse headers: #{res.headers.to_h}\nAbout to process streaming response..." }

    process_json_data(app: app, session: session, query: body,
                      res: res.body, call_depth: call_depth, &block)
  end

  def invoke_deepseek_tool_function(app, session, tool_call, function_name, &block)
    begin
      escaped = tool_call.dig("function", "arguments")
      argument_hash = if escaped.to_s.strip.empty?
                        {}
                      else
                        JSON.parse(escaped)
                      end
    rescue JSON::ParserError
      argument_hash = {}
    end

    converted = argument_hash.each_with_object({}) do |(k, v), memo|
      memo[k.to_sym] = v
    end

    method_obj = APPS[app].method(function_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |_type, name| name == :session }
      converted[:session] = session
    end

    begin
      function_return = if converted.empty?
                          APPS[app].send(function_name.to_sym)
                        else
                          APPS[app].send(function_name.to_sym, **converted)
                        end
    rescue StandardError => e
      function_return = "ERROR: #{e.message}"
    end

    send_verification_notification(session, &block) if function_name == "report_verification"

    # Store gallery_html for server-side injection
    if function_return.is_a?(Hash) && function_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << function_return[:gallery_html]
    end

    content_value = function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
    entry = {
      "role" => "tool",
      "tool_call_id" => tool_call["id"],
      "name" => function_name,
      "content" => content_value
    }

    error_stop = handle_function_error(session, function_return, function_name, &block)
    [entry, error_stop]
  end

  # Terminal tools that signal the end of a tool-calling sequence
  # After these tools are executed, the model should not call more tools
  TERMINAL_TOOLS = %w[
    save_learning_progress
    save_conversation_analysis
    save_diagnosis_progress
    save_analysis_result
  ].freeze

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    terminal_tool_called = false

    tools.each do |tool_call|
      function_name = tool_call.dig("function", "name")
      next if function_name.nil?

      block&.call({ "type" => "tool_executing", "content" => function_name })

      if TERMINAL_TOOLS.include?(function_name)
        terminal_tool_called = true
        DebugHelper.debug("DeepSeek: Terminal tool '#{function_name}' called - will disable tools in next request", category: :api, level: :debug)
      end

      tool_entry, error_stop = invoke_deepseek_tool_function(app, session, tool_call, function_name, &block)
      context << tool_entry if tool_entry
      next if error_stop
    end

    obj["function_returns"] = context

    # Stop if repeated errors detected
    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected." } }] }]
    end

    # If terminal tool was called, do NOT make another api_request
    # The terminal tool signals that the assistant's turn is complete
    # Making another request would cause empty response and "content_not_found" error
    if terminal_tool_called
      Monadic::Utils::ExtraLogger.log { "[DeepSeek] Terminal tool called - sending DONE and ending turn" }
      # Send DONE message to signal completion to frontend
      # This is necessary because previous html message may have had more_coming=true
      done_res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call done_res

      # Return a properly structured response that websocket.rb can process
      # without triggering content_not_found error
      # The response must have choices[0].message.content structure
      final_response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => ""  # Empty content is OK, will not trigger error
          },
          "finish_reason" => "stop"
        }]
      }
      return [final_response]
    end

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
