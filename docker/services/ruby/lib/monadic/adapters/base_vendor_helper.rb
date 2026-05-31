# frozen_string_literal: true

# BaseVendorHelper
# Shared utilities for vendor helpers. Provides macros for common patterns
# (timeouts, model cache) to reduce boilerplate across providers.
# Each vendor helper can adopt these incrementally without changing behavior.

module BaseVendorHelper
  DEFAULT_MAX_RETRIES = 5
  DEFAULT_RETRY_DELAY = 1 # seconds

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Generates timeout class methods and instance methods for a vendor.
    # Each method reads from CONFIG with a fallback to the specified default.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_timeouts "OPENAI", open: 20, read: 600, write: 120
    #   end
    #
    # This creates:
    #   - OpenAIHelper.open_timeout  (class method, reads CONFIG["OPENAI_OPEN_TIMEOUT"])
    #   - instance.open_timeout      (delegates to class method)
    #   - Same for read_timeout and write_timeout
    def define_timeouts(prefix, open: 10, read: 600, write: 120)
      vendor_mod = self

      { open_timeout: [open, "OPEN"], read_timeout: [read, "READ"], write_timeout: [write, "WRITE"] }.each do |method_name, (default_val, suffix)|
        config_key = "#{prefix}_#{suffix}_TIMEOUT"

        define_singleton_method(method_name) do
          defined?(CONFIG) ? (CONFIG[config_key]&.to_i || default_val) : default_val
        end

        define_method(method_name) do
          vendor_mod.public_send(method_name)
        end
      end
    end

    # Generates a clear_models_cache method for the given cache key.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_models_cache :openai
    #   end
    #
    # This creates:
    #   - instance.clear_models_cache  (sets $MODELS[:openai] = nil)
    def define_models_cache(cache_key)
      define_method(:clear_models_cache) do
        $MODELS[cache_key] = nil
      end
    end

    # Generates list_models (instance + class) and clear_models_cache methods.
    # Replaces the boilerplate cache-check → auth → HTTP GET → parse → cache pattern.
    #
    # The block receives the parsed JSON response body and must return an Array of
    # model ID strings. If omitted, defaults to `json["data"].map { |m| m["id"] }`.
    #
    # Usage:
    #   define_model_lister :deepseek,
    #     api_key_config: "DEEPSEEK_API_KEY",
    #     endpoint_path: "/models" do |json|
    #       json["data"].sort_by { |m| m["created"] }.reverse.map { |m| m["id"] }
    #         .reject { |id| id.include?("embed") }
    #     end
    #
    # Options:
    #   cache_key        - Symbol for $MODELS cache (e.g. :deepseek)
    #   api_key_config:  - CONFIG key for the API key (e.g. "DEEPSEEK_API_KEY")
    #   endpoint_path:   - Path appended to API_ENDPOINT (e.g. "/models")
    #   headers:         - Lambda receiving api_key, returns headers hash.
    #                      Default: Bearer token + Content-Type JSON.
    #   fallback_provider: - Provider name for ModelSpec fallback on failure (e.g. "anthropic").
    #                        nil means return [] on failure (original behavior for most providers).
    def define_model_lister(cache_key, api_key_config:, endpoint_path:, headers: nil, fallback_provider: nil, &parser)
      vendor_mod = self

      default_headers = ->(api_key) {
        { "Content-Type" => "application/json", "Authorization" => "Bearer #{api_key}" }
      }
      headers_builder = headers || default_headers

      default_parser = ->(json) {
        (json["data"] || []).map { |m| m["id"] }
      }
      model_parser = parser || default_parser

      fallback_proc = if fallback_provider
        -> {
          models = Monadic::Utils::ModelSpec.get_provider_models(fallback_provider, "chat") rescue []
          $MODELS[cache_key] = models
          models
        }
      else
        -> { [] }
      end

      # Instance method: list_models
      define_method(:list_models) do
        return $MODELS[cache_key] if $MODELS[cache_key]

        api_key = CONFIG[api_key_config]
        return fallback_proc.call if api_key.nil? || api_key.to_s.strip.empty?

        target_uri = "#{vendor_mod.const_get(:API_ENDPOINT)}#{endpoint_path}"
        http = HTTP.headers(headers_builder.call(api_key))

        begin
          res = http.get(target_uri)
          if res.status.success?
            json = JSON.parse(res.body)
            $MODELS[cache_key] = model_parser.call(json)
            $MODELS[cache_key]
          else
            fallback_proc.call
          end
        rescue HTTP::Error, HTTP::TimeoutError, StandardError
          fallback_proc.call
        end
      end

      # Class method: list_models (for DSL access)
      define_singleton_method(:list_models) do
        # Delegate to instance method via a temporary instance
        allocator = Class.new { include vendor_mod }
        allocator.new.list_models
      end

      # clear_models_cache (unless already defined by define_models_cache)
      unless method_defined?(:clear_models_cache)
        define_method(:clear_models_cache) do
          $MODELS[cache_key] = nil
        end
      end
    end
  end

  # Strip base64 image data from inactive session messages to prevent
  # unbounded session growth.  Keeps filenames/titles so auto-attach
  # (fetch_last_images_from_session) can still locate files on disk.
  # Idempotent — safe to call on every request.
  def strip_inactive_image_data(session)
    return unless session[:messages].is_a?(Array)

    session[:messages].each do |msg|
      next if msg.nil? || msg["active"]

      # "images" array (Gemini image gen, user uploads)
      if msg["images"].is_a?(Array)
        msg["images"].each do |img|
          next unless img.is_a?(Hash)
          if img["data"].is_a?(String) && img["data"].start_with?("data:")
            img["data"] = "[stripped]"
          end
        end
      end

      # "content" array — OpenAI multimodal format
      if msg["content"].is_a?(Array)
        msg["content"].each do |part|
          next unless part.is_a?(Hash)
          if part["type"] == "image_url" && part.dig("image_url", "url")&.start_with?("data:")
            part["image_url"]["url"] = "[stripped]"
          end
        end
      end
    end
  end

  # Privacy Filter integration helpers.
  # Vendor helpers call apply_privacy_to_messages just before http.post and
  # restore_response_text after the response text is finalized. The work is
  # delegated to a session-scoped Pipeline so registry state survives across
  # turns within the same conversation.
  #
  # Two-gate activation: the app must declare `privacy do; enabled true; end`
  # in MDSL AND the user must opt in via the session-level toggle (in Session
  # Controls). Default OFF means privacy filter is fully opt-in per session.
  def privacy_enabled_for?(app_settings, session = nil)
    return false unless app_settings && app_settings.dig(:privacy, :enabled) == true
    # Duck-typed gate: production Rack sessions
    # (Rack::Session::Abstract::PersistedSecure::SecureSessionHash) are not
    # Hash subclasses but do support `[]`. Tightening to `is_a?(Hash)` would
    # disable masking entirely in production while passing plain-Hash unit
    # fixtures.
    return false unless session && session.respond_to?(:[])

    # Backend-authoritative session state. PRIVACY_TOGGLE is the only path
    # that sets this key, and only after a container health check, so a
    # missing key means "user has not opted in" and we must not mask.
    session[:_privacy_session_enabled] == true
  end

  def privacy_pipeline_for(session, app_settings)
    return nil unless privacy_enabled_for?(app_settings, session)
    session[:_privacy_pipeline] ||= begin
      require_relative '../utils/privacy/pipeline'
      Monadic::Utils::Privacy::Pipeline.new(
        backend: Monadic::Utils::Privacy::PresidioBackend.new,
        config: app_settings[:privacy],
        session: session
      )
    end
  end

  # Substitution Pipeline integration (Vocabulary provider only).
  #
  # Vocabulary lets the user and assistant share `${TOKEN}` variables (e.g.
  # ${SHARED} for the synced data folder). It is opt-in per app via a
  # `vocabulary do; use :shared; end` MDSL block and carries zero overhead for
  # apps that do not declare it.
  #
  # Privacy is deliberately NOT registered here: it stays on its own
  # `:_privacy_pipeline` hot path. The two providers have opposite failure
  # contracts (Privacy :closed for PII safety, Vocabulary :open so a miss never
  # breaks a turn) and independent lifecycles, so they are kept on separate
  # pipelines.
  #
  # @return [Monadic::Substitution::Pipeline, nil] nil when the app exposes no
  #   vocabulary tokens (the common case).
  def substitution_pipeline_for(session, app_settings)
    require_relative '../substitution/vocabulary'
    # Default-on policy: ${SHARED} is available to every app unless it opts out
    # with `vocabulary false`. Vocabulary.build_pipeline is the single source of
    # truth for both token selection (shared with the system-prompt injector)
    # and pipeline construction (shared with the streaming handler attach site).
    Monadic::Substitution::Vocabulary.build_pipeline(session, app_settings)
  end

  # Expand owned `${TOKEN}`s in a tool-call argument structure just before the
  # tool runs, so tools operate on real (mode-aware) paths. Deep over
  # Hash/Array/String; non-string values (incl. the injected :session) pass
  # through. Non-fatal: Vocabulary is :open, so the Pipeline swallows provider
  # errors and returns the value-so-far. No-op (returns args) when the app has
  # no vocabulary.
  def expand_tool_args_for_vocabulary(args, session, app_settings)
    pipeline = substitution_pipeline_for(session, app_settings)
    return args unless pipeline
    pipeline.process_tool_invoke(nil, args)
  end

  # Decorate owned `${TOKEN}`s in finalized display text (keeps the symbol,
  # wraps it in <code> with a hover title of the resolved value). Display-only —
  # never apply to the TTS buffer.
  def decorate_response_text(text, session, app_settings)
    return text unless text.is_a?(String) && !text.empty?
    pipeline = substitution_pipeline_for(session, app_settings)
    return text unless pipeline
    pipeline.process_output(text)
  end

  # Replace masked text in user/assistant messages with placeholders.
  # Returns a new array so callers can keep the original messages
  # untouched. The system_prompt is never masked — privacy filtering
  # applies to conversational turns only.
  #
  # Why both user and assistant: session[:messages] stores the **restored**
  # text for past assistant responses (the user-visible form with real
  # values restored from `<<TYPE_N>>` placeholders). When that history is
  # replayed as context on the next turn, those past assistant entries
  # would otherwise leak the original PII to the LLM API. Re-masking is
  # safe because the privacy backend's `_build_masked` reuses any
  # (type, original) pair already in the registry — placeholder numbering
  # stays stable across turns.
  #
  # Handles two payload shapes:
  #   1. Chat Completions: content is a String
  #   2. Responses API: content is Array of {type, text} items
  def apply_privacy_to_messages(messages, session, app_settings)
    pipeline = privacy_pipeline_for(session, app_settings)
    return messages unless pipeline

    require_relative '../utils/privacy/types'
    # Note: language detection for "auto" mode happens upstream in
    # handle_ws_streaming on the raw user-typed text, not here. Hooking it
    # here would see vendor-adapter-injected placeholders (e.g. OpenAI
    # Responses API's "Let's start" filler) and lock to the wrong language.
    messages.map do |msg|
      role = msg[:role] || msg["role"]
      # System / developer / tool roles are app-defined (system prompts,
      # tool plumbing) and must not be re-masked.
      next msg unless %w[user assistant].include?(role.to_s)
      text_key = msg.key?(:content) ? :content : "content"
      content = msg[text_key]

      if content.is_a?(String)
        raw = Monadic::Utils::Privacy::RawMessage.new(content, "user", {})
        masked = pipeline.before_send_to_llm(raw)
        msg.merge(text_key => masked.text)
      elsif content.is_a?(Array)
        new_content = content.map do |item|
          next item unless item.is_a?(Hash)
          item_type = (item[:type] || item["type"]).to_s
          next item unless %w[input_text text].include?(item_type)
          item_text_key = item.key?(:text) ? :text : "text"
          text = item[item_text_key]
          next item unless text.is_a?(String) && !text.empty?
          raw = Monadic::Utils::Privacy::RawMessage.new(text, "user", {})
          masked = pipeline.before_send_to_llm(raw)
          item.merge(item_text_key => masked.text)
        end
        msg.merge(text_key => new_content)
      else
        msg
      end
    end
  end

  def restore_response_text(text, session, app_settings)
    pipeline = privacy_pipeline_for(session, app_settings)
    return text unless pipeline
    return text unless text.is_a?(String) && !text.empty?
    pipeline.after_receive_from_llm(text).text
  end

  # Generic backoff wrapper. Yields a block and retries on common transient
  # network errors. The caller remains responsible for logging.
  def retry_with_backoff(max_retries: DEFAULT_MAX_RETRIES, delay: DEFAULT_RETRY_DELAY)
    attempts = 0
    begin
      return yield
    rescue HTTP::Error, HTTP::TimeoutError => e
      attempts += 1
      raise e if attempts > max_retries
      sleep(delay)
      retry
    rescue StandardError => e
      # Non-network errors are re-raised immediately; helpers already have
      # their own handling and we do not want to change behavior here.
      raise e
    end
  end
end
