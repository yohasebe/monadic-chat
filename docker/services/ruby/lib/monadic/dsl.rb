# Add required utilities
require_relative 'utils/fa_icons'
begin
  require_relative 'utils/mdsl_validator'
rescue LoadError
  # mdsl_validator is optional
end
require_relative 'utils/provider_model_cache'
require_relative 'shared_tools/registry'
require_relative 'shared_tools/file_operations'
require_relative 'shared_tools/python_execution'
require_relative 'shared_tools/web_search_tools'
require_relative 'shared_tools/app_creation'
require_relative 'shared_tools/file_reading'
require_relative 'shared_tools/jupyter_operations'
require_relative 'shared_tools/web_automation'
require_relative 'shared_tools/audio_transcription'
require_relative 'shared_tools/image_analysis'
require_relative 'shared_tools/video_analysis'
require_relative 'shared_tools/session_context'
require_relative 'shared_tools/context_panel_helper'
require_relative 'shared_tools/planning'
require_relative 'shared_tools/verification'
require_relative 'shared_tools/parallel_dispatch'
require_relative 'shared_tools/library_search'
require_relative 'dsl/configurations'
require_relative 'dsl/loader'
require_relative 'dsl/provider_config'
require_relative 'dsl/tool_definitions'
require_relative 'dsl/tool_formatters'

# Add the app method to top-level scope to enable the simplified DSL
def app(name, &block)
  MonadicDSL.app(name, &block)
end

