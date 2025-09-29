require_relative "../utils/system_defaults"

module SecondOpinionAgent

  def second_opinion_agent(user_query: "", agent_response: "", provider: nil, model: nil)
    # Determine provider and model
    target_provider, target_model = determine_provider_and_model(provider, model)
    
    # Debug output to track the issue
    puts "SecondOpinionAgent DEBUG: Input provider=#{provider.inspect}, model=#{model.inspect}"
    puts "SecondOpinionAgent DEBUG: Determined provider=#{target_provider.inspect}, model=#{target_model.inspect}"
    
    # Validate model is not nil or empty
    if target_model.nil? || target_model.to_s.strip.empty?
      return {
        comments: "Error: Model not specified or invalid for provider #{target_provider}",
        validity: "error", 
        model: "none"
      }
    end
    
    # Get the appropriate helper module
    helper = get_provider_helper(target_provider)
    
    # For debugging
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "SecondOpinionAgent: Using provider #{target_provider} with model #{target_model}"
    end

    # Create a single user message containing all context
    user_message_content = <<~TEXT
      Please verify and make comments about the following query and response pair. If the response is correct, you should say 'The response is correct'. But you should be rather critical and meticulous, considering many factors, so it is more likely that you will find possible caveats in the response.

      You should point out the errors or possible caveats in the response and suggest corrections where necessary.
      
      ### Query
      #{user_query}

      ### Response
      #{agent_response}
      
      IMPORTANT: Your response MUST be formatted EXACTLY as follows:

      ### COMMENTS
      YOUR_COMMENTS_HERE

      ### VALIDITY
      X/10

      ### Evaluation Model
      #{target_provider}:#{target_model}

      Replace YOUR_COMMENTS_HERE with your actual comments and X with a number from 1 to 10.
    TEXT

    # All providers will receive the same single user message format
    messages = [
      {
        "role" => "user",
        "content" => user_message_content
      }
    ]
    
    # Let each provider use its own default max_tokens
    # Don't specify max_tokens here - providers will use their defaults
    parameters = {
      "messages" => messages,
      "model" => target_model
    }
    
    # Delegate reasoning configuration to the provider implementation
    # Each provider class knows how to configure its own reasoning models
    if respond_to?(:configure_reasoning_params)
      parameters = configure_reasoning_params(parameters, target_model)
    else
      # Fallback for when called from module directly (e.g., tests)
      # Use simple default configuration
      parameters["temperature"] = 0.7
    end

    begin
      # Use the provider's helper to send the query
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "SecondOpinionAgent: Sending query to #{target_provider} with model #{target_model}"
        puts "SecondOpinionAgent: Messages: #{messages.inspect}"
      end
      
      response = helper.send_query(parameters, model: target_model)
      
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "SecondOpinionAgent: Received response: #{response.inspect[0..200]}..."
      end
    rescue => e
      # Error handling
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "SecondOpinionAgent Error: #{e.message}"
        puts "SecondOpinionAgent Error Backtrace: #{e.backtrace.first(3).join("\n")}"
      end
      return {
        comments: "Failed to get second opinion from #{target_provider}: #{e.message}",
        validity: "error",
        model: "#{target_provider}:#{target_model}"
      }
    end
    
    # Parse the response to extract comments, validity, and model
    if response.is_a?(String)
      comments = ""
      validity = "unknown"
      
      # Extract comments - make regex more flexible with whitespace
      if response =~ /###\s*COMMENTS\s*\n(.*?)(?=\n###\s*VALIDITY|\z)/mi
        comments = $1.strip
      end
      
      # Extract validity - handle variations in formatting
      if response =~ /###\s*VALIDITY\s*\n\s*(\d+)\s*\/\s*10/mi
        validity = "#{$1}/10"
      end
      
      # If we have comments but no validity (e.g., response was cut off)
      if !comments.empty? && validity == "unknown"
        # Log for debugging if enabled
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "SecondOpinionAgent: Found comments but no validity score (response may have been truncated)"
        end
        validity = "incomplete"
      elsif comments.empty? && validity == "unknown"
        # If parsing failed completely, use the entire response as comments
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "SecondOpinionAgent: Failed to parse structured response, using full response as comments"
        end
        comments = response.strip
      end
      
      {
        comments: comments,
        validity: validity,
        model: "#{target_provider}:#{target_model}"
      }
    else
      {
        comments: "Failed to get second opinion",
        validity: "error",
        model: "#{target_provider}:#{target_model}"
      }
    end
  end

  private

  def determine_provider_and_model(provider, model)
    # Normalize provider name if provided
    if provider
      # Handle common provider name variations
      provider_normalized = case provider.to_s.downcase
      when "claude", "anthropic"
        "claude"
      when "openai", "gpt"
        "openai"
      when "gemini", "google"
        "gemini"
      when "xai", "grok"
        "grok"
      else
        provider.to_s.downcase
      end
    end
    
    # If both provider and model are specified, validate and use them
    if provider && model && !model.to_s.strip.empty?
      # For Claude, check if the model name is incomplete (missing full date)
      if provider_normalized == "claude" && model.to_s =~ /claude.*sonnet.*\d{4}-\d{2}$/
        # Model name appears to be cut off (ends with YYYY-MM instead of YYYYMMDD)
        puts "SecondOpinionAgent WARNING: Incomplete Claude model name detected: #{model}"
        # Use default model instead
        model = get_default_model_for_provider(provider_normalized)
        puts "SecondOpinionAgent INFO: Using default model: #{model}"
      end
      return [provider_normalized, model]
    end
    
    # If only provider is specified, use default model for that provider
    if provider && (model.nil? || model.to_s.strip.empty?)
      default_model = get_default_model_for_provider(provider_normalized)
      
      # Special handling for Ollama
      if provider_normalized == "ollama" && default_model.nil?
        default_model = get_ollama_default_model
      end
      
      # Log for debugging
      puts "SecondOpinionAgent DEBUG: Provider #{provider_normalized} -> Default model: #{default_model.inspect}"
      
      return [provider_normalized, default_model]
    end
    
    # If neither is specified, use OpenAI as default provider with its default model
    default_provider = "openai"
    default_model = get_default_model_for_provider(default_provider)
    
    # Log for debugging
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "SecondOpinionAgent: No provider specified, using default: #{default_provider} with model #{default_model}"
    end
    
    return [default_provider, default_model]
  end

  def get_provider_helper(provider)
    # Return an object instance that includes the appropriate helper
    klass = case provider.downcase
            when "openai"
              Class.new { include OpenAIHelper }
            when "claude", "anthropic"
              Class.new { include ClaudeHelper }
            when "gemini", "google"
              Class.new { include GeminiHelper }
            when "mistral"
              Class.new { include MistralHelper }
            when "ollama"
              Class.new { include OllamaHelper }
            when "cohere"
              Class.new { include CohereHelper }
            when "perplexity"
              Class.new { include PerplexityHelper }
            when "grok"
              Class.new { include GrokHelper }
            when "deepseek"
              Class.new { include DeepSeekHelper }
            else
              raise "Unknown provider: #{provider}"
            end
    klass.new
  end

  def get_ollama_default_model
    # Try to get the first available Ollama model
    if defined?(OllamaHelper)
      models = OllamaHelper.list_models
      return models.first if models && !models.empty?
    end
    
    # Use CONFIG variable (set in main.js with default)
    CONFIG["OLLAMA_DEFAULT_MODEL"]
  end
  
  def get_default_model_for_provider(provider)
    # Get default model based on provider using CONFIG variables
    # CONFIG variables are always set with defaults in main.js
    provider_downcase = provider.to_s.downcase
    
    case provider_downcase
    when "claude", "anthropic"
      SystemDefaults.get_default_model('anthropic')
    when "openai", "gpt"
      SystemDefaults.get_default_model('openai')
    when "gemini", "google"
      SystemDefaults.get_default_model('gemini')
    when "mistral"
      SystemDefaults.get_default_model('mistral')
    when "cohere"
      SystemDefaults.get_default_model('cohere')
    when "perplexity"
      SystemDefaults.get_default_model('perplexity')
    when "grok", "xai"
      SystemDefaults.get_default_model('xai')
    when "deepseek"
      SystemDefaults.get_default_model('deepseek')
    when "ollama"
      get_ollama_default_model
    else
      # Fallback to OpenAI default
      SystemDefaults.get_default_model('openai')
    end
  end
  
end
