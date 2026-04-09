# frozen_string_literal: true

require_relative 'model_spec'

module SystemDefaults
  module_function

  # Get default model for a provider
  # Priority: ENV variable > providerDefaults (model_spec.js SSOT) > nil
  def get_default_model(provider)
    provider = provider.to_s.downcase

    # Map provider names to environment variable names
    env_var_map = {
      'openai' => 'OPENAI_DEFAULT_MODEL',
      'anthropic' => 'ANTHROPIC_DEFAULT_MODEL',
      'claude' => 'ANTHROPIC_DEFAULT_MODEL',
      'cohere' => 'COHERE_DEFAULT_MODEL',
      'gemini' => 'GEMINI_DEFAULT_MODEL',
      'google' => 'GEMINI_DEFAULT_MODEL',
      'mistral' => 'MISTRAL_DEFAULT_MODEL',
      'xai' => 'GROK_DEFAULT_MODEL',
      'grok' => 'GROK_DEFAULT_MODEL',
      'perplexity' => 'PERPLEXITY_DEFAULT_MODEL',
      'deepseek' => 'DEEPSEEK_DEFAULT_MODEL',
      'ollama' => 'OLLAMA_DEFAULT_MODEL'
    }

    env_var = env_var_map[provider]

    if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
      puts "[SystemDefaults] Getting default model for provider: #{provider}"
      puts "[SystemDefaults] Env var name: #{env_var}"
    end

    # First, check environment variable (user override)
    if env_var && defined?(CONFIG) && CONFIG
      val = CONFIG[env_var]
      if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
        puts "[SystemDefaults] CONFIG[#{env_var}] value: #{val.inspect}"
      end
      # Treat nil/empty/whitespace-only as not configured
      return val unless val.nil? || val.to_s.strip.empty?
    end

    # Second, check providerDefaults in model_spec.js (SSOT)
    begin
      model_spec_default = Monadic::Utils::ModelSpec.get_provider_default(provider, "chat")
      if model_spec_default
        if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
          puts "[SystemDefaults] Using providerDefaults from model_spec.js: #{model_spec_default}"
        end
        return model_spec_default
      end
    rescue => e
      puts "[SystemDefaults] Warning: Failed to read providerDefaults: #{e.message}" if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
    end

    # No default found
    if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
      puts "[SystemDefaults] No default model found for #{provider}"
    end
    nil
  end
end
