# frozen_string_literal: true

module Monadic
  module Utils
    # Which provider handles image, video and audio analysis for an app.
    #
    # An analysis runs on the app's own provider or not at all. The agents
    # used to fall back to whichever other provider had a key, so a Claude or
    # Mistral app could send a user's file to OpenAI without saying so; that
    # breaks Provider Independence. A capability lists only the providers this
    # code can actually call for it: a model named in the model spec does not
    # count until a request path exists.
    module ProviderCapabilities
      ALIASES = {
        "claude" => "anthropic",
        "gemini" => "google",
        "grok" => "xai"
      }.freeze

      KNOWN = %w[openai anthropic google xai mistral cohere deepseek ollama].freeze

      CAPABILITIES = {
        image: %w[openai anthropic google xai mistral cohere deepseek],
        video: %w[openai anthropic google xai],
        audio: %w[openai google]
      }.freeze

      API_KEYS = {
        "openai" => "OPENAI_API_KEY",
        "anthropic" => "ANTHROPIC_API_KEY",
        "google" => "GEMINI_API_KEY",
        "xai" => "XAI_API_KEY",
        "mistral" => "MISTRAL_API_KEY",
        "cohere" => "COHERE_API_KEY",
        "deepseek" => "DEEPSEEK_API_KEY"
      }.freeze

      LABELS = {
        image: "Image analysis",
        video: "Video analysis",
        audio: "Audio transcription"
      }.freeze

      module_function

      # The provider key the agents use, or nil when the name is empty or unknown.
      def normalize(provider)
        key = provider.to_s.strip.downcase
        return nil if key.empty?

        key = ALIASES.fetch(key, key)
        KNOWN.include?(key) ? key : nil
      end

      def supports?(capability, provider)
        normalized = normalize(provider)
        !normalized.nil? && CAPABILITIES.fetch(capability).include?(normalized)
      end

      def api_key_name(provider)
        API_KEYS[normalize(provider)]
      end

      # { provider: "openai" } when the app's provider can do it and has a key,
      # otherwise { error: "ERROR: ..." }. Never another provider.
      def resolve(capability, provider, config = (defined?(CONFIG) ? CONFIG : {}))
        label = LABELS.fetch(capability)
        normalized = normalize(provider)
        if normalized.nil?
          name = provider.to_s.strip
          return { error: "ERROR: #{label} needs a provider, and none was given" } if name.empty?

          return { error: "ERROR: #{label} is not available for the provider '#{name}'" }
        end
        unless CAPABILITIES.fetch(capability).include?(normalized)
          return { error: "ERROR: #{label} is not available for the provider '#{normalized}'" }
        end

        key_name = API_KEYS[normalized]
        if key_name.nil? || config[key_name].to_s.strip.empty?
          return { error: "ERROR: #{label} with '#{normalized}' needs #{key_name || 'an API key'}" }
        end

        { provider: normalized }
      end
    end
  end
end
