# frozen_string_literal: false

require_relative "../../utils/interaction_utils"
require 'strscan'
require 'securerandom'

module DeepSeekHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20
  # Note: Beta API (/beta) with strict mode has schema validation issues
  # Keeping standard endpoint for now
  API_ENDPOINT = "https://api.deepseek.com"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120
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
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
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

    num_retrial = 0

    begin
      api_key = CONFIG["DEEPSEEK_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: DEEPSEEK_API_KEY not found. Please set the DEEPSEEK_API_KEY environment variable in the ~/monadic/config/env file."
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

    # Debug app loading
    DebugHelper.debug("DeepSeek app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
    
    # Get tools from app settings
    app_tools = APPS[app] && APPS[app].settings["tools"] ? APPS[app].settings["tools"] : []
    
    # Debug logging
    DebugHelper.debug("DeepSeek app_tools from settings: #{app_tools.inspect}", category: :api, level: :debug)
    DebugHelper.debug("DeepSeek websearch enabled: #{websearch}", category: :api, level: :debug)
    
    # Only include tools if this is not a tool response
    if role != "tool"
      # Build the tools array
      if websearch
        # Always include websearch tools when websearch is enabled
        body["tools"] = WEBSEARCH_TOOLS.dup
        # Add any app-specific tools
        if app_tools && !app_tools.empty?
          body["tools"].concat(app_tools)
          body["tools"].uniq!
        end
        body["tool_choice"] = "auto"

        # Debug logging for tools
        DebugHelper.debug("DeepSeek tools configured: #{body["tools"].map { |t| t.dig(:function, :name) || t.dig("function", "name") }.join(", ")}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tool_choice: #{body["tool_choice"]}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tools full: #{body["tools"].inspect}", category: :api, level: :verbose)
      elsif app_tools && !app_tools.empty?
        # Only app tools, no websearch
        body["tools"] = app_tools
        body["tool_choice"] = "auto"
      else
        # No tools at all - don't send empty array
        body.delete("tools")
        body.delete("tool_choice")
      end

      # Final check: ensure tools is not an empty array
      if body["tools"] && body["tools"].empty?
        DebugHelper.debug("DeepSeek: Removing empty tools array", category: :api, level: :debug)
        body.delete("tools")
        body.delete("tool_choice")
      end
    end # end of role != "tool"

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      body["messages"].last["content"] += "\n\n" + APPS[app].settings["prompt_suffix"] if APPS[app].settings["prompt_suffix"]
    end

    if obj["model"].include?("reasoner")
      # Reasoner model has specific requirements
      body.delete("temperature")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")
      # Note: Reasoner now supports tool calling (as of V3.2)
      # Keep tools and tool_choice if they exist

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].map do |msg|
        msg["content"] = msg["content"]&.sub(/---\n\n/, "") || msg["content"]
        msg
      end
    else
      # Only set response_format for explicit json mode (not monadic mode)
      # Monadic apps use tools for state management, not JSON response format
      if is_json && role != "tool"
        body["response_format"] ||= { "type" => "json_object" }
      end
    end

    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    
    # Debug the final API request body
    DebugHelper.debug("DeepSeek streaming API final body: #{JSON.pretty_generate(body)}", category: :api, level: :debug)
    
    # Send initial spinner/waiting message
    res = { "type" => "wait", "content" => "<i class='fas fa-spinner fa-pulse'></i> THINKING" }
    block&.call res
    
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
      pp error_report
      formatted_error = format_api_error(error_report, "deepseek")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
      block&.call res
      return [res]
    end
    
    # Debug: Log before passing to process_json_data
    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("Response status: #{res.status}")
        log.puts("Response headers: #{res.headers.to_h}")
        log.puts("About to process streaming response...")
      end
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

    # Define monadic/json mode flags for consistent checking
    is_monadic = obj["monadic"].to_s == "true"
    is_json = obj["json"].to_s == "true"

    buffer = String.new.force_encoding("UTF-8")
    texts = {}
    tools = {}
    finish_reason = nil
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
        if chunk_count <= 3 && CONFIG["EXTRA_LOGGING"]
          extra_log.puts("Chunk #{chunk_count}: #{chunk[0..100]}")
        end

        if buffer.valid_encoding? == false
          next
        end

        # Check for [DONE] message
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
                      if CONFIG["EXTRA_LOGGING"]
                        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                          log.puts("!!! EARLY ABORT: Detected DSML infinite loop during streaming !!!")
                          log.puts("  function_calls blocks: #{dsml_fc_count}, invoke tags: #{dsml_invoke_count}, close tags: #{invoke_close_count}")
                          log.puts("  Aborting stream to prevent long wait")
                        end
                      end
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
                      "index" => choice["message"]["content"].length - fragment.length,
                      "timestamp" => Time.now.to_f,
                      "is_first" => choice["message"]["content"].length == fragment.length
                    }
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
              pp "JSON parse error: #{e.message}"
            end
          else
            scanner.pos += 1
          end
        end

        buffer = scanner.rest

      rescue StandardError => e
        pp e.message
        pp e.backtrace
        next
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.puts("Total chunks received: #{chunk_count}")
      if @dsml_abort_streaming
        extra_log.puts("!!! Streaming was ABORTED due to malformed DSML loop !!!")
      end
      extra_log.close
    end

    text_result = texts.empty? ? nil : texts.first[1]

    if text_result
      content = text_result.dig("choices", 0, "message", "content") || ""

      # Check if DeepSeek has output function calls in DSML format
      # Format: <｜DSML｜function_calls><｜DSML｜invoke name="..."><｜DSML｜param name="...">value</｜DSML｜/param></｜DSML｜/invoke></｜DSML｜/function_calls>
      # NOTE: DSML is NOT documented in official DeepSeek API docs - model should use native tool_calls
      # This parser exists as a fallback to handle cases where the model outputs DSML format
      if content.include?("<｜DSML｜") || content.include?("<|DSML|")
        DebugHelper.debug("DeepSeek: Detected DSML format in response (model should use native tool_calls)", category: :api, level: :warn)

        # Log raw DSML for debugging (first 500 chars to avoid log spam)
        if CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts("=== DeepSeek DSML Raw Content (first 500 chars) ===")
            log.puts(content[0..500])
            log.puts("=== End DSML Raw Content ===")
          end
        end

        # Step 1: Normalize DSML - convert all variations to a standard format
        # This makes parsing more reliable
        normalized_content = content.dup
        # Normalize pipe characters: ｜ (fullwidth) -> | (ASCII)
        normalized_content.gsub!("｜", "|")
        # Normalize closing tag format: </|DSML|tag> -> <|DSML|/tag>
        normalized_content.gsub!(/<\/\|DSML\|(\w+)>/, '<|DSML|/\1>')
        # Normalize whitespace around tag boundaries (but preserve content whitespace)
        normalized_content.gsub!(/>\s+<\|DSML\|/, "><|DSML|")

        DebugHelper.debug("DeepSeek: Normalized DSML content", category: :api, level: :verbose)

        # Step 2: Check for malformed DSML patterns
        dsml_invoke_count = normalized_content.scan(/<\|DSML\|invoke/).length
        dsml_close_invoke_count = normalized_content.scan(/<\|DSML\|\/invoke>/).length
        dsml_function_calls_count = normalized_content.scan(/<\|DSML\|function_calls>/).length

        # Also check for alternative close pattern that might have been missed
        alt_close_count = content.scan(/<\/[｜|]DSML[｜|]invoke>/).length
        total_close_count = dsml_close_invoke_count + alt_close_count

        # Log DSML tag counts for debugging
        if CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts("=== DSML Tag Analysis ===")
            log.puts("  invoke open tags: #{dsml_invoke_count}")
            log.puts("  invoke close tags: #{total_close_count}")
            log.puts("  function_calls tags: #{dsml_function_calls_count}")
            log.puts("=========================")
          end
        end

        # Detect malformed patterns:
        # 1. Many open invoke tags with no close tags (incomplete loop)
        # 2. Multiple function_calls blocks (repeating pattern)
        is_malformed = (dsml_invoke_count > 3 && total_close_count == 0) ||
                       (dsml_function_calls_count > 2)

        if is_malformed
          # Malformed DSML - model is in a loop outputting incomplete tags
          if CONFIG["EXTRA_LOGGING"]
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
              log.puts("!!! MALFORMED DSML DETECTED !!!")
              log.puts("  Pattern: #{dsml_invoke_count} open invoke, #{total_close_count} close, #{dsml_function_calls_count} function_calls blocks")
              log.puts("  Call depth: #{call_depth}, will retry: #{call_depth < 2}")
            end
          end
          DebugHelper.debug("DeepSeek: Detected malformed DSML (#{dsml_invoke_count} open invoke tags, #{total_close_count} close tags, #{dsml_function_calls_count} function_calls blocks) - likely infinite loop", category: :api, level: :warn)

          # Auto-retry without adding error to session (prevents model from "learning" to avoid tools)
          # Allow up to 4 retries for malformed DSML (call_depth 0, 1, 2, 3)
          max_dsml_retries = 4
          if call_depth < max_dsml_retries
            if CONFIG["EXTRA_LOGGING"]
              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                log.puts("  Action: Auto-retrying request (attempt #{call_depth + 1} of #{max_dsml_retries})")
              end
            end

            # Send a wait message to UI with retry count
            res = { "type" => "wait", "content" => "<i class='fas fa-redo'></i> RETRYING TOOL CALL (#{call_depth + 1}/#{max_dsml_retries})" }
            block&.call res

            # Exponential backoff: 1s, 2s, 3s, 4s
            sleep_time = call_depth + 1
            sleep sleep_time

            # Retry the request without modifying the session
            return api_request("user", session, call_depth: call_depth + 1, &block)
          end

          # All retries exhausted - provide user feedback
          if CONFIG["EXTRA_LOGGING"]
            File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
              log.puts("  Action: All retries exhausted, returning error to user")
            end
          end

          # Remove all DSML content and return clean response with helpful message
          clean_content = content.gsub(/<[｜|]DSML[｜|][^>]*>/, "").gsub(/<\/[｜|]DSML[｜|][^>]*>/, "").strip

          # Provide a user-friendly message about the tool call failure
          error_notice = "⚠️ **Tool Call Issue**: The AI attempted to use a tool but encountered repeated formatting errors. Please try starting a new conversation.\n\n"

          if clean_content.empty?
            text_result["choices"][0]["message"]["content"] = error_notice + "I was trying to perform an action but encountered an issue."
          else
            text_result["choices"][0]["message"]["content"] = error_notice + clean_content
          end

          # Send an info message to the UI
          res = { "type" => "info", "content" => "DeepSeek tool call failed after multiple attempts. Please start a new conversation." }
          block&.call res

          # Don't process as tool calls - the DSML is malformed
        else
          # Step 3: Parse DSML function calls from normalized content
          tool_calls = []

          # Match invoke blocks with or without parameters
          # Pattern handles: <|DSML|invoke name="func_name">...</|DSML|/invoke>
          # Also handle self-closing or empty invoke tags
          invoke_pattern = /<\|DSML\|invoke\s+name="([^"]+)"(?:\s*\/>|>(.*?)<\|DSML\|\/invoke>)/m
          normalized_content.scan(invoke_pattern) do |name, params_block|
            arguments = {}

            # Only parse params if the block exists and has content
            if params_block && !params_block.strip.empty?
              # Parse parameters - handle both "param" and "invoke_arg" tag names
              # Also handle self-closing param tags: <|DSML|param name="x"/>
              param_pattern = /<\|DSML\|(?:param|invoke_arg)\s+name="([^"]+)"(?:\s*\/>|>(.*?)<\|DSML\|\/(?:param|invoke_arg)>)/m
              params_block.scan(param_pattern) do |param_name, param_value|
                # Handle self-closing tags (param_value will be nil)
                param_value ||= ""

                # Try to parse as JSON, otherwise use as string
                cleaned_value = param_value.strip
                begin
                  # Handle quoted strings that aren't valid JSON
                  if cleaned_value.start_with?('"') && cleaned_value.end_with?('"')
                    arguments[param_name] = JSON.parse(cleaned_value)
                  elsif cleaned_value =~ /\A[\[\{]/
                    # Looks like JSON array or object
                    arguments[param_name] = JSON.parse(cleaned_value)
                  else
                    # Plain string value
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

          # Step 4: Fallback parsing for incomplete DSML
          # If no tool calls found with standard pattern, try to recover from partial DSML
          if tool_calls.empty? && normalized_content.include?("<|DSML|invoke")
            DebugHelper.debug("DeepSeek: Standard DSML parsing found no calls, trying fallback recovery", category: :api, level: :debug)

            # Try to extract function names even from incomplete tags
            # Pattern: <|DSML|invoke name="func_name" (may not have closing bracket)
            fallback_pattern = /<\|DSML\|invoke\s+name="([^"]+)"/
            potential_names = normalized_content.scan(fallback_pattern).flatten.uniq

            if potential_names.any?
              DebugHelper.debug("DeepSeek: Fallback found potential function names: #{potential_names.join(', ')}", category: :api, level: :debug)

              # Try to extract parameters using a more lenient pattern
              potential_names.each do |func_name|
                arguments = {}

                # Look for param tags anywhere after the invoke
                # This is a last-resort fallback
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

          if tool_calls.any?
            # Validate function names against registered tools (including websearch tools if enabled)
            app_tools = APPS[app]&.settings&.[]("tools") || []
            all_tools = app_tools.dup

            # Include websearch tools if websearch is enabled
            websearch_enabled = CONFIG["TAVILY_API_KEY"] && (obj["websearch"].to_s == "true" || obj["websearch"] == true)
            all_tools.concat(WEBSEARCH_TOOLS) if websearch_enabled

            valid_tool_names = all_tools.map { |t|
              t.dig(:function, :name) || t.dig("function", "name")
            }.compact

            # Check for invalid function names
            invalid_calls = tool_calls.select do |tc|
              func_name = tc.dig("function", "name")
              !valid_tool_names.include?(func_name)
            end

            if invalid_calls.any? && call_depth < 1
              # Retry with correction message
              invalid_names = invalid_calls.map { |tc| tc.dig("function", "name") }.join(", ")
              DebugHelper.debug("DeepSeek: Invalid function name(s) detected: #{invalid_names}. Triggering retry.", category: :api, level: :warn)

              correction_message = "Error: The function name '#{invalid_names}' is not valid. " \
                                   "You must use the exact function name from this list: #{valid_tool_names.join(', ')}. " \
                                   "Please call the correct function with the proper name."

              # Add correction message to session and retry
              session[:messages] << {
                "role" => "user",
                "text" => correction_message,
                "active" => true
              }

              # Return retry result
              return api_request("user", session, call_depth: call_depth + 1, &block)
            end

            text_result["choices"][0]["message"]["tool_calls"] = tool_calls

            # Remove DSML content from the response using normalized pattern
            # First try to remove complete function_calls block
            clean_content = normalized_content.gsub(/<\|DSML\|function_calls>.*?<\|DSML\|\/function_calls>/m, "")
            # Also remove any standalone DSML tags that might remain
            clean_content = clean_content.gsub(/<\|DSML\|[^>]*>/, "").gsub(/<\/\|DSML\|[^>]*>/, "").strip
            text_result["choices"][0]["message"]["content"] = clean_content

            # Set finish reason to function_call
            text_result["choices"][0]["finish_reason"] = "function_call"
            finish_reason = "function_call"

            # Add to tools for processing
            tid = tool_calls.first["id"]
            tools[tid] = text_result

            DebugHelper.debug("DeepSeek: Converted #{tool_calls.length} DSML function call(s) to tool call format", category: :api, level: :debug)
          else
            # DSML detected but no valid tool calls parsed - clean up the content
            DebugHelper.debug("DeepSeek: DSML detected but no valid tool calls could be parsed", category: :api, level: :warn)
            clean_content = content.gsub(/<[｜|]DSML[｜|][^>]*>/, "").gsub(/<\/[｜|]DSML[｜|][^>]*>/, "").strip
            text_result["choices"][0]["message"]["content"] = clean_content.empty? ? content : clean_content
          end
        end
      # Also check for JSON format function calls (legacy handling for websearch)
      elsif content =~ /```json\s*\n?\s*(\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\})\s*\n?\s*```/m
        json_match = $1
        begin
          # Parse the function call from text
          func_call = JSON.parse(json_match)

          # Convert text-based function call to proper tool call format
          if func_call["name"] && func_call["arguments"]
            text_result["choices"][0]["message"]["tool_calls"] = [{
              "id" => "call_#{SecureRandom.hex(8)}",
              "type" => "function",
              "function" => {
                "name" => func_call["name"],
                "arguments" => func_call["arguments"].is_a?(String) ? func_call["arguments"] : JSON.generate(func_call["arguments"])
              }
            }]

            # Remove the JSON block from the content
            text_result["choices"][0]["message"]["content"] = content.gsub(/```json\s*\n?\s*\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\}\s*\n?\s*```/m, "").strip

            # Set finish reason to function_call
            text_result["choices"][0]["finish_reason"] = "function_call"
            finish_reason = "function_call"

            # Add to tools for processing
            tid = text_result["choices"][0]["message"]["tool_calls"][0]["id"]
            tools[tid] = text_result

            DebugHelper.debug("DeepSeek: Converted JSON text function call to tool call format", category: :api, level: :debug)
          end
        rescue JSON::ParserError => e
          DebugHelper.debug("DeepSeek: Failed to parse function call from text: #{e.message}", category: :api, level: :debug)
        end
      end
      
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
              "index" => 0,
              "timestamp" => Time.now.to_f,
              "is_first" => true
            }
            block&.call res
          rescue JSON::ParserError
            # If parsing fails, use the original content
            # Send the raw content as fragment
            res = {
              "type" => "fragment",
              "content" => message,
              "index" => 0,
              "timestamp" => Time.now.to_f,
              "is_first" => true
            }
            block&.call res
          end
        end
      end
    end

    # If we have tool calls, ignore the finish_reason from streaming
    # as it will be "tool_calls" and we need to wait for the actual completion
    if tools.any?
      finish_reason = nil
    end

    if tools.any?
      # Handle tool/function calls
      DebugHelper.debug("DeepSeek tools before processing: #{tools.inspect}", category: :api, level: :verbose)
      
      tools_data = tools.first[1].dig("choices", 0, "message", "tool_calls")
      
      # If tool_calls is not an array, make it one
      if tools_data && !tools_data.is_a?(Array)
        tools_data = [tools_data]
      end
      
      DebugHelper.debug("DeepSeek tools_data after processing: #{tools_data.inspect}", category: :api, level: :debug)
      
      context = []
      # DeepSeek API requires content to be null/empty when tool_calls is present
      res = {
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
      context << res

      # Check for maximum function call depth
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      # Process function calls and get new results - don't send DONE here
      new_results = process_functions(app, session, tools_data, context, call_depth, &block)

      if new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      # Only send DONE when there are no tool calls
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      text_result["choices"][0]["finish_reason"] = finish_reason
      [text_result]
    else
      # Return done message if no result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  private

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        escaped = function_call["arguments"]
        # Handle empty string arguments for tools with no parameters
        if escaped.to_s.strip.empty?
          argument_hash = {}
        else
          argument_hash = JSON.parse(escaped)
        end
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      # Inject session for tools that need it (e.g., monadic state tools)
      method_obj = APPS[app].method(function_name.to_sym) rescue nil
      if method_obj && method_obj.parameters.any? { |type, name| name == :session }
        converted[:session] = session
      end

      begin
      if converted.empty?
        function_return = APPS[app].send(function_name.to_sym)
      else
        function_return = APPS[app].send(function_name.to_sym, **converted)
      end
      rescue StandardError => e
        function_return = "ERROR: #{e.message}"
      end

      context << {
        "role" => "tool",
        "tool_call_id" => tool_call["id"],
        "name" => function_name,
        "content" => function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
      }
    end

    obj["function_returns"] = context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
