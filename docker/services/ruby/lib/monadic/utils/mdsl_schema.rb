# frozen_string_literal: true

# MDSL (Monadic DSL) Schema Definition
# This module defines the types and validation rules for MDSL properties
module MDSLSchema
  # Property aliases for backward compatibility
  # Maps alternative names to canonical property names
  ALIASES = {
    # Format variations
    "response_format" => "response_format",  # canonical
    "responseFormat" => "response_format",   # camelCase variant
    
    # Submit variations
    "easy_submit" => "easy_submit",         # canonical
    "easySubmit" => "easy_submit",          # camelCase variant
    
    # Speech variations
    "auto_speech" => "auto_speech",         # canonical
    "autoSpeech" => "auto_speech",          # camelCase variant
    
    # Assistant initiation variations
    "initiate_from_assistant" => "initiate_from_assistant",  # canonical
    "initiateFromAssistant" => "initiate_from_assistant",    # camelCase variant
    
    # Context size variations
    "context_size" => "context_size",       # canonical
    "contextSize" => "context_size",        # camelCase variant
    
    # Display name variations
    "display_name" => "display_name",       # canonical
    "displayName" => "display_name",        # camelCase variant
    
    # System prompt variations
    "system_prompt" => "system_prompt",     # canonical
    "systemPrompt" => "system_prompt",      # camelCase variant
    
    # App name variations
    "app_name" => "app_name",               # canonical
    "appName" => "app_name",                # camelCase variant
    
    # AI user variations
    "ai_user" => "ai_user",                 # canonical
    "aiUser" => "ai_user"                   # camelCase variant
  }.freeze
  
  # Property type definitions
  # Each property has a type, description, and optional validation rules
  PROPERTIES = {
    # App-level properties
    description: {
      type: :string,
      description: "App description with optional HTML"
    },
    icon: {
      type: :string,
      description: "Icon name (FontAwesome or built-in)"
    },
    display_name: {
      type: :string,
      description: "Display name for the app"
    },
    system_prompt: {
      type: :string,
      description: "System prompt for the AI"
    },
    
    # LLM properties
    provider: {
      type: :string,
      description: "LLM provider name",
      enum: %w[openai anthropic gemini mistral cohere perplexity grok deepseek ollama]
    },
    model: {
      type: :string,
      description: "Model identifier"
    },
    temperature: {
      type: :float,
      description: "Temperature setting for LLM",
      range: 0.0..2.0
    },
    context_size: {
      type: :integer,
      description: "Number of messages to keep in context",
      minimum: 1
    },
    response_format: {
      type: :hash,
      description: "Response format configuration (e.g., JSON mode)"
    },
    
    # Feature flags (boolean)
    disabled: {
      type: :boolean,
      description: "Whether the app is disabled"
    },
    monadic: {
      type: :boolean,
      description: "Enable monadic JSON response format"
    },
    easy_submit: {
      type: :boolean,
      description: "Enable easy submit mode"
    },
    auto_speech: {
      type: :boolean,
      description: "Enable automatic speech"
    },
    initiate_from_assistant: {
      type: :boolean,
      description: "Start conversation from assistant"
    },
    image: {
      type: :boolean,
      description: "Enable image input support"
    },
    pdf: {
      type: :boolean,
      description: "Enable PDF upload support"
    },
    jupyter: {
      type: :boolean,
      description: "Enable Jupyter notebook support"
    },
    mathjax: {
      type: :boolean,
      description: "Enable MathJax rendering"
    },
    websearch: {
      type: :boolean,
      description: "Enable web search capability"
    },
    stream: {
      type: :boolean,
      description: "Enable streaming responses"
    },
    vision: {
      type: :boolean,
      description: "Enable vision capabilities"
    },
    reasoning: {
      type: :boolean,
      description: "Enable reasoning mode"
    },
    ai_user: {
      type: :boolean,
      description: "Enable AI user simulation"
    },
    
    # Complex data types (arrays/objects)
    images: {
      type: :array,
      description: "Array of image data objects",
      element_type: :hash
    },
    messages: {
      type: :array,
      description: "Array of message objects",
      element_type: :hash
    },
    parameters: {
      type: :hash,
      description: "Additional parameters"
    },
    tools: {
      type: :array,
      description: "Array of tool definitions",
      element_type: :hash
    },
    progressive_tools: {
      type: :hash,
      description: "Metadata describing conditional tool disclosure behaviour"
    },
    cells: {
      type: :array,
      description: "Array of Jupyter notebook cells",
      element_type: :hash
    },
    
    # String properties
    message: {
      type: :string,
      description: "User message text"
    },
    text: {
      type: :string,
      description: "Text content"
    },
    content: {
      type: :string_or_hash,
      description: "Message content (can be string or structured data)"
    },
    html: {
      type: :string,
      description: "HTML content"
    },
    data: {
      type: :any,
      description: "Generic data field"
    },
    role: {
      type: :string,
      description: "Message role",
      enum: %w[user assistant system]
    },
    app_name: {
      type: :string,
      description: "Application name"
    },
    
    # Other properties
    group: {
      type: :string,
      description: "UI group for the app"
    }
  }.freeze
  
  # Normalize property name to canonical form
  def self.normalize(property)
    prop_str = property.to_s
    ALIASES[prop_str] || prop_str
  end
  
  # Get all aliases for a property
  def self.aliases_for(property)
    canonical = normalize(property)
    ALIASES.select { |_, v| v == canonical }.keys
  end
  
  # Check if a property name is an alias
  def self.alias?(property)
    prop_str = property.to_s
    ALIASES.key?(prop_str) && ALIASES[prop_str] != prop_str
  end
  
  # Get property type
  def self.type_of(property)
    prop = normalize(property)
    PROPERTIES.dig(prop.to_sym, :type)
  end
  
  # Check if property should be treated as boolean
  def self.boolean?(property)
    type_of(property) == :boolean
  end
  
  # Check if property should be protected from type conversion
  def self.protected?(property)
    type = type_of(property)
    [:array, :hash, :any, :string_or_hash].include?(type)
  end
  
  # Get all boolean properties (including aliases)
  def self.boolean_properties
    props = PROPERTIES.select { |_, v| v[:type] == :boolean }.keys.map(&:to_s)
    # Add all aliases for boolean properties
    props.flat_map { |prop| aliases_for(prop) + [prop] }.uniq
  end
  
  # Get all protected properties (including aliases)
  def self.protected_properties
    props = PROPERTIES.select { |_, v| [:array, :hash, :any, :string_or_hash].include?(v[:type]) }.keys.map(&:to_s)
    # Add all aliases for protected properties
    props.flat_map { |prop| aliases_for(prop) + [prop] }.uniq
  end
  
  # Validate a value against its schema
  def self.validate(property, value)
    normalized_prop = normalize(property)
    prop_schema = PROPERTIES[normalized_prop.to_sym]
    return true unless prop_schema
    
    case prop_schema[:type]
    when :boolean
      value.is_a?(TrueClass) || value.is_a?(FalseClass)
    when :string
      value.is_a?(String)
    when :integer
      value.is_a?(Integer)
    when :float
      value.is_a?(Float) || value.is_a?(Integer)
    when :array
      value.is_a?(Array)
    when :hash
      value.is_a?(Hash)
    when :string_or_hash
      value.is_a?(String) || value.is_a?(Hash)
    when :any
      true
    else
      true
    end
  end
  
  # Convert value to expected type (for boolean properties)
  def self.coerce(property, value)
    normalized_prop = normalize(property)
    prop_schema = PROPERTIES[normalized_prop.to_sym]
    return value unless prop_schema
    
    case prop_schema[:type]
    when :boolean
      # Use BooleanParser for consistent conversion
      require_relative 'boolean_parser'
      BooleanParser.parse(value)
    when :integer
      begin
        Integer(value.to_s)
      rescue ArgumentError, TypeError
        value
      end
    when :float
      begin
        Float(value.to_s)
      rescue ArgumentError, TypeError
        value
      end
    else
      value
    end
  end
  
  # Normalize a hash by converting all aliased keys to canonical form
  def self.normalize_hash(hash)
    return hash unless hash.is_a?(Hash)
    
    normalized = {}
    hash.each do |key, value|
      canonical_key = normalize(key)
      normalized[canonical_key] = value
    end
    normalized
  end
end
