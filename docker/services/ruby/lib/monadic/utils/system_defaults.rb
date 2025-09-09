# frozen_string_literal: true

require 'json'

module SystemDefaults
  module_function

  # Load system defaults from JSON file
  def load_defaults
    # Try multiple possible locations for system_defaults.json
    possible_paths = [
      # Non-mounted internal defaults inside image
      '/monadic/internal_config/system_defaults.json',
      # Relative path (may resolve under /monadic/config which can be a bind mount)
      File.join(File.dirname(__FILE__), '../../../config/system_defaults.json'),
      # Typical mounted path
      '/monadic/config/system_defaults.json',
      File.join(ENV['WORKSPACE'] || '/monadic', 'config/system_defaults.json')
    ]
    
    defaults_file = possible_paths.find { |path| File.exist?(path) }
    
    unless defaults_file
      puts "Warning: system_defaults.json not found in any of: #{possible_paths.join(', ')}" if ENV['DEBUG'] || ENV['EXTRA_LOGGING']
      return {}
    end
    
    begin
      JSON.parse(File.read(defaults_file))
    rescue JSON::ParserError => e
      puts "Warning: Failed to parse system_defaults.json: #{e.message}" if ENV['DEBUG'] || ENV['EXTRA_LOGGING']
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
    
    # Log for debugging AI User issues
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
    
    # Second, check system defaults
    defaults = load_defaults
    provider_defaults = defaults.dig('provider_defaults', provider)
    
    if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
      puts "[SystemDefaults] Loaded defaults: #{defaults.keys.inspect}"
      puts "[SystemDefaults] Provider defaults for #{provider}: #{provider_defaults.inspect}"
    end
    
    if provider_defaults && provider_defaults['model']
      model = provider_defaults['model']
      if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
        puts "[SystemDefaults] Returning default model: #{model}"
      end
      return model
    end
    
    # No default found
    if ENV['EXTRA_LOGGING'] || ENV['DEBUG']
      puts "[SystemDefaults] No default model found for #{provider}"
    end
    nil
  end


end
