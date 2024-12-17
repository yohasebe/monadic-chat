# frozen_string_literal: true

module GeminiHelper
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 90
  WRITE_TIMEOUT = 90
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5

  attr_reader :models

  def self.list_models
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

      models.filter do |model|
        /(?:embedding|aqa|vision)/ !~ model && model != "gemini-pro"
      end.reverse
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      # ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/data/.env file.
      error_message = "ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/data/.env file."
      pp error_message
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i
    top_p = obj["top_p"]&.to_f

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

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
      safety_settings: [
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
    }

    if temperature || max_tokens || top_p
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
      body["generationConfig"]["topP"] = top_p if top_p
    end

    body["contents"] = context.compact.map do |msg|
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => msg["text"] }
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
      body["tools"] = settings["tools"]
      if body["tools"]
        body["tool_config"] = {
          "function_calling_config" => {
            "mode" => "ANY"
          }
        }
      end
    end

    if role == "tool"
      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "NONE"
        }
      }
      body["contents"] << {
        "role" => "model",
        "parts" => obj["tool_results"].map { |result|
          { "text" => result.dig("functionResponse", "response", "content") }
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
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
        block&.call res
      return [res]
    end

    process_json_data(app, session, res.body, call_depth, &block)
  rescue HTTP::Error, HTTP::TimeoutError, OpenSSL::SSL::SSLError => e
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY * num_retrial
      retry
    else
      error_message = e.is_a?(OpenSSL::SSL::SSLError) ? "SSL ERROR: #{e.message}" : "The request has timed out."
        pp error_message
      res = { "type" => "error", "content" => "HTTP/SSL ERROR: #{error_message}" }
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

  def process_json_data(app, session, body, call_depth, &block)
    buffer = String.new
    texts = []
    tool_calls = []
    finish_reason = nil

    body.each do |chunk|
      buffer << chunk
      if /(\{\s*"candidates":.*\})/m =~ buffer.strip
        json = Regexp.last_match(1)
        begin
          candidates = JSON.parse(json)["candidates"]
          candidate = candidates.first

          finish_reason = candidate["finishReason"]
          case finish_reason
          when "MAX_TOKENS"
            finish_reason = "length"
          when "STOP"
            finish_reason = "stop"
          when "SAFETY"
            finish_reason = "safety"
          end

          content = candidate["content"]
          next if content.nil?

          content["parts"]&.each do |part|
            if part["text"]
              fragment = part["text"]
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
          buffer = String.new
        rescue JSON::ParserError
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.empty? ? nil : texts

    if tool_calls.any?
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      begin
        new_results = process_functions(app, session, tool_calls, call_depth, &block)
      rescue StandardError => e
        new_results = [{ "type" => "error", "content" => "ERROR: #{e.message}" }]
      end

      if result && new_results
        begin
          result = result.join("").strip + "\n\n" + new_results.dig(0, "choices", 0, "message", "content").strip
        rescue StandardError
          result = result.join("").strip + "\n\n" + new_results.to_s.strip
        end
        [{ "choices" => [{ "message" => { "content" => result } }] }]
      elsif new_results
        new_results
      elsif result
        [{ "choices" => [{ "message" => { "content" => result.join("") } }] }]
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

  def process_functions(_app, session, tool_calls, call_depth, &block)
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
        if function_return && function_return["result"] == "success"
          tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => function_return["data"]
              }
            }
          }
        else
          # Error handling
          pp "ERROR: Function call failed: #{function_name}"
            pp function_return
          tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => "ERROR: Function call failed: #{function_name}. #{function_return.to_s}"
              }
            }
          }
        end
      rescue StandardError => e
        pp "ERROR: Function call failed: #{function_name}"
          pp e.message
        pp e.backtrace
        tool_results << {
          "functionResponse" => {
            "name" => function_name,
            "response" => {
              "name" => function_name,
              "content" => "ERROR: Function call failed: #{function_name}. #{e.message}"
            }
          }
        }
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
end
