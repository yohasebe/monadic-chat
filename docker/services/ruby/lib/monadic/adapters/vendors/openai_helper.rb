# frozen_string_literal: true

require 'fileutils'
require 'base64'
require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/debug_helper"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require_relative "../../utils/pdf_storage_config"
require_relative "../../utils/json_repair"
require_relative "../../monadic_provider_interface"
require_relative "../base_vendor_helper"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"
module OpenAIHelper
  include BaseVendorHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.openai.com/v1"
  REASONING_CONTEXT_MAX = 3

  OPEN_TIMEOUT = 20
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  MODELS_N_LATEST = -1

  # NOTE: This list intentionally remains (partial string match)
  # Why it exists:
  # - OpenAI's /models endpoint returns many non-chat SKUs (embeddings, TTS, moderation,
  #   realtime, legacy families, image generators, etc.). Our UI lists available chat models,
  #   so we defensively filter out obvious non-chat categories here to avoid confusing users.
  # - This filter is ONLY used for model discovery (list_models). Capability gating elsewhere
  #   must be driven by model_spec (SSOT).
  # Trade-offs:
  # - We prefer spec-driven allow/deny decisions, but spec may not include every SKU returned
  #   by the provider. Keeping this coarse deny-list avoids surfacing irrelevant models when
  #   spec coverage is incomplete.
  # Future direction:
  # - If provider returns richer metadata (categories/endpoints), or once spec coverage is
  #   complete for discovery, we can remove this and rely solely on spec.
  EXCLUDED_MODELS = [
    "vision",
    "instruct",
    "realtime",
    "audio",
    "moderation",
    "embedding",
    "tts",
    "davinci",
    "babbage",
    "turbo",
    "dall-e",
    "whisper",
    "gpt-3.5",
    "gpt-4-",
    "o1-preview",
    "search",
    "trascribe",
    "computer-use",
    "image"
  ]

  # Reasoning detection is spec-driven (see model_spec: reasoning_effort)

  # Tool capability is determined by model_spec (tool_capability: true/false)


  # Streaming support is spec-driven (supports_streaming: true/false)
  
  # Latency notification is spec/config-driven (e.g., model_spec: latency_tier: "slow")
  

  # Native OpenAI web search tool configuration for responses API
  NATIVE_WEBSEARCH_TOOL = {
    type: "web_search_preview"
  }
  
  # Built-in tools available in Responses API
  RESPONSES_API_BUILTIN_TOOLS = {
    "web_search" => { type: "web_search_preview" },
    "file_search" => ->(vector_store_ids: [], max_num_results: 20) {
      {
        type: "file_search",
        vector_store_ids: vector_store_ids,
        max_num_results: max_num_results
      }
    },
    "code_interpreter" => { type: "code_interpreter" },
    "computer_use" => ->(display_width: 1280, display_height: 720) {
      {
        type: "computer_use",
        display_width: display_width,
        display_height: display_height
      }
    },
    "image_generation" => { type: "image_generation" },
    "mcp" => ->(method:, server:) {
      {
        type: "mcp",
        method: method,
        server: server
      }
    }
  }

  SMART_QUOTE_REPLACEMENTS = {
    "“" => '"',
    "”" => '"',
    "„" => '"',
    "‟" => '"',
    "«" => '"',
    "»" => '"',
    "＂" => '"',
    "〝" => '"',
    "〞" => '"',
    "﹁" => '"',
    "﹂" => '"',
    "﹃" => '"',
    "﹄" => '"',
    "‘" => "'",
    "’" => "'",
    "‚" => "'",
    "‛" => "'",
    "‹" => "'",
    "›" => "'",
    "＇" => "'"
  }.freeze

  # --- PDF storage routing helpers (DocumentStore switching) ---
  def get_current_app_key(session)
    raw = (defined?(session) ? (session.dig(:parameters, "app_name") || session[:current_app]) : nil)
    raw = 'default' if raw.nil? || raw.to_s.strip.empty?
    if defined?(Monadic::Utils::DocumentStoreRegistry)
      Monadic::Utils::DocumentStoreRegistry.sanitize_app_key(raw)
    else
      raw.to_s.strip.downcase.gsub(/[^a-z0-9_\-]/, '_')
    end
  end

  def resolve_openai_vs_id(session)
    # Per-instance cache keyed by session-scoped cache version to avoid stale values
    ver = (defined?(session) && session && session[:pdf_cache_version]) || 0
    if instance_variable_defined?(:@cached_vs_id) && instance_variable_defined?(:@cached_vs_id_version)
      return @cached_vs_id if @cached_vs_id_version == ver
    end
    vs_id = nil
    begin
      # 1) session
      vs_id ||= (defined?(session) ? session[:openai_vector_store_id] : nil)
      # 2) app-specific ENV
      if vs_id.nil? && defined?(CONFIG)
        app_key = get_current_app_key(session).upcase
        app_env = CONFIG["OPENAI_VECTOR_STORE_ID__#{app_key}"] rescue nil
        vs_id = app_env.to_s.strip unless app_env.nil? || app_env.to_s.strip.empty?
      end
      # 3) global ENV (explicit config should take precedence over registry)
      if vs_id.nil? && defined?(CONFIG)
        env_vs = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip rescue ""
        vs_id = env_vs unless env_vs.empty?
      end
      # 4) registry
      if vs_id.nil? && defined?(Monadic::Utils::DocumentStoreRegistry)
        app_key = get_current_app_key(session)
        vs_id ||= Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
      end
      # 5) fallback meta file
      if vs_id.nil? && defined?(Monadic::Utils::Environment)
        meta_path = File.join(Monadic::Utils::Environment.data_path, 'pdf_navigator_openai.json')
        if File.exist?(meta_path)
          begin
            meta = JSON.parse(File.read(meta_path))
            vs_id = meta["vector_store_id"] if meta && meta["vector_store_id"]
          rescue StandardError
            vs_id = nil
          end
        end
      end
    rescue StandardError
      vs_id = nil
    end
    @cached_vs_id = vs_id
    @cached_vs_id_version = ver
    vs_id
  end

  def resolve_pdf_storage_mode(session)
    # Per-instance cache keyed by session-scoped version to avoid stale results
    begin
      if Monadic::Utils::PdfStorageConfig.refresh_from_env
        remove_instance_variable(:@cached_pdf_mode) if instance_variable_defined?(:@cached_pdf_mode)
        remove_instance_variable(:@cached_pdf_mode_version) if instance_variable_defined?(:@cached_pdf_mode_version)
      end
    rescue StandardError
      # Ignore refresh issues and continue with existing cache.
    end
    ver = (defined?(session) && session && session[:pdf_cache_version]) || 0
    if instance_variable_defined?(:@cached_pdf_mode) && instance_variable_defined?(:@cached_pdf_mode_version)
      return @cached_pdf_mode if @cached_pdf_mode_version == ver
    end
    begin
      vs_present = !!resolve_openai_vs_id(session)
      # Fast local presence check (prefer DB-level LIMIT 1; fallback to title listing if unavailable)
      local_present = begin
        if defined?(EMBEDDINGS_DB) && EMBEDDINGS_DB
          if EMBEDDINGS_DB.respond_to?(:any_docs?)
            EMBEDDINGS_DB.any_docs?
          elsif Kernel.respond_to?(:list_pdf_titles, true)
            begin
              titles = Kernel.send(:list_pdf_titles)
              titles.respond_to?(:empty?) ? !titles.empty? : false
            rescue StandardError
              false
            end
          else
            false
          end
        else
          false
        end
      rescue StandardError
        false
      end
      session_mode = (defined?(session) ? session[:pdf_storage_mode].to_s.downcase : '')
      # Session override takes precedence (immediate switch during runtime)
      if session_mode == 'local'
        @cached_pdf_mode = 'local'
        return @cached_pdf_mode
      end
      if session_mode == 'cloud' && vs_present
        @cached_pdf_mode = 'cloud'
        return @cached_pdf_mode
      end

      # Determine configured mode (ENV), with backward compatibility
      env_mode = begin
        m = (defined?(CONFIG) ? (CONFIG["PDF_STORAGE_MODE"] || CONFIG["PDF_DEFAULT_STORAGE"] || 'local') : 'local')
        m.to_s.downcase
      rescue StandardError
        'local'
      end

      # Honor configured mode when available; otherwise fall back to availability
      @cached_pdf_mode = if env_mode == 'cloud' && vs_present
        'cloud'
      elsif env_mode == 'local' && local_present
        'local'
      elsif vs_present
        'cloud'
      elsif local_present
        'local'
      else
        # Neither available; return configured mode (sanitized)
        %w[local cloud].include?(env_mode) ? env_mode : 'local'
      end
      @cached_pdf_mode_version = ver
      @cached_pdf_mode
    rescue StandardError
      @cached_pdf_mode = 'local'
      @cached_pdf_mode_version = ver
      'local'
    end
  end


  WEBSEARCH_PROMPT = <<~TEXT

    Web search is enabled for this conversation. You should proactively use web search whenever:
    - The user asks about current events, news, or recent information
    - The user asks about specific people, companies, organizations, or entities
    - The user asks questions that would benefit from up-to-date or factual information
    - You need to verify facts or get the latest information about something
    - The user asks "who is" or similar questions about people or entities
    
    You don't need to ask permission to search - just search when it would be helpful. The web search happens automatically when you need it.

    Always ensure that your answers are comprehensive, accurate, and support the user's needs with relevant citations. When you find information through web search, provide detailed and informative responses.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs. Example: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT
  


  class << self
    attr_reader :cached_models

    def vendor_name
      "OpenAI"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:openai] if $MODELS[:openai]

      api_key = CONFIG["OPENAI_API_KEY"]
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
          begin
            res_body = JSON.parse(res.body)
          rescue JSON::ParserError => e
            DebugHelper.debug("Invalid JSON from OpenAI models API: #{res.body[0..200]}", "api", level: :error)
            return []
          end
          
          if res_body && res_body["data"]
            # Cache the filtered and sorted models
            $MODELS[:openai] = res_body["data"].sort_by do |item|
              item["created"]
            end.reverse[0..MODELS_N_LATEST].map do |item|
              item["id"]
              # Filter out excluded models, embedding each string in a regex
            end.reject do |model|
              EXCLUDED_MODELS.any? { |excluded_model| /\b#{excluded_model}\b/ =~ model }
            end
            $MODELS[:openai]
          end
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:openai] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    # Resolve model via SSOT only (no hardcoded fallback)
    model = model.to_s.strip
    model = nil if model.empty?
    model ||= SystemDefaults.get_default_model('openai')
    
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    api_key = CONFIG["OPENAI_API_KEY"]
    
    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Basic request body
    body = {
      "model" => model,
      "stream" => false
    }
    
    # Add messages from options if available
    if options["messages"]
      body["messages"] = options["messages"]
    elsif options["message"]
      body["messages"] = [{ "role" => "user", "content" => options["message"] }]
    end
    
    # Add temperature only when supported by the model
    if options["temperature"]
      begin
        # Treat models marked as reasoning or responses API as not supporting custom temperature
        # Also explicitly exclude GPT-5 models
        disallow_sampling = Monadic::Utils::ModelSpec.is_reasoning_model?(model) ||
                            Monadic::Utils::ModelSpec.responses_api?(model) ||
                            model.to_s.downcase.include?("gpt-5")
        body["temperature"] = options["temperature"].to_f unless disallow_sampling
      rescue StandardError
        # On any spec lookup failure, be conservative and omit temperature
      end
    end

    # Add reasoning_effort when provided and model supports it (reasoning family)
    if options["reasoning_effort"]
      begin
        if Monadic::Utils::ModelSpec.is_reasoning_model?(model)
          body["reasoning_effort"] = options["reasoning_effort"]
        end
      rescue StandardError
        # ignore if spec lookup fails
      end
    end
    
    # Add response_format if specified (for structured JSON output)
    if options["response_format"] || options[:response_format]
      response_format = options["response_format"] || options[:response_format]
      body["response_format"] = response_format.is_a?(Hash) ? response_format : { "type" => "json_object" }
      
      DebugHelper.debug("Using response format: #{body['response_format'].inspect}", "api")
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
      # Properly read response body content
      response_body = res.body.respond_to?(:read) ? res.body.read : res.body.to_s
      parsed_response = JSON.parse(response_body)
      return parsed_response.dig("choices", 0, "message", "content")
    else
      # Properly read error response body content
      error_body = res && res.body ? (res.body.respond_to?(:read) ? res.body.read : res.body.to_s) : nil
      error_response = error_body ? JSON.parse(error_body) : { "error" => "No response received" }
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "OpenAI",
        message: error_response["error"]["message"] || error_response["error"],
        code: res.status.code
      )
    end
  rescue StandardError => e
    return Monadic::Utils::ErrorFormatter.api_error(
      provider: "OpenAI",
      message: e.message
    )
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    
    app = obj["app_name"]
    api_key = CONFIG["OPENAI_API_KEY"]
    
    # Log removed - not needed in production

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    reasoning_effort = obj["reasoning_effort"]
    verbosity = obj["verbosity"]  # GPT-5 verbosity setting

    # Handle max_tokens
    max_completion_tokens = obj["max_completion_tokens"]&.to_i || obj["max_tokens"]&.to_i

    # Store the original model for comparison later
    original_user_model = model

    # If no max_tokens specified, use model defaults for reasoning models
    if max_completion_tokens.nil? || max_completion_tokens == 0
      require_relative '../../utils/model_token_utils'
      max_completion_tokens = ModelTokenUtils.get_max_tokens(original_user_model)
      DebugHelper.debug("OpenAI: Using default max_tokens #{max_completion_tokens} for model #{original_user_model}", category: :api, level: :info)
    end

    # Get image generation flag
    image_generation = obj["image_generation"] == "true"

    # Define shared folder path based on environment
    shared_folder = Monadic::Utils::Environment.shared_volume

    temperature = obj["temperature"].to_f
    presence_penalty = obj["presence_penalty"].to_f
    frequency_penalty = obj["frequency_penalty"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil
    
    # Check if original model requires Responses API via model_spec
    use_responses_api = Monadic::Utils::ModelSpec.responses_api?(original_user_model)
    
    # Check if web search is enabled in settings
    # Handle both string and boolean values for websearch parameter
    websearch_enabled = obj["websearch"] == "true" || obj["websearch"] == true
    
    # Check if web search is enabled
    # OpenAI web search requires Responses API according to official documentation
    # https://platform.openai.com/docs/guides/tools-web-search
    use_responses_api_for_websearch = websearch_enabled &&
                                      Monadic::Utils::ModelSpec.supports_web_search?(model)
    
    DebugHelper.debug("OpenAI web search check - websearch_enabled: #{websearch_enabled}, model: #{model}, use_responses_api_for_websearch: #{use_responses_api_for_websearch}", category: :api, level: :debug)
    # Model-spec driven; no local hardcoded lists
    
    # OpenAI only uses native web search, no Tavily support
    
    # Store these variables in obj for later use in the method
    obj["websearch_enabled"] = websearch_enabled
    obj["use_responses_api_for_websearch"] = use_responses_api_for_websearch
    
    # Update use_responses_api flag if we need it for websearch
    if use_responses_api_for_websearch && !use_responses_api
      use_responses_api = true
    end

    # Force Responses API when Cloud PDF file_search should be available
    begin
      app_has_docstore = APPS[app]&.settings&.[]("pdf_vector_storage")
      if app_has_docstore
        vs_id_forcing = resolve_openai_vs_id(session)
        mode_forcing = resolve_pdf_storage_mode(session)
        if vs_id_forcing && mode_forcing != 'local'
          use_responses_api = true
          DebugHelper.debug("OpenAI: Forcing Responses API due to file_search availability (vs_id present, mode=#{mode_forcing})", category: :api, level: :info)
        end
      end
    rescue StandardError
      # conservative: do nothing
    end

    message = nil
    data = nil

    if role != "tool"
      message = obj["message"].to_s
      
      # Reset model switch notification flag for new user messages
      if role == "user"
        session.delete(:model_switch_notified)
        if app.to_s == "MonadicHelpOpenAI"
          obj["help_topics_call_count"] = 0
          obj.delete("help_topics_prev_queries")
        end
      end

      # Apply monadic transformation if needed (for display purposes only)
      # The actual API transformation happens later when building messages

      html = markdown_to_html(message, mathjax: obj["mathjax"])

      if message != "" && role == "user"

        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "role" => role,
                  "lang" => detect_language(message)
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages] ||= []
    session[:messages].each { |msg| msg["active"] = false if msg }
    context = [session[:messages].first].compact
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size).compact
    end
    context.each { |msg| msg["active"] = true if msg }

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
    }

    # Check if model supports reasoning via model_spec (reasoning_effort present)
    reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(model, "reasoning_effort")
    non_stream_model = (Monadic::Utils::ModelSpec.get_model_property(model, "supports_streaming") == false)
    tool_capability = Monadic::Utils::ModelSpec.get_model_property(model, "tool_capability") == true
    non_tool_model = !tool_capability
    supports_websearch = Monadic::Utils::ModelSpec.supports_web_search?(model)
    
    # If websearch is enabled but the model doesn't support it, disable websearch
    # (No fallback - let the model work without web search capability)
    if websearch_enabled && !supports_websearch && !use_responses_api
      websearch_enabled = false
      
      # Send system notification that web search is not available
      if block
        system_msg = {
          "type" => "system_info", 
          "content" => "Web search is not available for model #{model}. Proceeding without web search."
        }
        block.call system_msg
      end
    end
    
    # Determine which prompt to use based on web search type
    websearch_prompt = if websearch_enabled
                       WEBSEARCH_PROMPT
                     else
                       nil
                     end

    # Add verbosity for models that support it (via ModelSpec)
    if verbosity && Monadic::Utils::ModelSpec.supports_verbosity?(model)
      body["verbosity"] = verbosity
    end
    
    if reasoning_model
      body["reasoning_effort"] = reasoning_effort || "medium"
      body.delete("temperature")
      body.delete("frequency_penalty")
      body.delete("presence_penalty")
      body.delete("max_completion_tokens")
    elsif supports_websearch
      body.delete("n")
      body.delete("temperature")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")
    else
      body["n"] = 1
      # Don't add temperature for GPT-5 models
      unless model.to_s.downcase.include?("gpt-5")
        body["temperature"] = temperature if temperature
        body["presence_penalty"] = presence_penalty if presence_penalty
        body["frequency_penalty"] = frequency_penalty if frequency_penalty
      end
      body["max_completion_tokens"] = max_completion_tokens if max_completion_tokens 

      if obj["response_format"]
        body["response_format"] = APPS[app].settings["response_format"]
      end

      # Use the new unified interface for monadic mode
      body = configure_monadic_response(body, :openai, app, use_responses_api)
    end

    if non_stream_model
      body["stream"] = false
    else
      body["stream"] = true
    end

    # GPT-5 models can use tools even though they are reasoning models
    # Only skip tools when the model_spec marks tool_capability as false
    # For reasoning models using Responses API, keep tools even on tool responses
    skip_tools = non_tool_model || (role == "tool" && !use_responses_api)
    
    if skip_tools
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] OpenAI: Skipping tools because non_tool_model=#{non_tool_model} or role='#{role}'")
        extra_log.close
      end
      body.delete("tools")
      body.delete("response_format")
    else
      # Parse tools if they're sent as JSON string
      tools_param = obj["tools"]
      if tools_param.is_a?(String)
        begin
          tools_param = JSON.parse(tools_param)
        rescue JSON::ParserError
          tools_param = nil
        end
      end
      
      # Get tools from app settings first
      app_tools = APPS[app]&.settings&.[]("tools")
      # For first turn in cloud mode, suppress local DB tools to force cloud file_search first
      begin
        app_has_docstore = APPS[app]&.settings&.[]("pdf_vector_storage")
        user_turns = (session[:messages] || []).count { |m| m && m["role"] == "user" }
        first_turn = user_turns <= 1
        if app_has_docstore && first_turn
          mode_now = resolve_pdf_storage_mode(session)
          if mode_now != 'local' && app_tools && !app_tools.empty?
            local_pdf_tools = %w[find_closest_text get_text_snippet list_titles find_closest_doc get_text_snippets]
            filtered = app_tools.reject do |t|
              fn = t.is_a?(Hash) ? t.dig("function", "name") : nil
              local_pdf_tools.include?(fn)
            end
            if filtered.size != app_tools.size
              app_tools = filtered
              DebugHelper.debug("OpenAI: Suppressed local PDF tools on first turn to force cloud search", category: :api, level: :info)
            end
          end
        end
      rescue StandardError
        # keep app_tools as-is on any error
      end
      # For PDF Navigator, suppress local DB tools when routing in cloud mode
      begin
        current_app = obj["app"] || (defined?(session) ? session.dig(:parameters, "app_name") : nil)
        if current_app.to_s == 'PDFNavigatorOpenAI'
          resolved_mode = resolve_pdf_storage_mode(session)
          if resolved_mode == 'cloud'
            app_tools = []
            DebugHelper.debug("PDFNavigator: Suppressing local tools (cloud mode)", category: :api, level: :debug)
          end
        end
      rescue StandardError
        # keep app_tools as-is on any error
      end
      
      # Tool detection logging removed - not needed in production
      
      if tools_param && !tools_param.empty?
        # If tools_param is provided, prefer app_tools if available
        if app_tools && !app_tools.empty?
          body["tools"] = app_tools
        elsif tools_param.is_a?(Array) && !tools_param.empty?
          # Use tools from request if app doesn't have them
          body["tools"] = tools_param
        else
          body["tools"] = []
        end
        
        # Web search for OpenAI is handled through Responses API, not regular chat API tools
        
        body["tools"].uniq!
      elsif app_tools && !app_tools.empty?
        # If no tools_param but app has tools, use them
        body["tools"] = app_tools
      else
        # No tools available from either source
        body.delete("tools")
        body.delete("tool_choice")
      end
      
      # Add file_search tool for Chat Completions API as well (when app opts into pdf_vector_storage)
      begin
        app_has_docstore = APPS[app]&.settings&.[]("pdf_vector_storage")
        # Only attach on Chat path when we are NOT going to use Responses API
        if app_has_docstore && !use_responses_api
          vs_id = resolve_openai_vs_id(session)
          resolved_mode = resolve_pdf_storage_mode(session)
          if vs_id && resolved_mode != 'local'
            body["tools"] ||= []
            body["tools"] << {
              "type" => "file_search",
              "description" => "Search for information in PDFs stored in OpenAI Vector Store.",
              "file_search" => {
                "vector_store_ids" => [vs_id],
                "max_num_results" => 20
              }
            }
            DebugHelper.debug("OpenAI(Chat): Adding file_search tool with vector_store_id=#{vs_id}", category: :api, level: :debug)
          else
            DebugHelper.debug("OpenAI(Chat): Skipping file_search (app_has_docstore=#{!!app_has_docstore}, vs_id_present=#{!!vs_id}, mode=#{resolved_mode}, app=#{app})", category: :api, level: :debug)
          end
        else
          DebugHelper.debug("OpenAI(Chat): Skipping file_search (use_responses_api=#{use_responses_api}, app_has_docstore=#{!!app_has_docstore}, app=#{app})", category: :api, level: :debug)
        end
      rescue StandardError => e
        DebugHelper.debug("OpenAI(Chat): Failed to attach file_search tool: #{e.message}", category: :api, level: :warning)
      end
      
      # Basic tool logging kept for debugging tool issues
    end

    
    # The context is added to the body
    messages_containing_img = false
    image_file_references = []
    
    # Process images if this is an image generation request
    if image_generation && role == "user"
      context.compact.each do |msg|
        if msg["images"]
          msg["images"].each do |img|
            begin
              # Skip if already a reference to shared folder
              next if img["data"].to_s.start_with?("/data/")
              
              # Generate a unique filename
              timestamp = Time.now.to_i
              random_suffix = SecureRandom.hex(4)
              ext = File.extname(img["data"].to_s).empty? ? ".png" : File.extname(img["data"].to_s)
              
              # Check if this is a mask image by looking at the title or is_mask flag
              is_mask = img["is_mask"] == true || img["title"].to_s.start_with?("mask__")
              
              # Use appropriate prefix based on image type
              prefix = is_mask ? "mask__" : "img_"
              new_filename = "#{prefix}#{timestamp}_#{random_suffix}#{ext}"
              target_path = File.join(shared_folder, new_filename)
              
              # Copy the file to shared folder if it exists locally
              if File.exist?(img["data"].to_s)
                FileUtils.cp(img["data"].to_s, target_path)
                # Store the full path for internal use
                image_file_references << "/data/#{new_filename}"
              # Handle data URIs
              elsif img["data"].to_s.start_with?("data:")
                # Extract and save base64 data
                data_uri = img["data"].to_s
                content_type, encoded_data = data_uri.match(/^data:([^;]+);base64,(.+)$/)[1..2]
                decoded_data = Base64.decode64(encoded_data)
                
                # Write to file
                File.open(target_path, 'wb') do |f|
                  f.write(decoded_data)
                end
                
                # Store the full path for internal use
                image_file_references << "/data/#{new_filename}"
              end
            rescue StandardError => e
              puts "Error processing image for generation: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            end
          end
          
          # Remove images from message to prevent them being sent to vision API
          msg.delete("images")
        end
      end
    end
    
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user" && !image_generation
        msg["images"].each do |img|
          messages_containing_img = true
          if img["type"] == "application/pdf"
            # PDFs need special handling
            message["content"] << {
              "type" => "file",
              "file" => {
                "file_data" => img["data"],
                "filename" => img["title"]
              }
            }
          else
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
          end
        end
      end
      message
    end

    # "system" role must be replaced with "developer" for reasoning models
    if reasoning_model
      num_system_messages = 0
      body["messages"].each do |msg|
        if msg["role"] == "system"
          msg["role"] = "developer" 
          msg["content"].each do |content_item|
            if content_item["type"] == "text" && num_system_messages == 0
              if websearch_enabled && websearch_prompt
                text = "Web search enabled\n---\n" + content_item["text"] + "\n---\n" + websearch_prompt
              else
                text = "Formatting re-enabled\n---\n" + content_item["text"]
              end
              
              # Inject language preference from runtime settings
              if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
                language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
                if CONFIG["EXTRA_LOGGING"]
                  puts "[DEBUG] OpenAI Reasoning Model Language Injection:"
                  puts "  - Language: #{session[:runtime_settings][:language]}"
                  puts "  - Prompt length: #{language_prompt.length}"
                end
                text += "\n\n" + language_prompt unless language_prompt.empty?
              end
              
              content_item["text"] = text
            end
          end
          num_system_messages += 1
        end
      end
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
      # Do not include tool_choice when processing tool results
      body.delete("tool_choice") if body["tool_choice"]
    end

    last_text = context.last&.dig("text")

    # Split the last message if it matches /\^__DATA__$/
    if last_text&.match?(/\^\s*__DATA__\s*$/m)
      last_text, data = last_text.split("__DATA__")
      # set last_text to the last message in the context
      context.last["text"] = last_text if context.last
    end

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    # If this is an image generation request, add the image filenames to the last message
    if image_generation && !image_file_references.empty? && role == "user"
      # Separate regular images and mask images
      regular_images = []
      mask_images = []
      
      image_file_references.each do |img_path|
        filename = File.basename(img_path)
        if filename.start_with?("mask__")
          mask_images << filename
        else
          regular_images << filename
        end
      end
      
      img_references_text = ""
      
      # Add regular images if any
      unless regular_images.empty?
        img_references_text += "\n\nAttached images:\n"
        regular_images.each do |filename|
          img_references_text += "- #{filename}\n"
        end
      end
      
      # Add mask images with clear indication for editing
      unless mask_images.empty?
        img_references_text += "\n\nMask images for editing (MUST use edit operation):\n"
        mask_images.each do |mask_filename|
          # Extract the original image name from mask filename
          # mask__1756299902_677f71fa.png -> img_1756299902_677f71fa.png
          original_name = mask_filename.sub(/^mask__/, "img_")
          img_references_text += "- #{mask_filename} (mask for editing)\n"
          
          # Check if we have a corresponding original image
          if regular_images.include?(original_name)
            img_references_text += "  Original image: #{original_name}\n"
          end
        end
        img_references_text += "\nIMPORTANT: You have mask files attached. You MUST use the 'edit' operation with these masks, NOT 'generate'.\n"
      end
      
      if last_text.to_s != ""
        last_text += img_references_text
      else
        # If there's no last text, add to the last message in context
        if context.last && context.last["text"]
          context.last["text"] += img_references_text
        end
      end
    end

    if last_text.to_s != "" && prompt_suffix.to_s != ""
      new_text = last_text.to_s + "\n\n" + prompt_suffix.strip
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
        "content" => [{ "type" => "text", "text" => data.strip }]
      }
      body["prediction"] = {
        "type" => "content",
        "content" => data.strip
      }
    end
    
    # Apply monadic transformation to the last user message for API
    if obj["monadic"].to_s == "true" && body["messages"].any? && 
       body["messages"].last["role"] == "user" && role == "user"
      last_msg = body["messages"].last
      if last_msg["content"].is_a?(Array)
        text_content = last_msg["content"].find { |c| c["type"] == "text" }
        if text_content
          original_text = text_content["text"]
          monadic_text = apply_monadic_transformation(original_text, app, "user")
          text_content["text"] = monadic_text
        end
      end
    end

    # initial prompt in the body is appended with the settings["system_prompt_suffix" and web search prompt if enabled
    if initial_prompt.to_s != ""
      parts = [initial_prompt.to_s]
      
      # Add web search prompt for non-reasoning models using Responses API
      if websearch_enabled && websearch_prompt && !reasoning_model
        parts << websearch_prompt.strip
      end
      
      # Add system prompt suffix if present
      if obj["system_prompt_suffix"].to_s != ""
        parts << obj["system_prompt_suffix"].strip
      end
      
      # Add language preference from runtime settings
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] OpenAI Language Injection Check:"
        extra_log.puts "  - session.object_id = #{session.object_id}"
        extra_log.puts "  - session[:runtime_settings] exists? = #{!session[:runtime_settings].nil?}"
        extra_log.puts "  - runtime_settings content = #{session[:runtime_settings].inspect}" if session[:runtime_settings]
        extra_log.puts "  - language = #{session[:runtime_settings][:language]}" if session[:runtime_settings]
        extra_log.close
      end
      
      if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
        language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts "[#{Time.now}] OpenAI Language Injection ACTIVE:"
          extra_log.puts "  - Language: #{session[:runtime_settings][:language]}"
          extra_log.puts "  - Prompt length: #{language_prompt.length}"
          extra_log.puts "  - Adding to parts: #{!language_prompt.empty?}"
          extra_log.close
        end
        parts << language_prompt.strip unless language_prompt.empty?
      elsif CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] OpenAI Language Injection SKIPPED - conditions not met"
        extra_log.close
      end
      
      if parts.length > 1
        new_text = parts.join("\n\n")
        body["messages"].first["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = new_text
          end
        end
      end
    end

    if messages_containing_img
      # Remove automatic fallback to a vision-capable model.
      # Instead, if the chosen model does not support vision, return an explicit error.
      supports_vision = !!obj["vision_capability"]
      begin
        # Fallback check via app helper (returns model string if capable, else nil)
        supports_vision ||= !!MonadicApp.check_vision_capability(body["model"]) if defined?(MonadicApp)
      rescue StandardError
        # If capability check fails, assume not supported and proceed to error below
      end

      unless supports_vision
        formatted_error = Monadic::Utils::ErrorFormatter.api_error(
          provider: "OpenAI",
          message: "This model does not support image input (vision). Please select a vision-capable model.",
          code: 400
        )
        error_res = { "type" => "error", "content" => formatted_error }
        block&.call error_res
        return [error_res]
      end

      # Clean up any incompatible params when sending images
      body.delete("stop")
    end

    # Handle initiate_from_assistant case where only system message exists
    # This matches Perplexity's working implementation
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      # Generic prompt that asks the assistant to follow system instructions
      initial_message = "Please proceed according to your system instructions and introduce yourself."
      
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => initial_message }]
      }
    end

    # Determine which API endpoint to use
    if use_responses_api
      # Use responses API for o3-pro
      target_uri = "#{API_ENDPOINT}/responses"
      
      # Send processing status only for long-running models
      is_slow = Monadic::Utils::ModelSpec.get_model_property(original_user_model, "latency_tier") == "slow" ||
                Monadic::Utils::ModelSpec.get_model_property(original_user_model, "is_slow_model") == true
      if block && is_slow
        processing_msg = {
          "type" => "processing_status",
          "content" => "This may take a while."
        }
        block.call processing_msg
      end
      
      # Convert messages format to responses API input format
      # Responses API uses different content types than chat API
      input_messages = body["messages"].map do |msg|
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        
        # Handle tool messages for Responses API
        if role == "tool"
          # Convert to function_call_output format for Responses API
          {
            "type" => "function_call_output",
            "call_id" => msg["tool_call_id"] || msg["call_id"] || msg[:tool_call_id] || msg[:call_id],
            "output" => content.to_s
          }
        else
          # For assistant messages, we need to include tool_calls if present
          if role == "assistant" && (msg["tool_calls"] || msg[:tool_calls])
            tool_calls = msg["tool_calls"] || msg[:tool_calls]
            # Convert assistant message with tool calls for Responses API
            output_items = []

            # Add reasoning content if present
            reasoning_items_payload = msg["reasoning_items"] || msg[:reasoning_items]
            if reasoning_items_payload && !reasoning_items_payload.empty?
              Array(reasoning_items_payload).each do |entry|
                unless entry.is_a?(Hash)
                  next
                end
                normalized = entry.transform_keys { |k| k.to_s }
                normalized["type"] ||= "reasoning"
                output_items << normalized
              end
            else
              reasoning_text = msg["reasoning_content"] || msg[:reasoning_content]
              if reasoning_text && !reasoning_text.to_s.strip.empty?
                output_items << {
                  "type" => "reasoning",
                  "content" => [
                    {
                      "type" => "output_text",
                      "text" => reasoning_text.to_s
                    }
                  ]
                }
              end
            end

            # Add text content if present
            if content
              output_items << {
                "type" => "message",
                "role" => "assistant",
                "content" => [
                  {
                    "type" => "output_text",
                    "text" => content.to_s
                  }
                ]
              }
            end
            
            # Add function calls
            tool_calls.each do |tool_call|
              call_id = tool_call["id"] || tool_call[:id]
              # Generate fc_ prefixed ID if needed
              fc_id = call_id.start_with?("fc_") ? call_id : "fc_#{SecureRandom.hex(16)}"
              
              output_items << {
                "type" => "function_call",
                "id" => fc_id,
                "call_id" => call_id,
                "name" => tool_call.dig("function", "name") || tool_call.dig(:function, :name),
                "arguments" => tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
              }
            end
            
            output_items
          else
            # Responses API uses specific text types based on role
            # System and user messages use "input_text", assistant messages use "output_text"
            text_type = (role == "assistant") ? "output_text" : "input_text"
            
            # Handle messages with complex content (text + images)
            if content.is_a?(Array)
              # Convert content types for responses API
              converted_content = content.map do |item|
                case item["type"]
                when "text"
                  {
                    "type" => text_type,
                    "text" => item["text"]
                  }
                when "image_url"
                  # For Responses API, keep the image_url format as specified in the documentation
                  {
                    "type" => "input_image",
                    "image_url" => item["image_url"]["url"]
                  }
                when "file"
                  # For Responses API, convert PDF file format
                  {
                    "type" => "input_file",
                    "filename" => item["file"]["filename"],
                    "file_data" => item["file"]["file_data"]
                  }
                else
                  item  # Keep as is for unknown types
                end
              end
              
              {
                "role" => role,
                "content" => converted_content
              }
            else
              # Simple text content
              {
                "role" => role,
                "content" => [
                  {
                    "type" => text_type,
                    "text" => content.to_s
                  }
                ]
              }
            end
          end
        end
      end.flatten.compact  # Flatten and remove nil entries
      
      # Create responses API body
      responses_body = {
        "model" => body["model"],
        "input" => input_messages,
        "stream" => body["stream"] || false,  # Default to false for responses API (o3-pro doesn't support streaming yet)
        "store" => false  # Disable storage for lower latency
      }
      
      # Add reasoning configuration for reasoning models
      if body["reasoning_effort"]
        responses_body["reasoning"] = {
          "effort" => body["reasoning_effort"],
          "summary" => "auto"  # Required to receive reasoning content in output
        }

        if obj["reasoning_context"].is_a?(Array) && !obj["reasoning_context"].empty?
          responses_body["reasoning"]["context"] = JSON.parse(JSON.generate(obj["reasoning_context"]))
        end
      end

      # Check if this is a reasoning model or GPT-5 (which doesn't support temperature)
      is_reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(model, "reasoning_effort")
      is_gpt5_model = model.to_s.downcase.include?("gpt-5")

      # Add temperature and sampling parameters only if supported
      # GPT-5 models and reasoning models don't support temperature/top_p
      unless is_reasoning_model || is_gpt5_model
        responses_body["temperature"] = body["temperature"] if body["temperature"]
        responses_body["top_p"] = body["top_p"] if body["top_p"]
      end

      # Explicitly remove temperature/top_p for GPT-5 models (defensive programming)
      if is_gpt5_model
        responses_body.delete("temperature")
        responses_body.delete("top_p")
      end
      
      # Add max_output_tokens if specified
      if body["max_completion_tokens"] || max_completion_tokens
        responses_body["max_output_tokens"] = body["max_completion_tokens"] || max_completion_tokens
      end
      
      # Add instructions (system prompt) if available
      if body["messages"].first && (body["messages"].first["role"] == "developer" || body["messages"].first["role"] == "system")
        # Extract the first developer/system message as instructions
        system_msg = body["messages"].first
        if system_msg["content"].is_a?(Array)
          instructions_text = system_msg["content"].find { |c| c["type"] == "text" }&.dig("text")
        else
          instructions_text = system_msg["content"]
        end
        
        if instructions_text
          responses_body["instructions"] = instructions_text
          # Remove the system message from input_messages as it's now in instructions
          # Find and remove it from input_messages (not body["messages"])
          if input_messages.first && (input_messages.first["role"] == "developer" || input_messages.first["role"] == "system")
            input_messages.shift
          end
        end
      end

      # If a Vector Store is configured and the app enables pdf_vector_storage,
      # gently steer the model to use file_search in cloud mode.
      begin
        current_app = obj["app"] || (defined?(session) ? session.dig(:parameters, "app_name") : nil)
        vs_hint_id = resolve_openai_vs_id(session)
        resolved_mode = resolve_pdf_storage_mode(session)
        app_has_docstore = begin
          APPS[current_app]&.settings&.[]("pdf_vector_storage")
        rescue
          false
        end

        if vs_hint_id && app_has_docstore && resolved_mode != 'local'
          extra = <<~TXT
          \n\nDOCUMENT SEARCH POLICY (Hybrid Ready):
          - You have two sources: Local PDF DB (functions) and Cloud File Search (vector store).
          - Call at most ONCE per source for a given user request.
          - Prefer the source that is more likely to contain the answer. If the first source returns no relevant results, try the other ONCE.
          - Do NOT loop or repeat similar searches. If both yield nothing, explain the limitation to the user.

          When you cite results, include a compact metadata footer after an `---` divider with:
          Doc Title, Snippet tokens, Snippet position. For example:
          ---
          Doc Title: <title>
          Snippet tokens: <tokens>
          Snippet position: <position>/<total>
          TXT
          responses_body["instructions"] = (responses_body["instructions"] || "") + extra
        end
      rescue StandardError
        # no-op hint
      end
      
      # Ensure we have at least one message in input
      if input_messages.empty?
        # Add a default user message if input is empty
        input_messages << {
          "role" => "user",
          "content" => [
            {
              "type" => "input_text",
              "text" => "Let's start"
            }
          ]
        }
      end
      
      # Support for stateful conversations (future use)
      if obj["previous_response_id"]
        responses_body["previous_response_id"] = obj["previous_response_id"]
      end
      
      # Support for background processing (future use)
      if obj["background"]
        responses_body["background"] = true
      end
      
      # We'll handle structured outputs after tools are added (moved below)
      
      # Add web search tool for responses API if needed
      if obj["use_responses_api_for_websearch"]
        # Add native web search tool for responses API
        responses_body["tools"] = [NATIVE_WEBSEARCH_TOOL]
        DebugHelper.debug("OpenAI: Adding web_search_preview tool via Responses API", category: :api, level: :debug)
        DebugHelper.debug("Responses API body tools: #{responses_body['tools'].inspect}", category: :api, level: :debug)
        
      end
      
      # Enhanced tool support for responses API
      # Check if we have tools to add (either built-in or custom functions)
      if (body["tools"] && !body["tools"].empty?) || obj["responses_api_tools"]
        responses_body["tools"] ||= []
        
        # Add built-in tools if specified
        if obj["responses_api_tools"]
          obj["responses_api_tools"].each do |tool_name, config|
            if RESPONSES_API_BUILTIN_TOOLS[tool_name]
              tool_def = RESPONSES_API_BUILTIN_TOOLS[tool_name]
              # Handle tools that are lambdas (need configuration)
              if tool_def.is_a?(Proc)
                responses_body["tools"] << tool_def.call(**config)
              else
                responses_body["tools"] << tool_def
              end
            end
          end
        end
        
        # Add custom function tools if available
        if body["tools"] && !body["tools"].empty?
          # Convert tools to Responses API format
          # - Functions are flattened
          # - Chat-style file_search entries are normalized to Responses style
          function_tools = body["tools"].map do |tool|
            tool_json = JSON.parse(tool.to_json)
            if tool_json["type"] == "function" && tool_json["function"]
              {
                "type" => "function",
                "name" => tool_json["function"]["name"],
                "description" => tool_json["function"]["description"],
                "parameters" => tool_json["function"]["parameters"]
              }
            elsif tool_json["type"] == "file_search"
              begin
                vs_id_conv = resolve_openai_vs_id(session)
                max_n = tool_json.dig("file_search", "max_num_results") || 8
                {
                  "type" => "file_search",
                  "vector_store_ids" => vs_id_conv ? [vs_id_conv] : [],
                  "max_num_results" => max_n
                }
              rescue StandardError
                tool_json
              end
            else
              tool_json
            end
          end
          
          responses_body["tools"].concat(function_tools)
        end
        
        # Set tool_choice if specified
        if body["tool_choice"]
          responses_body["tool_choice"] = body["tool_choice"]
        end
        
        # Enable parallel tool calls by default
        responses_body["parallel_tool_calls"] = true
        
      end

      # Compatibility: some models/efforts do not allow tools with reasoning enabled.
      # If file_search (or any tool) is present alongside reasoning, drop reasoning to avoid
      # invalid_request_error such as: "tools cannot be used with reasoning.effort 'minimal'".
      # Attach File Search tool only when the current app explicitly opts into PDF vector storage
      begin
        current_app = obj["app"] || (defined?(session) ? session.dig(:parameters, "app_name") : nil)
        app_has_docstore = APPS[current_app]&.settings&.[]("pdf_vector_storage")
        vs_id = resolve_openai_vs_id(session)
        resolved_mode = resolve_pdf_storage_mode(session)

        if app_has_docstore && vs_id && resolved_mode != 'local'
          responses_body["tools"] ||= []
          responses_body["tools"] << RESPONSES_API_BUILTIN_TOOLS["file_search"].call(vector_store_ids: [vs_id], max_num_results: 8)
          DebugHelper.debug("OpenAI: Adding file_search tool with vector_store_id=#{vs_id} for app=#{current_app}", category: :api, level: :debug)
        else
          DebugHelper.debug("OpenAI: Skipping file_search tool (app_has_docstore=#{!!app_has_docstore}, vs_id_present=#{!!vs_id}, mode=#{resolved_mode}, app=#{current_app})", category: :api, level: :debug)
        end
      rescue => e
        DebugHelper.debug("Failed to attach file_search tool: #{e.message}", category: :api, level: :warning)
      end
      
      # Support for structured outputs and verbosity
      # Check if text.format was already set by configure_monadic_response
      if body["text"] && body["text"]["format"]
        responses_body["text"] = body["text"]
        # Add verbosity to existing text object if model supports it (spec-driven)
        if body["verbosity"] && Monadic::Utils::ModelSpec.supports_verbosity?(model)
          responses_body["text"]["verbosity"] = body["verbosity"]
        end
      elsif body["response_format"] && body["response_format"]["type"] == "json_object"
        responses_body["text"] = {
          "format" => {
            "type" => "json",
            "json_schema" => body["response_format"]["json_schema"] || {
              "name" => "response",
              "schema" => {
                "type" => "object",
                "additionalProperties" => true
              }
            }
          }
        }
      else
        # If no text.format but verbosity is specified and supported
        if body["verbosity"] && Monadic::Utils::ModelSpec.supports_verbosity?(model)
          responses_body["text"] = {
            "verbosity" => body["verbosity"]
          }
        end
      end
      
      # Use responses body instead
      body = responses_body
      
      # Simplified logging for Responses API
      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts("[#{Time.now}] Responses API: model=#{body['model']}, tools=#{body['tools']&.length || 0}")
        # Debug log for PDF content
        if body['input']
          body['input'].each_with_index do |msg, idx|
            if msg['content'].is_a?(Array)
              msg['content'].each do |item|
                if item['type'] == 'file' || item['type'] == 'input_file'
                  extra_log.puts("  Message #{idx} has #{item['type']}: filename=#{item['filename'] || item.dig('file', 'filename')}")
                end
              end
            end
          end
        end
        extra_log.close
      end
      
    else
      # Use standard chat/completions API
      target_uri = "#{API_ENDPOINT}/chat/completions"
      
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
    end
    
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)
    
    # Debug which API endpoint is being used
    DebugHelper.debug("OpenAI API endpoint: #{target_uri}", category: :api, level: :debug)
    DebugHelper.debug("Using Responses API: #{use_responses_api}", category: :api, level: :debug)

    # Use longer timeout for responses API as o3-pro and GPT-5-Codex can take many minutes
    timeout_settings = if use_responses_api
                        {
                          connect: OPEN_TIMEOUT,
                          write: WRITE_TIMEOUT,
                          read: 1200  # 20 minutes for GPT-5-Codex and o3-pro
                        }
                      else
                        {
                          connect: OPEN_TIMEOUT,
                          write: WRITE_TIMEOUT,
                          read: READ_TIMEOUT
                        }
                      end


    MAX_RETRIES.times do
      # Debug log the actual body being sent for Responses API with PDF
      if use_responses_api && CONFIG["EXTRA_LOGGING"]
        if body["input"]&.any? { |msg| msg["content"]&.is_a?(Array) && msg["content"].any? { |c| c["type"] == "input_file" || c["type"] == "file" } }
          puts "DEBUG: Sending to Responses API with PDF content:"
          puts "Body structure: #{body.keys}"
          body["input"].each_with_index do |msg, idx|
            if msg["content"].is_a?(Array)
              msg["content"].each do |item|
                puts "  Input[#{idx}] content type: #{item['type']}"
              end
            end
          end
        end
      end
      
      res = http.timeout(**timeout_settings).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      
      error_body = JSON.parse(res.body)
      error_report = error_body["error"]
      pp error_report
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "OpenAI",
        message: error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      return [res]
    end

    # return Array
    if !body["stream"]
      obj = JSON.parse(res.body)
      
      if use_responses_api
        # Handle non-streaming responses API response
        # Support multiple possible response structures
        frag = ""
        
        
        # Try different paths for output
        if obj.dig("response", "output")
          output_array = obj.dig("response", "output")
        elsif obj["output"]
          output_array = obj["output"]
        else
          output_array = []
        end
        
        
        # Extract text from output array
        output_array.each do |item|
          
          if item.is_a?(Hash)
            # Direct text type
            if item["type"] == "text" && item["text"]
              frag += item["text"]
            # Message type with content array
            elsif item["type"] == "message" && item["content"]
              if item["content"].is_a?(Array)
                item["content"].each do |content_item|
                  # Handle both "text" and "output_text" types
                  if (content_item["type"] == "text" || content_item["type"] == "output_text") && content_item["text"]
                    frag += content_item["text"]
                  end
                end
              elsif item["content"].is_a?(String)
                frag += item["content"]
              end
            end
          end
        end
        
        # Fallback to standard format if available
        if frag.empty? && obj.dig("choices", 0, "message", "content")
          frag = obj.dig("choices", 0, "message", "content")
        end
      else
        # Handle standard chat API response
        frag = obj.dig("choices", 0, "message", "content")
      end
      
      
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      
      # For responses API, we need to format the response to match standard structure
      if use_responses_api
        formatted_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => frag
            },
            "finish_reason" => "stop"
          }],
          "model" => obj["model"] || body["model"]
        }
        [formatted_response]
      else
        [obj]
      end
    else
      # Include original model in the query for comparison
      body["original_user_model"] = original_user_model
      
      if use_responses_api
        # Process responses API streaming response
        process_responses_api_data(app: app,
                                  session: session,
                                  query: body,
                                  res: res.body,
                                  call_depth: call_depth, &block)
      else
        # Process standard chat API streaming response
        process_json_data(app: app,
                          session: session,
                          query: body,
                          res: res.body,
                          call_depth: call_depth, &block)
      end
    end
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      pp error_message = "The request has timed out."
      formatted_error = Monadic::Utils::ErrorFormatter.network_error(
        provider: "OpenAI",
        message: error_message,
        timeout: true
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      [res]
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "OpenAI",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
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
    # Determine reasoning model solely via model_spec
    reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(obj["model"], "reasoning_effort")

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil

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

            if CONFIG["EXTRA_LOGGING"] && extra_log && !extra_log.closed?
              extra_log.puts(JSON.pretty_generate(json))
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
            if json.dig("choices", 0, "delta", "content")
              # Merge text fragments based on "id"
              id = json["id"]
              texts[id] ||= json
              choice = texts[id]["choices"][0]
              choice["message"] ||= choice["delta"].dup
              choice["message"]["content"] ||= ""
              fragment = json.dig("choices", 0, "delta", "content").to_s
              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

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
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.empty? ? nil : texts.first[1]
    
    
    if CONFIG["EXTRA_LOGGING"]
      begin
        extra_log.close unless extra_log.closed?
      rescue
        # Already closed, ignore
      end
    end

    if result
      if obj["monadic"]
        choice = result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          
          
          # Use performance-optimized processing with caching
          cache_key = MonadicPerformance.generate_cache_key("openai", obj["model"], body["messages"])
          
          # Process and validate the monadic response
          processed = MonadicPerformance.performance_monitor.measure("monadic_processing") do
            # First, apply monadic transformation
            transformed = process_monadic_response(message, app)
            # Then validate the response
            validated = validate_monadic_response!(transformed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
            validated
          end
          
          # Update the choice with processed content
          if processed.is_a?(Hash)
            # For monadic responses, we need to preserve the entire JSON structure
            # not just the "message" field, so the UI can display the "context" properly
            choice["message"]["content"] = JSON.generate(processed)
          elsif processed.is_a?(String)
            # If it's already a JSON string, use it as-is
            choice["message"]["content"] = processed
          else
            # Fallback: convert to string
            choice["message"]["content"] = processed.to_s
          end
        end
      end
    end

    
    if tools.any?
      call_depth += 1

      if call_depth > MAX_FUNC_CALLS
        # Send notice fragment
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
        block&.call res
        
        # Create a mock HTML response to properly end the conversation
        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
        
        # Return appropriate result to end the conversation
        if result
          result["choices"][0]["finish_reason"] = "stop"
          return [result]
        else
          return [{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }]
        end
      else
        context = []
        if result
          merged = result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
          context << merged
        else
          context << tools.first[1].dig("choices", 0, "message")
        end

        tools = tools.first[1].dig("choices", 0, "message", "tool_calls")
        
        
        new_results = process_functions(app, session, tools, context, call_depth, &block)
        
        # Check if we should stop retrying due to repeated errors
        if should_stop_for_errors?(session)
          res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
          block&.call res
          if result
            result["choices"][0]["finish_reason"] = "stop"
            return [result]
          else
            return [res]
          end
        end
      end

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
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    
    # Log tool calls for debugging
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Tools] Processing #{tools.length} tool calls:"
      tools.each { |tc| puts "  - #{tc.dig('function', 'name')} with args: #{tc.dig('function', 'arguments').to_s[0..200]}" }
    end
    
    # Minimal guard: avoid repeated local PDF DB tool calls within a single turn
    local_pdf_tools = %w[find_closest_text get_text_snippet list_titles find_closest_doc get_text_snippets]
    seen_functions = {}
    seen_local_group = false

    filtered_tools = tools.select do |tc|
      fname = tc.dig('function', 'name').to_s
      # Drop exact duplicates by name+args
      args_sig = tc.dig('function', 'arguments').to_s
      sig = fname + '|' + args_sig
      next false if seen_functions[sig]
      seen_functions[sig] = true

      if local_pdf_tools.include?(fname)
        if seen_local_group
          # Suppress repeated local DB calls to enforce retrial policy
          DebugHelper.debug("Suppressing repeated local PDF tool call: #{fname}", category: :api, level: :info) rescue nil
          next false
        end
        seen_local_group = true
      end
      true
    end

    tools = filtered_tools

    tools.each do |tool_call|
      tool_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      function_call = tool_call["function"]
      function_name = function_call["name"]

      argument_hash = parse_function_call_arguments(function_call["arguments"], function_name: function_name)
      argument_hash = {} unless argument_hash.is_a?(Hash)

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      skip_function_execution = false
      function_return = nil

      if function_name == "find_help_topics" && app.to_s == "MonadicHelpOpenAI"
        obj["help_topics_call_count"] = obj["help_topics_call_count"].to_i + 1
        call_count = obj["help_topics_call_count"]

        normalized_text = argument_hash[:text].to_s.strip
        argument_hash[:text] = normalized_text unless normalized_text.empty?

        top_n = argument_hash[:top_n].to_i
        top_n = 12 if top_n <= 0
        top_n = 15 if top_n > 15
        argument_hash[:top_n] = top_n

        chunks = argument_hash[:chunks_per_result].to_i
        chunks = 2 if chunks <= 0
        chunks = 3 if chunks > 3
        argument_hash[:chunks_per_result] = chunks

        obj["help_topics_prev_queries"] ||= []
        downcased_query = normalized_text.downcase
        duplicate_query = !downcased_query.empty? && obj["help_topics_prev_queries"].include?(downcased_query)
        obj["help_topics_prev_queries"] << downcased_query unless downcased_query.empty?

        if duplicate_query || call_count > 2
          skip_function_execution = true
          notice_key = call_count > 2 ? "search_limit_reached" : "duplicate_query_skipped"
          notice_msg = call_count > 2 ? "Documentation search limited to two calls per request." : "Duplicate documentation search skipped."
          function_return = JSON.generate({ "results" => [], "notice" => notice_key, "message" => notice_msg })
        end
      end

      unless skip_function_execution
        begin
          if argument_hash.empty?
            function_return = APPS[app].send(function_name.to_sym)
          else
            function_return = APPS[app].send(function_name.to_sym, **argument_hash)
          end
          
          # Log the result for debugging
          if CONFIG["EXTRA_LOGGING"]
            puts "[DEBUG Tools] #{function_name} returned: #{function_return.to_s[0..500]}"
          end
        rescue StandardError => e
          pp e.message
          pp e.backtrace
          function_return = Monadic::Utils::ErrorFormatter.tool_error(
            provider: "OpenAI",
            tool_name: function_name,
            message: e.message
          )
        end
      end

      # Use the error handler module to check for repeated errors
      if handle_function_error(session, function_return, function_name, &block)
        # Stop retrying - add a special response
        context << {
          tool_call_id: tool_call["id"],
          role: "tool",
          name: function_name,
          content: function_return.to_s
        }
        
        obj["function_returns"] = context
        return api_request("tool", session, call_depth: call_depth, &block)
      end

     context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }

      if CONFIG["EXTRA_LOGGING"]
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_start) * 1000).round(1)
        query_preview = argument_hash[:text].to_s[0..80]
        DebugHelper.debug("[ToolTiming] app=#{app} function=#{function_name} duration_ms=#{duration_ms} query=#{query_preview}", category: :metrics, level: :info)
      end
    end

    obj["function_returns"] = context

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def normalize_function_call_arguments(raw_arguments)
    return "" if raw_arguments.nil?

    normalized = raw_arguments.dup

    SMART_QUOTE_REPLACEMENTS.each do |original, replacement|
      normalized.gsub!(original, replacement)
    end

    if normalized.respond_to?(:tr!)
      normalized.tr!("｛｝［］【】〖〗｟｠", "{}[]{}{}()")
      normalized.tr!("，、﹑﹐﹒", ',,,,,')
      normalized.tr!("：﹕", '::')
      normalized.gsub!('；', ',')
    end

    # Replace common whitespace variants that break JSON parsing
    normalized.gsub!(/\u00A0/u, ' ')
    normalized
  end

  def parse_function_call_arguments(raw_arguments, function_name: nil)
    normalized = normalize_function_call_arguments(raw_arguments)
    return {} if normalized.strip.empty?

    JSON.parse(normalized)
  rescue JSON::ParserError => e
    repaired = JSONRepair.attempt_repair(normalized)
    unless repaired.is_a?(Hash) && !repaired["_json_repair_failed"]
      log_tool_argument_failure(function_name, normalized, error: e)
      return {}
    end

    repaired
  rescue StandardError => e
    log_tool_argument_failure(function_name, normalized, error: e)
    {}
  end

  def log_tool_argument_failure(function_name, arguments, error: nil)
    return unless defined?(MonadicApp)
    return unless MonadicApp.const_defined?(:EXTRA_LOG_FILE)

    File.open(MonadicApp::EXTRA_LOG_FILE, 'a') do |f|
      f.puts "[OpenAIHelper] Failed to parse tool arguments at #{Time.now}:"
      f.puts "  Tool: #{function_name || 'unknown'}"
      f.puts "  Error: #{error.class}: #{error.message}" if error
      preview = arguments.to_s[0..500]
      f.puts "  Arguments preview: #{preview}"
      f.puts "---"
    end
  rescue StandardError
    # Ignore logging failures
  end

  def process_responses_api_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing responses API query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]
    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil
    current_tool_calls = []
    reasoning_segments = []
    reasoning_indices = {}
    current_reasoning_id = nil
    web_search_results = []
    file_search_results = []
    image_generation_status = {}
    # Track usage reported by Responses API
    usage_input_tokens = nil
    usage_output_tokens = nil
    usage_total_tokens = nil

    chunk_count = 0

    reasoning_extract_text = lambda do |content_array|
      next "" unless content_array.is_a?(Array)
      content_array.map do |entry|
        if entry.is_a?(Hash)
          type = entry["type"] || entry[:type]
          text = entry["text"] || entry[:text]
          if %w[output_text text].include?(type.to_s)
            text.to_s
          else
            ""
          end
        else
          ""
        end
      end.join
    end

    ensure_reasoning_segment = lambda do |rid|
      identifier = rid || current_reasoning_id || :__default_reasoning__
      index = reasoning_indices[identifier] if identifier && reasoning_indices.key?(identifier)

      if index.nil?
        index = reasoning_segments.length
        reasoning_segments << { text: "" }
        reasoning_indices[identifier] = index if identifier
      end

      reasoning_segments[index]
    end
    res.each do |chunk|
      event_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk
      chunk_count += 1
      

      if buffer.valid_encoding? == false
        next
      end

      begin
        # Check for completion patterns
        if /\Rdata: \[DONE\]\R/ =~ buffer || /\Revent: done\R/ =~ buffer
          break
        end
      rescue
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      # Responses API uses different event format
      pattern = /data: (\{.*?\})(?=\n|\z)/
      
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            if CONFIG["EXTRA_LOGGING"] && extra_log && !extra_log.closed?
              extra_log.puts(JSON.pretty_generate(json))
            end
            
            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            # Store the model for use throughout streaming
            # This helps us determine which events to process
            streaming_model = response_model || requested_model || body["model"]

            # Handle different event types for responses API
            event_type = json["type"]
            
            
            case event_type
            when "response.created"
              # Response created - just log for now
              # Response created
              
              # Store model information from response.created event if available
              if json["response"] && json["response"]["model"]
                streaming_model = json["response"]["model"]
              end
              
            when "response.in_progress"
              # Response in progress - check for any output
              # IMPORTANT: GPT-5, GPT-4.1, and chatgpt-4o models emit BOTH response.in_progress 
              # AND response.output_text.delta events, causing duplicate text fragments.
              # We skip response.in_progress for these models to prevent duplication.
              # Other models only emit response.in_progress, so we process them normally.
              response_data = json["response"]
              
              # Update streaming_model if we find it in the response
              if response_data && response_data["model"]
                streaming_model = response_data["model"]
              end
              
              # Use the stored streaming_model or try to find it in various locations
              current_model = streaming_model || 
                             json["model"] || 
                             response_data&.dig("metadata", "model") || 
                             response_data&.dig("model") ||
                             query["model"] || 
                             obj["model"] ||
                             body["model"]
              
              # Debug logging for GPT-5 streaming issues
              if CONFIG["EXTRA_LOGGING"]
                STDERR.puts "[OpenAI Streaming] response.in_progress event"
                STDERR.puts "  current_model: #{current_model}"
                STDERR.puts "  streaming_model: #{streaming_model}"
                STDERR.puts "  Will skip: #{current_model && Monadic::Utils::ModelSpec.skip_in_progress_events?(current_model)}"
              end
              
              # Skip for models that emit proper delta events (configured in ModelSpec)
              if current_model && Monadic::Utils::ModelSpec.skip_in_progress_events?(current_model)
                if CONFIG["EXTRA_LOGGING"]
                  STDERR.puts "[OpenAI Streaming] Skipping response.in_progress for model: #{current_model}"
                end
                next
              end
              
              if response_data
                
                if response_data["output"] && !response_data["output"].empty?
                  output = response_data["output"]
                  output.each do |item|
                    if item["type"] == "text" && item["text"]
                      id = response_data["id"] || "default"
                      texts[id] ||= ""
                      current_text = item["text"]
                      
                      # Calculate the delta - only send the new portion
                      if current_text.length > texts[id].length
                        delta = current_text[texts[id].length..-1]
                        texts[id] = current_text  # Update stored text
                        res = { "type" => "fragment", "content" => delta }
                        block&.call res
                      end
                    end
                  end
                end
              end
              
            when "response.output_text.delta"
              # Text fragment
              fragment = json["delta"]
              
              # Debug logging for GPT-5 streaming issues
              if CONFIG["EXTRA_LOGGING"]
                current_model = streaming_model || json["model"] || query["model"] || obj["model"] || body["model"]
                if current_model && (current_model.to_s.downcase.include?("gpt-5") || current_model.to_s.include?("gpt-4.1"))
                  STDERR.puts "[OpenAI Streaming] response.output_text.delta for #{current_model} - fragment: #{fragment.inspect}"
                end
              end
              
              if fragment && !fragment.empty?
                id = json["response_id"] || json["item_id"] || "default"
                texts[id] ||= ""
                
                # Add index for duplicate detection on client side
                res = { 
                  "type" => "fragment", 
                  "content" => fragment,
                  "index" => texts[id].length,
                  "timestamp" => Time.now.to_f,
                  "is_first" => texts[id].empty?
                }
                
                texts[id] += fragment
                block&.call res
              end
              
            when "response.output_text.done"
              # Text output completed
              text = json["text"]
              if text
                id = json["item_id"] || "default"
                texts[id] = text  # Final text
              end
              
            when "response.output_item.added"
              # New output item added
              item = json["item"]

              if item && item["type"] == "function_call"
                # Store the function name and ID for later use
                item_id = item["id"]
                if item_id
                  tools[item_id] ||= {}
                  tools[item_id]["name"] = item["name"] if item["name"]
                  tools[item_id]["call_id"] = item["call_id"] if item["call_id"]
                  tools[item_id]["arguments"] ||= ""
                end
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              elsif item && item["type"] == "reasoning"
                rid = item["id"]
                current_reasoning_id = rid if rid
                segment = ensure_reasoning_segment.call(rid)
                # Reasoning content can be in item["content"] or item["summary"]
                if item["summary"].is_a?(Array)
                  # With summary: "auto", reasoning text is in the summary array
                  # Extract text from summary_text items
                  summary_text = item["summary"].map do |entry|
                    if entry.is_a?(Hash) && entry["type"] == "summary_text"
                      entry["text"].to_s
                    else
                      ""
                    end
                  end.join("\n\n")
                  segment[:text] << summary_text unless summary_text.empty?
                elsif item["content"]
                  segment[:text] << reasoning_extract_text.call(item["content"])
                end
              end
              
            when "response.output_item.done"
              # Output item completed
              item = json["item"]

              if item && item["type"] == "function_call"
                item_id = item["id"]
                if item_id
                  # Create or update tool entry
                  tools[item_id] ||= {}
                  tools[item_id]["name"] = item["name"] if item["name"]
                  tools[item_id]["arguments"] = item["arguments"] if item["arguments"]
                  tools[item_id]["call_id"] = item["call_id"] if item["call_id"]
                  tools[item_id]["completed"] = true
                end
              elsif item && item["type"] == "reasoning"
                rid = item["id"]
                current_reasoning_id = rid if rid
                segment = ensure_reasoning_segment.call(rid)
                # Reasoning content can be in item["content"] or item["summary"]
                if item["summary"].is_a?(Array)
                  # With summary: "auto", reasoning text is in the summary array
                  # Extract text from summary_text items
                  summary_text = item["summary"].map do |entry|
                    if entry.is_a?(Hash) && entry["type"] == "summary_text"
                      entry["text"].to_s
                    else
                      ""
                    end
                  end.join("\n\n")
                  segment[:text] << summary_text unless summary_text.empty?
                elsif item["content"]
                  segment[:text] << reasoning_extract_text.call(item["content"])
                end
              end
              
            when "response.function_call_arguments.delta", "response.function_call.arguments.delta", "response.function_call.delta"
              # Tool call arguments fragment
              item_id = json["item_id"]
              delta = json["delta"]
              
              if item_id && delta
                tools[item_id] ||= {}
                tools[item_id]["arguments"] ||= ""
                tools[item_id]["arguments"] += delta
              end
              
            when "response.function_call_arguments.done", "response.function_call.arguments.done", "response.function_call.done"
              # Tool call arguments completed
              item_id = json["item_id"]
              arguments = json["arguments"]
              name = json["name"]
              
              if item_id
                tools[item_id] ||= {}
                tools[item_id]["arguments"] = arguments if arguments
                tools[item_id]["name"] = name if name
                tools[item_id]["completed"] = true
              end
              
            when "response.reasoning.delta"
              # Reasoning content delta
              rid = json["item_id"] || current_reasoning_id
              delta = json.dig("delta", "text") || json["delta"]
              if delta
                segment = ensure_reasoning_segment.call(rid)
                segment[:text] << delta.to_s
                current_reasoning_id = rid if rid

                # Send reasoning delta to frontend (like Claude's thinking)
                res = {
                  "type" => "reasoning",
                  "content" => delta.to_s
                }
                block&.call res
              end

            when "response.reasoning.done"
              # Reasoning completed
              rid = json["item_id"] || current_reasoning_id
              text = json["text"]
              if text
                segment = ensure_reasoning_segment.call(rid)
                segment[:text] = text.to_s
                current_reasoning_id = nil
              end
              
            when "response.web_search_call.in_progress"
              # Web search started
              res = { "type" => "wait", "content" => "<i class='fas fa-search'></i> SEARCHING WEB" }
              block&.call res
              
            when "response.web_search_call.searching"
              # Web search in progress
              # Could show progress if needed
              
            when "response.web_search_call.completed"
              # Web search completed
              item_id = json["item_id"]
              if item_id
                web_search_results << item_id
              end
              
            when "response.file_search_call.in_progress"
              # File search started
              res = { "type" => "wait", "content" => "<i class='fas fa-file-search'></i> SEARCHING FILES" }
              block&.call res
              
            when "response.file_search_call.searching"
              # File search in progress
              
            when "response.file_search_call.completed"
              # File search completed
              item_id = json["item_id"]
              if item_id
                file_search_results << item_id
              end
              
            when "response.image_generation_call.in_progress"
              # Image generation started
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "in_progress"
                res = { "type" => "wait", "content" => "<i class='fas fa-image'></i> GENERATING IMAGE" }
                block&.call res
              end
              
            when "response.image_generation_call.generating"
              # Image generation in progress
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "generating"
              end
              
            when "response.image_generation_call.partial_image"
              # Partial image available
              item_id = json["item_id"]
              partial_image = json["partial_image_b64"]
              if item_id && partial_image
                # Could display partial image if desired
              end
              
            when "response.image_generation_call.completed"
              # Image generation completed
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "completed"
              end
              
            when "response.mcp_call.in_progress"
              # MCP tool call started
              res = { "type" => "wait", "content" => "<i class='fas fa-plug'></i> CALLING MCP TOOL" }
              block&.call res
              
            when "response.mcp_call.arguments.delta"
              # MCP arguments delta
              item_id = json["item_id"]
              delta = json["delta"]
              if item_id && delta
                tools[item_id] ||= { "mcp_arguments" => {} }
                tools[item_id]["mcp_arguments"].merge!(delta)
              end
              
            when "response.mcp_call.arguments.done"
              # MCP arguments completed
              item_id = json["item_id"]
              arguments = json["arguments"]
              if item_id && arguments
                tools[item_id] ||= {}
                tools[item_id]["mcp_arguments"] = arguments
                tools[item_id]["mcp_completed"] = true
              end
              
            when "response.mcp_call.completed"
              # MCP call completed successfully
              
            when "response.mcp_call.failed"
              # MCP call failed
              res = { "type" => "error", "content" => "MCP tool call failed" }
              block&.call res
              
            when "response.completed", "response.done"
              # Response completed - extract final output
              response_data = json["response"] || json  # Handle both nested and flat structures
              # Capture usage if present
              usage = response_data["usage"] || json["usage"]
              if usage.is_a?(Hash)
                usage_input_tokens = usage["input_tokens"] || usage["prompt_tokens"] || usage_input_tokens
                usage_output_tokens = usage["output_tokens"] || usage["completion_tokens"] || usage_output_tokens
                usage_total_tokens = usage["total_tokens"] || (usage_input_tokens.to_i + usage_output_tokens.to_i if usage_input_tokens && usage_output_tokens) || usage_total_tokens
              end
              
              
              if response_data && response_data["output"] && !response_data["output"].empty?
                output = response_data["output"]
                output.each do |item|
                  if item["type"] == "text" && item["text"]
                    id = response_data["id"] || "default"
                    texts[id] ||= ""
                    texts[id] = item["text"]  # Replace with final text
                    
                  end
                end
              else
              end
              finish_reason = response_data["stop_reason"] || json["stop_reason"] || "stop"
              
            when "response.output.done"
              # Alternative completion event
              # Extract final output if available
              if json["output"]
                output_text = json.dig("output", 0, "content", 0, "text")
                if output_text && !output_text.empty?
                  id = json["response_id"] || "default"
                  texts[id] ||= ""
                  texts[id] = output_text  # Replace with final text
                end
              end
              finish_reason = "stop"
              
            when "response.error"
              # Error occurred
              error_msg = json.dig("error", "message") || "Unknown error"
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "OpenAI",
                message: error_msg
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              
              if CONFIG["EXTRA_LOGGING"]
                begin
                  extra_log.close unless extra_log.closed?
                rescue
                  # Already closed, ignore
                end
              end
              return [res]
              
            else
              # Unknown event type
            end
            
          rescue JSON::ParserError => e
            # JSON parsing error, continue to next iteration
          rescue StandardError => e
            pp e.message
            pp e.backtrace
            pp e.inspect
          end
          if CONFIG["EXTRA_LOGGING"]
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - event_start) * 1000).round(1)
            DebugHelper.debug("[ResponsesTiming] app=#{app} event=#{event_type.inspect} duration_ms=#{duration_ms}", category: :metrics, level: :info)
          end
        else
          scanner.terminate
        end
      end
      
      buffer = scanner.rest
    end

    if CONFIG["EXTRA_LOGGING"]
      begin
        extra_log.close unless extra_log.closed?
      rescue
        # Already closed, ignore
      end
    end

    # Handle tool calls if any were collected
    if tools.any? && tools.any? { |_, tool| tool["completed"] || tool["mcp_completed"] }
      call_depth += 1
      
      if call_depth > MAX_FUNC_CALLS
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
        block&.call res
        
        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
      else
        # Process function tools
        function_results = []
        tools.each do |item_id, tool_data|
          if tool_data["completed"] && tool_data["arguments"]
            # This is a regular function call
            function_results << {
              "id" => tool_data["call_id"] || item_id,  # Use call_id if available
              "function" => {
                "name" => tool_data["name"] || "unknown",
                "arguments" => tool_data["arguments"]
              }
            }
          elsif tool_data["mcp_completed"] && tool_data["mcp_arguments"]
            # This is an MCP call - handle differently if needed
            function_results << {
              "id" => tool_data["call_id"] || item_id,  # Use call_id if available
              "type" => "mcp",
              "function" => {
                "name" => tool_data["name"] || "mcp_tool",
                "arguments" => JSON.generate(tool_data["mcp_arguments"])
              }
            }
          end
        end
        
        if function_results.any?
          # Convert to standard format for process_functions
          tool_calls = function_results.map do |result|
            {
              "id" => result["id"],
              "function" => result["function"]
            }
          end
          
          # Build context with any text content so far
          context = []
          message = {
            "role" => "assistant",
            "tool_calls" => tool_calls
          }

          if texts.any?
            complete_text = texts.values.join("")
            message["content"] = complete_text
          end

          reasoning_entries = reasoning_segments.filter_map do |segment|
            text = segment[:text].to_s.strip
            next if text.empty?
            {
              "type" => "reasoning",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => text
                }
              ]
            }
          end

          unless reasoning_entries.empty?
            message["reasoning_items"] = reasoning_entries
            reasoning_text_combined = reasoning_entries.map do |entry|
              Array(entry["content"]).select { |c| c.is_a?(Hash) && c["type"] == "output_text" }.map { |c| c["text"] }
            end.flatten.join("\n\n").strip
            message["reasoning_content"] = reasoning_text_combined unless reasoning_text_combined.empty?
            obj["reasoning_context"] = JSON.parse(JSON.generate(reasoning_entries.last(REASONING_CONTEXT_MAX)))
          end

          context << message
          
          new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
          
          if should_stop_for_errors?(session)
            res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
            block&.call res
            return new_results || []
          end
          
          return new_results || []
        end
      end
    end
    
    # Return text response if no tools were called
    if texts.any?
      complete_text = texts.values.join("")
      
      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => complete_text
          },
          "finish_reason" => finish_reason || "stop"
        }],
        "model" => query["model"]
      }
      # Attach usage if available
      if usage_input_tokens || usage_output_tokens || usage_total_tokens
        response["usage"] = {
          "input_tokens" => usage_input_tokens,
          "output_tokens" => usage_output_tokens,
          "total_tokens" => usage_total_tokens
        }.compact
      end
      
      reasoning_texts = reasoning_segments.map { |segment| segment[:text].to_s.strip }.reject(&:empty?)
      if reasoning_texts.any?
        response["choices"][0]["message"]["reasoning_content"] = reasoning_texts.join("\n\n")
        obj["reasoning_context"] = JSON.parse(JSON.generate(reasoning_segments.filter_map do |segment|
          text = segment[:text].to_s.strip
          next if text.empty?
          {
            "type" => "reasoning",
            "content" => [
              {
                "type" => "output_text",
                "text" => text
              }
            ]
          }
        end.last(REASONING_CONTEXT_MAX)))
      else
        obj.delete("reasoning_context") if obj.key?("reasoning_context")
      end
      
      # Apply monadic transformation if needed
      if obj["monadic"] && (finish_reason == "stop" || finish_reason == "length")
        choice = response["choices"][0]
        message = choice["message"]["content"]
        
        # Process and validate the monadic response
        processed = begin
          # First, apply monadic transformation
          transformed = process_monadic_response(message, app)
          # Then validate the response
          validated = validate_monadic_response!(transformed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
          validated
        rescue => e
          DebugHelper.debug("Monadic processing error in Responses API: #{e.message}", category: :api, level: :error)
          # Fall back to original content if processing fails
          message
        end
        
        # Update the choice with processed content
        # IMPORTANT: Preserve full JSON structure for monadic apps (message + context)
        # This ensures UI cards display context information correctly
        if processed.is_a?(Hash)
          # For monadic responses, we need to preserve the entire JSON structure
          # not just the "message" field, so the UI can display the "context" properly
          choice["message"]["content"] = JSON.generate(processed)
        elsif processed.is_a?(String)
          # If it's already a JSON string, use it as-is
          choice["message"]["content"] = processed
        else
          # Fallback: convert to string
          choice["message"]["content"] = processed.to_s
        end
      end
      
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" })
      [response]
    else
      # Return a properly formatted empty response instead of empty hash
      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => ""
          },
          "finish_reason" => "stop"
        }],
        "model" => query["model"]
      }
      
      
      [response]
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "OpenAI",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end
  
  # Helper methods for Responses API
  
  # Check if a model should use the Responses API
  def use_responses_api?(model)
    Monadic::Utils::ModelSpec.responses_api?(model)
  end
  
  # Get a response by ID (for stateful conversations)
  def get_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}"
    http = HTTP.headers(headers)
    
    begin
      res = http.get(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
  
  # Delete a response by ID
  def delete_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}"
    http = HTTP.headers(headers)
    
    begin
      res = http.delete(target_uri)
      res.status.success?
    rescue HTTP::Error, HTTP::TimeoutError
      false
    end
  end
  
  # Cancel a background response
  def cancel_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}/cancel"
    http = HTTP.headers(headers)
    
    begin
      res = http.post(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
  
  # Get input items for a response
  def get_response_input_items(response_id, options = {})
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    params = {}
    params[:limit] = options[:limit] if options[:limit]
    params[:after] = options[:after] if options[:after]
    params[:before] = options[:before] if options[:before]
    params[:include] = options[:include] if options[:include]
    
    query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}/input_items"
    target_uri += "?#{query_string}" unless query_string.empty?
    
    http = HTTP.headers(headers)
    
    begin
      res = http.get(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
end
