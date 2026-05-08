# frozen_string_literal: true

require_relative '../utils/system_defaults'

module Monadic
  module Library
    # Asks the active provider's LLM for a concise conversation title
    # suitable as a Knowledge Base entry default. Used by the Save modal
    # when there is no existing title to surface (= first save). The
    # call is best-effort: if the API key is missing, the chat app for
    # the provider can't be located, or the LLM errors, we return nil
    # and the UI falls back to its existing blank/app-name placeholder.
    #
    # We piggy-back on the running app instance for the user's current
    # provider rather than wiring a separate vendor matrix here, because
    # (a) the API key is guaranteed to be configured (the user is
    # already chatting with that provider) and (b) every vendor helper
    # exposes a uniform `send_query` entry point.
    module TitleSuggester
      module_function

      MAX_LENGTH = 60
      MAX_INPUT_TURNS = 4 # cap on user/assistant turns we feed in

      # Provider-name canonicalisation. The current app's group string
      # may use either the human label ("OpenAI") or the family name
      # ("anthropic"); both flow through here to a stable internal key.
      PROVIDER_FROM_GROUP = {
        'openai' => 'openai',
        'anthropic' => 'anthropic', 'claude' => 'anthropic',
        'gemini' => 'gemini', 'google' => 'gemini',
        'cohere' => 'cohere',
        'mistral' => 'mistral',
        'grok' => 'xai', 'xai' => 'xai',
        'deepseek' => 'deepseek',
        'ollama' => 'ollama'
      }.freeze

      API_KEY_ENV = {
        'openai' => 'OPENAI_API_KEY',
        'anthropic' => 'ANTHROPIC_API_KEY',
        'gemini' => 'GEMINI_API_KEY',
        'cohere' => 'COHERE_API_KEY',
        'mistral' => 'MISTRAL_API_KEY',
        'xai' => 'XAI_API_KEY',
        'deepseek' => 'DEEPSEEK_API_KEY'
        # Ollama runs locally and does not need an API key.
      }.freeze

      # @param messages [Array<Hash>] frontend-shaped messages with
      #   role/text fields (system entries are ignored).
      # @param app_name [String, nil] the currently active app's class
      #   name (e.g. "ChatOpenAI"); resolves the provider via APPS.
      # @param pipeline [Privacy::Pipeline, nil] when present, mask each
      #   message text before sending to the LLM and keep any returned
      #   placeholders in human-readable form ("PERSON 1") instead of
      #   restoring them. This stops the title-suggestion call from
      #   re-introducing PII that the user has chosen to mask in the
      #   primary chat path.
      # @return [String, nil] a normalised title, or nil on any failure.
      def suggest(messages:, app_name:, pipeline: nil)
        provider = derive_provider(app_name)
        return nil unless provider
        return nil unless api_key_present?(provider)

        prep_messages = pipeline ? mask_messages(messages, pipeline) : messages
        prompt = build_prompt(prep_messages)
        return nil unless prompt

        chat_pair = find_chat_app(provider)
        return nil unless chat_pair
        _, app_instance = chat_pair

        model = ::SystemDefaults.get_default_model(provider)
        return nil if model.to_s.empty?

        body = build_request_body(prompt, model, provider)
        raw = app_instance.send_query(body, model: model)
        title = normalize(raw)
        pipeline ? humanize_placeholders(title, pipeline) : title
      rescue StandardError => e
        warn "[TitleSuggester] #{e.class}: #{e.message}" if defined?(CONFIG) && CONFIG['EXTRA_LOGGING']
        nil
      end

      # Internal: pre-mask each message so the title-suggestion LLM call
      # never sees raw PII. Errors are intentionally not rescued here —
      # the outer suggest() rescue turns them into a nil return so the
      # UI falls back to its placeholder rather than silently echoing
      # raw PII when masking is unavailable.
      def mask_messages(messages, pipeline)
        return messages unless messages.is_a?(Array)
        require_relative '../utils/privacy/types'
        messages.map do |m|
          next m unless m.is_a?(Hash)
          text = (m['text'] || m[:text]).to_s
          next m if text.empty?
          raw = Monadic::Utils::Privacy::RawMessage.new(text, (m['role'] || m[:role]).to_s, {})
          masked = pipeline.before_send_to_llm(raw)
          m.merge('text' => masked.text)
        end
      end

      # Replace remaining placeholders ("<<PERSON_1>>") with their
      # readable form ("PERSON 1"). Mirrors the pattern Pipeline uses
      # for TTS — same goal: human-facing string with no raw PII.
      def humanize_placeholders(title, pipeline)
        return title if title.nil? || title.to_s.empty?
        return title unless pipeline.respond_to?(:sanitize_for_tts)
        pipeline.sanitize_for_tts(title)
      end

      # Resolve the active app's class name to a canonical provider key.
      def derive_provider(app_name)
        return nil if app_name.nil? || app_name.to_s.strip.empty?
        return nil unless defined?(::APPS)
        app = ::APPS[app_name.to_s]
        return nil unless app && app.respond_to?(:settings)
        group = app.settings['group'].to_s.downcase
        PROVIDER_FROM_GROUP.each_pair do |needle, key|
          return key if group.include?(needle)
        end
        nil
      end

      def api_key_present?(provider)
        env_key = API_KEY_ENV[provider]
        return true unless env_key # Ollama / local providers
        return false unless defined?(::CONFIG)
        v = ::CONFIG[env_key]
        v.is_a?(String) && !v.strip.empty?
      end

      # Find a Chat app instance whose group matches the provider so we
      # can call its send_query without re-implementing per-vendor
      # routing. Mirrors AIUserAgent#find_chat_app_for_provider.
      def find_chat_app(provider)
        return nil unless defined?(::APPS)
        keywords = case provider
                   when 'anthropic' then %w[anthropic claude]
                   when 'xai' then %w[grok xai]
                   when 'gemini' then %w[gemini google]
                   else [provider]
                   end
        ::APPS.each do |key, app|
          next unless app.respond_to?(:settings) && app.settings['group']
          group = app.settings['group'].to_s.downcase.strip
          display = app.settings['display_name']
          if keywords.any? { |kw| group.include?(kw) } && display == 'Chat'
            return [key, app]
          end
        end
        nil
      end

      # Pull the first few user/assistant turns and shape them into a
      # short directive prompt the LLM can summarise into a title.
      def build_prompt(messages)
        return nil unless messages.is_a?(Array)
        snippets = []
        messages.each do |m|
          next unless m.is_a?(Hash)
          role = (m['role'] || m[:role]).to_s
          next unless %w[user assistant].include?(role)
          text = (m['text'] || m[:text]).to_s.strip
          next if text.empty?
          # 240 chars per turn is enough to convey topic without
          # bloating the prompt or leaking long boilerplate.
          snippets << "#{role}: #{text[0, 240]}"
          break if snippets.size >= MAX_INPUT_TURNS
        end
        return nil if snippets.empty?

        <<~PROMPT
          Suggest a concise, descriptive title for the following conversation.
          Constraints:
          - At most #{MAX_LENGTH} characters.
          - Plain text only, no surrounding quotes, no markdown, no trailing punctuation.
          - Match the conversation's primary language.
          - Reply with the title alone — nothing else.

          Conversation:
          #{snippets.join("\n\n")}
        PROMPT
      end

      # Most vendor helpers accept a Chat-Completions style payload via
      # send_query. We intentionally keep options minimal and let each
      # helper apply its own provider-specific defaults (sampling/limits/etc).
      def build_request_body(prompt, model, _provider)
        {
          'messages' => [
            { 'role' => 'system', 'content' => 'You generate concise titles for conversations. Reply with only the title.' },
            { 'role' => 'user', 'content' => prompt }
          ],
          'model' => model
        }
      end

      # Strip the noise that LLMs tend to add around bare titles — leading
      # quotes, trailing punctuation, "Title:" prefixes — and clamp to
      # MAX_LENGTH so an over-eager model can't blow out the input field.
      def normalize(text)
        return nil unless text.is_a?(String)
        title = text.strip
        return nil if title.empty?
        # Take only the first non-empty line (LLMs sometimes reply with
        # "Title: X\n\n(rationale)" despite the directive).
        title = title.lines.find { |l| !l.strip.empty? }.to_s.strip
        title = title.sub(/\A(?:title|タイトル)\s*[:：]\s*/i, '')
        title = title.sub(/\A["「『'']/, '').sub(/["」』''.,!?]\z/, '')
        return nil if title.empty?
        title.length > MAX_LENGTH ? title[0, MAX_LENGTH].rstrip : title
      end
    end
  end
end
