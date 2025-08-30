# frozen_string_literal: true

require 'json'

module SystemDefaults
  module_function

  # Load system defaults from JSON file
  def load_defaults
    defaults_file = File.join(File.dirname(__FILE__), '../../../config/system_defaults.json')
    return {} unless File.exist?(defaults_file)
    
    begin
      JSON.parse(File.read(defaults_file))
    rescue JSON::ParserError => e
      puts "Warning: Failed to parse system_defaults.json: #{e.message}" if ENV['DEBUG']
      {}
    end
  end

  # Get default model for a provider
  # Priority: ENV variable > system_defaults.json > fallback
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
    
    # First, check environment variable (user override)
    if env_var && defined?(CONFIG) && CONFIG && CONFIG[env_var]
      return CONFIG[env_var]
    end
    
    # Second, check system defaults
    defaults = load_defaults
    provider_defaults = defaults.dig('provider_defaults', provider)
    
    if provider_defaults && provider_defaults['model']
      return provider_defaults['model']
    end
    
    # No default found
    nil
  end


end