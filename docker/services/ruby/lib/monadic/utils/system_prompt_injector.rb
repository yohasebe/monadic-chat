# frozen_string_literal: true

require_relative 'language_config'
require_relative 'tts_marker_vocabulary'

module Monadic
  module Utils
    # Unified prompt injection manager
    # Provides consistent dynamic prompt augmentation across all vendor helpers
    # Supports both system messages (conversation start) and user messages (each input)
    class SystemPromptInjector
      # Standard separator between prompt sections
      DEFAULT_SEPARATOR = "\n\n---\n\n"
      USER_MESSAGE_SEPARATOR = "\n\n"

      # Autonomy mode prompts
      AUTONOMY_HIGH_PROMPT = <<~PROMPT.strip
        AUTONOMY MODE: HIGH

        You operate with high autonomy. Follow these rules strictly — they OVERRIDE any earlier instructions about confirmation, explanation before actions, or plan approval:

        - Execute actions immediately without asking for user confirmation or approval
        - Do NOT ask "Is this okay?", "Shall I proceed?", or similar confirmation questions
        - Do NOT use propose_plan — skip the Plan-Approve-Execute Protocol entirely
        - When the user's intent is clear, proceed directly with the appropriate tools
        - After completing a sequence of actions, provide a brief summary of what was done
        - Only pause to ask the user when:
          (a) Their intent is genuinely ambiguous
          (b) You need to enter passwords or sensitive credentials
          (c) An irreversible destructive action is about to occur
      PROMPT

      AUTONOMY_LOW_PROMPT = <<~PROMPT.strip
        AUTONOMY MODE: LOW

        You operate with low autonomy. Follow these rules strictly:

        - Before EVERY action, explain what you plan to do and ask for explicit user confirmation
        - Never execute any tool without the user's approval first
        - Always use propose_plan for any task with 2 or more steps
        - Present each step individually and wait for approval before proceeding
        - When in doubt, ask rather than assume
      PROMPT

      # STT Diarization warning prompt
      DIARIZATION_STT_PROMPT = <<~PROMPT.strip
        IMPORTANT: Speaker Diarization Context

        The user's messages may contain speaker labels (A:, B:, C:, etc.) from multi-speaker transcription.
        These labels indicate DIFFERENT PEOPLE speaking in the user's environment, NOT separate conversation participants.

        Your role:
        - You are an AI assistant responding to ALL speakers collectively
        - Do NOT adopt the role of any labeled speaker (A, B, C, etc.)
        - Do NOT respond as if you are one of the speakers in the conversation
        - Respond in a neutral, assistant voice addressing the entire group

        Example:
        User message: "A: I'm planning to study abroad. B: That's great, good luck!"
        ❌ WRONG: "A: Thanks! I'm excited but a bit nervous."
        ✅ CORRECT: "That sounds like an exciting plan! Studying abroad can be both thrilling and challenging. How can I help you prepare?"
      PROMPT

      # Math formatting prompt (base)
      MATH_BASE_PROMPT = <<~PROMPT.strip
        You use the LaTeX notation to write mathematical expressions. In doing so, you should follow the format requirements: Use double dollar signs `$$` to enclose LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly. Either type of LaTeX expression should be presntend without surrounding backticks.
      PROMPT

      # Math formatting prompt for monadic/jupyter mode (requires extra escaping)
      MATH_MONADIC_PROMPT = <<~'PROMPT'.strip
        Make sure to escape properly in the LaTeX expressions.

          Good examples of inline LaTeX expressions:
          - `$1 + 2 + 3 + … + k + (k + 1) = \\frac{k(k + 1)}{2} + (k + 1)$`
          - `$\\textbf{a} + \\textbf{b} = (a_1 + b_1, a_2 + b_2)$`
          - `$\\begin{align} 1 + 2 + … + k + (k+1) &= \\frac{k(k+1)}{2} + (k+1)\\end{align}$`
          - `$\\sin(\\theta) = \\frac{\\text{opposite}}{\\text{hypotenuse}}$`

        Good examples of block LaTeX expressions:
          - `$$1 + 2 + 3 + … + k + (k + 1) = \\frac{k(k + 1)}{2} + (k + 1)$$`
          - `$$\\textbf{a} + \\textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
          - `$$\\begin{align} 1 + 2 + … + k + (k+1) &= \\frac{k(k+1)}{2} + (k+1)\\end{align}$$`
          - `$$\\sin(\\theta) = \\frac{\\text{opposite}}{\\text{hypotenuse}}$$`
      PROMPT

      # Library RAG prompt header — injected when the per-session "Use
      # Knowledge Base" toggle is on. The user has explicitly opted in, so
      # the LLM should treat library_search as the primary source of truth
      # for any topic the user may have stored content about. Without this
      # rule the model often answers from training knowledge even when the
      # Knowledge Base contains an authoritative passage, which violates the
      # user's opt-in expectation. The directive also pins the citation
      # format so the frontend's mc:conv: link interception keeps
      # round-tripping back to the source conversation.
      #
      # The actual injected text is built dynamically by
      # build_library_rag_prompt so the LLM also sees a category-aware
      # inventory ("what's currently in the Knowledge Base") plus the
      # available filter parameters. This lets the LLM make targeted
      # `library_search` calls instead of blind cross-corpus queries.
      LIBRARY_RAG_HEADER = <<~PROMPT.strip
        Knowledge Base RAG is enabled for this session. The user has stored content in the project-wide Knowledge Base and expects you to use it.

        - BEFORE answering substantive factual questions, call `library_search` first to check whether the Knowledge Base contains relevant prior content. This applies even when you believe you already know the answer from your training data.
        - When `library_search` returns hits, base your answer on the retrieved passages and preserve the markdown citation links `[Title](mc:conv:<id>)` exactly as they appear so the user can click through to the original conversation.
        - Only fall back to your general knowledge when `library_search` returns no relevant hits, or when the question is purely conversational (greetings, clarifications, formatting requests, etc.).
        - You may issue multiple `library_search` calls in a single turn with different queries when the user's question spans several topics.
      PROMPT

      LIBRARY_RAG_FOOTER = <<~PROMPT.strip
        You may narrow `library_search` with these optional parameters when you have a strong prior about where the answer lives:
          - `content_type`: one of "conversation", "pdf", "document", "markdown", "code"
          - `source`: a specific source key from the inventory above (e.g. matching the user's prior corpus or saved chats)
        Omit them to search the entire Knowledge Base.
      PROMPT

      # Math formatting prompt for regular mode (standard escaping)
      MATH_REGULAR_PROMPT = <<~'PROMPT'.strip
        Good examples of inline LaTeX expressions:
          - `$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$`
          - `$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$`
          - `$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$`
          - `$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$`

        Good examples of block LaTeX expressions:
          - `$$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$$`
          - `$$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
          - `$$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$$`
          - `$$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$$`

        Remember that the following are not available in LaTeX:
          - `\begin{itemize}` and `\end{itemize}`
      PROMPT

      # System message injection rules (applied at conversation start)
      # Each rule has: name, priority, condition, and generator
      SYSTEM_INJECTION_RULES = [
        {
          name: :language_preference,
          priority: 100,
          condition: ->(session, _options) {
            !session&.[](:runtime_settings)&.[](:language).nil?
          },
          generator: ->(session, _options) {
            lang = session[:runtime_settings][:language]
            Monadic::Utils::LanguageConfig.system_prompt_for_language(lang)
          }
        },
        {
          name: :autonomy,
          priority: 90,
          condition: ->(session, _options) {
            autonomy = session&.dig(:parameters, "autonomy") || session&.dig(:parameters, :autonomy)
            %w[high low].include?(autonomy.to_s)
          },
          generator: ->(session, _options) {
            autonomy = (session&.dig(:parameters, "autonomy") || session&.dig(:parameters, :autonomy)).to_s
            case autonomy
            when "high"
              AUTONOMY_HIGH_PROMPT
            when "low"
              AUTONOMY_LOW_PROMPT
            end
          }
        },
        {
          name: :websearch,
          priority: 80,
          condition: ->(session, options) {
            options[:websearch_enabled] == true &&
              options[:reasoning_model] != true &&
              !options[:websearch_prompt].to_s.empty?
          },
          generator: ->(_session, options) {
            options[:websearch_prompt].to_s.strip
          }
        },
        {
          name: :library_rag,
          priority: 70,
          condition: ->(session, _options) {
            params = session&.[](:parameters) || {}
            toggle = params['library_rag_enabled'] || params[:library_rag_enabled]
            next false unless toggle == true || toggle.to_s == 'true'
            # Gate on app capability: the per-session RAG toggle persists across
            # app changes, so a stale "on" value must not leak the RAG header
            # into apps that have no library_search tool (e.g. Music Analyst,
            # image/video generators). Their toggle row is hidden in the UI, so
            # it must be inert here too — keeping toggle state and behavior
            # consistent. Capable apps keep the user's preference untouched.
            app_name = params['app_name'] || params[:app_name]
            app = (APPS[app_name] if defined?(APPS) && app_name)
            !!(app && app.settings && app.settings[:library_search] == true)
          },
          generator: ->(session, _options) {
            Monadic::Utils::SystemPromptInjector.build_library_rag_prompt(session)
          }
        },
        {
          # Vocabulary: tell the model about the `${TOKEN}` variables the active
          # app exposes (e.g. ${SHARED}) so it uses them verbatim. Opt-in per
          # app via a `vocabulary do` block; no-op otherwise.
          name: :vocabulary_variables,
          priority: 65,
          condition: ->(session, _options) {
            !Monadic::Utils::SystemPromptInjector.vocabulary_tokens_for(session).empty?
          },
          generator: ->(session, _options) {
            Monadic::Utils::SystemPromptInjector.build_vocabulary_addendum(session)
          }
        },
        {
          name: :stt_diarization_warning,
          priority: 60,
          condition: ->(session, _options) {
            stt_model = session&.[](:parameters)&.[]("stt_model")
            stt_model && stt_model.to_s.include?("diarize")
          },
          generator: ->(_session, _options) {
            DIARIZATION_STT_PROMPT
          }
        },
        {
          name: :math,
          priority: 50,
          condition: ->(session, _options) {
            session&.[](:parameters)&.[]("math") == true
          },
          generator: ->(session, _options) {
            parts = [MATH_BASE_PROMPT]

            # Add mode-specific escaping instructions
            monadic_mode = session&.[](:parameters)&.[]("monadic") == true
            jupyter_mode = session&.[](:parameters)&.[]("jupyter") == true

            if monadic_mode || jupyter_mode
              parts << MATH_MONADIC_PROMPT
            else
              parts << MATH_REGULAR_PROMPT
            end

            parts.join("\n\n")
          }
        },
        {
          name: :system_prompt_suffix,
          priority: 40,
          condition: ->(_session, options) {
            !options[:system_prompt_suffix].to_s.strip.empty?
          },
          generator: ->(_session, options) {
            options[:system_prompt_suffix].to_s.strip
          }
        },
        # Expressive Speech — appended at the very end so that prompt caches
        # (Anthropic, OpenAI) keep the stable prefix hot even when the user
        # switches TTS providers mid-conversation.
        #
        # Apps can opt out by declaring `expressive_speech false` in their
        # MDSL `features` block; this covers both this rule and the
        # plain_voice_enforcement mirror below.
        {
          name: :expressive_speech,
          priority: 30,
          condition: ->(session, _options) {
            next false unless Monadic::Utils::SystemPromptInjector.__expressive_speech_active?(session)
            params = session[:parameters] || {}
            tts_provider = params["tts_provider"] || params[:tts_provider]
            # Active for either inline-marker families (xAI / ElevenLabs v3 /
            # Gemini) or the out-of-band instruction-meta family (OpenAI
            # gpt-4o-mini-tts). Both are dispatched through
            # prompt_addendum_for; the generator picks the right variant.
            Monadic::Utils::TtsMarkerVocabulary.tag_aware?(tts_provider) ||
              Monadic::Utils::TtsMarkerVocabulary.instruction_mode?(tts_provider)
          },
          generator: ->(session, _options) {
            params = session[:parameters] || {}
            tts_provider = params["tts_provider"] || params[:tts_provider]
            # Instruction-mode's addendum shape depends on whether the active
            # app is Monadic (JSON sibling field) or not (sentinel prefix).
            # Marker-mode addendum ignores this flag.
            app_is_monadic = Monadic::Utils::SystemPromptInjector.__app_is_monadic?(session)
            Monadic::Utils::TtsMarkerVocabulary.prompt_addendum_for(
              tts_provider,
              app_is_monadic: app_is_monadic
            )
          }
        },
        # Plain-voice enforcement — the mirror of expressive_speech. When Auto
        # Speech is on but the chosen TTS engine cannot interpret inline
        # markers, instruct the model to emit plain prose. This prevents
        # in-context learning from old turns (e.g., switching xAI Grok TTS →
        # OpenAI TTS mid-session) from bleeding markers into the new voice,
        # where they would be read literally.
        {
          name: :plain_voice_enforcement,
          priority: 29,
          condition: ->(session, _options) {
            next false unless Monadic::Utils::SystemPromptInjector.__expressive_speech_active?(session)
            params = session[:parameters] || {}
            tts_provider = params["tts_provider"] || params[:tts_provider]
            # Active when auto_speech is on, a provider is selected, AND that
            # provider has NO marker vocabulary AND is NOT instruction-mode.
            # Skipping instruction-mode here is deliberate: the
            # :expressive_speech rule already instructs the LLM to emit plain
            # prose within the JSON/sentinel wrapper, so a parallel rule
            # repeating "plain prose only" would be redundant AND potentially
            # contradictory with "emit a directive block first". See
            # docs_dev/expressive_speech_instruction_mode.md §5.7.
            tts_provider && !tts_provider.to_s.empty? &&
              !Monadic::Utils::TtsMarkerVocabulary.tag_aware?(tts_provider) &&
              !Monadic::Utils::TtsMarkerVocabulary.instruction_mode?(tts_provider)
          },
          generator: ->(_session, _options) {
            "Voice output note: the current Text-to-Speech engine reads every " \
            "character literally, including anything inside square or angle " \
            "brackets. Do NOT include inline speech markers such as " \
            "[laugh], [pause], <whisper>, etc. in your reply — output plain " \
            "prose only. If earlier turns contain such markers, ignore them " \
            "as stage directions from a previous voice engine, not a pattern " \
            "to continue."
          }
        }
      ].freeze

      # User message injection rules (applied to each user input)
      # Typically simpler than system rules - just appending instructions
      USER_INJECTION_RULES = [
        {
          name: :prompt_suffix,
          priority: 10,
          condition: ->(_session, options) {
            !options[:prompt_suffix].to_s.strip.empty?
          },
          generator: ->(_session, options) {
            options[:prompt_suffix].to_s.strip
          }
        }
      ].freeze

      class << self
        # Build the library_rag injection. Combines a static directive
        # (LIBRARY_RAG_HEADER), a data-driven inventory block summarising
        # what's currently in the Knowledge Base, and a footer describing
        # the optional filter parameters. The inventory part is best-effort:
        # if Library can't be reached (Qdrant down, transient error) we
        # skip the inventory but still emit the directive so the LLM at
        # least knows to call `library_search`.
        def build_library_rag_prompt(session)
          parts = [LIBRARY_RAG_HEADER]
          # Match exactly what library_search would return: scope to the
          # requesting app's class plus "Global". Otherwise the LLM is
          # told about entries it can never retrieve.
          params = (session && (session[:parameters] || session['parameters'])) || {}
          app_name = (params['app_name'] || params[:app_name]).to_s.strip
          app_name = nil if app_name.empty?
          inventory_block = library_inventory_block(app_name)
          parts << inventory_block if inventory_block
          parts << LIBRARY_RAG_FOOTER
          parts.join("\n\n")
        end

        # Render the inventory as plain-text bullet lists. Returns nil when
        # the Library is empty or the lookup fails — the caller still
        # injects the directive in that case.
        def library_inventory_block(app_name = nil)
          return nil unless defined?(Monadic::Library::Store)

          store = Monadic::Library::Store.new
          inv = Monadic::Library::Inventory.summarize(store: store, app_name: app_name)
          return nil if inv[:total].to_i.zero?

          lines = ["Knowledge Base inventory (currently stored):"]
          lines << "Total entries: #{inv[:total]}"

          if inv[:by_source] && !inv[:by_source].empty?
            lines << ''
            lines << 'By source:'
            inv[:by_source].each do |src, count|
              lines << "  - #{src}: #{count} #{count == 1 ? 'entry' : 'entries'}"
            end
          end

          if inv[:by_content_type] && !inv[:by_content_type].empty?
            lines << ''
            lines << 'By content type:'
            inv[:by_content_type].each do |ct, count|
              lines << "  - #{ct}: #{count} #{count == 1 ? 'entry' : 'entries'}"
            end
          end

          lines.join("\n")
        rescue StandardError => e
          warn "[SystemPromptInjector] library_inventory_block error: #{e.message}" if defined?(CONFIG) && CONFIG['EXTRA_LOGGING']
          nil
        end

        # Shared gate for the two Expressive Speech rules. Returns true when
        # Auto Speech is on AND the active app has not opted out via MDSL
        # (`features { expressive_speech false }`). Callers still check the
        # TTS provider's tag-awareness separately.
        def __expressive_speech_active?(session)
          params = session&.[](:parameters) || {}
          auto_speech = params["auto_speech"] || params[:auto_speech]
          return false unless auto_speech == true || auto_speech.to_s == "true"

          # Per-app opt-out: if the MDSL declares `expressive_speech false`,
          # skip both addenda. This lets apps with strict output formats
          # (e.g., JSON-producing apps) keep their prompt intact.
          app_name = params["app_name"] || params[:app_name]
          if defined?(APPS) && app_name && (app = APPS[app_name])
            opt_out = app.settings["expressive_speech"] rescue nil
            return false if opt_out == false
          end

          true
        end

        # Decide the instruction-mode addendum variant. Monadic apps receive
        # the JSON-sibling version; non-Monadic apps receive the sentinel
        # prefix version. Uses the session's `monadic` parameter first, then
        # falls back to the MDSL `monadic` setting.
        def __app_is_monadic?(session)
          params = session&.[](:parameters) || {}

          session_monadic = params["monadic"] || params[:monadic]
          return true if session_monadic == true || session_monadic.to_s == "true"

          app_name = params["app_name"] || params[:app_name]
          if defined?(APPS) && app_name && (app = APPS[app_name])
            mdsl_monadic = app.settings["monadic"] rescue nil
            return true if mdsl_monadic == true || mdsl_monadic.to_s == "true"
          end

          false
        end

        # Resolve the active app's effective vocabulary token symbols. Delegates
        # to Vocabulary.tokens_for (the single source of truth, shared with the
        # pipeline builder), which defaults ${SHARED} on unless the app opts out.
        def vocabulary_tokens_for(session)
          params = session&.[](:parameters) || {}
          app_name = params["app_name"] || params[:app_name]
          return [] unless defined?(APPS) && app_name && (app = APPS[app_name])
          require_relative '../substitution/vocabulary'
          Monadic::Substitution::Vocabulary.tokens_for(app.settings)
        rescue StandardError
          []
        end

        # Build the "## Shared variables" system-prompt section for the active
        # app via the Vocabulary provider (single source of the wording). Nil
        # when the app exposes no tokens.
        def build_vocabulary_addendum(session)
          tokens = vocabulary_tokens_for(session)
          return nil if tokens.empty?
          require_relative '../substitution/providers/vocabulary'
          require_relative '../substitution/context'
          provider = Monadic::Substitution::Providers::Vocabulary.new(tokens: tokens)
          provider.system_prompt_addendum(Monadic::Substitution::Context.new(session: session, app: nil))
        end

        # Build injection parts based on session and options
        # @param session [Hash] Session data containing runtime settings and parameters
        # @param options [Hash] Options hash containing:
        #   - websearch_enabled [Boolean] Whether web search is enabled
        #   - reasoning_model [Boolean] Whether the model is a reasoning model
        #   - websearch_prompt [String] Provider-specific web search prompt
        #   - system_prompt_suffix [String] Custom system prompt suffix
        #   - prompt_suffix [String] User message suffix
        # @param context [Symbol] Context type (:system or :user), defaults to :system
        # @return [Array<Hash>] Array of injection parts with :name and :content
        def build_injections(session:, options: {}, context: :system)
          # Select appropriate rule set based on context
          rules = case context
                  when :user
                    USER_INJECTION_RULES
                  else
                    SYSTEM_INJECTION_RULES
                  end

          # Evaluate each rule and collect matching injections
          injections = rules.select do |rule|
            rule[:condition].call(session, options)
          rescue StandardError => e
            # Log error and skip this rule
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              warn "[SystemPromptInjector] Error evaluating rule #{rule[:name]}: #{e.message}"
            end
            false
          end

          # Sort by priority (highest first) and generate content
          injections.sort_by { |rule| -rule[:priority] }.map do |rule|
            content = rule[:generator].call(session, options)
            { name: rule[:name], content: content }
          rescue StandardError => e
            # Log error and skip this injection
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              warn "[SystemPromptInjector] Error generating content for #{rule[:name]}: #{e.message}"
            end
            nil
          end.compact
        end

        # Combine base prompt with injection parts
        # @param base_prompt [String] The base system prompt
        # @param injections [Array<Hash>] Array of injection parts from build_injections
        # @param separator [String] Separator between sections (default: "\n\n---\n\n")
        # @return [String] Combined system prompt
        def combine(base_prompt:, injections:, separator: DEFAULT_SEPARATOR)
          parts = [base_prompt.to_s]

          injections.each do |injection|
            content = injection[:content].to_s.strip
            parts << content unless content.empty?
          end

          parts.reject(&:empty?).join(separator)
        end

        # Convenience method: build and combine in one call
        # @param base_prompt [String] The base prompt (system or user message)
        # @param session [Hash] Session data
        # @param options [Hash] Options hash
        # @param context [Symbol] Context type (:system or :user), defaults to :system
        # @param separator [String] Separator between sections
        # @return [String] Combined prompt
        def augment(base_prompt:, session:, options: {}, context: :system, separator: nil)
          # Use appropriate default separator based on context
          separator ||= (context == :user ? USER_MESSAGE_SEPARATOR : DEFAULT_SEPARATOR)

          injections = build_injections(session: session, options: options, context: context)
          combine(base_prompt: base_prompt, injections: injections, separator: separator)
        end

        # Convenience method specifically for user messages
        # @param base_message [String] The base user message
        # @param session [Hash] Session data
        # @param options [Hash] Options hash (should include :prompt_suffix)
        # @return [String] Augmented user message
        def augment_user_message(base_message:, session:, options: {})
          augment(
            base_prompt: base_message,
            session: session,
            options: options,
            context: :user
          )
        end
      end
    end
  end
end
