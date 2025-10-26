# frozen_string_literal: true

require_relative 'language_config'

module Monadic
  module Utils
    # Unified prompt injection manager
    # Provides consistent dynamic prompt augmentation across all vendor helpers
    # Supports both system messages (conversation start) and user messages (each input)
    class SystemPromptInjector
      # Standard separator between prompt sections
      DEFAULT_SEPARATOR = "\n\n---\n\n"
      USER_MESSAGE_SEPARATOR = "\n\n"

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

      # MathJax formatting prompt (base)
      MATHJAX_BASE_PROMPT = <<~PROMPT.strip
        You use the MathJax notation to write mathematical expressions. In doing so, you should follow the format requirements: Use double dollar signs `$$` to enclose MathJax/LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly. Either type of MathJax expression should be presntend without surrounding backticks.
      PROMPT

      # MathJax formatting prompt for monadic/jupyter mode (requires extra escaping)
      MATHJAX_MONADIC_PROMPT = <<~'PROMPT'.strip
        Make sure to escape properly in the MathJax expressions.

          Good examples of inline MathJax expressions:
          - `$1 + 2 + 3 + … + k + (k + 1) = \\frac{k(k + 1)}{2} + (k + 1)$`
          - `$\\textbf{a} + \\textbf{b} = (a_1 + b_1, a_2 + b_2)$`
          - `$\\begin{align} 1 + 2 + … + k + (k+1) &= \\frac{k(k+1)}{2} + (k+1)\\end{align}$`
          - `$\\sin(\\theta) = \\frac{\\text{opposite}}{\\text{hypotenuse}}$`

        Good examples of block MathJax expressions:
          - `$$1 + 2 + 3 + … + k + (k + 1) = \\frac{k(k + 1)}{2} + (k + 1)$$`
          - `$$\\textbf{a} + \\textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
          - `$$\\begin{align} 1 + 2 + … + k + (k+1) &= \\frac{k(k+1)}{2} + (k+1)\\end{align}$$`
          - `$$\\sin(\\theta) = \\frac{\\text{opposite}}{\\text{hypotenuse}}$$`
      PROMPT

      # MathJax formatting prompt for regular mode (standard escaping)
      MATHJAX_REGULAR_PROMPT = <<~'PROMPT'.strip
        Good examples of inline MathJax expressions:
          - `$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$`
          - `$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$`
          - `$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$`
          - `$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$`

        Good examples of block MathJax expressions:
          - `$$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$$`
          - `$$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
          - `$$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$$`
          - `$$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$$`

        Remember that the following are not available in MathJax:
          - `\begin{itemize}` and `\end{itemize}`
      PROMPT

      # System message injection rules (applied at conversation start)
      # Each rule has: name, priority, condition, and generator
      SYSTEM_INJECTION_RULES = [
        {
          name: :language_preference,
          priority: 100,
          condition: ->(session, _options) {
            session[:runtime_settings]&.[](:language) &&
              session[:runtime_settings][:language] != "auto"
          },
          generator: ->(session, _options) {
            lang = session[:runtime_settings][:language]
            Monadic::Utils::LanguageConfig.system_prompt_for_language(lang)
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
          name: :stt_diarization_warning,
          priority: 60,
          condition: ->(session, _options) {
            stt_model = session[:parameters]&.[]("stt_model")
            stt_model && stt_model.to_s.include?("diarize")
          },
          generator: ->(_session, _options) {
            DIARIZATION_STT_PROMPT
          }
        },
        {
          name: :mathjax,
          priority: 50,
          condition: ->(session, _options) {
            session[:parameters]&.[]("mathjax") == true
          },
          generator: ->(session, _options) {
            parts = [MATHJAX_BASE_PROMPT]

            # Add mode-specific escaping instructions
            monadic_mode = session[:parameters]&.[]("monadic") == true
            jupyter_mode = session[:parameters]&.[]("jupyter") == true

            if monadic_mode || jupyter_mode
              parts << MATHJAX_MONADIC_PROMPT
            else
              parts << MATHJAX_REGULAR_PROMPT
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
