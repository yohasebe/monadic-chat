# frozen_string_literal: true

require 'json'

module ModelSpecUtils
  module_function
  
  # Provider configuration registry
  # This can be extended or overridden as needed
  PROVIDER_DEFAULTS = {
    "openai" => {
      strategy: :latest,
      fallback_chain: ["gpt-4.1-mini", "gpt-4o-mini", "gpt-3.5-turbo"],
      special_cases: {
        vision: :auto_detect,
        reasoning: :explicit_flag
      }
    },
    "claude" => {
      strategy: :first,
      fallback_chain: ["claude-3.5-sonnet-v4-20250805", "claude-3.5-sonnet-20241022"],
      special_cases: {
        reasoning: :minimal_effort,
        batch_processing: true
      }
    },
    "gemini" => {
      strategy: :first,
      fallback_chain: ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"],
      special_cases: {
        vision: :endpoint_switch,
        reasoning: :reasoning_effort
      }
    },
    "deepseek" => {
      strategy: :first,
      fallback_chain: ["deepseek-chat"],
      special_cases: {
        strict_schema: true
      }
    },
    "cohere" => {
      strategy: :most_capable,
      fallback_chain: ["command-a-08-2025", "command-a-reasoning-08-2025"],
      special_cases: {
        reasoning: :model_switch
      }
    },
    "grok" => {
      strategy: :latest,
      fallback_chain: ["grok-4-2025-01-09", "grok-4-0709"],
      special_cases: {
        live_search: true
      }
    },
    "mistral" => {
      strategy: :first,
      fallback_chain: ["mistral-large-latest"],
      special_cases: {}
    },
    "perplexity" => {
      strategy: :first,
      fallback_chain: ["llama-3.1-sonar-large"],
      special_cases: {
        no_tools: true
      }
    }
  }.freeze

  # Load and parse model_spec.js
  def load_model_spec
    spec_file = File.join(File.dirname(__FILE__), "../../../public/js/monadic/model_spec.js")
    return {} unless File.exist?(spec_file)
    
    content = File.read(spec_file)
    # Extract the JSON-like content
    match = content.match(/const\s+modelSpec\s*=\s*(\{[\s\S]*?\n\});?/m)
    return {} unless match
    
    json_content = match[1]
    # Remove comments
    json_content = json_content.gsub(%r{//[^\n]*}, "")
    # Fix trailing commas (not valid in JSON)
    json_content = json_content.gsub(/,(\s*[}\]])/, '\1')
    
    begin
      JSON.parse(json_content)
    rescue JSON::ParserError => e
      puts "Warning: Failed to parse model_spec.js: #{e.message}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
      {}
    end
  end
  
  # Get models for a specific provider
  def get_provider_models(provider_prefix)
    spec = load_model_spec
    models = spec.select { |name, _| name.start_with?(provider_prefix) }
    
    # Preserve the order from model_spec.js
    # Ruby 1.9+ maintains insertion order for hashes
    models
  end
  
  # Get the default model for a provider with optional requirements
  # The first model that meets all requirements will be selected
  def get_default_model(provider_prefix, requirements = {})
    models = get_provider_models(provider_prefix)
    
    # If no requirements, return the first model
    return models.keys.first if requirements.empty?
    
    # Find the first model that meets all requirements
    models.find do |model_name, spec|
      requirements.all? do |key, value|
        spec[key.to_s] == value
      end
    end&.first
  end
  
  # Check if a model supports a specific capability
  def model_supports?(model_name, capability)
    spec = load_model_spec[model_name]
    return false unless spec
    
    spec["#{capability}_capability"] == true || spec[capability.to_s] == true
  end
  
  # Get all capabilities of a model
  def get_model_capabilities(model_name)
    spec = load_model_spec[model_name]
    return [] unless spec
    
    capabilities = []
    spec.each do |key, value|
      if key.end_with?("_capability") && value == true
        capabilities << key.sub(/_capability$/, "")
      end
    end
    capabilities
  end
  
  # Check if a model is a thinking/reasoning model
  def is_thinking_model?(model_name)
    return false unless model_name
    
    # First check model spec for explicit reasoning_model flag
    spec = load_model_spec[model_name]
    return true if spec && spec["reasoning_model"] == true
    
    # Fallback to name pattern matching for models not in spec
    model_name.include?("thinking") || model_name.include?("reasoning")
  end
  
  # Get the default image generation model for a provider
  # Note: Image generation models like Imagen are typically separate APIs
  # not listed in the regular model specs, so providers should define their own
  def get_image_generation_model(provider_prefix)
    # Look for models with explicit image_generation capability flag
    models = get_provider_models(provider_prefix)
    image_model = models.find { |name, spec|
      spec["image_generation_capability"] == true
    }&.first
    
    # Return nil if not found - providers should handle their own defaults
    # (e.g., Gemini uses IMAGE_GENERATION_MODEL constant for Imagen API)
    image_model
  end
  
  # Check if a model supports vision/images based on model spec
  def supports_vision?(model_name)
    spec = load_model_spec[model_name]
    return false unless spec
    
    # Check for explicit vision capability or if it's a vision model
    spec["vision_capability"] == true || 
    spec["supports_images"] == true || 
    model_name.include?("vision")
  end
  
  # Get the vision model for a provider
  def get_vision_model(provider_prefix)
    # Find models with explicit vision capability or vision in the name
    models = get_provider_models(provider_prefix)
    
    # Prefer models with explicit vision in the name for clarity
    vision_model = models.find { |name, spec| 
      name.include?("vision")
    }&.first
    
    # Fallback to any model with vision capability
    if vision_model.nil?
      vision_model = models.find { |name, spec| 
        spec["vision_capability"] == true
      }&.first
    end
    
    vision_model
  end
  
  # Find model by capability requirements
  # Returns the first model that has all required capabilities and the most optional ones
  def find_model_by_capabilities(provider_prefix, required_caps = [], optional_caps = [])
    models = get_provider_models(provider_prefix)
    
    # Filter models that have all required capabilities
    eligible_models = models.select do |name, spec|
      required_caps.all? do |cap|
        cap_key = cap.to_s.end_with?("_capability") ? cap.to_s : "#{cap}_capability"
        spec[cap_key] == true || spec[cap.to_s] == true
      end
    end
    
    return nil if eligible_models.empty?
    
    # If there are optional capabilities, prefer models with more of them
    if optional_caps && !optional_caps.empty?
      # Score each model by how many optional capabilities it has
      scored_models = eligible_models.map do |name, spec|
        score = optional_caps.count do |cap|
          cap_key = cap.to_s.end_with?("_capability") ? cap.to_s : "#{cap}_capability"
          spec[cap_key] == true || spec[cap.to_s] == true
        end
        [name, score]
      end
      
      # Return the model with the highest score
      best_model = scored_models.max_by { |_, score| score }
      best_model&.first
    else
      # No optional capabilities, return the first eligible model
      eligible_models.keys.first
    end
  end
  
  # Compare model versions (e.g., "gpt-4.1" vs "gpt-5")
  # Returns -1 if model1 < model2, 0 if equal, 1 if model1 > model2
  def compare_model_versions(model1, model2)
    return 0 if model1 == model2
    return 0 if model1.nil? && model2.nil?
    return -1 if model1.nil?
    return 1 if model2.nil?
    
    # Extract version numbers from model names
    v1 = extract_version(model1)
    v2 = extract_version(model2)
    
    # Compare versions
    v1 <=> v2
  end
  
  # Extract version from model name
  # e.g., "gpt-4.1-mini" => [4, 1]
  # e.g., "claude-3.5-sonnet" => [3, 5]
  def extract_version(model_name)
    # Look for patterns like 4.1, 3.5, or just 5
    if model_name =~ /(\d+)\.(\d+)/
      [$1.to_i, $2.to_i]
    elsif model_name =~ /-(\d+)-/
      [$1.to_i, 0]
    elsif model_name =~ /^[^-]+-?(\d+)/
      [$1.to_i, 0]
    else
      [0, 0]
    end
  end
  
  # Get the latest version of a model family
  # e.g., get_latest_version("gpt") might return "gpt-5"
  def get_latest_version(provider_prefix)
    models = get_provider_models(provider_prefix)
    return nil if models.empty?
    
    # Find the model with the highest version number
    models_with_versions = models.keys.map do |name|
      [name, extract_version(name)]
    end
    
    latest = models_with_versions.max_by { |_, version| version }
    latest&.first
  end
  
  # Get provider selection strategy
  # Returns :first, :latest, :most_capable, or :custom
  def get_provider_strategy(provider)
    # Default strategies per provider
    # This could be extended to read from configuration
    case provider.downcase
    when "openai", "gpt"
      :latest
    when "claude", "anthropic"
      :first  # Claude apps often specify exact models
    when "gemini", "google"
      :first  # Gemini uses specific flash models
    when "deepseek"
      :first  # Usually deepseek-chat
    when "cohere"
      :most_capable
    when "grok", "xai"
      :latest
    when "mistral"
      :first
    when "perplexity"
      :first
    else
      :first  # Safe default
    end
  end
  
  # Get model based on provider strategy
  def get_model_by_strategy(provider_prefix, strategy = nil)
    strategy ||= get_provider_strategy(provider_prefix)
    
    case strategy
    when :latest
      get_latest_version(provider_prefix)
    when :most_capable
      # Find model with most capabilities
      models = get_provider_models(provider_prefix)
      return nil if models.empty?
      
      models_with_caps = models.map do |name, spec|
        cap_count = spec.count { |k, v| k.end_with?("_capability") && v == true }
        [name, cap_count]
      end
      
      best = models_with_caps.max_by { |_, count| count }
      best&.first
    when :first, :custom
      get_default_model(provider_prefix)
    else
      get_default_model(provider_prefix)
    end
  end
end