# frozen_string_literal: true

module MonadicDSL
  class ProviderConfig
    # Provider information mapping
    PROVIDER_INFO = {
      # Anthropic/Claude
      "anthropic" => {
        helper_module: 'ClaudeHelper',
        api_key: 'ANTHROPIC_API_KEY',
        default_model_env: 'ANTHROPIC_DEFAULT_MODEL',
        display_group: 'Anthropic',
        aliases: ['claude', 'anthropicclaude']
      },
      # Google/Gemini
      "gemini" => {
        helper_module: 'GeminiHelper',
        api_key: 'GEMINI_API_KEY',
        default_model_env: 'GEMINI_DEFAULT_MODEL',
        display_group: 'Google',
        aliases: ['google', 'googlegemini']
      },
      # Cohere
      "cohere" => {
        helper_module: 'CohereHelper',
        api_key: 'COHERE_API_KEY',
        default_model_env: 'COHERE_DEFAULT_MODEL',
        display_group: 'Cohere',
        aliases: ['command', 'commandr', 'coherecommandr']
      },
      # Mistral
      "mistral" => {
        helper_module: 'MistralHelper',
        api_key: 'MISTRAL_API_KEY',
        default_model_env: 'MISTRAL_DEFAULT_MODEL',
        display_group: 'Mistral',
        aliases: ['mistralai']
      },
      # DeepSeek
      "deepseek" => {
        helper_module: 'DeepSeekHelper',
        api_key: 'DEEPSEEK_API_KEY',
        default_model_env: 'DEEPSEEK_DEFAULT_MODEL',
        display_group: 'DeepSeek',
        aliases: ['deep seek']
      },
      # Perplexity
      "perplexity" => {
        helper_module: 'PerplexityHelper',
        api_key: 'PERPLEXITY_API_KEY',
        default_model_env: 'PERPLEXITY_DEFAULT_MODEL',
        display_group: 'Perplexity',
        aliases: []
      },
      # XAI/Grok
      "xai" => {
        helper_module: 'GrokHelper',
        api_key: 'XAI_API_KEY',
        default_model_env: 'GROK_DEFAULT_MODEL',
        display_group: 'xAI',
        aliases: ['grok', 'xaigrok']
      },
      # OpenAI (default)
      "openai" => {
        helper_module: 'OpenAIHelper',
        api_key: 'OPENAI_API_KEY',
        default_model_env: 'OPENAI_DEFAULT_MODEL',
        display_group: 'OpenAI',
        aliases: ['gpt']
      },
      # Ollama (local)
      "ollama" => {
        helper_module: 'OllamaHelper',
        api_key: nil,  # Ollama doesn't need an API key
        default_model_env: 'OLLAMA_DEFAULT_MODEL',
        display_group: 'Ollama',
        aliases: ['local', 'ollama-local']
      }
    }.freeze

    # Constructor
    def initialize(provider_name)
      @provider_name = provider_name.to_s.downcase.gsub(/[\s\-]+/, "")
      @config = find_provider_config
    end

    # Get helper module name
    def helper_module
      @config[:helper_module]
    end

    # Get API key environment variable name
    def api_key_name
      @config[:api_key]
    end

    # Get display group name
    def display_group
      @config[:display_group]
    end

    # Get standard provider key
    def standard_key
      @config[:standard_key] || @provider_name
    end

    # Get default model environment variable name (e.g., "ANTHROPIC_DEFAULT_MODEL")
    def default_model_env
      @config[:default_model_env]
    end

    # Get model list using the appropriate helper
    def model_list
      if Object.const_defined?(@config[:helper_module])
        helper_class = Object.const_get(@config[:helper_module])
        if helper_class.respond_to?(:list_models)
          return helper_class.list_models
        end
      end
      []
    end

    private

    # Find the provider configuration based on name or aliases
    def find_provider_config
      # Direct match
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if key == @provider_name
      end

      # Check aliases
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if config[:aliases].include?(@provider_name)
      end

      # Default to OpenAI if no match
      PROVIDER_INFO["openai"]
    end
  end
end
