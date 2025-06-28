# frozen_string_literal: true

require_relative "../../utils/interaction_utils"

module GrokHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.x.ai/v1"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60

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
    return "Error: XAI_API_KEY not found" if api_key.nil?
    
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

    case options["reasoning_effort"]
    when "low"
      body["reasoning_effort"] = "low"
    when "medium", "high"
      body["reasoning_effort"] = "high"
    end
    
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
    return "Error: #{e.message}"
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
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
    websearch = obj["websearch"] == "true"
    websearch_native = websearch

    message = nil
    data = nil

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
        res["content"]["images"] = obj["images"] if obj["images"]
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

    body["stream"] = true
    body["n"] = 1
    body["temperature"] = temperature if temperature
    body["presence_penalty"] = presence_penalty if presence_penalty
    body["frequency_penalty"] = frequency_penalty if frequency_penalty
    body["max_tokens"] = max_tokens if max_tokens

    if obj["response_format"]
      body["response_format"] = APPS[app].settings["response_format"]
    end

    if obj["monadic"] || obj["json"]
      body["response_format"] ||= { "type" => "json_object" }
    end

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"] || []
      body["tool_choice"] = "auto" if body["tools"] && !body["tools"].empty?
    else
      body.delete("tools")
      body.delete("tool_choice")
    end
    
    # Add search_parameters for native Grok Live Search
    if websearch_native
      body["search_parameters"] = {
        "mode" => "on",  # "on" forces live search, "auto" lets model decide
        "return_citations" => true,
        "sources" => [
          { "type" => "web" },
          { "type" => "news" },
          { "type" => "x" }
        ]
      }
      
      # Debug logging
      if DebugHelper.extra_logging?
        DebugHelper.debug("Grok Live Search enabled with search_parameters:\n#{JSON.pretty_generate(body["search_parameters"])}", category: :api, level: :info)
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

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body["tool_choice"] = "auto"
    end

    last_text = context.last["text"]

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    if last_text != "" && prompt_suffix.to_s != ""
      new_text = last_text + "\n\n" + prompt_suffix.strip if prompt_suffix.to_s != ""
      if body.dig("messages", -1, "content")
        body["messages"].last["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = new_text
          end
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
      body["messages"].first["content"].each do |content_item|
        if content_item["type"] == "text"
          content_item["text"] = new_text
        end
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


    # Process tool calls if any
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
              DebugHelper.debug("Response: #{JSON.pretty_generate(json)}", category: :api, level: :debug)
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
            if json.dig("choices", 0, "delta", "tool_calls")
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res

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
      if result
        merged = result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
        context << merged
      else
        context << tools.first[1].dig("choices", 0, "message")
      end

      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tools, context, call_depth, &block)

      # return Array
      if result && new_results
        [result].concat new_results
      elsif new_results
        new_results
      elsif result
        [result]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result["choices"][0]["finish_reason"] = finish_reason
      [result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        argument_hash = JSON.parse(function_call["arguments"])
      rescue JSON::ParserError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      rescue StandardError => e
        DebugHelper.debug("Function call error in #{function_name}: #{e.message}", category: :api, level: :error)
        DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
        function_return = "ERROR: #{e.message}"
      end

      context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
