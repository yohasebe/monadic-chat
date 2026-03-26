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
require_relative "../../utils/system_prompt_injector"
require_relative "../../utils/openai_file_inputs_cache"
require_relative "../../utils/extra_logger"
require_relative "../base_vendor_helper"
require_relative "../../monadic_performance"
module OpenAIHelper
  include BaseVendorHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicPerformance
  # Maximum tool-call round-trips per user turn.
  # Each round-trip may contain multiple parallel tool calls, so effective tool count can be higher.
  # 20 round-trips is generous for most workflows; Auto Forge complex builds may use 15+.
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.openai.com/v1"
  REASONING_CONTEXT_MAX = 3

  define_timeouts "OPENAI", open: 20, read: 600, write: 120

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
    type: "web_search"
  }

  # Built-in tools available in Responses API
  RESPONSES_API_BUILTIN_TOOLS = {
    "web_search" => { type: "web_search" },
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

  # Pre-compiled regex for single-pass replacement (performance optimization)
  SMART_QUOTE_REGEX = Regexp.union(SMART_QUOTE_REPLACEMENTS.keys).freeze

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

  end

  define_model_lister :openai,
    api_key_config: "OPENAI_API_KEY",
    endpoint_path: "/models" do |json|
      (json["data"] || [])
        .sort_by { |m| m["created"] }.reverse
        .first(MODELS_N_LATEST + 1)
        .map { |m| m["id"] }
        .reject { |id| EXCLUDED_MODELS.any? { |ex| /\b#{ex}\b/ =~ id } }
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

      DebugHelper.debug("Using response format: #{body['response_format'].inspect}", category: :api)
    end

    # Add max_completion_tokens if specified (required for GPT-5.x models)
    # Also check for max_tokens for backward compatibility
    if options["max_completion_tokens"]
      body["max_completion_tokens"] = options["max_completion_tokens"].to_i
    elsif options["max_tokens"]
      # Use max_completion_tokens for all OpenAI models (GPT-5.x requires it, others accept it)
      body["max_completion_tokens"] = options["max_tokens"].to_i
    end

    # Add tool definitions if provided (for testing tool-calling apps)
    if options["tools"] && options["tools"].any?
      # Convert to OpenAI format if needed
      body["tools"] = options["tools"].map do |tool|
        if tool["type"] == "function" && tool["function"]
          # Already in OpenAI format
          tool
        else
          # Convert from simple format to OpenAI format
          {
            "type" => "function",
            "function" => {
              "name" => tool["name"] || tool[:name],
              "description" => tool["description"] || tool[:description] || "",
              "parameters" => tool["parameters"] || tool[:parameters] || { "type" => "object", "properties" => {} }
            }
          }
        end
      end
      body["tool_choice"] = "auto"
    end

    # Set API endpoint
    target_uri = API_ENDPOINT + "/chat/completions"

    # Make the request
    http = HTTP.headers(headers)
   
    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout,
                         write: write_timeout,
                         read: read_timeout).post(target_uri, json: body)
      break if res && res.status && res.status.success?
      sleep RETRY_DELAY
    end

    # Process response
    if res && res.status && res.status.success?
      # Properly read response body content
      response_body = res.body.respond_to?(:read) ? res.body.read : res.body.to_s
      parsed_response = JSON.parse(response_body)
      message = parsed_response.dig("choices", 0, "message")

      # Check for tool calls in the response
      if message && message["tool_calls"] && message["tool_calls"].any?
        tool_calls = message["tool_calls"].map do |tc|
          {
            "name" => tc.dig("function", "name"),
            "args" => begin
              JSON.parse(tc.dig("function", "arguments") || "{}")
            rescue JSON::ParserError
              {}
            end
          }
        end
        text_content = message["content"] || ""
        return { text: text_content, tool_calls: tool_calls }
      end

      return message["content"]
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

  # Resolve model capability flags from model_spec.
  # Returns a hash of boolean/string flags used throughout api_request.
  private def resolve_openai_model_capabilities(model, obj, use_responses_api, &block)
    reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(model, "reasoning_effort")
    non_stream_model = (Monadic::Utils::ModelSpec.get_model_property(model, "supports_streaming") == false)
    tool_capability = Monadic::Utils::ModelSpec.get_model_property(model, "tool_capability") == true
    non_tool_model = !tool_capability
    supports_websearch = Monadic::Utils::ModelSpec.supports_web_search?(model)

    websearch_enabled = obj["websearch"] == "true" || obj["websearch"] == true
    use_responses_api_for_websearch = websearch_enabled &&
                                      Monadic::Utils::ModelSpec.supports_web_search?(model)

    # If websearch is enabled but the model doesn't support it, disable websearch
    if websearch_enabled && !supports_websearch && !use_responses_api
      websearch_enabled = false
      if block
        system_msg = {
          "type" => "system_info",
          "content" => "Web search is not available for model #{model}. Proceeding without web search."
        }
        block.call system_msg
      end
    end

    websearch_prompt = websearch_enabled ? WEBSEARCH_PROMPT : nil

    {
      reasoning_model: reasoning_model,
      non_stream_model: non_stream_model,
      tool_capability: tool_capability,
      non_tool_model: non_tool_model,
      supports_websearch: supports_websearch,
      websearch_enabled: websearch_enabled,
      use_responses_api_for_websearch: use_responses_api_for_websearch,
      websearch_prompt: websearch_prompt
    }
  end

  # Build the base request body (model, stream, temperature, penalties, reasoning, max_tokens).
  private def build_openai_base_body(model, obj, app, caps, max_completion_tokens, temperature, presence_penalty, frequency_penalty)
    body = { "model" => model }
    reasoning_model = caps[:reasoning_model]
    reasoning_effort = obj["reasoning_effort"]
    verbosity = obj["verbosity"]

    # Add verbosity for models that support it (via ModelSpec)
    if verbosity && Monadic::Utils::ModelSpec.supports_verbosity?(model)
      body["verbosity"] = verbosity
    end

    if reasoning_model
      if reasoning_effort && reasoning_effort != "none"
        body["reasoning_effort"] = reasoning_effort
      end
      body.delete("temperature")
      body.delete("frequency_penalty")
      body.delete("presence_penalty")
      body.delete("max_completion_tokens")
    elsif caps[:supports_websearch]
      body.delete("n")
      body.delete("temperature")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")
    else
      body["n"] = 1
      unless model.to_s.downcase.include?("gpt-5")
        body["temperature"] = temperature if temperature
        body["presence_penalty"] = presence_penalty if presence_penalty
        body["frequency_penalty"] = frequency_penalty if frequency_penalty
      end
      body["max_completion_tokens"] = max_completion_tokens if max_completion_tokens

      if obj["response_format"]
        body["response_format"] = APPS[app].settings["response_format"]
      end
    end

    body["stream"] = !caps[:non_stream_model]
    body
  end

  # Configure tools on the request body (parse, PTD filter, PDF cloud file_search).
  private def configure_openai_tools(body, obj, app, session, role, caps, use_responses_api)
    skip_tools = caps[:non_tool_model] || (role == "tool" && !use_responses_api)

    if skip_tools
      Monadic::Utils::ExtraLogger.log { "OpenAI: Skipping tools because non_tool_model=#{caps[:non_tool_model]} or role='#{role}'" }
      body.delete("tools")
      body.delete("response_format")
      return
    end

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

    if APPS[app]
      begin
        app_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
          app_name: app,
          session: session,
          app_settings: APPS[app].settings,
          default_tools: app_tools
        )
      rescue StandardError => e
        DebugHelper.debug("OpenAI: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning) if defined?(DebugHelper)
      end
    end

    if tools_param && !tools_param.empty?
      if app_tools && !app_tools.empty?
        body["tools"] = app_tools
      elsif tools_param.is_a?(Array) && !tools_param.empty?
        body["tools"] = tools_param
      else
        body["tools"] = []
      end
      body["tools"].uniq!
    elsif app_tools && !app_tools.empty?
      body["tools"] = app_tools
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Add file_search tool for Chat Completions API as well (when app opts into pdf_vector_storage)
    begin
      app_has_docstore = APPS[app]&.settings&.[]("pdf_vector_storage")
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
  end

  # Save image/mask files to shared folder and return reference paths for image generation.
  # Returns an array of image file reference paths (e.g. ["/data/img_foo.png"]).
  private def prepare_openai_image_generation_refs(context, image_generation, role, shared_folder)
    image_file_references = []
    return image_file_references unless image_generation && role == "user"

    image_name_map = {}
    pending_masks = []

    ext_for_image = lambda do |img|
      ext = File.extname(img["data"].to_s)
      ext = File.extname(img["title"].to_s) if ext.to_s.empty?
      ext = ".png" if ext.to_s.empty?
      ext
    end

    save_image_to_shared = lambda do |img, target_path|
      begin
        if File.exist?(img["data"].to_s)
          FileUtils.cp(img["data"].to_s, target_path)
          true
        elsif img["data"].to_s.start_with?("data:")
          data_uri = img["data"].to_s
          _content_type, encoded_data = data_uri.match(/^data:([^;]+);base64,(.+)$/)[1..2]
          decoded_data = Base64.decode64(encoded_data)
          File.open(target_path, 'wb') { |f| f.write(decoded_data) }
          true
        else
          false
        end
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "Error processing image for generation: #{e.message}" }
        false
      end
    end

    find_mapped_image = lambda do |name|
      return nil if name.to_s.strip.empty?
      key = name.to_s.strip.downcase
      return image_name_map[key] if image_name_map[key]
      base_key = File.basename(key, File.extname(key))
      image_name_map[base_key]
    end

    context.compact.each do |msg|
      next unless msg["images"]

      msg["images"].each do |img|
        begin
          is_mask = img["is_mask"] == true || img["title"].to_s.start_with?("mask__")
          if img["data"].to_s.start_with?("/data/")
            stored_filename = File.basename(img["data"].to_s)
            image_file_references << img["data"].to_s
            unless is_mask
              raw_title = img["title"].to_s
              unless raw_title.strip.empty?
                key = raw_title.strip.downcase
                image_name_map[key] = stored_filename
                base_key = File.basename(key, File.extname(key))
                image_name_map[base_key] ||= stored_filename if base_key && !base_key.empty?
              end
            else
              pending_masks << img.merge("stored_name" => stored_filename)
            end
            next
          end

          if is_mask
            pending_masks << img
            next
          end

          timestamp = Time.now.to_i
          random_suffix = SecureRandom.hex(4)
          ext = ext_for_image.call(img)

          raw_title = img["title"].to_s
          sanitized_title = raw_title.strip.empty? ? nil : raw_title.gsub(/[^a-zA-Z0-9_.-]/, "_")
          base_name = sanitized_title ? "img_#{sanitized_title}" : "img_#{timestamp}_#{random_suffix}"
          base_name += ext unless base_name.downcase.end_with?(ext.downcase)
          new_filename = base_name
          target_path = File.join(shared_folder, new_filename)

          if save_image_to_shared.call(img, target_path)
            image_file_references << "/data/#{new_filename}"

            unless raw_title.to_s.strip.empty?
              key = raw_title.strip.downcase
              image_name_map[key] = new_filename
              base_key = File.basename(key, File.extname(key))
              image_name_map[base_key] ||= new_filename if base_key && !base_key.empty?
            end
          end
        rescue StandardError => e
          Monadic::Utils::ExtraLogger.log { "Error processing image for generation: #{e.message}" }
        end
      end

      msg.delete("images")
    end

    pending_masks.each do |img|
      begin
        timestamp = Time.now.to_i
        random_suffix = SecureRandom.hex(4)
        ext = ext_for_image.call(img)

        raw_title = img["title"].to_s
        associated_title = img["mask_for"].to_s
        associated_title = raw_title.sub(/^mask__/, "") if associated_title.to_s.strip.empty?
        mapped_original = find_mapped_image.call(associated_title)

        if img["stored_name"]
          new_filename = img["stored_name"]
          image_file_references << "/data/#{new_filename}"
          next
        end

        base_name = if mapped_original
                      "mask__#{mapped_original}"
                    elsif !associated_title.to_s.strip.empty?
                      safe_mask_base = associated_title.gsub(/[^a-zA-Z0-9_.-]/, "_")
                      "mask__#{safe_mask_base}"
                    else
                      "mask__#{timestamp}_#{random_suffix}"
                    end
        base_name += ext unless base_name.downcase.end_with?(ext.downcase)
        new_filename = base_name
        target_path = File.join(shared_folder, new_filename)

        if save_image_to_shared.call(img, target_path)
          image_file_references << "/data/#{new_filename}"
        end
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "Error processing mask for generation: #{e.message}" }
      end
    end

    image_file_references
  end

  # Build body["messages"] from context, handle image expansion, system→developer conversion,
  # prompt injection, and vision capability check.
  # Returns true/false for messages_containing_img, or an Array (early return) on vision error.
  private def build_openai_messages(body, context, session, obj, role, image_generation, image_file_references,
                                    reasoning_model, websearch_enabled, websearch_prompt, initial_prompt, prompt_suffix, message_with_snippet, &block)
    messages_containing_img = false
    data = nil

    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user" && !image_generation
        msg["images"].each do |img|
          messages_containing_img = true
          if img["type"] == "application/pdf" || document_type?(img["type"])
            file_id = resolve_file_id_for_input(session, img)
            if file_id
              message["content"] << {
                "type" => "file",
                "file" => { "file_id" => file_id }
              }
            else
              message["content"] << {
                "type" => "file",
                "file" => {
                  "file_data" => img["data"],
                  "filename" => img["title"]
                }
              }
            end
          elsif img["source"] == "url"
            message["content"] << {
              "type" => "file",
              "file" => {
                "file_url" => img["data"],
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
              base_text = if websearch_enabled && websearch_prompt
                            "Web search enabled\n---\n" + content_item["text"]
                          else
                            "Formatting re-enabled\n---\n" + content_item["text"]
                          end

              augmented_text = Monadic::Utils::SystemPromptInjector.augment(
                base_prompt: base_text,
                session: session,
                options: {
                  websearch_enabled: false,
                  reasoning_model: true,
                  websearch_prompt: nil,
                  system_prompt_suffix: obj["system_prompt_suffix"]
                },
                separator: "\n\n"
              )

              if websearch_enabled && websearch_prompt
                augmented_text += "\n---\n" + websearch_prompt
              end

              Monadic::Utils::ExtraLogger.log { "[DEBUG] OpenAI Reasoning Model System Prompt Injection:\n  - Base text length: #{base_text.length}\n  - Augmented text length: #{augmented_text.length}" }

              content_item["text"] = augmented_text
            end
          end
          num_system_messages += 1
        end
      end
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body.delete("tool_choice") if body["tool_choice"]
    end

    last_text = context.last&.dig("text")

    if last_text&.match?(/\^\s*__DATA__\s*$/m)
      last_text, data = last_text.split("__DATA__")
      context.last["text"] = last_text if context.last
    end

    last_text = message_with_snippet if message_with_snippet.to_s != ""

    # If this is an image generation request, add the image filenames to the last message
    if image_generation && !image_file_references.empty? && role == "user"
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

      unless regular_images.empty?
        img_references_text += "\n\nAttached images:\n"
        regular_images.each do |filename|
          img_references_text += "- #{filename}\n"
        end
      end

      unless mask_images.empty?
        img_references_text += "\n\nMask images for editing (MUST use edit operation):\n"
        mask_images.each do |mask_filename|
          original_name = mask_filename.sub(/^mask__/, "img_")
          img_references_text += "- #{mask_filename} (mask for editing)\n"

          if regular_images.include?(original_name)
            img_references_text += "  Original image: #{original_name}\n"
          end
        end
        img_references_text += "\nIMPORTANT: You have mask files attached. You MUST use the 'edit' operation with these masks, NOT 'generate'.\n"
      end

      begin
        session[:openai_last_image_generation] = {
          images: regular_images,
          masks: mask_images
        }
      rescue StandardError
        # Ignore session storage issues
      end

      if last_text.to_s != ""
        last_text += img_references_text
      else
        if context.last && context.last["text"]
          context.last["text"] += img_references_text
        end
      end
    end

    # Detect initiate_from_assistant initial greeting (skip prompt_suffix)
    is_initial_greeting = body["messages"].length == 1 &&
                          (body["messages"][0]["role"] == "system" || body["messages"][0]["role"] == "developer")

    if last_text.to_s != "" && body.dig("messages", -1, "content") && !is_initial_greeting
      augmented_text = Monadic::Utils::SystemPromptInjector.augment_user_message(
        base_message: last_text.to_s,
        session: session,
        options: {
          prompt_suffix: prompt_suffix
        }
      )

      if augmented_text != last_text.to_s
        body["messages"].last["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = augmented_text
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

    # Use unified system prompt injector for dynamic prompt augmentation
    if initial_prompt.to_s != ""
      augmented_prompt = Monadic::Utils::SystemPromptInjector.augment(
        base_prompt: initial_prompt.to_s,
        session: session,
        options: {
          websearch_enabled: websearch_enabled,
          reasoning_model: reasoning_model,
          websearch_prompt: websearch_prompt,
          system_prompt_suffix: obj["system_prompt_suffix"]
        },
        separator: "\n\n"
      )

      Monadic::Utils::ExtraLogger.log { "OpenAI System Prompt Injection:\n  - Base prompt length: #{initial_prompt.to_s.length}\n  - Augmented prompt length: #{augmented_prompt.length}\n  - Injections applied: #{augmented_prompt != initial_prompt.to_s}" }

      if augmented_prompt != initial_prompt.to_s
        body["messages"].first["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = augmented_prompt
          end
        end
      end
    end

    if messages_containing_img
      supports_vision = !!obj["vision_capability"]
      begin
        supports_vision ||= !!MonadicApp.check_vision_capability(body["model"]) if defined?(MonadicApp)
      rescue StandardError
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

      body.delete("stop")
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      initial_message = "Please proceed according to your system instructions and introduce yourself."

      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => initial_message }]
      }
    end

    messages_containing_img
  end

  # Convert a Chat API body to Responses API body format.
  # Handles input message conversion, instructions extraction, tools, reasoning, and verbosity.
  private def convert_to_responses_api_body(body, obj, model, session, max_completion_tokens, original_user_model, &block)
    # Send processing status only for long-running models
    is_slow = Monadic::Utils::ModelSpec.get_model_property(original_user_model, "latency_tier") == "slow" ||
              Monadic::Utils::ModelSpec.get_model_property(original_user_model, "is_slow_model") == true
    if block && is_slow
      block.call({ "type" => "processing_status", "content" => "This may take a while." })
    end

    # Convert messages format to responses API input format
    input_messages = body["messages"].map do |msg|
      role = msg["role"] || msg[:role]
      content = msg["content"] || msg[:content]

      if role == "tool"
        {
          "type" => "function_call_output",
          "call_id" => msg["tool_call_id"] || msg["call_id"] || msg[:tool_call_id] || msg[:call_id],
          "output" => content.to_s
        }
      elsif role == "assistant" && (msg["tool_calls"] || msg[:tool_calls])
        tool_calls = msg["tool_calls"] || msg[:tool_calls]
        output_items = []

        has_reasoning = false
        reasoning_items_payload = msg["reasoning_items"] || msg[:reasoning_items]
        if reasoning_items_payload && !reasoning_items_payload.empty?
          Array(reasoning_items_payload).each do |entry|
            next unless entry.is_a?(Hash)
            normalized = entry.transform_keys { |k| k.to_s }
            normalized["type"] ||= "reasoning"
            normalized.delete("id")
            output_items << normalized
            has_reasoning = true
          end
        else
          reasoning_text = msg["reasoning_content"] || msg[:reasoning_content]
          if reasoning_text && !reasoning_text.to_s.strip.empty?
            output_items << {
              "type" => "reasoning",
              "content" => [{ "type" => "output_text", "text" => reasoning_text.to_s }]
            }
            has_reasoning = true
          end
        end

        if has_reasoning || content || !tool_calls.empty?
          output_items << {
            "type" => "message",
            "role" => "assistant",
            "content" => [{ "type" => "output_text", "text" => content.to_s }]
          }
        end

        tool_calls.each do |tool_call|
          call_id = tool_call["id"] || tool_call[:id]
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
        text_type = (role == "assistant") ? "output_text" : "input_text"

        if content.is_a?(Array)
          converted_content = content.map do |item|
            case item["type"]
            when "text"
              { "type" => text_type, "text" => item["text"] }
            when "image_url"
              { "type" => "input_image", "image_url" => item["image_url"]["url"] }
            when "file"
              if item["file"]["file_id"]
                { "type" => "input_file", "file_id" => item["file"]["file_id"] }
              elsif item["file"]["file_url"]
                { "type" => "input_file", "url" => item["file"]["file_url"] }
              else
                {
                  "type" => "input_file",
                  "filename" => item["file"]["filename"],
                  "file_data" => item["file"]["file_data"]
                }
              end
            else
              item
            end
          end
          { "role" => role, "content" => converted_content }
        else
          { "role" => role, "content" => [{ "type" => text_type, "text" => content.to_s }] }
        end
      end
    end.flatten.compact

    responses_body = {
      "model" => body["model"],
      "input" => input_messages,
      "stream" => body["stream"] || false,
      "store" => true
    }

    if body["reasoning_effort"] && body["reasoning_effort"] != "none"
      responses_body["reasoning"] = {
        "effort" => body["reasoning_effort"],
        "summary" => "auto"
      }
    end

    is_reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(model, "reasoning_effort")
    is_gpt5_model = model.to_s.downcase.include?("gpt-5")

    unless is_reasoning_model || is_gpt5_model
      responses_body["temperature"] = body["temperature"] if body["temperature"]
      responses_body["top_p"] = body["top_p"] if body["top_p"]
    end

    if is_gpt5_model
      responses_body.delete("temperature")
      responses_body.delete("top_p")
    end

    if body["max_completion_tokens"] || max_completion_tokens
      responses_body["max_output_tokens"] = body["max_completion_tokens"] || max_completion_tokens
    end

    # Add instructions (system prompt) if available
    if body["messages"].first && (body["messages"].first["role"] == "developer" || body["messages"].first["role"] == "system")
      system_msg = body["messages"].first
      if system_msg["content"].is_a?(Array)
        instructions_text = system_msg["content"].find { |c| c["type"] == "text" }&.dig("text")
      else
        instructions_text = system_msg["content"]
      end

      if instructions_text
        responses_body["instructions"] = instructions_text
        if input_messages.first && (input_messages.first["role"] == "developer" || input_messages.first["role"] == "system")
          input_messages.shift
        end
      end
    end

    # Document search policy hint for cloud mode
    begin
      current_app = obj["app"] || (defined?(session) ? session.dig(:parameters, "app_name") : nil)
      vs_hint_id = resolve_openai_vs_id(session)
      resolved_mode = resolve_pdf_storage_mode(session)
      app_has_docstore = begin
        APPS[current_app]&.settings&.[]("pdf_vector_storage")
      rescue StandardError
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

    if input_messages.empty?
      input_messages << {
        "role" => "user",
        "content" => [{ "type" => "input_text", "text" => "Let's start" }]
      }
    end

    if obj["previous_response_id"]
      responses_body["previous_response_id"] = obj["previous_response_id"]
    end

    if obj["background"]
      responses_body["background"] = true
    end

    # Add web search tool for responses API if needed
    if obj["use_responses_api_for_websearch"]
      responses_body["tools"] = [NATIVE_WEBSEARCH_TOOL]
      DebugHelper.debug("OpenAI: Adding web_search tool via Responses API", category: :api, level: :debug)
    end

    # Enhanced tool support for responses API
    if (body["tools"] && !body["tools"].empty?) || obj["responses_api_tools"]
      responses_body["tools"] ||= []

      if obj["responses_api_tools"]
        obj["responses_api_tools"].each do |tool_name, config|
          if RESPONSES_API_BUILTIN_TOOLS[tool_name]
            tool_def = RESPONSES_API_BUILTIN_TOOLS[tool_name]
            if tool_def.is_a?(Proc)
              responses_body["tools"] << tool_def.call(**config)
            else
              responses_body["tools"] << tool_def
            end
          end
        end
      end

      if body["tools"] && !body["tools"].empty?
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

      responses_body["tool_choice"] = body["tool_choice"] if body["tool_choice"]
      responses_body["parallel_tool_calls"] = true
    end

    # Attach File Search tool for Responses API
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
    if body["text"] && body["text"]["format"]
      responses_body["text"] = body["text"]
      if body["verbosity"] && Monadic::Utils::ModelSpec.supports_verbosity?(model)
        responses_body["text"]["verbosity"] = body["verbosity"]
      end
    elsif body["response_format"] && body["response_format"]["type"] == "json_object"
      responses_body["text"] = {
        "format" => {
          "type" => "json",
          "json_schema" => body["response_format"]["json_schema"] || {
            "name" => "response",
            "schema" => { "type" => "object", "additionalProperties" => true }
          }
        }
      }
    else
      if body["verbosity"] && Monadic::Utils::ModelSpec.supports_verbosity?(model)
        responses_body["text"] = { "verbosity" => body["verbosity"] }
      end
    end

    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      responses_body.delete("tools")
      responses_body.delete("tool_choice")
    end

    # Simplified logging for Responses API
    Monadic::Utils::ExtraLogger.log {
      lines = ["Responses API: model=#{responses_body['model']}, tools=#{responses_body['tools']&.length || 0}"]
      if responses_body['input']
        responses_body['input'].each_with_index do |msg, idx|
          if msg['content'].is_a?(Array)
            msg['content'].each do |item|
              if item['type'] == 'file' || item['type'] == 'input_file'
                lines << "  Message #{idx} has #{item['type']}: filename=#{item['filename'] || item.dig('file', 'filename')}"
              end
            end
          end
        end
      end
      lines.join("\n")
    }

    responses_body
  end

  # Execute the HTTP API call, handle retries, and route to streaming or non-streaming processing.
  private def execute_openai_api_call(headers, body, target_uri, app, session, obj,
                                      use_responses_api, reasoning_model, reasoning_effort,
                                      original_user_model, current_call_depth, num_retrial, &block)
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)
    model = body["model"]

    DebugHelper.debug("OpenAI API endpoint: #{target_uri}", category: :api, level: :debug)
    DebugHelper.debug("Using Responses API: #{use_responses_api}", category: :api, level: :debug)

    timeout_settings = if use_responses_api
                        { connect: open_timeout, write: write_timeout, read: 1200 }
                      elsif reasoning_model && reasoning_effort && %w[medium high].include?(reasoning_effort.to_s.downcase)
                        { connect: open_timeout, write: write_timeout, read: 600 }
                      else
                        { connect: open_timeout, write: write_timeout, read: read_timeout }
                      end

    res = nil
    MAX_RETRIES.times do
      if use_responses_api
        Monadic::Utils::ExtraLogger.log {
          if body["input"]&.any? { |msg| msg["content"]&.is_a?(Array) && msg["content"].any? { |c| c["type"] == "input_file" || c["type"] == "file" } }
            lines = ["DEBUG: Sending to Responses API with PDF content:", "Body structure: #{body.keys}"]
            body["input"].each_with_index do |msg, idx|
              if msg["content"].is_a?(Array)
                msg["content"].each do |item|
                  lines << "  Input[#{idx}] content type: #{item['type']}"
                end
              end
            end
            lines.join("\n")
          end
        }
      end

      res = http.timeout(**timeout_settings).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res&.status&.success?
      error_body = JSON.parse(res.body)
      error_report = error_body["error"]
      Monadic::Utils::ExtraLogger.log { "[OpenAI API Error] #{error_report}" }
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "OpenAI",
        message: error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      return [res]
    end

    if !body["stream"]
      obj = JSON.parse(res.body)

      if use_responses_api
        frag = ""
        output_array = obj.dig("response", "output") || obj["output"] || []

        output_array.each do |item|
          if item.is_a?(Hash)
            if item["type"] == "text" && item["text"]
              frag += item["text"]
            elsif item["type"] == "message" && item["content"]
              if item["content"].is_a?(Array)
                item["content"].each do |content_item|
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

        if frag.empty? && obj.dig("choices", 0, "message", "content")
          frag = obj.dig("choices", 0, "message", "content")
        end
      else
        frag = obj.dig("choices", 0, "message", "content")
      end

      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })

      if use_responses_api
        formatted_response = {
          "choices" => [{
            "message" => { "role" => "assistant", "content" => frag },
            "finish_reason" => "stop"
          }],
          "model" => obj["model"] || body["model"]
        }
        [formatted_response]
      else
        [obj]
      end
    else
      body["original_user_model"] = original_user_model

      if use_responses_api
        process_responses_api_data(app: app, session: session, query: body,
                                  res: res.body, call_depth: current_call_depth, &block)
      else
        process_json_data(app: app, session: session, query: body,
                          res: res.body, call_depth: current_call_depth, &block)
      end
    end
  end

  public

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    # Reset call_depth counter for each new user turn
    # This allows unlimited user iterations while preventing infinite loops within a single response
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
      session[:images_injected_this_turn] = Set.new

      # Reset help topics call tracking for new user turn
      # This allows the AI to perform fresh searches for each user question
      session[:parameters]["help_topics_call_count"] = 0 if session[:parameters]
      session[:parameters]["help_topics_prev_queries"] = [] if session[:parameters]
    end

    # Use per-turn counter instead of parameter for tracking
    current_call_depth = session[:call_depth_per_turn] || 0

    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]

    app = obj["app_name"]
    api_key = CONFIG["OPENAI_API_KEY"]

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    reasoning_effort = obj["reasoning_effort"]

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
    image_generation = obj["image_generation"] == true || obj["image_generation"].to_s == "true"

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

    # Resolve model capabilities
    caps = resolve_openai_model_capabilities(model, obj, use_responses_api, &block)
    websearch_enabled = caps[:websearch_enabled]
    websearch_prompt = caps[:websearch_prompt]
    reasoning_model = caps[:reasoning_model]

    DebugHelper.debug("OpenAI web search check - websearch_enabled: #{websearch_enabled}, model: #{model}, use_responses_api_for_websearch: #{caps[:use_responses_api_for_websearch]}", category: :api, level: :debug)

    # Store these variables in obj for later use in the method
    obj["websearch_enabled"] = websearch_enabled
    obj["use_responses_api_for_websearch"] = caps[:use_responses_api_for_websearch]

    # Update use_responses_api flag if we need it for websearch
    if caps[:use_responses_api_for_websearch] && !use_responses_api
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
                  "lang" => detect_language(message),
                  "app_name" => obj["app_name"]
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
        block&.call res

        # Check if this user message was already added by websocket.rb (for context extraction)
        # to avoid duplicate consecutive user messages that cause API errors
        existing_msg = session[:messages].find do |m|
          m["role"] == "user" && m["text"] == obj["message"]
        end

        if existing_msg
          # Update existing message with additional fields instead of adding new one
          existing_msg.merge!(res["content"])
        else
          session[:messages] << res["content"]
        end
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
    strip_inactive_image_data(session)

    # Prune old orchestration history to prevent the model from seeing stale
    # tool results and making duplicate calls, while keeping enough rounds
    # for iterative edit/variation workflows.
    if @clear_orchestration_history
      keep_rounds = @orchestration_keep_rounds || 1
      Monadic::Utils::ExtraLogger.log { "OpenAI: Pruning orchestration history (keep #{keep_rounds} rounds)\n  Original context size: #{context.size}\n  self.class: #{self.class.name}" }

      first_msg = context.first
      user_indices = context.each_index.select { |i| context[i]&.[]("role") == "user" }

      # keep_rounds+1 because we need N previous rounds + current user message
      needed = keep_rounds + 1
      if user_indices.length >= needed
        keep_from = user_indices[-needed]
        context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
      elsif user_indices.length >= 2
        keep_from = user_indices.first
        context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
      else
        last_user_msg = context.reverse.find { |msg| msg&.[]("role") == "user" }
        context = [first_msg]
        context << last_user_msg if last_user_msg && first_msg != last_user_msg
      end
      context.compact.each { |msg| msg["active"] = true }

      Monadic::Utils::ExtraLogger.log { "  Filtered context size: #{context.size}" }
    end

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Build base body and configure tools
    body = build_openai_base_body(model, obj, app, caps, max_completion_tokens, temperature, presence_penalty, frequency_penalty)
    configure_openai_tools(body, obj, app, session, role, caps, use_responses_api)

    # Process images and build messages
    image_file_references = prepare_openai_image_generation_refs(context, image_generation, role, shared_folder)
    messages_containing_img = build_openai_messages(
      body, context, session, obj, role, image_generation, image_file_references,
      reasoning_model, websearch_enabled, websearch_prompt, initial_prompt, prompt_suffix, message_with_snippet, &block
    )
    # build_openai_messages returns :early_return for vision errors
    return messages_containing_img if messages_containing_img.is_a?(Array)

    # Determine which API endpoint to use and convert body if needed
    if use_responses_api
      target_uri = "#{API_ENDPOINT}/responses"
      body = convert_to_responses_api_body(body, obj, model, session, max_completion_tokens, original_user_model, &block)
    else
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

    execute_openai_api_call(
      headers, body, target_uri, app, session, obj,
      use_responses_api, reasoning_model, reasoning_effort,
      original_user_model, current_call_depth, num_retrial, &block
    )
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = "The request has timed out."
      Monadic::Utils::ExtraLogger.log { "[OpenAI] #{error_message}" }
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
    Monadic::Utils::ExtraLogger.log { "[OpenAI] Unexpected error: #{e.message}\n[OpenAI] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "OpenAI",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log_json("Processing query (Call depth: #{call_depth})", query)

    obj = session[:parameters]
    # Determine reasoning model solely via model_spec
    reasoning_model = Monadic::Utils::ModelSpec.model_has_property?(obj["model"], "reasoning_effort")

    buffer = String.new
    texts = {}
    fragment_sequence = 0  # Sequence number for fragments to ensure ordering
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
      rescue StandardError
        next
      end

      # Skip encoding cleanup - buffer.valid_encoding? check above is sufficient
      # Encoding cleanup with replace: "" can delete valid bytes from incomplete multibyte characters
      # that will become complete when the next chunk arrives
      # buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      # buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      # Use multiline mode (m flag) to allow . to match newlines within JSON
      pattern = /data: (\{.*?\})(?=\n|\z)/m
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            # Log raw JSON data before parsing (for debugging delta issues)
            if Monadic::Utils::ExtraLogger.enabled?
              if json_data.include?("delta") && (json_data.include?("き") || json_data.include?("れ"))
                Monadic::Utils::ExtraLogger.log { "[RAW JSON BEFORE PARSE - Chat API] #{json_data}" }
              end
            end

            json = JSON.parse(json_data)

            Monadic::Utils::ExtraLogger.log_json("Chat API chunk", json)

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
              # Use String.new to create mutable string (file has frozen_string_literal: true)
              choice["message"]["content"] ||= String.new
              fragment = json.dig("choices", 0, "delta", "content").to_s
              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

              if fragment.length > 0
                res = {
                  "type" => "fragment",
                  "content" => fragment,
                  "sequence" => fragment_sequence,
                  "timestamp" => Time.now.to_f,
                  "is_first" => fragment_sequence == 0
                }
                fragment_sequence += 1
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
      Monadic::Utils::ExtraLogger.log { "[OpenAI Streaming] Error: #{e.message}\n[OpenAI Streaming] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    end

    result = texts.empty? ? nil : texts.first[1]

    if tools.any?
      assemble_openai_chat_tool_results(app, session, tools, result, &block)
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result["choices"][0]["finish_reason"] = finish_reason
      [result]
    else
      # Check for JupyterNotebook app fallback handling
      jupyter_result = handle_openai_jupyter_fallback(obj, session, &block)
      return jupyter_result if jupyter_result

      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  # Assemble tool call results from Chat API streaming and invoke process_functions.
  # Returns result Array.
  private def assemble_openai_chat_tool_results(app, session, tools_hash, result, &block)
    session[:call_depth_per_turn] += 1

    if session[:call_depth_per_turn] > MAX_FUNC_CALLS
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
    end

    context = []
    if result
      merged = result["choices"][0]["message"].merge(tools_hash.first[1]["choices"][0]["message"])
      context << merged
    else
      context << tools_hash.first[1].dig("choices", 0, "message")
    end

    tools = tools_hash.first[1].dig("choices", 0, "message", "tool_calls")

    new_results = process_functions(app, session, tools, context, session[:call_depth_per_turn], &block)

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

    # return Array
    if result && new_results
      [result].concat new_results
    elsif new_results
      new_results
    elsif result
      [result]
    end
  end

  # Handle JupyterNotebook app fallback when Chat API returns empty response.
  # Returns result Array if fallback was triggered, nil otherwise.
  private def handle_openai_jupyter_fallback(obj, session, &block)
    app_name = obj["app_name"].to_s
    return nil unless app_name.include?("JupyterNotebook") && app_name.include?("OpenAI")

    tool_results = session[:parameters]["tool_results"] || []
    has_successful_jupyter_result = tool_results.any? do |r|
      content = r.dig("functionResponse", "response", "content")
      content.is_a?(String) && !content.include?("ERRORS DETECTED") && (
        content.include?("executed successfully") ||
        content.include?("Notebook") && content.include?("created successfully") ||
        content.include?("Cells added to notebook")
      )
    end

    if has_successful_jupyter_result
      # Extract notebook link from tool results
      notebook_info = tool_results.find do |r|
        content = r.dig("functionResponse", "response", "content")
        content.is_a?(String) && content.include?(".ipynb")
      end
      notebook_content = notebook_info&.dig("functionResponse", "response", "content") || ""

      success_msg = "Notebook created and executed successfully."
      if notebook_content =~ /(http:\/\/[^\s]+\.ipynb)/
        link = $1
        filename = link.split("/").last
        success_msg += "\n\nAccess it at: <a href='#{link}' target='_blank'>#{filename}</a>"
      end

      res = { "type" => "fragment", "content" => success_msg }
      block&.call res
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => success_msg } }] }]
    end

    # Jupyter app but no successful result - check for errors
    notebook_error_result = tool_results.find do |r|
      content = r.dig("functionResponse", "response", "content")
      content.is_a?(String) && content.include?("ERRORS DETECTED")
    end

    if notebook_error_result
      error_content = notebook_error_result.dig("functionResponse", "response", "content")
      if error_content =~ /⚠️\s*ERRORS DETECTED.*?(?=\n\nAccess the notebook|$)/m
        error_summary = $&
      else
        error_summary = "Notebook execution errors occurred."
      end
      error_msg = "Errors occurred during notebook execution.\n\n#{error_summary}"
      res = { "type" => "fragment", "content" => error_msg }
      block&.call res
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => error_msg } }] }]
    end

    nil  # No fallback triggered
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]

    Monadic::Utils::ExtraLogger.log {
      lines = ["[DEBUG Tools] Processing #{tools.length} tool calls (depth: #{call_depth}):"]
      tools.each { |tc| lines << "  - #{tc.dig('function', 'name')} with args: #{tc.dig('function', 'arguments').to_s[0..200]}" }
      lines.join("\n")
    }

    tools = filter_openai_duplicate_tools(tools)

    pending_tool_images = nil
    tools.each do |tool_call|
      function_return, function_name, argument_hash, pending_tool_images = invoke_openai_tool_function(
        app, session, obj, tool_call, context, pending_tool_images, &block
      )
    end

    inject_openai_vision_images(context, session, pending_tool_images)

    obj["function_returns"] = context

    # Image/Video Generator intercept
    intercepted = intercept_openai_media_generation(context, session, &block)
    return intercepted if intercepted

    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected. Stopping." } }] }]
    end

    api_request("tool", session, call_depth: session[:call_depth_per_turn], &block)
  end

  # Remove duplicate tool calls and suppress repeated local PDF DB tool calls.
  private def filter_openai_duplicate_tools(tools)
    local_pdf_tools = %w[find_closest_text get_text_snippet list_titles find_closest_doc get_text_snippets]
    seen_functions = {}
    seen_local_group = false

    tools.select do |tc|
      fname = tc.dig('function', 'name').to_s
      args_sig = tc.dig('function', 'arguments').to_s
      sig = fname + '|' + args_sig
      next false if seen_functions[sig]
      seen_functions[sig] = true

      if local_pdf_tools.include?(fname)
        if seen_local_group
          DebugHelper.debug("Suppressing repeated local PDF tool call: #{fname}", category: :api, level: :info) rescue nil
          next false
        end
        seen_local_group = true
      end
      true
    end
  end

  # Execute a single tool function call: parse args, invoke, handle errors, collect results.
  # Returns [function_return, function_name, argument_hash, pending_tool_images].
  private def invoke_openai_tool_function(app, session, obj, tool_call, context, pending_tool_images, &block)
    tool_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    function_call = tool_call["function"]
    function_name = function_call["name"]
    block&.call({ "type" => "tool_executing", "content" => function_name })

    argument_hash = parse_function_call_arguments(function_call["arguments"], function_name: function_name)
    argument_hash = {} unless argument_hash.is_a?(Hash)

    argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
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
        method_obj = APPS[app].method(function_name.to_sym) rescue nil
        if method_obj && method_obj.parameters.any? { |type, name| name == :session }
          argument_hash[:session] = session
        end

        if argument_hash.empty?
          function_return = APPS[app].send(function_name.to_sym)
        else
          function_return = APPS[app].send(function_name.to_sym, **argument_hash)
        end

        Monadic::Utils::ExtraLogger.log { "[DEBUG Tools] #{function_name} returned: #{function_return.to_s[0..500]}" }

        send_verification_notification(session, &block) if function_name == "report_verification"

        Monadic::Utils::TtsTextExtractor.extract_tts_text(
          app: app,
          function_name: function_name,
          argument_hash: argument_hash,
          session: session
        )
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[OpenAI Tools] Error in #{function_name}: #{e.message}\n[OpenAI Tools] Backtrace: #{e.backtrace.first(5).join("\n")}" }
        function_return = Monadic::Utils::ErrorFormatter.tool_error(
          provider: "OpenAI",
          tool_name: function_name,
          message: e.message
        )
      end
    end

    if handle_function_error(session, function_return, function_name, &block)
      context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }
      return [function_return, function_name, argument_hash, pending_tool_images]
    end

    if function_return.is_a?(Hash) && function_return[:_image]
      pending_tool_images = Array(function_return[:_image])
      clean_return = function_return.reject { |k, _| k.to_s.start_with?("_") }
      serialized = JSON.generate(clean_return)
    else
      serialized = function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
    end

    if function_return.is_a?(Hash) && function_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << function_return[:gallery_html]
    end

    context << {
      tool_call_id: tool_call["id"],
      role: "tool",
      name: function_name,
      content: serialized
    }

    if CONFIG["EXTRA_LOGGING"]
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_start) * 1000).round(1)
      query_preview = argument_hash[:text].to_s[0..80]
      DebugHelper.debug("[ToolTiming] app=#{app} function=#{function_name} duration_ms=#{duration_ms} query=#{query_preview}", category: :metrics, level: :info)
    end

    [function_return, function_name, argument_hash, pending_tool_images]
  end

  # Inject screenshot image(s) as user message for vision-capable models.
  private def inject_openai_vision_images(context, session, pending_tool_images)
    return unless pending_tool_images&.any?

    injected_set = session[:images_injected_this_turn] ||= Set.new
    new_images = pending_tool_images.reject { |f| injected_set.include?(f) }

    return unless new_images.any?

    image_parts = new_images.filter_map do |img_filename|
      img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
      next unless img

      injected_set << img_filename
      { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}", "detail" => "high" } }
    end

    if image_parts.any?
      context << {
        role: "user",
        content: [
          { "type" => "text", "text" => "[Screenshot of the browser after the action above. Use this visual context to continue with your task.]" },
          *image_parts
        ]
      }
    end
  end

  # Intercept image/video generation results to prevent unnecessary recursive API calls.
  # Returns an Array result if intercepted, or nil to continue normal flow.
  private def intercept_openai_media_generation(context, session, &block)
    app_name = session[:parameters]["app_name"].to_s
    return nil unless @clear_orchestration_history && (app_name.include?("ImageGenerator") || app_name.include?("VideoGenerator"))

    context.each do |ctx|
      next unless ctx[:content].is_a?(String)
      response_content = ctx[:content]

      if response_content.include?("image_url") || (response_content.include?('"success"') && response_content.include?("filename"))
        begin
          parsed = JSON.parse(response_content)
          if parsed["image_url"]
            image_url = parsed["image_url"]
            prompt = parsed["prompt"] || "Image generation"

            image_html = <<~HTML
              <div class="prompt" style="margin-bottom: 15px;">
                <b>generate</b>: #{prompt}
              </div>
              <div class="generated_image">
                <img src="#{image_url}" style="max-width: 100%; border-radius: 8px; border: 1px solid #eee;">
              </div>
            HTML

            block&.call({ "type" => "fragment", "content" => image_html, "is_first" => true })
            block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
            return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => image_html } }] }]
          elsif parsed["success"] && parsed["filename"]
            filename = parsed["filename"]
            prompt = parsed["prompt"] || "Media generation"

            if filename.to_s.end_with?(".mp4")
              media_html = <<~HTML
                <div class="prompt" style="margin-bottom: 15px;">
                  <b>Prompt</b>: #{prompt}
                </div>
                <div class="generated_video">
                  <video controls width="600">
                    <source src="/data/#{filename}" type="video/mp4" />
                  </video>
                </div>
              HTML
            else
              media_html = <<~HTML
                <div class="prompt" style="margin-bottom: 15px;">
                  <b>generate</b>: #{prompt}
                </div>
                <div class="generated_image">
                  <img src="/data/#{filename}" style="max-width: 100%; border-radius: 8px; border: 1px solid #eee;">
                </div>
              HTML
            end

            block&.call({ "type" => "fragment", "content" => media_html, "is_first" => true })
            block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
            return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => media_html } }] }]
          end
        rescue JSON::ParserError
          # Continue to normal flow
        end
      end

      if response_content.include?("Successfully saved video") || response_content.include?(".mp4")
        if response_content =~ /\/data\/([^\s,]+\.mp4)/
          video_filename = $1
          prompt_match = response_content.match(/Original prompt: (.+?)(?:\n|$)/)
          prompt = prompt_match ? prompt_match[1] : "Video generation"

          video_html = <<~HTML
            <div class="prompt" style="margin-bottom: 15px;">
              <b>Prompt</b>: #{prompt}
            </div>
            <div class="generated_video">
              <video controls width="600">
                <source src="/data/#{video_filename}" type="video/mp4" />
              </video>
            </div>
          HTML

          block&.call({ "type" => "fragment", "content" => video_html, "is_first" => true })
          block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
          return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => video_html } }] }]
        end
      end

      if response_content.include?('"error"') || response_content.include?('"success":false') || response_content.include?('"success": false')
        begin
          parsed = JSON.parse(response_content)
          error_msg = parsed["error"] || parsed["message"] || "Media generation failed"

          block&.call({ "type" => "fragment", "content" => error_msg, "is_first" => true })
          block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
          return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => error_msg } }] }]
        rescue JSON::ParserError
          # Continue to normal flow
        end
      end
    end

    nil
  end

  public

  def normalize_function_call_arguments(raw_arguments)
    return "" if raw_arguments.nil?

    normalized = raw_arguments.dup

    # Single-pass replacement using pre-compiled regex (21x fewer string scans)
    normalized.gsub!(SMART_QUOTE_REGEX) { |match| SMART_QUOTE_REPLACEMENTS[match] }

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
    Monadic::Utils::ExtraLogger.log {
      lines = ["[OpenAIHelper] Failed to parse tool arguments:"]
      lines << "  Tool: #{function_name || 'unknown'}"
      lines << "  Error: #{error.class}: #{error.message}" if error
      preview = arguments.to_s[0..500]
      lines << "  Arguments preview: #{preview}"
      lines << "---"
      lines.join("\n")
    }
  end

  def process_responses_api_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log_json("Processing responses API query (Call depth: #{call_depth})", query)

    obj = session[:parameters]
    buffer = String.new
    chunk_count = 0

    state = {
      texts: {},
      tools: {},
      finish_reason: nil,
      current_tool_calls: [],
      reasoning_segments: [],
      reasoning_indices: {},
      current_reasoning_id: nil,
      reasoning_items_raw: {},  # Store original reasoning items for reconstruction
      web_search_results: [],
      file_search_results: [],
      image_generation_status: {},
      # Track usage reported by Responses API
      usage_input_tokens: nil,
      usage_output_tokens: nil,
      usage_total_tokens: nil,
      fragment_sequence: 0,  # Sequence number for fragments to ensure ordering
      streaming_model: nil
    }
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
      rescue StandardError
        next
      end

      # Skip encoding cleanup - buffer.valid_encoding? check above is sufficient
      # Encoding cleanup with replace: "" can delete valid bytes from incomplete multibyte characters
      # that will become complete when the next chunk arrives
      # buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      # buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      # Responses API uses different event format
      # Use multiline mode (m flag) to allow . to match newlines within JSON
      pattern = /data: (\{.*?\})(?=\n|\z)/m
      
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            # Log raw JSON data before parsing (for debugging delta issues)
            if Monadic::Utils::ExtraLogger.enabled?
              if json_data.include?("output_text.delta") && (json_data.include?("き") || json_data.include?("れ"))
                Monadic::Utils::ExtraLogger.log { "[RAW JSON BEFORE PARSE] #{json_data}" }
              end
            end

            json = JSON.parse(json_data)

            Monadic::Utils::ExtraLogger.log_json("Responses API chunk", json)

            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            # Store the model for use throughout streaming
            state[:streaming_model] = response_model || requested_model

            # Dispatch event to handler; returns nil (continue), :skip (next), or Array (early return)
            event_type = json["type"]
            result = dispatch_openai_response_event(json, event_type, state, query, obj, &block)
            if result == :skip
              next
            elsif result.is_a?(Array)
              return result
            end
            
          rescue JSON::ParserError => e
            # JSON parsing error, continue to next iteration
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[OpenAI Events] Error: #{e.message}\n[OpenAI Events] Backtrace: #{e.backtrace.first(5).join("\n")}" }
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

    # Handle tool calls if any were collected
    tool_result = assemble_openai_tool_results_from_responses(app, session, state, &block)
    return tool_result if tool_result

    # Return text response
    build_openai_text_response(state, query, obj, &block)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[OpenAI] Unexpected error: #{e.message}\n[OpenAI] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "OpenAI",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end

  # Dispatch a single Responses API SSE event to the appropriate handler.
  # Returns nil to continue, :skip to skip to next event, or Array for early return.
  private def dispatch_openai_response_event(json, event_type, state, query, obj, &block)
    case event_type
    when "response.created"
      # Store model information from response.created event if available
      if json["response"] && json["response"]["model"]
        state[:streaming_model] = json["response"]["model"]
      end

    when "response.in_progress"
      # IMPORTANT: GPT-5, GPT-4.1, and chatgpt-4o models emit BOTH response.in_progress
      # AND response.output_text.delta events, causing duplicate text fragments.
      # We skip response.in_progress for these models to prevent duplication.
      response_data = json["response"]

      if response_data && response_data["model"]
        state[:streaming_model] = response_data["model"]
      end

      current_model = state[:streaming_model] ||
                      json["model"] ||
                      response_data&.dig("metadata", "model") ||
                      response_data&.dig("model") ||
                      query["model"] ||
                      obj["model"]

      Monadic::Utils::ExtraLogger.log { "[OpenAI Streaming] response.in_progress event\n  current_model: #{current_model}\n  streaming_model: #{state[:streaming_model]}\n  Will skip: #{current_model && Monadic::Utils::ModelSpec.skip_in_progress_events?(current_model)}" }

      # Skip for models that emit proper delta events (configured in ModelSpec)
      if current_model && Monadic::Utils::ModelSpec.skip_in_progress_events?(current_model)
        Monadic::Utils::ExtraLogger.log { "[OpenAI Streaming] Skipping response.in_progress for model: #{current_model}" }
        return :skip
      end

      if response_data
        if response_data["output"] && !response_data["output"].empty?
          output = response_data["output"]
          output.each do |item|
            if item["type"] == "text" && item["text"]
              id = response_data["id"] || "default"
              state[:texts][id] ||= ""
              current_text = item["text"]

              # Calculate the delta - only send the new portion
              if current_text.length > state[:texts][id].length
                delta = current_text[state[:texts][id].length..-1]
                state[:texts][id] = current_text  # Update stored text
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
      if Monadic::Utils::ExtraLogger.enabled?
        current_model = state[:streaming_model] || json["model"] || query["model"] || obj["model"]
        if current_model && (current_model.to_s.downcase.include?("gpt-5") || current_model.to_s.include?("gpt-4.1"))
          Monadic::Utils::ExtraLogger.log { "[OpenAI Streaming] response.output_text.delta for #{current_model} - fragment: #{fragment.inspect}, sequence: #{state[:fragment_sequence]}" }
        end
      end

      if fragment && !fragment.empty?
        id = json["response_id"] || json["item_id"] || "default"
        state[:texts][id] ||= ""

        # Use sequence number instead of text length for reliable ordering
        # Increment sequence for each fragment sent
        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => state[:fragment_sequence],
          "timestamp" => Time.now.to_f,
          "is_first" => state[:fragment_sequence] == 0
        }

        state[:fragment_sequence] += 1
        state[:texts][id] += fragment
        block&.call res
      end

    when "response.output_text.done"
      # Text output completed
      text = json["text"]
      if text
        id = json["item_id"] || "default"
        state[:texts][id] = text  # Final text
      end

    when "response.output_item.added"
      # New output item added
      item = json["item"]

      if item && item["type"] == "function_call"
        # Store the function name and ID for later use
        item_id = item["id"]
        if item_id
          state[:tools][item_id] ||= {}
          state[:tools][item_id]["name"] = item["name"] if item["name"]
          state[:tools][item_id]["call_id"] = item["call_id"] if item["call_id"]
          state[:tools][item_id]["arguments"] ||= ""
        end
        res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
        block&.call res
      elsif item && item["type"] == "reasoning"
        rid = item["id"]
        state[:current_reasoning_id] = rid if rid
        segment = ensure_openai_reasoning_segment(state, rid)

        # Reasoning content can be in item["content"] or item["summary"]
        if item["summary"].is_a?(Array)
          # With summary: "auto", reasoning text is in the summary array
          # Extract text from summary_text items
          summary_text = item["summary"].filter_map do |entry|
            next unless entry.is_a?(Hash) && entry["type"] == "summary_text"

            text = entry["text"]
            if text.nil? || text.to_s.empty?
              STDERR.puts "[OpenAI] Reasoning summary_text entry with no text: #{entry.inspect}" if ENV["EXTRA_LOGGING"] == "true"
              next
            end

            text.to_s
          end.join("\n\n")

          if summary_text.empty?
            STDERR.puts "[OpenAI] Reasoning summary array returned no text: #{item["summary"].inspect}" if ENV["EXTRA_LOGGING"] == "true"
          else
            segment[:text] << summary_text
          end
        elsif item["content"]
          segment[:text] << extract_openai_reasoning_text(item["content"])
        else
          STDERR.puts "[OpenAI] Reasoning item has neither summary nor content: #{item.inspect}" if ENV["EXTRA_LOGGING"] == "true"
        end
      end

    when "response.output_item.done"
      # Output item completed
      item = json["item"]

      if item && item["type"] == "function_call"
        item_id = item["id"]
        if item_id
          # Create or update tool entry
          state[:tools][item_id] ||= {}
          state[:tools][item_id]["name"] = item["name"] if item["name"]
          state[:tools][item_id]["arguments"] = item["arguments"] if item["arguments"]
          state[:tools][item_id]["call_id"] = item["call_id"] if item["call_id"]
          state[:tools][item_id]["completed"] = true
        end
      elsif item && item["type"] == "reasoning"
        rid = item["id"]
        state[:current_reasoning_id] = rid if rid
        segment = ensure_openai_reasoning_segment(state, rid)

        # Store the original reasoning item for reconstruction
        if rid
          state[:reasoning_items_raw][rid] = item
        end

        # Only set text if not already accumulated from delta events
        # This prevents duplication when both delta and done events provide the same text
        if segment[:text].to_s.empty?
          # Reasoning content can be in item["content"] or item["summary"]
          if item["summary"].is_a?(Array)
            # With summary: "auto", reasoning text is in the summary array
            # Extract text from summary_text items
            summary_text = item["summary"].filter_map do |entry|
              next unless entry.is_a?(Hash) && entry["type"] == "summary_text"

              text = entry["text"]
              if text.nil? || text.to_s.empty?
                STDERR.puts "[OpenAI] Reasoning summary_text entry with no text: #{entry.inspect}" if ENV["EXTRA_LOGGING"] == "true"
                next
              end

              text.to_s
            end.join("\n\n")

            if summary_text.empty?
              STDERR.puts "[OpenAI] Reasoning summary array returned no text: #{item["summary"].inspect}" if ENV["EXTRA_LOGGING"] == "true"
            else
              segment[:text] = summary_text
            end
          elsif item["content"]
            segment[:text] = extract_openai_reasoning_text(item["content"])
          else
            STDERR.puts "[OpenAI] Reasoning item has neither summary nor content: #{item.inspect}" if ENV["EXTRA_LOGGING"] == "true"
          end
        end
      end

    when "response.function_call_arguments.delta", "response.function_call.arguments.delta", "response.function_call.delta"
      # Tool call arguments fragment
      item_id = json["item_id"]
      delta = json["delta"]

      if item_id && delta
        state[:tools][item_id] ||= {}
        state[:tools][item_id]["arguments"] ||= ""
        state[:tools][item_id]["arguments"] += delta
      end

    when "response.function_call_arguments.done", "response.function_call.arguments.done", "response.function_call.done"
      # Tool call arguments completed
      item_id = json["item_id"]
      arguments = json["arguments"]
      name = json["name"]

      if item_id
        state[:tools][item_id] ||= {}
        state[:tools][item_id]["arguments"] = arguments if arguments
        state[:tools][item_id]["name"] = name if name
        state[:tools][item_id]["completed"] = true
      end

    when "response.reasoning_summary_text.delta"
      # Reasoning summary delta (streaming)
      rid = json["item_id"] || state[:current_reasoning_id]
      delta = json["delta"]

      if delta && !delta.to_s.empty?
        segment = ensure_openai_reasoning_segment(state, rid)
        segment[:text] << delta.to_s
        state[:current_reasoning_id] = rid if rid

        # Send reasoning delta to frontend (like Claude's thinking)
        res = {
          "type" => "reasoning",
          "content" => delta.to_s
        }
        block&.call res
      else
        # Log unexpected delta structure
        STDERR.puts "[OpenAI] Reasoning delta event with no text: #{json.inspect}" if ENV["EXTRA_LOGGING"] == "true"
      end

    when "response.reasoning_summary_text.done", "response.reasoning_summary_part.done"
      # Reasoning summary completed - text is already accumulated from deltas
      rid = json["item_id"] || state[:current_reasoning_id]
      if rid
        state[:current_reasoning_id] = nil
      end

    when "response.web_search_call.in_progress"
      # Web search started
      res = { "type" => "wait", "content" => "<i class='fas fa-search'></i> SEARCHING WEB" }
      block&.call res

    when "response.web_search_call.searching"
      # Web search in progress

    when "response.web_search_call.completed"
      # Web search completed
      item_id = json["item_id"]
      if item_id
        state[:web_search_results] << item_id
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
        state[:file_search_results] << item_id
      end

    when "response.image_generation_call.in_progress"
      # Image generation started
      item_id = json["item_id"]
      if item_id
        state[:image_generation_status][item_id] = "in_progress"
        res = { "type" => "wait", "content" => "<i class='fas fa-image'></i> GENERATING IMAGE" }
        block&.call res
      end

    when "response.image_generation_call.generating"
      # Image generation in progress
      item_id = json["item_id"]
      if item_id
        state[:image_generation_status][item_id] = "generating"
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
        state[:image_generation_status][item_id] = "completed"
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
        state[:tools][item_id] ||= { "mcp_arguments" => {} }
        state[:tools][item_id]["mcp_arguments"].merge!(delta)
      end

    when "response.mcp_call.arguments.done"
      # MCP arguments completed
      item_id = json["item_id"]
      arguments = json["arguments"]
      if item_id && arguments
        state[:tools][item_id] ||= {}
        state[:tools][item_id]["mcp_arguments"] = arguments
        state[:tools][item_id]["mcp_completed"] = true
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
        state[:usage_input_tokens] = usage["input_tokens"] || usage["prompt_tokens"] || state[:usage_input_tokens]
        state[:usage_output_tokens] = usage["output_tokens"] || usage["completion_tokens"] || state[:usage_output_tokens]
        state[:usage_total_tokens] = usage["total_tokens"] || (state[:usage_input_tokens].to_i + state[:usage_output_tokens].to_i if state[:usage_input_tokens] && state[:usage_output_tokens]) || state[:usage_total_tokens]
      end


      if response_data && response_data["output"] && !response_data["output"].empty?
        output = response_data["output"]
        output.each do |item|
          if item["type"] == "text" && item["text"]
            id = response_data["id"] || "default"
            state[:texts][id] ||= ""
            state[:texts][id] = item["text"]  # Replace with final text

          end
        end
      else
      end
      state[:finish_reason] = response_data["stop_reason"] || json["stop_reason"] || "stop"

    when "response.output.done"
      # Alternative completion event
      # Extract final output if available
      if json["output"]
        output_text = json.dig("output", 0, "content", 0, "text")
        if output_text && !output_text.empty?
          id = json["response_id"] || "default"
          state[:texts][id] ||= ""
          state[:texts][id] = output_text  # Replace with final text
        end
      end
      state[:finish_reason] = "stop"

    when "response.error"
      # Error occurred
      error_msg = json.dig("error", "message") || "Unknown error"
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "OpenAI",
        message: error_msg
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res

      return [res]

    else
      # Unknown event type
    end

    nil
  end

  # Assemble tool call results from Responses API events and invoke process_functions.
  # Returns result Array if tools were processed, nil otherwise.
  private def assemble_openai_tool_results_from_responses(app, session, state, &block)
    return nil unless state[:tools].any? && state[:tools].any? { |_, tool| tool["completed"] || tool["mcp_completed"] }

    obj = session[:parameters]
    session[:call_depth_per_turn] += 1

    if session[:call_depth_per_turn] > MAX_FUNC_CALLS
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
      return []
    end

    # Process function tools
    function_results = []
    state[:tools].each do |item_id, tool_data|
      if tool_data["completed"] && tool_data["arguments"]
        function_results << {
          "id" => tool_data["call_id"] || item_id,
          "function" => {
            "name" => tool_data["name"] || "unknown",
            "arguments" => tool_data["arguments"]
          }
        }
      elsif tool_data["mcp_completed"] && tool_data["mcp_arguments"]
        function_results << {
          "id" => tool_data["call_id"] || item_id,
          "type" => "mcp",
          "function" => {
            "name" => tool_data["name"] || "mcp_tool",
            "arguments" => JSON.generate(tool_data["mcp_arguments"])
          }
        }
      end
    end

    return nil unless function_results.any?

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

    if state[:texts].any?
      complete_text = state[:texts].values.join("")
      message["content"] = complete_text
    end

    # Build reasoning entries using original structure when available
    reasoning_entries = state[:reasoning_segments].filter_map do |segment|
      text = segment[:text].to_s.strip
      next if text.empty?

      # Use original reasoning item if available (preserves summary structure)
      segment_id = segment[:id]
      if segment_id && state[:reasoning_items_raw][segment_id]
        original_item = state[:reasoning_items_raw][segment_id]
        # Preserve original structure (may have summary or content)
        original_item.transform_keys(&:to_s)
      else
        # Fallback to content structure
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

    new_results = process_functions(app, session, tool_calls, context, session[:call_depth_per_turn], &block)

    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return new_results || []
    end

    new_results || []
  end

  # Build the final text response from accumulated Responses API state.
  private def build_openai_text_response(state, query, obj, &block)
    if state[:texts].any?
      complete_text = state[:texts].values.join("")

      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => complete_text
          },
          "finish_reason" => state[:finish_reason] || "stop"
        }],
        "model" => query["model"]
      }
      # Attach usage if available
      if state[:usage_input_tokens] || state[:usage_output_tokens] || state[:usage_total_tokens]
        response["usage"] = {
          "input_tokens" => state[:usage_input_tokens],
          "output_tokens" => state[:usage_output_tokens],
          "total_tokens" => state[:usage_total_tokens]
        }.compact
      end

      reasoning_texts = state[:reasoning_segments].map { |segment| segment[:text].to_s.strip }.reject(&:empty?)
      if reasoning_texts.any?
        response["choices"][0]["message"]["reasoning_content"] = reasoning_texts.join("\n\n")
        obj["reasoning_context"] = JSON.parse(JSON.generate(state[:reasoning_segments].filter_map do |segment|
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

      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => state[:finish_reason] || "stop" })
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
  end

  # Extract text from a reasoning content array.
  private def extract_openai_reasoning_text(content_array)
    return "" unless content_array.is_a?(Array)
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

  # Find or create a reasoning segment in the state, indexed by reasoning ID.
  private def ensure_openai_reasoning_segment(state, rid)
    identifier = rid || state[:current_reasoning_id] || :__default_reasoning__
    index = state[:reasoning_indices][identifier] if identifier && state[:reasoning_indices].key?(identifier)

    if index.nil?
      index = state[:reasoning_segments].length
      state[:reasoning_segments] << { text: String.new, id: rid }
      state[:reasoning_indices][identifier] = index if identifier
    end

    state[:reasoning_segments][index]
  end

  public

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

  # Document MIME types supported by OpenAI File Inputs API
  DOCUMENT_MIME_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    text/csv text/plain text/markdown text/html text/xml application/json
    text/yaml
    text/x-python application/javascript text/javascript application/typescript
    text/x-ruby text/x-java-source text/x-c text/x-c++src
    text/x-go text/x-rustsrc text/x-shellscript
  ].freeze

  # Check if a MIME type is a document (non-image) type supported by File Inputs API
  def document_type?(mime_type)
    return false if mime_type.nil? || mime_type.empty?

    DOCUMENT_MIME_TYPES.include?(mime_type)
  end

  # Attempt to resolve a file_id from the OpenAI File Inputs cache.
  # Returns file_id string on success, nil on failure (caller falls back to base64).
  def resolve_file_id_for_input(session, img)
    return nil unless img["data"].is_a?(String) && img["data"].include?(";base64,")

    # Parse data URI → mime_type, base64_data
    _header, base64_data = img["data"].split(";base64,", 2)
    return nil if base64_data.nil? || base64_data.empty?

    filename = img["title"] || "document"
    mime_type = img["type"] || "application/octet-stream"

    Monadic::Utils::OpenAIFileInputsCache.resolve_or_upload(
      session, base64_data, filename, mime_type
    )
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[OpenAIHelper] resolve_file_id_for_input error: #{e.message}" }
    nil
  end
end
