module CommandRHelper
  # API endpoint and configuration constants
  API_ENDPOINT = "https://api.cohere.ai/v2"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5
  VALID_ROLES = %w[user assistant system tool].freeze

  attr_reader :models

  # Fetches available models from Cohere API
  # Returns an array of model names, excluding embedding and reranking models
  def self.list_models
    api_key = CONFIG["COHERE_API_KEY"]
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
        model_data = JSON.parse(res.body)
        model_data["models"].map do |model|
          model["name"]
        end.filter do |model|
          !model.include?("embed") && !model.include?("rerank")
        end
      end
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  # Main API request handler
  # @param role [String] The role of the message sender
  # @param session [Hash] Session data containing parameters and message history
  # @param call_depth [Integer] Current depth of function calls
  # @yield [Hash] Yields response chunks for streaming
  # Main API request handler
  # @param role [String] The role of the message sender
  # @param session [Hash] Session data containing parameters and message history
  # @param call_depth [Integer] Current depth of function calls
  # @yield [Hash] Yields response chunks for streaming
  def api_request(role, session, call_depth: 0, &block)
    empty_tool_results = role == "empty_tool_results"
    num_retrial = 0

    # Verify API key existence
    begin
      api_key = CONFIG["COHERE_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: COHERE_API_KEY not found. Please set the COHERE_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the initial system prompt from the session
    initial_prompt = session[:messages].first["text"].to_s

    # Parse numerical parameters
    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i
    top_p = obj["top_p"]&.to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"]

    # Handle non-tool messages and update session
    if role != "tool"
      message ||= "Hi there!"
      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      if role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Initialize and manage message context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages][0...-1].last(context_size).each { |msg| msg["active"] = true }

    # Configure API request headers
    headers = {
      "accept" => "application/json",
      "content-type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Prepare messages array for v2 API format
    messages = []

    # Add system message (initial prompt)
    messages << {
      "role" => "system",
      "content" => initial_prompt.to_s
    }

    # Add context messages with appropriate roles
    context.each do |msg|
      next if msg["text"].to_s.strip.empty?  # Skip empty messages
      messages << {
        "role" => translate_role(msg["role"]),
        "content" => msg["text"].to_s.strip
      }
    end

    # Add current user message if not a tool call
    if role != "tool"
      current_message = "#{message}\n\n#{obj["prompt_suffix"]}".strip
      messages << {
        "role" => "user",
        "content" => current_message
      }
    end

    # Construct request body with v2 API compatible parameters
    body = {
      "model" => obj["model"],
      "stream" => true,
    }

    # Add optional parameters with validation
    body["temperature"] = temperature if temperature && temperature.between?(0.0, 2.0)
    body["max_tokens"] = max_tokens if max_tokens && max_tokens.positive?
    body["p"] = top_p if top_p && top_p.between?(0.0, 1.0)

    # Add tools configuration if available
    if role != "tool" && APPS[app]&.settings&.dig("tools")
      body["tools"] = APPS[app].settings["tools"].map do |tool|
        # Build parameters in object format
        properties = {}
        required = []

        unless tool["parameter_definitions"].empty?
          tool["parameter_definitions"].each do |name, definition|
            properties[name] = {
              "type" => definition["type"],
              "description" => definition["description"]
            }
            required << name if definition["required"]
          end
        end

        {
          "type" => "function",
          "function" => {
            "name" => tool["name"],
            "description" => tool["description"],
            "parameters" => {
              "type" => "object",
              "properties" => properties,
              "required" => required
            }
          }
        }
      end
    end

    # Handle tool results in v2 format
    if role == "tool" && obj["tool_results"]
      body["messages"] = obj["tool_results"]
    else
      body["messages"] = messages
    end


    target_uri = "#{API_ENDPOINT}/chat"
    http = HTTP.headers(headers)

    res = nil
    MAX_RETRIES.times do |i|
      begin
        res = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)
        
        break if res.status.success?
        
        sleep RETRY_DELAY * (i + 1) # Exponential backoff
      rescue HTTP::Error, HTTP::TimeoutError => e
        next unless i == MAX_RETRIES - 1
        
        pp error_message = "Network error: #{e.message}"
        res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
        block&.call res
        return [res]
      end
    end

    # Handle API error responses
    unless res&.status&.success?
      error_report = begin
                      JSON.parse(res.body)
                    rescue StandardError
                      { "message" => "Unknown error occurred" }
                    end
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    # Process streaming response
    process_json_data(app, session, res.body, call_depth, &block)
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
    block&.call res
    [res]
  end

  # Process streaming JSON response data
  # @param app [String] Application name
  # @param session [Hash] Session data
  # @param body [String] Response body
  # @param call_depth [Integer] Current depth of function calls
  # @yield [Hash] Yields processed response chunks
  def process_json_data(app, session, body, call_depth, &block)
    texts = []
    tool_calls = []
    finish_reason = nil
    complete_text = ""
    buffer = ""
    current_tool_call = nil
    accumulated_tool_calls = []

    if body.respond_to?(:each)
      body.each do |chunk|
        begin
          # Split chunk into separate JSON objects if multiple exist
          chunk.to_s.split("\n").each do |json_str|
            next if json_str.empty?
            
            begin
              json = JSON.parse(json_str)

              # Handle different event types from v2 streaming API
              case json["type"]
              when "message-start"
                buffer = ""
                accumulated_tool_calls = []
              when "content-start"
              when "content-delta"
                if content = json.dig("delta", "message", "content")
                  if text = content["text"]
                    buffer += text
                    texts << text
                    complete_text = buffer

                    unless text.strip.empty?
                      res = {
                        "type" => "fragment",
                        "content" => text
                      }
                      block&.call res
                    end
                  end
                end
              when "tool-plan-delta"
                if text = json.dig("delta", "message", "tool_plan")
                  buffer += text
                  texts << text
                  complete_text = buffer

                  unless text.strip.empty?
                    res = {
                      "type" => "fragment",
                      "content" => text
                    }
                    block&.call res
                  end
                end
              when "tool-call-start"
                tool_call_data = json.dig("delta", "message", "tool_calls")
                current_tool_call = tool_call_data.dup
              when "tool-call-delta"
                if current_tool_call && args = json.dig("delta", "message", "tool_calls", "function", "arguments")
                  current_tool_call["function"]["arguments"] += args
                end
              when "tool-call-end"
                if current_tool_call
                  accumulated_tool_calls << current_tool_call
                  current_tool_call = nil
                  res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res
                end
              when "message-end"
                if json.dig("delta", "finish_reason")
                  finish_reason = case json["delta"]["finish_reason"]
                                 when "MAX_TOKENS"
                                   "length"
                                 when "COMPLETE"
                                   "stop"
                                 else
                                   json["delta"]["finish_reason"]
                                 end
                end
                break
              end
            rescue JSON::ParserError => e
              pp "JSON parse error in split: #{e.message}"  # Debug log
              next
            end
          end
        rescue StandardError => e
          pp "Error processing chunk: #{e.message}"  # Debug log
          pp e.backtrace  # Debug log
          next
        end
      end
    end

    # Prepare final result from accumulated text
    result = complete_text.empty? ? nil : complete_text.strip

    # Process accumulated tool calls if any exist
    if accumulated_tool_calls.any?

      context = [
        {
          "role" => "assistant",
          "tool_calls" => accumulated_tool_calls,
          "tool_plan" => result
        }
      ]

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Maximum function call depth exceeded" }]
      end

      # Execute tool calls and get results
      new_results = process_functions(app, session, accumulated_tool_calls, context, call_depth, &block)

      # Handle different result scenarios
      if result.is_a?(Hash) && result["error"]
        # Handle error case
        res = { "type" => "error", "content" => result["error"] }
      elsif result && new_results
        # Combine text result with function results
        combined_result = "#{result}\n\n#{new_results.dig(0, "choices", 0, "message", "content")}"
        res = { "choices" => [{ "message" => { "content" => combined_result } }] }
      elsif new_results
        # Use only function results
        res = new_results
      elsif result
        # Use only text result
        res = { "choices" => [{ "message" => { "content" => result } }] }
      end
      block&.call res
      [res]
    elsif result
      # Return final text result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result }
            }
          ]
        }
      ]
    else
      # Handle empty tool results
      api_request("empty_tool_results", session, call_depth: call_depth, &block)
    end
  end

  # Process function calls from the API response
  # @param app [String] Application name
  # @param session [Hash] Session data
  # @param tool_calls [Array] Array of tool calls to process
  # @param call_depth [Integer] Current depth of function calls
  # @yield [Hash] Yields processed response chunks
  def process_functions(app, session, tool_calls, context, call_depth, &block)
    obj = session[:parameters]
    tool_results = []

    tool_calls.each do |tool_call|
      # Extract function name and validate
      function_name = tool_call.dig("function", "name")
      next if function_name.nil?

      # Important: Keep the original tool_call_id exactly as received
      tool_call_id = tool_call["id"]  # This ID must match exactly what the API sent

      begin
        # Parse and sanitize function arguments
        arguments = tool_call.dig("function", "arguments")
        argument_hash = if arguments.is_a?(String) && !arguments.empty?
          JSON.parse(arguments)
        else
          {}
        end
      rescue JSON::ParserError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      # Execute function and capture result
      begin
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      rescue StandardError => e
        pp "Function execution error: #{e.message}"  # Debug log
        function_return = "Error executing function: #{e.message}"
      end

      # Format tool results maintaining exact tool_call_id
      context << {
        "role" => "tool",
        "tool_call_id" => tool_call_id,
        "content" => [
          {
            "type" => "document", 
            "document" => {
              "id" => tool_call_id,
              "data" => {
                "results" => function_return.to_s
              }
            }
          }
        ]
      }
    end

    # Store the tool results in the session
    obj["tool_results"] = context

    # Make recursive API request with tool results
    api_request("tool", session, call_depth: call_depth, &block)
  end

  # Translate role names to v2 API format
  # @param role [String] Role name to translate
  # @return [String] Translated role name
  def translate_role(role)
    role_lower = role.to_s.downcase
    VALID_ROLES.include?(role_lower) ? role_lower : "user"
  end
end