module MonadicDSL
  # Base class for application state management

  # The following setting parameters are available for defining applications:
  #
  # - image: Enables image handling and attachments in the UI
  # - pdf: Enables PDF document upload, parsing, and interaction
  # - easy_submit: Enables submitting messages on Enter key (without needing to click Send)
  # - auto_speech: Enables automatic text-to-speech for assistant messages
  # - initiate_from_assistant: Allows assistant to proactively send follow-up messages
  # - mermaid: Enables Mermaid diagram rendering and interaction for flowcharts and diagrams
  # - math: Enables mathematical notation rendering (KaTeX)
  # - abc: Enables ABC music notation rendering and playback for music composition
  # - tools: Defines function-calling capabilities available to the model
  # - image_generation: Enables AI image generation within the conversation
  # - monadic: Enables monadic mode for structured JSON responses and special rendering
  # - websearch: Enables web search functionality for retrieving external information (web_search)
  # - jupyter: Enables access to Jupyter notebooks in the conversation
  # - temperature: Controls randomness in model responses (0.0-2.0)
  # - model: Specifies which AI model to use for this app
  # - group: Groups apps by provider (e.g., "OpenAI", "Anthropic", "Google")
  # - app_name: Defines the display name of the application
  # - description: Provides UI description text for the application
  # - icon: Specifies the FontAwesome icon to use for the app
  # - initial_prompt: Sets the system prompt/instructions for the model
  # - disabled: Indicates if the app should be disabled (e.g., when API key is missing)
  # - reasoning_effort: Controls the depth of reasoning (e.g., "high")
  # - context_size: Controls the context window size for the conversation
  # - max_tokens: Specifies the maximum number of tokens to generate (max_output_tokens)
  #
  # Note: Some parameters support aliases (shown in parentheses) for backward compatibility:
  # - websearch (web_search)
  # - max_tokens (max_output_tokens)

  class AppState
    attr_reader :name
    attr_accessor :settings, :features, :ui, :prompts
    
    def initialize(name)
      @name = name
      @settings = {}
      @features = {}
      @ui = {}
      @prompts = {}
    end
    
    # Bind operation for state transformation

    def bind(&block)
      Result.new(block.call(self))
    rescue StandardError => e
      Result.new(nil, e)
    end
    
    # Map operation for value transformation

    def map(&block)
      bind { |state| self.class.new(block.call(state)) }
    end
    
    # Validate the current state

    def validate!
      raise ValidationError, "Name is required" unless @name
      raise ValidationError, "Settings are required" if @settings.empty?
      raise ValidationError, "Provider is required" unless @settings[:provider]
      true
    end
  end
  
  # Result monad for error handling

  class Result
    attr_reader :value, :error
    
    def initialize(value, error = nil)
      @value = value
      @error = error
    end
    
    def bind(&block)
      return self if @error
      begin
        block.call(@value)
      rescue => e
        Result.new(nil, e)
      end
    end
    
    def map(&block)
      bind { |value| Result.new(block.call(value)) }
    end
    
    def success?
      !@error
    end
  end
  
  
  class ConfigurationError < StandardError; end
  
  # Per-app capability defaults. Apps that omit a flag inherit these
  # values; MDSL `features do; library_save false; ...; end` overrides
  # explicitly. Defaults bias toward KB-only conversational apps because
  # that is the dominant pattern; PF and artifact-centric apps are the
  # explicit exceptions and must opt out via MDSL.
  CAPABILITY_DEFAULTS = {
    library_save: true,
    library_search: true
  }.freeze

  # Apply MDSL-declared capabilities + defaults + privacy-derived
  # overrides + invariant validation. Run AFTER the MDSL block has
  # populated state.features and state.settings, BEFORE library_search
  # auto-injection.
  #
  # Decision order:
  #   1. If `privacy do; enabled true; end` was declared, force
  #      library_save=false and library_search=false. MDSL is not
  #      allowed to contradict (raises on `library_save true` mixed
  #      with privacy-on).
  #   2. Otherwise, read MDSL-declared library_save / library_search
  #      from features, falling back to CAPABILITY_DEFAULTS.
  #   3. Validate the cross-flag invariant: library_search=true
  #      implies library_save=true (search without save is a no-op
  #      since results would have nowhere to come from).
  def self.finalize_capabilities!(state)
    privacy_on = state.settings[:privacy_enabled] == true
    # MDSL may write to either state.features (preferred — `features do`
    # block) or state.settings directly; we read both for backward
    # compat. nil indicates "not declared".
    declared_save   = first_nonnil(state.features[:library_save],   state.settings[:library_save])
    declared_search = first_nonnil(state.features[:library_search], state.settings[:library_search])

    if privacy_on
      if declared_save == true
        raise ConfigurationError,
              "App '#{state.name}': library_save=true conflicts with privacy.enabled=true. " \
              "Privacy Filter apps cannot save to the Knowledge Base. " \
              "Remove `library_save true` from the features block, or remove the privacy block."
      end
      if declared_search == true
        raise ConfigurationError,
              "App '#{state.name}': library_search=true conflicts with privacy.enabled=true. " \
              "Privacy Filter apps cannot retrieve from the Knowledge Base. " \
              "Remove `library_search true` from the features block, or remove the privacy block."
      end
      state.settings[:library_save] = false
      state.settings[:library_search] = false
      return
    end

    save_value   = declared_save.nil?   ? CAPABILITY_DEFAULTS[:library_save]   : !!declared_save
    search_value = declared_search.nil? ? CAPABILITY_DEFAULTS[:library_search] : !!declared_search

    if search_value && !save_value
      raise ConfigurationError,
            "App '#{state.name}': library_search=true requires library_save=true. " \
            "Retrieving from a Knowledge Base entries this app cannot save to is " \
            "self-contradictory. Either set library_save true or set library_search false."
    end

    state.settings[:library_save] = save_value
    state.settings[:library_search] = search_value
  end

  # Helper: pick the first non-nil value from the args. Used to merge
  # MDSL declarations that may live in either state.features (modern
  # `features do` block) or state.settings (legacy direct write).
  def self.first_nonnil(*values)
    values.find { |v| !v.nil? }
  end

  # True when the app should auto-import library_search. Reads the
  # capability flag set by finalize_capabilities!.
  def self.library_search_eligible?(state)
    state.settings[:library_search] == true
  end

  # True when the app should expose the Knowledge Base "Save" button.
  # Thin wrapper over the capability flag for symmetry.
  def self.library_save_eligible?(state)
    state.settings[:library_save] == true
  end

  def self.library_search_already_imported?(state)
    (state.settings[:imported_tool_groups] || []).any? { |g| g[:name] == :library_search }
  end

  # After the user's MDSL block runs, ensure library_search is wired into
  # eligible apps even when they did not declare a `tools do` block at
  # all. The tool itself is gated by a per-session UI toggle (default
  # OFF), so this injection just makes RAG *available* — users still
  # have to enable it explicitly per session in the Knowledge Base panel.
  def self.inject_library_search!(state)
    provider = state.settings[:provider].to_s.downcase.to_sym
    tool_config = ToolConfiguration.new(state, provider)
    # `conditional` reflects reality: the tool is exposed to the LLM only
    # when the per-session "Use Knowledge Base for retrieval" toggle in
    # the Knowledge Base panel is ON. The `web_search_tools` group uses
    # the same `conditional` visibility for the parallel reason. The
    # visibility tag affects only badge categorization (Tools (Always) vs
    # Tools (Conditional)) — actual API gating is independent.
    tool_config.import_shared_tools(:library_search, visibility: "conditional")
    new_tools = tool_config.to_h

    # Merge with any existing tools the user already configured. The
    # provider-specific wrapper differs (Gemini uses a function_declarations
    # hash, others use plain arrays), so we handle both shapes.
    existing = state.settings[:tools]
    state.settings[:tools] = merge_tools_for_provider(provider, existing, new_tools)
  end

  def self.file_operations_already_imported?(state)
    (state.settings[:imported_tool_groups] || []).any? { |g| g[:name] == :file_operations }
  end

  # After the user's MDSL block runs, ensure shared-folder read/write is wired
  # into EVERY app so `${SHARED}` is actionable everywhere (Phase 9) — file
  # interaction (editing local images, supplying source text, saving
  # transcripts) is broadly useful and reflects Monadic Chat's Docker shared-
  # folder integration. Unlike library_search this is unconditional: no
  # per-app eligibility and no opt-out. Non-tool-capable models simply never
  # receive the tools (the vendor helpers gate on `tool_capability`), so this
  # is a no-op for them rather than an error. Visibility "always" matches the
  # apps that already import :file_operations.
  def self.inject_file_operations!(state)
    provider = state.settings[:provider].to_s.downcase.to_sym
    tool_config = ToolConfiguration.new(state, provider)
    tool_config.import_shared_tools(:file_operations, visibility: "always")
    new_tools = tool_config.to_h

    existing = state.settings[:tools]
    state.settings[:tools] = merge_tools_for_provider(provider, existing, new_tools)
  end

  def self.merge_tools_for_provider(provider, existing, additions)
    return dedup_tools_by_name(additions) if existing.nil? || (existing.respond_to?(:empty?) && existing.empty?)
    if provider == :gemini
      existing_arr = (existing.is_a?(Hash) ? (existing['function_declarations'] || []) : []).dup
      additions_arr = (additions.is_a?(Hash) ? (additions['function_declarations'] || []) : []).dup
      { 'function_declarations' => dedup_tools_by_name(existing_arr + additions_arr) }
    elsif existing.is_a?(Array) && additions.is_a?(Array)
      dedup_tools_by_name(existing + additions)
    else
      existing
    end
  end

  # Drop duplicate tools by function name. Each auto-injection ToolConfiguration
  # re-adds request_tool (via ensure_request_tool_defined), so concatenating tool
  # arrays across passes yields duplicate request_tool entries; some providers
  # reject duplicate function names. Keeps the first occurrence.
  def self.dedup_tools_by_name(tools)
    return tools unless tools.is_a?(Array)
    seen = {}
    tools.each_with_object([]) do |tool, result|
      name = if tool.is_a?(Hash)
        fn = tool[:function] || tool['function']
        (fn && (fn[:name] || fn['name'])) || tool[:name] || tool['name']
      end
      if name.nil?
        result << tool
      elsif !seen[name]
        seen[name] = true
        result << tool
      end
    end
  end

  # Module methods

  # App definition method
  def self.app(name, &block)
    state = AppState.new(name.gsub(/\s+/, ''))
    # Always store original name as display_name to ensure consistency
    state.settings[:display_name] = name

    # Initialize default values
    state.features = {}
    state.settings[:provider] = "OpenAI"
    # model is NOT pre-set here; convert_to_class resolves it per-provider
    # via providerDefaults (SSOT) or ENV variable
    state.settings[:temperature] = 0.7

    # Process the DSL block
    app_def = SimplifiedAppDefinition.new(state)
    app_def.instance_eval(&block)

    # Resolve per-app capability flags from MDSL declarations + defaults
    # + privacy-derived overrides. This must run BEFORE library_search
    # auto-injection because the injection eligibility now reads the
    # resolved state.settings[:library_search] flag.
    finalize_capabilities!(state)

    # Auto-inject library_search for eligible conversational apps that
    # did not opt in themselves. Eligibility is the AND of (per-app
    # capability flag from MDSL) and (provider supports tool calling).
    if library_search_eligible?(state) && !library_search_already_imported?(state)
      begin
        inject_library_search!(state)
      rescue StandardError => e
        puts "[DSL] library_search auto-inject skipped for #{state.name}: #{e.class}: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      end
    end

    # Universal: every app gets shared-folder read/write so ${SHARED} works
    # everywhere. Dedupe against the apps that already import :file_operations.
    unless file_operations_already_imported?(state)
      begin
        inject_file_operations!(state)
      rescue StandardError => e
        puts "[DSL] file_operations auto-inject skipped for #{state.name}: #{e.class}: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      end
    end

    # Debug the state
    puts "After DSL eval: #{state.name}, display_name: #{state.settings[:display_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]

    convert_to_class(state)
    state
  end
  
  # Simplified app definition class
  class SimplifiedAppDefinition
    def initialize(state)
      @state = state
    end
    
    def description(text = nil, &block)
      if block_given?
        # Multi-language description using block syntax
        desc_builder = DescriptionBuilder.new
        desc_builder.instance_eval(&block)
        @state.ui[:description] = desc_builder.descriptions
      else
        # Single string description (backward compatibility)
        @state.ui[:description] = text
      end
    end
    
    def icon(name)
      @state.ui[:icon] = IconHelper.to_html(name)
    end
    
    def app_name(name)
      @state.settings[:app_name] = name
    end
    
    def display_name(name)
      @state.settings[:display_name] = name
    end
    
    def system_prompt(text)
      @state.prompts[:initial] = text
    end
    
    # Module include support
    def include_modules(*modules)
      @state.settings[:include_modules] = modules.map(&:to_s)
    end
    
    # Monadic mode for structured output
    def monadic(value)
      @state.features[:monadic] = value
    end
    
    # Assistant initiation flag
    def initiate_from_assistant(value)
      @state.features[:initiate_from_assistant] = value
    end
    
    def llm(&block)
      LLMConfiguration.new(@state).instance_eval(&block)
    end
    
    def features(&block)
      SimplifiedFeatureConfiguration.new(@state).instance_eval(&block)
    end
    
    # Anthropic Context Management (beta, default-on for models that support it).
    # Usage:
    #   context_management do              # custom edits (overrides default clear_thinking/clear_tool_uses)
    #     edits [...]
    #   end
    #   context_management false           # explicit opt-out → fall back to context_size sliding window only
    def context_management(enable = nil, &block)
      if block_given?
        config = ContextManagementConfiguration.new
        config.instance_eval(&block)
        @state.settings[:context_management] = config.to_hash
      elsif enable == false
        # Explicit opt-out sentinel: claude_helper checks `== false`
        # and skips attaching context_management, leaving context_size
        # (client-side sliding window) as the only trimming mechanism.
        @state.settings[:context_management] = false
      end
    end

    # OpenAI Compaction (Responses API server-side compaction, GA).
    # Default-on: apps inherit the default threshold unless they opt out.
    # Usage:
    #   compaction                         # explicit default (same as not specifying)
    #   compaction do
    #     compact_threshold 180_000        # custom threshold
    #   end
    #   compaction false                   # explicit opt-out → fall back to context_size sliding window only
    def compaction(enable = nil, &block)
      if block_given?
        config = CompactionConfiguration.new
        config.instance_eval(&block)
        @state.settings[:compaction] = config.to_hash
      elsif enable == false
        # Explicit opt-out sentinel: openai_helper checks `== false`
        # and skips attaching context_management, leaving context_size
        # (client-side sliding window) as the only trimming mechanism.
        @state.settings[:compaction] = false
      elsif enable.is_a?(Hash)
        @state.settings[:compaction] = enable
      else
        @state.settings[:compaction] = { compact_threshold: CompactionConfiguration::DEFAULT_COMPACT_THRESHOLD }
      end
    end

    # Privacy Filter (PII masking before LLM, restoration on response).
    # Usage:
    #   privacy do
    #     enabled true
    #     languages ["ja", "en"]
    #   end
    # Setting privacy_enabled=true triggers container_dependencies to require
    # the :privacy service. The privacy container is part of the default build
    # set; PRIVACY_FILTER=false in env opts out at runtime.
    def privacy(&block)
      config = PrivacyFilterConfiguration.new
      config.instance_eval(&block) if block_given?
      hash = config.to_hash
      @state.settings[:privacy] = hash
      @state.settings[:privacy_enabled] = hash[:enabled]
    end

    # Vocabulary: shared ${TOKEN} variables between the user and the assistant.
    # `${SHARED}` is ON by default for every app (Monadic Chat's shared-folder
    # integration is universal) — no declaration is needed to get it. An app
    # only declares this block to:
    #   * opt out entirely:        vocabulary false
    #   * (future) add other tokens: vocabulary do; use :other; end
    def vocabulary(arg = nil, &block)
      config = VocabularyConfiguration.new
      config.disable! if arg == false
      config.instance_eval(&block) if block_given?
      @state.settings[:vocabulary] = config.to_hash
    end

    # Advisor Tool opt-in (Anthropic Advisor Tool beta).
    # Usage:
    #   advisor_tool  # enable with defaults (claude-opus-4-8)
    #   advisor_tool do
    #     model    "claude-opus-4-8"
    #     max_uses 3
    #     caching  true
    #   end
    def advisor_tool(enable = nil, &block)
      if block_given?
        config = AdvisorToolConfiguration.new
        config.instance_eval(&block)
        @state.settings[:advisor_tool] = config.to_hash
      elsif enable == false
        @state.settings[:advisor_tool] = nil
      elsif enable.is_a?(Hash)
        @state.settings[:advisor_tool] = enable
      else
        @state.settings[:advisor_tool] = { model: AdvisorToolConfiguration::DEFAULT_MODEL }
      end
    end

    def tools(tools_array = nil, &block)
      if tools_array
        # Direct array of tools provided (e.g., for Gemini/OpenAI style)
        @state.settings[:tools] = tools_array
      elsif block_given?
        # Convert provider to symbol
        provider = @state.settings[:provider].to_s.downcase.to_sym

        tool_config = ToolConfiguration.new(@state, provider)
        tool_config.instance_eval(&block)

        # Auto-inject library_search into the SAME ToolConfiguration so
        # progressive_tools metadata, formatter wrapping, and tool count
        # stay coherent with whatever the user declared. The tool runs
        # inside its own per-session toggle gate, default OFF.
        if MonadicDSL.library_search_eligible?(@state) &&
           !MonadicDSL.library_search_already_imported?(@state)
          begin
            # See `inject_library_search!` for why `conditional`: the tool
            # is gated by the per-session Knowledge Base retrieval toggle.
            tool_config.import_shared_tools(:library_search, visibility: "conditional")
          rescue StandardError => e
            puts "[DSL] library_search inline-inject skipped for #{@state.name}: #{e.class}: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          end
        end

        @state.settings[:tools] = tool_config.to_h
      end
    end

    def agents(&block)
      if block_given?
        config = AppAgentsConfiguration.new
        config.instance_eval(&block)
        @state.settings[:agents] = config.to_hash
      end
    end

    # Context schema for monadic apps
    # Defines what context fields should be tracked automatically
    # @example
    #   context_schema do
    #     field :topics, icon: "fa-tags", label: "Topics", description: "Main subjects"
    #     field :people, icon: "fa-users", label: "People", description: "Names mentioned"
    #     field :notes, icon: "fa-sticky-note", label: "Notes", description: "Important facts"
    #   end
    def context_schema(&block)
      if block_given?
        config = ContextSchemaConfiguration.new
        config.instance_eval(&block)
        @state.settings[:context_schema] = config.to_hash
      end
    end

    # Import shared tools at app level (delegates to ToolConfiguration)
    # This allows import_shared_tools to be called outside of tools {} block
    # Uses a persistent ToolConfiguration to accumulate tools across multiple calls
    def import_shared_tools(*groups, **options)
      provider = @state.settings[:provider].to_s.downcase.to_sym
      @tool_config ||= ToolConfiguration.new(@state, provider)

      @tool_config.import_shared_tools(*groups, **options)

      @state.settings[:tools] = @tool_config.to_h
    end

    # App-level sugar for declaring reachable (conditional) skill groups outside a
    # tools {} block. Delegates to ToolConfiguration#reachable_skills; `:safe`
    # expands to the read-only Registry.safe_groups pool.
    def reachable_skills(*groups, **options)
      provider = @state.settings[:provider].to_s.downcase.to_sym
      @tool_config ||= ToolConfiguration.new(@state, provider)

      @tool_config.reachable_skills(*groups, **options)

      @state.settings[:tools] = @tool_config.to_h
    end
  end

  # Helper method to convert simplified state to class
  def self.convert_to_class(state)
    # Get standardized provider configuration
    provider_config = ProviderConfig.new(state.settings[:provider])
    helper_module = provider_config.helper_module
    
    # Build fallback model list using configured models, providerDefaults, and defaults
    fallback_models = []
    fallback_models.concat(Array(state.settings[:models])) if state.settings[:models]
    fallback_models << state.settings[:model] if state.settings[:model]
    # Add providerDefaults chat list as additional fallback
    pd_models = Monadic::Utils::ModelSpec.get_provider_models(provider_config.standard_key, "chat")
    fallback_models.concat(pd_models) if pd_models
    fallback_models = fallback_models.flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
    fallback_literal = if fallback_models.empty?
      "[]"
    else
      "[#{fallback_models.map { |m| m.inspect }.join(', ')}]"
    end

    # Get model list via helper module with centralized fallback handling
    model_list_code = "Monadic::Utils::ProviderModelCache.fetch('#{provider_config.standard_key}', fallback: #{fallback_literal}) do\n        defined?(#{helper_module}) ? Array(#{helper_module}.list_models) : []\n      end"

    # Debug the state
    puts "Converting class: #{state.name}, app_name: #{state.settings[:app_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]

    # Make sure app_name is set from either settings or features
    app_name = state.settings[:app_name] || state.name
    
    # Use display_name if provided, otherwise use app_name
    display_name = state.settings[:display_name] || app_name

    # Get distributed mode from CONFIG hash (loaded from .env file) instead of environment variable
    distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] ? CONFIG["DISTRIBUTED_MODE"] : "off"
    
    # Check if this app should be disabled in server mode due to security concerns
    jupyter_disabled_in_server = distributed_mode == "server" &&
      (state.features[:jupyter] == true ||
       state.features[:jupyter] == "true")
    
    # Get appropriate environment variable name based on provider
    provider_name = state.settings[:provider].to_s.downcase
    provider_env_var = provider_config.default_model_env

    # Determine model value for class definition
    # Priority: MDSL explicit model > ENV > providerDefaults (SSOT) > hardcoded
    model_value = if state.settings[:model]
                    # Use model from MDSL file if specified
                    state.settings[:model].inspect
                  elsif provider_env_var
                    # Resolve default: providerDefaults (SSOT) > ENV variable
                    default_model = Monadic::Utils::ModelSpec.get_provider_default(provider_config.standard_key, "chat")
                    if default_model.nil?
                      warn "[DSL] No providerDefault for #{provider_config.standard_key}/chat; relying on ENV['#{provider_env_var}']"
                    end
                    "ENV['#{provider_env_var}'] || #{default_model.inspect}"
                  else
                    # Fallback to providerDefaults (providers without ENV variable, e.g. Ollama)
                    pd_default = Monadic::Utils::ModelSpec.get_provider_default(provider_config.standard_key, "chat")
                    if pd_default.nil?
                      warn "[DSL] No providerDefault for #{provider_config.standard_key}/chat and no ENV variable configured"
                    end
                    pd_default.inspect
                  end

    # Construct disabled logic based on API key availability and server mode restrictions
    if provider_config.api_key_name.nil?
      # For providers that don't need API keys (like Ollama)
      # Check if provider has an endpoint availability method (e.g., OllamaHelper.find_endpoint)
      ollama_check = provider_name == "ollama" ? "(defined?(OllamaHelper) && OllamaHelper.find_endpoint.nil?)" : "false"
      if jupyter_disabled_in_server
        disabled_condition = "(defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\") || #{ollama_check}"
      else
        disabled_condition = ollama_check
      end
    elsif jupyter_disabled_in_server
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"] || (defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\")"
    else
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"]"
    end

    # Add extra modules if specified
    include_modules = state.settings[:include_modules] || []
    include_statements = [helper_module]

    # Automatically include tool module if it exists
    # Remove provider suffix to get base app name
    app_base_name = state.name.sub(/OpenAI|Claude|Gemini|Mistral|Cohere|Grok|DeepSeek|Ollama$/, '')
    tool_module_name = "#{app_base_name}Tools"
    include_statements << tool_module_name

    include_statements += include_modules

    # Include shared tool modules for imported tool groups
    # This ensures the Ruby methods are available when AI calls the tools
    if state.settings[:imported_tool_groups]
      state.settings[:imported_tool_groups].each do |group_info|
        group_name = group_info[:name]
        module_name = MonadicSharedTools::Registry.module_name_for(group_name)
        if module_name
          include_statements << module_name
        end
      end
    end

    include_lines = include_statements.map { |m| "        include #{m} if defined?(#{m})" }.join("\n")
    
    # Use group from features if defined, otherwise use provider's display_group
    group_value = state.features[:group] || provider_config.display_group
    
    # Use models from state if specified, otherwise use provider's model list
    # When neither MDSL model nor models is set, inject providerDefaults into settings
    # so the fallback list is richer for the ProviderModelCache
    if !state.settings[:models]
      pd_chat = Monadic::Utils::ModelSpec.get_provider_models(provider_config.standard_key, "chat")
      if pd_chat && !pd_chat.empty?
        state.settings[:models] = pd_chat
      end
    end

    models_value = if state.settings[:models]
                     state.settings[:models].inspect
                   else
                     model_list_code
                   end
    
    class_def = <<~RUBY
      class #{state.name} < MonadicApp
