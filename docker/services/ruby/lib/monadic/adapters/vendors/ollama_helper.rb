require 'http'
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"

module OllamaHelper
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 2
  MAX_FUNC_CALLS = 20
  
  # Default model can be overridden by OLLAMA_DEFAULT_MODEL environment variable
  DEFAULT_MODEL = ENV['OLLAMA_DEFAULT_MODEL'] || 'llama3.2:latest'

  ollama_endpoint = nil

  endpoints = [
    "http://monadic-chat-ollama-container:11434/api",
    "http://host.docker.internal:11434/api",
    "http://localhost:11434/api"
  ]

  MAX_RETRIES.times do
    break if ollama_endpoint
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
    sleep RETRY_DELAY
  end

  API_ENDPOINT = ollama_endpoint || endpoints.last

  attr_reader :models

  def vendor_name
    "Ollama"
  end
  module_function :vendor_name

  def list_models
    # Use global $MODELS cache like other providers
    return $MODELS[:ollama] if $MODELS[:ollama]

    # Dynamically find Ollama endpoint
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

    # If no endpoint found, return empty array
    unless ollama_endpoint
      # Return empty array - Ollama service is not available
      return []
    end

    headers = {
      "Content-Type": "application/json"
    }

    target_uri = "#{ollama_endpoint}/tags"

    http = HTTP.headers(headers)

    begin
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        models = model_data["models"].map do |model|
          model["name"]
        end
        # Cache and return models if found
        $MODELS[:ollama] = models unless models.empty?
        models.empty? ? [] : models
      else
        # Return empty array on API error
        []
      end
    rescue HTTP::Error, HTTP::TimeoutError
      # Return empty array on connection error
      []
    end
  end
  module_function :list_models

  # No streaming plain text completion/chat call
  def send_query(options, model: nil)
    # Dynamically find Ollama endpoint
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

    return "Error: Ollama service is not available" unless ollama_endpoint

    headers = {
      "Content-Type" => "application/json"
    }

    body = {
      "model" => model,
      "stream" => false,
      "messages" => []
    }

    body.merge!(options)
    target_uri = "#{ollama_endpoint}/chat"
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

    if res.status.success?
      JSON.parse(res.body).dig("choices", 0, "message", "content")
    else
      pp JSON.parse(res.body)["error"]
      "ERROR: #{JSON.parse(res.body)["error"]}"
    end
  rescue StandardError
    "Error: The request could not be completed."
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    session[:messages].delete_if do |msg|
      msg["role"] == "assistant" && msg["content"].to_s == ""
    end

    obj = session[:parameters]
    app = obj["app_name"]
    model = obj["model"]

    # Validate model exists
    available_models = list_models
    if !available_models.empty? && !available_models.include?(model)
      error_message = "Model '#{model}' not found. Available models: #{available_models.join(', ')}"
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return [res]
    end

    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    if message != ""
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
      res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
      block&.call res
    end

    if message != "" && role == "user"
      res = { "mid" => request_id,
              "role" => role,
              "text" => obj["message"],
              "html" => html,
              "lang" => detect_language(obj["message"]),
              "active" => true }
      if obj["images"] && obj["images"].is_a?(Array)
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

    # Dynamically find Ollama endpoint
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

    unless ollama_endpoint
      res = { "type" => "error", "content" => "Ollama service is not available. Please ensure the Ollama container is running." }
      block&.call res
      return [res]
    end

    headers = {
      "Content-Type" => "application/json"
    }

    body = {
      "model" => obj["model"],
      "stream" => true,
      "options" => {
        "temperature" => temperature,
      }
    }

    # Configure monadic response format using unified interface
    body = configure_monadic_response(body, :ollama, app)

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

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      body["messages"] << {
        "role" => "user",
        "content" => "Please proceed according to your system instructions and introduce yourself."
      }
    end

    if role == "user"
      # Apply monadic transformation if in monadic mode
      if obj["monadic"].to_s == "true" && body["messages"].any? && body["messages"].last["role"] == "user"
        # Get the base message without prompt suffix
        base_message = body["messages"].last["content"]
        # Apply monadic transformation using unified interface
        monadic_message = apply_monadic_transformation(base_message, app, "user")
        body["messages"].last["content"] = monadic_message
      end
      
      body["messages"].last["content"] += "\n\n" + settings[:prompt_suffix] if settings[:prompt_suffix]
    end

    target_uri = "#{ollama_endpoint}/chat"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    # Don't send initial spinner - let the client handle it
    # The spinner will be shown automatically when the request starts
    # res = { "type" => "wait", "content" => "<i class='fas fa-spinner fa-pulse'></i> THINKING" }
    # block&.call res

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

  def process_json_data(app, session, body, _call_depth, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing Ollama streaming response at #{Time.now}")
    end

    obj = session[:parameters]

    buffer = String.new
    texts = []
    finish_reason = nil
    fragment_index = 0
    is_first_fragment = true

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
            "content" => fragment,
            "index" => fragment_index
            # Don't send is_first flag to prevent spinner from disappearing
            # "is_first" => is_first_fragment
          }
          
          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts("Fragment: index=#{fragment_index}, is_first=#{is_first_fragment}, length=#{fragment.length}, content=#{fragment.inspect}")
          end
          
          block&.call res
          texts << fragment
          fragment_index += fragment.length
          is_first_fragment = false
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

    if CONFIG["EXTRA_LOGGING"]
      extra_log.puts("Total fragments processed: #{texts.length}")
      extra_log.puts("Final result length: #{result.length}")
      extra_log.close
    end

    if result && obj["monadic"]
      # Process through unified interface
      processed = process_monadic_response(result, app)
      # Validate the response
      validated = validate_monadic_response!(processed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
      result = validated.is_a?(Hash) ? JSON.generate(validated) : validated
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
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end
end
