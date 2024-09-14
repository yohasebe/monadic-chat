module OllamaHelper
  ollama_endpoint = nil

  endpoints = [
    "http://host.docker.internal:11434/api",
    "http://localhost:11434/api"
  ]

  endpoints.each do |endpoint|
    url = endpoint.gsub("/api", "")
    begin
      if HTTP.get(url).status.success?
        ollama_endpoint = endpoint
        break
      end
    rescue HTTP::Error
      next
    end
  end

  API_ENDPOINT = ollama_endpoint || endpoints.last

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5

  attr_reader :models

  def self.list_models
    headers = {
      "Content-Type": "application/json"
    }

    target_uri = "#{API_ENDPOINT}/tags"

    http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        models = []
        model_data["models"].each do |model|
          models << model["model"] || model["name"]
        end
      end
      models
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  def process_json_data(app, session, body, _call_depth, &block)
    obj = session[:parameters]

    buffer = String.new
    texts = []
    finish_reason = nil

    body.each do |chunk|
      begin
        buffer << chunk
        json = JSON.parse(buffer)
        buffer = String.new
        finish_reason = json["done"] ? "stop" : nil
        if json.dig("message", "content")
          fragment = json.dig("message", "content").to_s
          res = {
            "type" => "fragment",
            "content" => fragment
          }
          block&.call res
          texts << fragment
        end
      rescue JSON::ParserError
        buffer << chunk
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.join("")

    if result && obj["monadic"]
      modified = APPS[app].monadic_map(result)
      result = modified
    end

    if result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result = {
        "choices" => [{
          "message" => {
            "content" => result
          },
          "finish_reason" => finish_reason
        }]
      }
      [result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    session[:messages].delete_if do |msg|
      msg["role"] == "assistant" && msg["content"].to_s == ""
    end

    obj = session[:parameters]
    app = obj["app_name"]

    temperature = obj["temperature"].to_f
    top_p = obj["top_p"].to_f
    top_p = 0.01 if top_p == 0.0
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    if obj["monadic"].to_s == "true" && message != ""
      message = APPS[app].monadic_unit(message)

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
              } }
      res["images"] = obj["images"] if obj["images"]
      block&.call res
    end

    if message != "" && role == "user"
      res = { "mid" => request_id,
              "role" => role,
              "text" => message,
              "html" => markdown_to_html(message),
              "lang" => detect_language(message),
              "active" => true }
      if obj["image"]
        res["images"] = obj["images"]
      end
      session[:messages] << res
    end

    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].size > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }

    headers = {
      "Content-Type" => "application/json"
    }

    body = {
      "model" => obj["model"],
      "stream" => true,
      "options" => {
        "temperature" => temperature,
        "top_p" => top_p
      }
    }

    if obj["monadic"] || obj["json"]
      body["response_format"] = { "type" => "json_object" }
    end

    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => msg["text"] }
      if msg["images"] && role == "user"
        message["images"] = msg["images"]&.map do |img|
          img["data"].split(",")[1]
        end
        messages_containing_img = true
      end
      message
    end

    if role == "user"
      body["messages"].last["content"] += "\n\n" + settings[:prompt_suffix] if settings[:prompt_suffix]
    end

    target_uri = "#{API_ENDPOINT}/chat"
    headers["Accept"] = "text/event-stream"
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
      error_report = JSON.parse(res.body)
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
      block&.call res
      return [res]
    end

    process_json_data(app, session, res.body, call_depth, &block)
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