#{include_lines}

        icon = #{state.ui[:icon].inspect}
        description = #{state.ui[:description].inspect}
        initial_prompt = #{state.prompts[:initial].inspect}

        @settings = {
          provider: #{state.settings[:provider].inspect},
          group: #{group_value.inspect},
          disabled: #{disabled_condition},
          models: #{models_value},
          model: #{model_value},
          temperature: #{state.settings[:temperature]},
          initial_prompt: initial_prompt,
          app_name: #{app_name.inspect},
          display_name: #{display_name.inspect},
          description: description,
          icon: icon,
        }
    RUBY

    # Add feature settings (excluding group which was already set)
    state.features.each do |feature, value|
      next if feature == :group  # Skip group as it's already set above
      class_def << "        @settings[:#{feature}] = #{value.inspect}\n"
    end
    
    # Add max_tokens if specified
    if state.settings[:max_tokens]
      class_def << "        @settings[:max_tokens] = #{state.settings[:max_tokens].inspect}\n"
    end
    
    # Default reasoning_effort to "none" (thinking disabled) unless the app
    # explicitly opts in. This prevents unexpected thinking token generation
    # and tool call loops. Apps that benefit from reasoning should declare
    # reasoning_effort "low"/"medium"/"high" in their MDSL llm block.
    effort = state.settings[:reasoning_effort] || "none"
    class_def << "        @settings[:reasoning_effort] = #{effort.inspect}\n"

    # reasoning_content ("disabled"/"enabled") is independent of
    # reasoning_effort: it sets the per-app default for the On/Off reasoning
    # toggle (currently DeepSeek V4). Only emit it when an app opts in so the
    # Web UI can seed the toggle without affecting apps that don't declare it.
    if state.settings[:reasoning_content]
      class_def << "        @settings[:reasoning_content] = #{state.settings[:reasoning_content].inspect}\n"
    end


    # Add tools if specified
    if state.settings[:tools]
      class_def << "        @settings[:tools] = #{state.settings[:tools].inspect}\n"
    end

    if state.settings[:progressive_tools]
      class_def << "        @settings[:progressive_tools] = #{state.settings[:progressive_tools].inspect}\n"
    end

    # Add imported_tool_groups if specified
    if state.settings[:imported_tool_groups]
      class_def << "        @settings[:imported_tool_groups] = #{state.settings[:imported_tool_groups].inspect}\n"
    end

    # Build and add badges
    begin
      require_relative "utils/badge_builder"

      # IMPORTANT: BadgeBuilder expects features as a nested hash
      # but DSL stores them flat in settings. Create a temporary hash with features nested.
      badge_settings = state.settings.dup
      badge_settings[:features] = state.features

      all_badges = Monadic::Utils::BadgeBuilder.build_all_badges(badge_settings)

      # Validate structure before serializing
      unless all_badges.is_a?(Hash) && all_badges[:tools].is_a?(Array) && all_badges[:capabilities].is_a?(Array)
        STDERR.puts "[BadgeBuilder] Invalid badge structure for #{state.name}, using empty badges"
        all_badges = { tools: [], capabilities: [] }
      end

      badges_json = all_badges.to_json
      class_def << "        @settings[:all_badges] = #{badges_json.inspect}\n"
    rescue StandardError => e
      STDERR.puts "[BadgeBuilder] Failed to build badges for #{state.name}: #{e.message}"
      STDERR.puts e.backtrace.first(5).join("\n") if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      # Fail gracefully - empty badges instead of crashing app load
      class_def << "        @settings[:all_badges] = #{({ tools: [], capabilities: [] }.to_json).inspect}\n"
    end

    # Add tool_choice if specified
    if state.settings[:tool_choice]
      class_def << "        @settings[:tool_choice] = #{state.settings[:tool_choice].inspect}\n"
    end
    
    # Add parallel_function_calling if specified
    if state.settings[:parallel_function_calling]
      class_def << "        @settings[:parallel_function_calling] = #{state.settings[:parallel_function_calling].inspect}\n"
    end

    # Add betas if specified
    if state.settings[:betas]
      class_def << "        @settings[:betas] = #{state.settings[:betas].inspect}\n"
    end

    # Add advisor_tool if specified (Anthropic Advisor Tool beta)
    if state.settings[:advisor_tool]
      class_def << "        @settings[:advisor_tool] = #{state.settings[:advisor_tool].inspect}\n"
    end

    # Add context_management if specified (Anthropic Context Management beta).
    # Emit `false` as-is so claude_helper can distinguish explicit opt-out from
    # the unset default (which falls through to the hardcoded default edits).
    unless state.settings[:context_management].nil?
      class_def << "        @settings[:context_management] = #{state.settings[:context_management].inspect}\n"
    end

    # Add compaction if specified (OpenAI Responses API server-side compaction).
    # Emit `false` as-is so openai_helper can distinguish explicit opt-out from
    # the unset default (which defaults to enabled at the default threshold).
    unless state.settings[:compaction].nil?
      class_def << "        @settings[:compaction] = #{state.settings[:compaction].inspect}\n"
    end

    # Add privacy filter settings if specified.
    # `:privacy_enabled` is a derived flag used by container_dependencies to
    # decide whether to require the privacy service.
    unless state.settings[:privacy].nil?
      class_def << "        @settings[:privacy] = #{state.settings[:privacy].inspect}\n"
      class_def << "        @settings[:privacy_enabled] = #{state.settings[:privacy_enabled].inspect}\n"
    end

    # Vocabulary opt-in tokens (plain symbol data; resolution is runtime).
    unless state.settings[:vocabulary].nil?
      class_def << "        @settings[:vocabulary] = #{state.settings[:vocabulary].inspect}\n"
    end

    # Capability flags resolved by finalize_capabilities!. These are written
    # to state.settings (not state.features) so the generic features-loop
    # above does not pick them up; we have to inject them explicitly so the
    # runtime app instance carries the same boolean the WS layer ships to
    # the frontend's body-class gate.
    unless state.settings[:library_save].nil?
      class_def << "        @settings[:library_save] = #{state.settings[:library_save].inspect}\n"
    end
    unless state.settings[:library_search].nil?
      class_def << "        @settings[:library_search] = #{state.settings[:library_search].inspect}\n"
    end

    # Add agents if specified (internal sub-agents like code_generator, speech_to_text)
    if state.settings[:agents] && !state.settings[:agents].empty?
      class_def << "        @settings[:agents] = #{state.settings[:agents].inspect}\n"
    end

    # Add context_schema if specified (for monadic apps)
    if state.settings[:context_schema]
      class_def << "        @settings[:context_schema] = #{state.settings[:context_schema].inspect}\n"
    end

    class_def << "      end\n"

    eval(class_def, TOPLEVEL_BINDING, state.name)
  end

  # Utility method for state conversion to YAML
  def self.to_yaml(app_state)
    {
      name: app_state.name,
      settings: app_state.settings,
      features: app_state.features,
      ui: app_state.ui,
      prompts: app_state.prompts
    }.to_yaml
  end
end
