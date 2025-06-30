# frozen_string_literal: false

require_relative "../../utils/interaction_utils"

module DeepSeekHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20
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
          required: ["url"],
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
          required: ["query"],
        }
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
        session[:messages] << res["content"]
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

    system_message_modified = false
    body["messages"] = context.compact.map do |msg|
      if websearch && !system_message_modified && msg["role"] == "system" 
        system_message_modified = true
        { "role" => msg["role"], "content" => msg["text"] + "\n\n---\n\n" + WEBSEARCH_PROMPT }
      else
        { "role" => msg["role"], "content" => msg["text"] }
      end
    end

    # Handle initiate_from_assistant case
    has_user_message = body["messages"].any? { |msg| msg["role"] == "user" }
    
    if !has_user_message && obj["initiate_from_assistant"]
      body["messages"] << {
        "role" => "user",
        "content" => "Let's start"
      }
      
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] DeepSeek: Added dummy user message for initiate_from_assistant")
        extra_log.close
      end
    end

    # Debug app loading
    DebugHelper.debug("DeepSeek app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
    
    # Get tools from app settings
    app_tools = APPS[app] && APPS[app].settings["tools"] ? APPS[app].settings["tools"] : []
    
    # Debug logging
    DebugHelper.debug("DeepSeek app_tools from settings: #{app_tools.inspect}", category: :api, level: :debug)
    DebugHelper.debug("DeepSeek websearch enabled: #{websearch}", category: :api, level: :debug)
    
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

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      body["messages"].last["content"] += "\n\n" + APPS[app].settings["prompt_suffix"] if APPS[app].settings["prompt_suffix"]
    end

    if obj["model"].include?("reasoner")
      body.delete("temperature")
      body.delete("tool_choice")
      body.delete("tools")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].map do |msg|
        msg["content"] = msg["content"].sub(/---\n\n/, "")
        msg
      end
    else
      if obj["monadic"] || obj["json"]
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

    buffer = String.new.force_encoding("UTF-8")
    texts = {}
    tools = {}
    finish_reason = nil
    partial_json = nil
    first_message = true

    res.each do |chunk|
      begin
        chunk = chunk.force_encoding("UTF-8")
        if buffer.valid_encoding? == false
          buffer << chunk
          next
        end

        if !chunk.force_encoding("UTF-8").valid_encoding?
          chunk = chunk.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace)
        end

        # Process partial JSON if exists
        if partial_json
          buffer = partial_json + chunk
        else
          buffer << chunk
        end

        # Try to extract complete JSON messages
        messages = extract_complete_messages(buffer)
        
        if messages.empty?
          # If no complete messages found, retain buffer and wait for next chunk
          partial_json = buffer
          next
        else
          # If the last message is incomplete, keep it for next processing
          last_message = messages.pop if !is_complete_json(messages.last)
          partial_json = last_message
          
          messages.each do |msg|
            begin
              data_content = msg.match(/data: (\{.*\})/m)
              return unless data_content && data_content[1]

              json = JSON.parse(data_content[1])

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

                  if fragment.length > 0
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
              pp "JSON parse error in message: #{e.message}"
            end
          end
        end

        buffer = String.new

      rescue StandardError => e
        pp e.message
        pp e.backtrace
        next
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    text_result = texts.empty? ? nil : texts.first[1]

    if text_result
      if obj["monadic"]
        choice = text_result["choices"][0]
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
      res = {
        "role" => "assistant",
        "content" => "The AI model is calling functions to process the data."
      }
      res["tool_calls"] = tools_data.map do |tool|
        {
          "id" => tool["id"],
          "type" => "function",
          "function" => tool["function"]
        }
      end
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
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  private

  def extract_complete_messages(buffer)
    # Split by data message boundary pattern
    messages = buffer.split(/(?<=\n\n)(?=data: )/)
    messages.select { |msg| msg.start_with?('data: ') }
  end

  def is_complete_json(message)
    return false unless message.start_with?('data: ')
    
    begin
      data_content = message.match(/data: (\{.*\})/m)
      return false unless data_content && data_content[1]
      
      json = JSON.parse(data_content[1])
      
      # Check if JSON structure meets expectations
      return false unless json["choices"]&.first&.key?("delta")
      
      true
    rescue JSON::ParserError
      false
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        escaped = function_call["arguments"]
        argument_hash = JSON.parse(escaped)
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
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
        role: "tool",
        tool_call_id: tool_call["id"],
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
