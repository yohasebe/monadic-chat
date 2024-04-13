# frozen_string_literal: false

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
    "This app accesses the Google Gemini API to answer questions about a wide range of topics."
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
      "max_tokens": 2000,
      "context_size": 20,
      "temperature": 0.3,
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
      #     }
      #   ]
      # }
    }
  end

  def fetch_web_content(url: "")
    selenium_job(url: url)
  end

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]
    buffer = ""
    texts = []
    tool_calls = []

    in_text_generation = false

    body.each do |chunk|
      buffer << chunk
      if /(\{\s*\"candidates\":.*\})/m =~ buffer.strip
        json = $1
        begin
          candidates = JSON.parse(json).dig("candidates")
          candidate = candidates.first
          content = candidate.dig("content")
          content.dig("parts")&.each do |part|
            if part["text"]
              texts << part["text"]
              res = { "type" => "fragment", "content" => part["text"] }
              block&.call res
            elsif part["functionCall"]
              tool_calls << part["functionCall"]
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res
            end
          end
          buffer = ""
        rescue JSON::ParserError => e
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
      end
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
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [{"choices" => [{"message" => {"content" => result.join("")}}]}]
    # else
    #   api_request("empty_tool_results", session, call_depth: call_depth, &block)
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
    # empty_tool_results = role == "empty_tool_results" ? true : false

    num_retrial = 0

    begin
      api_key = nil
      model = nil
      if File.file?("/.dockerenv")
        File.read("/monadic/data/.env").split("\n").each do |line|
          api_key = line.split("=").last if line.start_with?("GEMINI_API_KEY")
          model = line.split("=").last if line.start_with?("GEMINI_MODEL")
        end
      else
        File.read("#{Dir.home}/monadic/data/.env").split("\n").each do |line|
          api_key = line.split("=").last if line.start_with?("GEMINI_API_KEY")
          model = line.split("=").last if line.start_with?("GEMINI_MODEL")
        end
      end
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
    temperature = obj["temperature"].to_f

    max_tokens = obj["max_tokens"].to_i
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

    body = {
      "generationConfig" => {
        "temperature" => temperature,
        "maxOutputTokens" => max_tokens
      }
    }

    body["contents"] = context.compact.map do |msg|
      {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => msg["text"] }
        ]
      }
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
    # elsif empty_tool_results
    #   body["tool_results"] = []
    end

    target_uri = "#{API_ENDPOINT}/#{model}:streamGenerateContent?key=#{api_key}"

    http = HTTP.headers(headers)

    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    # return Array
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
