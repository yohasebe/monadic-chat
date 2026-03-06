require 'http'
require_relative "../../utils/system_prompt_injector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../monadic_performance"
require_relative "../base_vendor_helper"

module OllamaHelper
  include BaseVendorHelper
  include MonadicPerformance
  include FunctionCallErrorHandler
  define_timeouts "OLLAMA", open: 5, read: 600, write: 60
  MAX_RETRIES = 5
  RETRY_DELAY = 2
  MAX_FUNC_CALLS = 20

  # Default model resolved via SystemDefaults (env var > providerDefaults > hardcoded fallback)
  DEFAULT_MODEL = (defined?(SystemDefaults) &&
    SystemDefaults.get_default_model('ollama')) || 'qwen3:4b'

  ENDPOINT_CANDIDATES = [
    "http://host.docker.internal:11434/api",
    "http://localhost:11434/api"
  ].freeze

  @cached_endpoint = nil
  @cache_checked_at = nil

  ENDPOINT_PROBE_TIMEOUT = 2  # seconds — keep short to avoid blocking startup
  CACHE_TTL = 30              # seconds — revalidate cached endpoint periodically

  def self.find_endpoint
    # Return cached endpoint if still fresh
    if @cached_endpoint && @cache_checked_at && (Time.now - @cache_checked_at) < CACHE_TTL
      return @cached_endpoint
    end

    # Revalidate cached endpoint if TTL expired
    if @cached_endpoint
      url = @cached_endpoint.sub("/api", "")
      begin
        res = HTTP.timeout(connect: ENDPOINT_PROBE_TIMEOUT, read: ENDPOINT_PROBE_TIMEOUT)
                   .get(url)
        if res.status.success?
          @cache_checked_at = Time.now
          return @cached_endpoint
        end
      rescue HTTP::Error, HTTP::TimeoutError, Errno::ECONNREFUSED, SocketError, Errno::EHOSTUNREACH
        # Cached endpoint is stale
      end
      @cached_endpoint = nil
      @cache_checked_at = nil
    end

    # Probe all candidates
    ENDPOINT_CANDIDATES.each do |endpoint|
      url = endpoint.sub("/api", "")
      begin
        res = HTTP.timeout(connect: ENDPOINT_PROBE_TIMEOUT, read: ENDPOINT_PROBE_TIMEOUT)
                   .get(url)
        if res.status.success?
          @cached_endpoint = endpoint
          @cache_checked_at = Time.now
          return endpoint
        end
      rescue HTTP::Error, HTTP::TimeoutError, Errno::ECONNREFUSED, SocketError, Errno::EHOSTUNREACH
        next
      end
    end
    nil
  end

  def self.reset_endpoint_cache
    @cached_endpoint = nil
    @cache_checked_at = nil
  end

  MAX_RETRIES.times do
    break if find_endpoint
    sleep RETRY_DELAY
  end

  API_ENDPOINT = find_endpoint || ENDPOINT_CANDIDATES.last

  attr_reader :models

  def vendor_name
    "Ollama"
  end
  module_function :vendor_name

  def list_models
    # Use global $MODELS cache like other providers
    return $MODELS[:ollama] if $MODELS[:ollama]

    ollama_endpoint = OllamaHelper.find_endpoint

    # If no endpoint found, return empty array
    unless ollama_endpoint
      return []
    end

    headers = {
      "Content-Type": "application/json"
    }

    target_uri = "#{ollama_endpoint}/tags"

    http = HTTP.headers(headers)

    begin
      res = http.timeout(connect: open_timeout, write: write_timeout, read: read_timeout).get(target_uri)

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
    ollama_endpoint = OllamaHelper.find_endpoint

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
    http = HTTP.headers(headers)

    res = nil
    last_error = nil
    MAX_RETRIES.times do |attempt|
      begin
        current_endpoint = OllamaHelper.find_endpoint
        unless current_endpoint
          last_error = StandardError.new("Ollama endpoint not found")
          sleep RETRY_DELAY
          next
        end
        target_uri = "#{current_endpoint}/chat"

        res = http.timeout(connect: open_timeout,
                           write: write_timeout,
                           read: read_timeout).post(target_uri, json: body)
        if res.status.success?
          last_error = nil
          break
        end
        sleep RETRY_DELAY
      rescue HTTP::Error, HTTP::TimeoutError => e
        last_error = e
        STDERR.puts "[Ollama] send_query attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        OllamaHelper.reset_endpoint_cache
        sleep RETRY_DELAY
      end
    end

    return "Error: Ollama is not reachable. (#{last_error.message})" if last_error

    if res&.status&.success?
      JSON.parse(res.body).dig("message", "content")
    else
      error = begin
        JSON.parse(res.body)["error"]
      rescue StandardError
        res.body.to_s
      end
      STDERR.puts "[Ollama API Error] #{error}" if CONFIG["EXTRA_LOGGING"]
      "ERROR: #{error}"
    end
  rescue StandardError => e
    "Error: The request could not be completed. (#{e.message})"
  end

  def api_request(role, session, call_depth: 0, &block)
    # Initialize call_depth_per_turn on user turns
    if role == "user"
      session[:call_depth_per_turn] = 0
    end

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
              "app_name" => obj["app_name"],
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

    ollama_endpoint = OllamaHelper.find_endpoint

    unless ollama_endpoint
      res = { "type" => "error", "content" => "Ollama service is not available. Please ensure Ollama is running on your system." }
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

    # Add tool definitions if available and within call depth limit
    tools_config = obj["tools"]
    if tools_config && session[:call_depth_per_turn].to_i < MAX_FUNC_CALLS
      formatted_tools = format_tools_for_ollama(tools_config)
      body["tools"] = formatted_tools unless formatted_tools.empty?
    end

    messages_containing_img = false
    system_message_modified = false
    body["messages"] = context.compact.map do |msg|
      # Apply unified system prompt injector to first system message
      if msg["role"] == "system" && !system_message_modified
        system_message_modified = true

        augmented_text = Monadic::Utils::SystemPromptInjector.augment(
          base_prompt: msg["text"],
          session: session,
          options: {
            websearch_enabled: false,
            reasoning_model: false,
            websearch_prompt: nil,
            system_prompt_suffix: obj["system_prompt_suffix"]
          },
          separator: "\n\n---\n\n"
        )

        message = { "role" => msg["role"], "content" => augmented_text }
      else
        message = { "role" => msg["role"], "content" => msg["text"] }
      end

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

    if role == "tool"
      # When processing tool results, use the function_returns context
      # which includes the full conversation + assistant tool_calls + tool responses
      if obj["function_returns"]
        body["messages"] = obj["function_returns"].compact.map do |msg|
          { "role" => msg["role"], "content" => msg["content"] || msg["text"] || "" }
        end
      end
    elsif role == "user"
      # Use unified system prompt injector for user message augmentation
      if body["messages"].last && body["messages"].last["content"]
        augmented_content = Monadic::Utils::SystemPromptInjector.augment_user_message(
          base_message: body["messages"].last["content"],
          session: session,
          options: {
            prompt_suffix: settings[:prompt_suffix]
          }
        )
        body["messages"].last["content"] = augmented_content
      end
    end

    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    res = nil
    last_error = nil
    MAX_RETRIES.times do |attempt|
      begin
        # Re-resolve endpoint on each retry (cache may have been cleared)
        current_endpoint = OllamaHelper.find_endpoint
        unless current_endpoint
          last_error = StandardError.new("Ollama endpoint not found")
          STDERR.puts "[Ollama] Endpoint not found on attempt #{attempt + 1}/#{MAX_RETRIES}" if CONFIG["EXTRA_LOGGING"]
          sleep RETRY_DELAY
          next
        end
        target_uri = "#{current_endpoint}/chat"

        res = http.timeout(connect: open_timeout,
                           write: write_timeout,
                           read: read_timeout).post(target_uri, json: body)
        if res.status.success?
          last_error = nil
          break
        end
        sleep RETRY_DELAY
      rescue HTTP::Error, HTTP::TimeoutError => e
        last_error = e
        STDERR.puts "[Ollama] Connection attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        OllamaHelper.reset_endpoint_cache
        sleep RETRY_DELAY
      end
    end

    if last_error
      error_message = "Ollama is not reachable. Please ensure Ollama is running. (#{last_error.message})"
      STDERR.puts "[Ollama] #{error_message}" if CONFIG["EXTRA_LOGGING"]
      res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
      block&.call res
      return [res]
    end

    unless res&.status&.success?
      error_report = begin
        JSON.parse(res.body)
      rescue StandardError
        res.body.to_s
      end
      STDERR.puts "[Ollama API Error] #{error_report}" if CONFIG["EXTRA_LOGGING"]
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
      block&.call res
      return [res]
    end

    process_json_data(app, session, res.body, call_depth, &block)
  rescue StandardError => e
    STDERR.puts "[Ollama] Unexpected error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
    STDERR.puts "[Ollama] Backtrace: #{e.backtrace.first(5).join("\n")}" if CONFIG["EXTRA_LOGGING"]
    OllamaHelper.reset_endpoint_cache
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}" }
    block&.call res
    [res]
  end

  def process_json_data(app, session, body, call_depth, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing Ollama streaming response at #{Time.now}")
    end

    obj = session[:parameters]

    buffer = String.new
    texts = []
    accumulated_tool_calls = []
    finish_reason = nil
    fragment_sequence = 0
    is_first_fragment = true

    body.each do |chunk|
      begin
        buffer << chunk
        json = JSON.parse(buffer)
        buffer = String.new
        finish_reason = json["done"] ? "stop" : nil

        # Detect tool calls (Ollama sends them in the done:true chunk)
        if json.dig("message", "tool_calls")
          json["message"]["tool_calls"].each do |tc|
            accumulated_tool_calls << tc
          end
          if CONFIG["EXTRA_LOGGING"]
            extra_log&.puts("Tool calls detected: #{accumulated_tool_calls.length}")
          end
        elsif json.dig("message", "content")
          fragment = json.dig("message", "content").to_s
          res = {
            "type" => "fragment",
            "content" => fragment,
            "sequence" => fragment_sequence,
            "timestamp" => Time.now.to_f,
            "is_first" => fragment_sequence == 0
          }

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts("Fragment: sequence=#{fragment_sequence}, is_first=#{is_first_fragment}, length=#{fragment.length}, content=#{fragment.inspect}")
          end

          fragment_sequence += 1
          block&.call res
          texts << fragment
          is_first_fragment = false
        end
      rescue JSON::ParserError
        # Incomplete JSON, continue buffering
      end
    rescue StandardError => e
      STDERR.puts "[Ollama Streaming] Error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      STDERR.puts "[Ollama Streaming] Backtrace: #{e.backtrace.first(5).join("\n")}" if CONFIG["EXTRA_LOGGING"]
      # Connection dropped mid-stream — invalidate cached endpoint
      OllamaHelper.reset_endpoint_cache
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log&.puts("Total fragments processed: #{texts.length}")
      extra_log&.puts("Tool calls accumulated: #{accumulated_tool_calls.length}")
      extra_log&.close
    end

    # Handle tool calls if any were detected
    if accumulated_tool_calls.any?
      session[:call_depth_per_turn] = session[:call_depth_per_turn].to_i + 1

      if session[:call_depth_per_turn] > MAX_FUNC_CALLS
        res = { "type" => "error", "content" => "ERROR: Maximum function call depth exceeded (#{MAX_FUNC_CALLS})" }
        block&.call res
        return [res]
      end

      # Build context from current session messages for tool result re-invocation
      context_size = obj["context_size"].to_i
      context = [session[:messages].first]
      if session[:messages].size > 1
        context += session[:messages][1..].last(context_size)
      end

      # Add assistant message with tool_calls to context
      assistant_msg = { "role" => "assistant", "content" => texts.join("") }
      assistant_msg["tool_calls"] = accumulated_tool_calls.map do |tc|
        {
          "function" => {
            "name" => tc.dig("function", "name"),
            "arguments" => tc.dig("function", "arguments")
          }
        }
      end
      context << assistant_msg

      return process_functions(app, session, accumulated_tool_calls, context, session[:call_depth_per_turn], &block)
    end

    result = texts.join("")

    if result && !result.empty?
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

  def process_functions(app, session, tool_calls, context, call_depth, &block)
    obj = session[:parameters]

    res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
    block&.call res

    tool_calls.each do |tool_call|
      function_name = tool_call.dig("function", "name")
      next unless function_name

      block&.call({ "type" => "tool_executing", "content" => function_name })

      begin
        arguments = tool_call.dig("function", "arguments")
        argument_hash = if arguments.is_a?(String) && !arguments.to_s.strip.empty?
                          JSON.parse(arguments)
                        elsif arguments.is_a?(Hash)
                          arguments
                        else
                          {}
                        end
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        memo[k.to_sym] = v
      end

      # Inject session for tools that need it
      method_obj = APPS[app].method(function_name.to_sym) rescue nil
      if method_obj && method_obj.parameters.any? { |type, name| name == :session }
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

      # Check for repeated errors
      if handle_function_error(session, function_return, function_name, &block)
        context << {
          "role" => "tool",
          "content" => function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
        }
        next
      end

      context << {
        "role" => "tool",
        "content" => function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
      }
    end

    obj["function_returns"] = context

    # Stop if repeated errors detected
    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected." } }] }]
    end

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end

  private

  def format_tools_for_ollama(tools_config)
    # Ollama uses OpenAI-compatible tool format
    return [] unless tools_config

    tools = case tools_config
            when Array
              tools_config
            when Hash
              tools_config["function_declarations"] || []
            else
              []
            end

    tools.map do |tool|
      if tool.is_a?(Hash) && tool["type"] == "function" && tool["function"]
        # Already in OpenAI format — pass through
        tool
      elsif tool.is_a?(Hash) && tool["name"]
        # Claude/Gemini format — convert to OpenAI format
        {
          "type" => "function",
          "function" => {
            "name" => tool["name"],
            "description" => tool["description"] || "",
            "parameters" => tool["input_schema"] || tool["parameters"] || { "type" => "object", "properties" => {} }
          }
        }
      else
        nil
      end
    end.compact
  end
end
