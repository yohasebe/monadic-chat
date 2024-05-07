#git push origin main frozen_string_literal: false

class Gemini < MonadicApp
  include UtilitiesHelper

  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5
  
  def icon
    "<i class='fab fa-google'></i>"
  end

  def description
    text = "This app accesses the Google Gemini API to answer questions about a wide range of topics."
    text += " (Model: <code>#{CONFIG['GEMINI_MODEL']}</code>)" if CONFIG["GEMINI_MODEL"]
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it.

      Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response. Use Japanese, for example, if the user's input is in Japanese.

      Your response must be formatted as a valid Markdown document.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Talk to Google Gemini",
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      # "tools": {
      #   "function_declarations": [
      #     {
      #       "name": "fetch_web_content",
      #       "description": "Fetch the content of the web page of the given URL and return it.",
      #       "parameters": {
      #         "type": "object",
      #         "properties": {
      #           "url": {
      #             "description": "URL of the web page.",
      #             "type": "string"
      #           }
      #         },
      #         "required": ["url"]
      #       }
      #     }, {
      #       "name": "fetch_text_from_file",
      #       "description": "Fetch the text from a file and return its content.",
      #       "parameters": {
      #         "type": "object",
      #         "properties": {
      #           "file": {
      #             "type": "string",
      #             "description": "File name or file path"
      #           }
      #         },
      #         "required": ["file"]
      #       }
      #     }
      #   ]
      # }
    }
  end

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]
    buffer = ""
    texts = []
    tool_calls = []
    finish_reason = nil

    in_text_generation = false

    body.each do |chunk|
      buffer << chunk
      if /(\{\s*\"candidates\":.*\})/m =~ buffer.strip
        json = $1
        begin
          candidates = JSON.parse(json).dig("candidates")
          candidate = candidates.first

          finish_reason = candidate["finishReason"]
          case finish_reason
          when "MAX_TOKENS"
            finish_reason = "length"
          when "STOP"
            finish_reason = "stop"
          end

          content = candidate.dig("content")
          next if content.nil?

          content.dig("parts")&.each do |part|
            if part["text"]
              texts << part["text"]
              part["text"].split(//).each do |char|
                res = { "type" => "fragment", "content" => char }
                block&.call res
                sleep 0.01
              end
            elsif part["functionCall"]
              tool_calls << part["functionCall"]
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res
            end
          end
          buffer = ""
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

      new_results = process_functions(app, session, tool_calls, call_depth, &block)

      if result && new_results
        result = result.join("") + "\n" + new_results.dig(0, "choices", 0, "message", "content")
        {"choices" => [{"message" => {"content" => result}}]}
      elsif new_results
        new_results
      elsif result
        {"choices" => [{"message" => {"content" => result.join("")}}]}
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason}
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => {"content" => result.join("")}
            }
          ]
        }
      ]
    end
  end

  def process_functions(app, session, tool_calls, call_depth, &block)
    obj = session[:parameters]
    tool_results = {"model_parts" => [], "function_parts" => []}
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        argument_hash = tool_call["args"]
      rescue
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      function_return = send(function_name.to_sym, **argument_hash)

      tool_results["model_parts"] << {
        "functionCall" => {
          "name" => function_name,
          "args" => argument_hash
        }
      }
      tool_results["function_parts"] << {
        "functionResponse" => {
          "name" => function_name,
          "response" => {
            "name" => function_name,
            "content" => {
              "result" => function_return.to_s
            }
          }
        }
      }
    end

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
      "system"
    else
      role.downcase
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      model = CONFIG["GEMINI_MODEL"]
      raise if api_key.nil? || model.nil?
    rescue StandardError
      puts "ERROR: GEMINI_API_KEY or GEMINI_MODEL not found."
      exit
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))

    temperature = obj["temperature"] ? obj["temperature"].to_f : nil
    max_tokens = obj["max_tokens"] ? obj["max_tokens"].to_i : nil
    top_p = obj["top_p"] ? obj["top_p"].to_f : nil

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    if role != "tool"
      message = obj["message"].to_s

      if obj["monadic"].to_s == "true" && message != ""
        message = monadic_unit(message) if message != ""
        html = markdown_to_html(obj["message"]) if message != ""
      elsif message != ""
        html = markdown_to_html(message)
      end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                }
        }
        res["image"] = obj["image"] if obj["image"]
        block&.call res
      end

      # If the role is "user", the message is added to the session
      if message != "" && role == "user"
        res = { "mid" => request_id,
                "role" => role,
                "text" => message,
                "html" => markdown_to_html(message),
                "lang" => detect_language(message),
                "active" => true,
        }
        if obj["image"]
          res["image"] = obj["image"]
        end
        session[:messages] << res
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!"}
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages].last(context_size).each { |msg| msg["active"] = true }

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json"
    }

    body = {}

    if temperature || max_tokens || top_p
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
      body["generationConfig"]["topP"] = top_p if top_p
    end

    messages_containing_img = false
    body["contents"] = context.compact.map do |msg|
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => msg["text"] }
        ]
      }

      if msg["image"] && role == "user"
        message["parts"] << {
          "inlineData" => {
            "mimeType" => msg["image"]["type"],
            "data" => msg["image"]["data"].split(",")[1]
          }
        }
        messages_containing_img = true
      end
      message
    end

    if settings[:tools]
      body["tools"] = settings[:tools]
    end

    if role == "tool"
      body["contents"] << {
        "role" => "model",
        "parts" => obj["tool_results"]["model_parts"]
      }
      body["contents"] << {
        "role" => "function",
        "parts" => obj["tool_results"]["function_parts"]
      }
    end

    target_uri = "#{API_ENDPOINT}/#{model}:streamGenerateContent?key=#{api_key}"

    http = HTTP.headers(headers)

    success = false
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      if res.status.success?
        success = true
        break
      end
      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    return process_json_data(app, session, res.body, call_depth, &block)

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
end
