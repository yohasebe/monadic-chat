# frozen_string_literal: true

# ConfigHelper provides a unified interface for accessing configuration values
# Priority: ENV (for overrides) > CONFIG (user settings) > default
module ConfigHelper
  # Get configuration value with consistent priority handling
  # ENV takes precedence (for Docker/deployment overrides)
  # CONFIG comes next (user's ~/monadic/config/env file)
  # Default value is returned if neither is set
  def self.get_config(key, default = nil)
    # ENV always takes precedence for deployment flexibility
    return ENV.fetch(key, nil) if ENV.key?(key) && !ENV[key].to_s.strip.empty?

    # Then check CONFIG if it's defined and has the key
    return CONFIG[key] if defined?(CONFIG) && CONFIG.is_a?(Hash) && CONFIG.key?(key) && !CONFIG[key].to_s.strip.empty?

    # Return default if provided
    default
  end

  # Get API key with backward compatibility for OpenAI's ENV-first pattern
  def self.get_api_key(provider)
    case provider.downcase
    when "openai"
      # Maintain OpenAI's existing ENV-first behavior for compatibility
      ENV["OPENAI_API_KEY"] || (defined?(CONFIG) ? CONFIG["OPENAI_API_KEY"] : nil)
    when "anthropic", "claude"
      get_config("ANTHROPIC_API_KEY")
    when "gemini"
      get_config("GEMINI_API_KEY")
    when "mistral"
      get_config("MISTRAL_API_KEY")
    when "cohere"
      get_config("COHERE_API_KEY")
    when "perplexity"
      get_config("PERPLEXITY_API_KEY")
    when "deepseek"
      get_config("DEEPSEEK_API_KEY")
    when "xai", "grok"
      get_config("XAI_API_KEY")
    when "elevenlabs"
      get_config("ELEVENLABS_API_KEY")
    end
  end

  # Check if running in distributed mode
  def self.distributed_mode?
    mode = get_config("DISTRIBUTED_MODE", "off")
    mode.to_s.downcase == "on"
  end

  # Check if extra logging is enabled
  def self.extra_logging?
    get_config("EXTRA_LOGGING", false).to_s.downcase == "true"
  end

  # Get AI user settings with consistent access
  def self.ai_user_max_tokens
    get_config("AI_USER_MAX_TOKENS", "2000").to_i
  end

  def self.ai_user_model
    get_config("AI_USER_MODEL", "gpt-4.1-mini")
  end

  # Get Jupyter port
  def self.jupyter_port
    get_config("JUPYTER_PORT", "8889")
  end
end
