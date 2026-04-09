require 'http'
require_relative "../../utils/system_prompt_injector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../monadic_performance"
require_relative "../base_vendor_helper"
require_relative "../../utils/extra_logger"

module OllamaHelper
  include BaseVendorHelper
  include MonadicPerformance
  include FunctionCallErrorHandler
  define_timeouts "OLLAMA", open: 5, read: 600, write: 60
  MAX_RETRIES = 5
  RETRY_DELAY = 2
  MAX_FUNC_CALLS = 20

  # Default model resolved via SystemDefaults (env var > providerDefaults)
  DEFAULT_MODEL = (defined?(SystemDefaults) &&
    SystemDefaults.get_default_model('ollama'))

  ENDPOINT_CANDIDATES = [
    "http://host.docker.internal:11434/api",
    "http://localhost:11434/api"
  ].freeze

  @cached_endpoint = nil
  @cache_checked_at = nil
  @capabilities_cache = {}
  @models_fetched_at = nil

  ENDPOINT_PROBE_TIMEOUT = 2  # seconds — keep short to avoid blocking startup
  CACHE_TTL = 30              # seconds — revalidate cached endpoint periodically
  CAPABILITIES_CACHE_TTL = 300 # seconds — per-model capability metadata cache
  MODELS_CACHE_TTL = 30       # seconds — Ollama model list cache; short TTL so
                              # newly pulled/removed models appear promptly

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

  def self.reset_capabilities_cache
    @capabilities_cache = {}
  end

  # Fetch capability metadata for a specific Ollama model via /api/show.
  # Returns a hash { capabilities: [...], context_length: N } on success, or
  # nil if Ollama is unreachable or the model is unknown. Results are cached
  # per-model for CAPABILITIES_CACHE_TTL seconds so that subsequent calls
  # (e.g. checking `supports_thinking?` on every request) don't re-hit the API.
  def self.fetch_model_capabilities(model)
    return nil unless model.is_a?(String) && !model.empty?

    @capabilities_cache ||= {}
    cached = @capabilities_cache[model]
    if cached && (Time.now - cached[:fetched_at]) < CAPABILITIES_CACHE_TTL
      return cached
    end

    endpoint = find_endpoint
    return nil unless endpoint

    begin
      res = HTTP.timeout(connect: ENDPOINT_PROBE_TIMEOUT, read: ENDPOINT_PROBE_TIMEOUT)
                 .post("#{endpoint}/show", json: { "model" => model })
      return nil unless res.status.success?

      data = JSON.parse(res.body)
      capabilities = data["capabilities"].is_a?(Array) ? data["capabilities"] : []

      # context_length is nested under model_info with arch-specific prefix
      # (e.g. "qwen3vl.context_length", "llama.context_length"). We scan for
      # any key ending in ".context_length" to remain architecture-agnostic.
      context_length = nil
      if data["model_info"].is_a?(Hash)
        data["model_info"].each do |key, val|
          if key.to_s.end_with?(".context_length") && val.is_a?(Integer)
            context_length = val
            break
          end
        end
      end

      entry = {
        capabilities: capabilities,
        context_length: context_length,
        fetched_at: Time.now
      }
      @capabilities_cache[model] = entry
      entry
    rescue HTTP::Error, HTTP::TimeoutError, JSON::ParserError, Errno::ECONNREFUSED, SocketError => e
      Monadic::Utils::ExtraLogger.log { "[Ollama] fetch_model_capabilities(#{model}) failed: #{e.message}" }
      nil
    end
  end

  MAX_RETRIES.times do
    break if find_endpoint
    sleep RETRY_DELAY
  end

  API_ENDPOINT = find_endpoint || ENDPOINT_CANDIDATES.last

  define_models_cache :ollama

  attr_reader :models

  def vendor_name
    "Ollama"
  end
  module_function :vendor_name

  def list_models
    # Return cached list if still fresh. Unlike cloud providers where the
    # model list rarely changes, Ollama users frequently `ollama pull/rm`
    # models, so we expire the cache after MODELS_CACHE_TTL seconds.
    if $MODELS[:ollama] && @models_fetched_at &&
       (Time.now - @models_fetched_at) < MODELS_CACHE_TTL
      return $MODELS[:ollama]
    end

    ollama_endpoint = OllamaHelper.find_endpoint

    # If no endpoint found, return cached (possibly stale) or empty
    unless ollama_endpoint
      return $MODELS[:ollama] || []
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
        unless models.empty?
          $MODELS[:ollama] = models
          @models_fetched_at = Time.now
        end
        models.empty? ? ($MODELS[:ollama] || []) : models
      else
        $MODELS[:ollama] || []
      end
    rescue HTTP::Error, HTTP::TimeoutError
      $MODELS[:ollama] || []
    end
  end
  module_function :list_models

  # Returns model metadata hash keyed by model name, shaped to match
  # frontend modelSpec entries. Each entry includes context_window,
  # tool/vision/thinking capability flags sourced from Ollama's /api/show.
  # If capability fetch fails for a model, a name-based heuristic fallback
  # is used so the model remains usable (with conservative flags).
  def list_models_with_capabilities
    names = list_models
    result = {}
    names.each do |name|
      caps = OllamaHelper.fetch_model_capabilities(name)
      if caps
        ctx = caps[:context_length] || 8192
        result[name] = {
          "context_window" => [1, ctx],
          "max_output_tokens" => [1, [ctx / 4, 32768].min],
          "tool_capability" => caps[:capabilities].include?("tools"),
          "vision_capability" => caps[:capabilities].include?("vision"),
          "supports_thinking" => caps[:capabilities].include?("thinking")
        }
      else
        # Fallback: conservative name-based heuristic when /api/show is unavailable.
        # Reading comprehension errors on name are preferable to hiding the model.
        lc = name.downcase
        result[name] = {
          "context_window" => [1, 8192],
          "max_output_tokens" => [1, 4096],
          "tool_capability" => true,
          "vision_capability" => lc.include?("-vl") || lc.include?(":vl") || lc.include?("vision") || lc.include?("llava"),
          "supports_thinking" => lc.include?("thinking") || lc.include?("-r1") || lc.include?("deepseek-r1")
        }
      end
    end
    result
  end
  module_function :list_models_with_capabilities

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
        Monadic::Utils::ExtraLogger.log { "[Ollama] send_query attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.message}" }
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
      Monadic::Utils::ExtraLogger.log { "[Ollama API Error] #{error}" }
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
    strip_inactive_image_data(session)

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

    # Enable thinking for models that support it. For Ollama, the Show Thinking
    # toggle is the sole control (Ollama has no reasoning_effort API parameter —
    # only binary think on/off). The toggle defaults to ON in the UI; users who
    # don't want thinking can switch it OFF for faster responses.
    show_thinking = obj["show_thinking"]
    show_thinking_off = [false, "false"].include?(show_thinking)
    if !show_thinking_off && supports_thinking?(obj["model"])
      body["think"] = true
    end

    # Add tool definitions if available and within call depth limit
    tools_config = obj["tools"]
    if tools_config && session[:call_depth_per_turn].to_i < MAX_FUNC_CALLS
      formatted_tools = format_tools_for_ollama(tools_config)
      body["tools"] = formatted_tools unless formatted_tools.empty?
    end

    # Structured Output: map Monadic Chat's OpenAI-compatible `response_format`
    # to Ollama's `format` parameter (Ollama 0.5+ supports constrained decoding).
    #   { "type": "json_object" } → "json"
    #   { "type": "json_schema", "json_schema": { "schema": {...} } } → <schema>
    response_format = obj["response_format"]
    if response_format
      ollama_format = translate_response_format_for_ollama(response_format)
      body["format"] = ollama_format if ollama_format
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
          Monadic::Utils::ExtraLogger.log { "[Ollama] Endpoint not found on attempt #{attempt + 1}/#{MAX_RETRIES}" }
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
        Monadic::Utils::ExtraLogger.log { "[Ollama] Connection attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.message}" }
        OllamaHelper.reset_endpoint_cache
        sleep RETRY_DELAY
      end
    end

    if last_error
      error_message = "Ollama is not reachable. Please ensure Ollama is running. (#{last_error.message})"
      Monadic::Utils::ExtraLogger.log { "[Ollama] #{error_message}" }
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
      Monadic::Utils::ExtraLogger.log { "[Ollama API Error] #{error_report}" }
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
      block&.call res
      return [res]
    end

    process_json_data(app, session, res.body, call_depth, &block)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Ollama] Unexpected error: #{e.message}" }
    Monadic::Utils::ExtraLogger.log { "[Ollama] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    OllamaHelper.reset_endpoint_cache
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}" }
    block&.call res
    [res]
  end

  def process_json_data(app, session, body, call_depth, &block)
    Monadic::Utils::ExtraLogger.log { "Processing Ollama streaming response" }

    obj = session[:parameters]

    # Show Thinking toggle: default to true when unset, disable only on an
    # explicit false/"false". Some thinking models ignore the `think:false`
    # request parameter so we filter at emit time regardless.
    show_thinking_param = obj["show_thinking"]
    show_thinking_enabled = show_thinking_param.nil? ||
                             ![false, "false"].include?(show_thinking_param)

    buffer = String.new
    texts = []
    thinking_texts = []
    accumulated_tool_calls = []
    finish_reason = nil
    fragment_sequence = 0

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
          Monadic::Utils::ExtraLogger.log { "Tool calls detected: #{accumulated_tool_calls.length}" }
        end

        # Thinking fragment (Ollama 0.9+ separate `thinking` field when think:true)
        # A single chunk may carry either `content` or `thinking` (or neither),
        # so we check and dispatch each independently.
        #
        # Respect the user's "Show Thinking" toggle: skip emitting thinking
        # fragments to the frontend when disabled. Some Ollama models
        # (e.g. qwen3-vl:*-thinking) emit reasoning regardless of the `think`
        # API parameter, so backend-side filtering is the reliable place to
        # honor the user's UI preference. The fragments are still accumulated
        # internally so `reasoning_content` remains available.
        thinking_fragment = json.dig("message", "thinking").to_s
        if !thinking_fragment.empty?
          emit_thinking = show_thinking_enabled
          if emit_thinking
            res = { "type" => "thinking", "content" => thinking_fragment }
            block&.call res
          end
          thinking_texts << thinking_fragment
        end

        content_fragment = json.dig("message", "content").to_s
        if !content_fragment.empty?
          res = {
            "type" => "fragment",
            "content" => content_fragment,
            "sequence" => fragment_sequence,
            "timestamp" => Time.now.to_f,
            "is_first" => fragment_sequence == 0
          }

          Monadic::Utils::ExtraLogger.log { "Fragment: sequence=#{fragment_sequence}, length=#{content_fragment.length}, content=#{content_fragment.inspect}" }

          fragment_sequence += 1
          block&.call res
          texts << content_fragment
        end
      rescue JSON::ParserError
        # Incomplete JSON, continue buffering
      end
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Ollama Streaming] Error: #{e.message}" }
      Monadic::Utils::ExtraLogger.log { "[Ollama Streaming] Backtrace: #{e.backtrace.first(5).join("\n")}" }
      # Connection dropped mid-stream — invalidate cached endpoint
      OllamaHelper.reset_endpoint_cache
    end

    Monadic::Utils::ExtraLogger.log { "Total fragments processed: #{texts.length}\nTool calls accumulated: #{accumulated_tool_calls.length}" }

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
    thinking_result = thinking_texts.join("")

    if result && !result.empty?
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      message = { "content" => result }
      message["reasoning_content"] = thinking_result unless thinking_result.empty?
      result = {
        "choices" => [{
          "message" => message,
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

      record_tool_call(session, function_name)
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

      # Collect gallery HTML for tool-generated images
      if function_return.is_a?(Hash) && function_return[:gallery_html]
        session[:tool_html_fragments] ||= []
        session[:tool_html_fragments] << function_return[:gallery_html]
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

  # Detect whether an Ollama model supports the `think:true` parameter.
  # Primary source: Ollama's /api/show endpoint returns a `capabilities`
  # array per model (e.g. ["completion","vision","tools","thinking"]).
  # Fallback: if the API call fails, fall back to a name-based heuristic
  # so thinking-named models still work when Ollama is temporarily flaky.
  def supports_thinking?(model_name)
    return false unless model_name.is_a?(String)
    caps = OllamaHelper.fetch_model_capabilities(model_name)
    return caps[:capabilities].include?("thinking") if caps
    # Fallback: name heuristic
    name = model_name.downcase
    name.include?("thinking") || name.include?("-r1") || name.include?("deepseek-r1")
  end

  # Translate Monadic Chat's OpenAI-style response_format into Ollama's
  # `format` parameter. Returns nil for unrecognized shapes so the caller
  # can skip setting `format` entirely rather than sending garbage.
  def translate_response_format_for_ollama(rf)
    rf = JSON.parse(rf) if rf.is_a?(String)
    return nil unless rf.is_a?(Hash)

    case rf["type"] || rf[:type]
    when "json_object"
      "json"
    when "json_schema"
      # OpenAI nests the schema under json_schema.schema
      schema = rf.dig("json_schema", "schema") || rf.dig(:json_schema, :schema)
      schema.is_a?(Hash) ? schema : nil
    else
      # Allow callers to pass a raw JSON Schema directly
      rf.is_a?(Hash) && (rf["type"] || rf[:type]) ? rf : nil
    end
  rescue JSON::ParserError => e
    Monadic::Utils::ExtraLogger.log { "[Ollama] translate_response_format_for_ollama: JSON parse failed: #{e.message}" }
    nil
  end

  def format_tools_for_ollama(tools_config)
    # Ollama uses OpenAI-compatible tool format
    return [] unless tools_config

    # Tools arrive from app_data.rb as a JSON string (see app_data.rb:78-82
    # which calls `.to_json` on the Array/Hash before sending via WebSocket).
    # Parse here so the case statement below can handle it as structured data.
    if tools_config.is_a?(String)
      return [] if tools_config.strip.empty?
      begin
        tools_config = JSON.parse(tools_config)
      rescue JSON::ParserError => e
        Monadic::Utils::ExtraLogger.log { "[Ollama] format_tools_for_ollama: JSON parse failed: #{e.message}" }
        return []
      end
    end

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
