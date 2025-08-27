module SecondOpinionAgent
  # Default models for each provider based on Chat app configurations
  PROVIDER_DEFAULT_MODELS = {
    "openai" => "gpt-4.1",  # Updated to match MDSL
    "claude" => "claude-3-5-sonnet-20241022",
    "gemini" => "gemini-2.5-flash",
    "mistral" => "mistral-large-latest",
    "cohere" => "command-a-03-2025",
    "perplexity" => "sonar",
    "grok" => "grok-4-0709",  # Updated to match MDSL
    "deepseek" => "deepseek-chat",
    "ollama" => nil  # Will be determined dynamically
  }.freeze

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
    
    # Use AI_USER_MAX_TOKENS from configuration or default to 2000 for second opinions
    max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || 2000
    
    parameters = {
      "messages" => messages,
      "model" => target_model,
      "max_tokens" => max_tokens
    }
    
    # Check if this is a reasoning/thinking model that uses reasoning_effort
    is_reasoning_model = is_model_reasoning_based?(target_provider, target_model)
    
    if is_reasoning_model
      parameters["reasoning_effort"] = "low"  # Use low effort for quick second opinions
      # Don't include temperature for thinking models
    else
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
        model = PROVIDER_DEFAULT_MODELS[provider_normalized]
        puts "SecondOpinionAgent INFO: Using default model: #{model}"
      end
      return [provider_normalized, model]
    end
    
    # If only provider is specified, use default model for that provider
    if provider && (model.nil? || model.to_s.strip.empty?)
      default_model = PROVIDER_DEFAULT_MODELS[provider_normalized]
      
      # Special handling for Ollama
      if provider_normalized == "ollama" && default_model.nil?
        default_model = get_ollama_default_model
      end
      
      # Log for debugging
      puts "SecondOpinionAgent DEBUG: Provider #{provider_normalized} -> Default model: #{default_model.inspect}"
      
      return [provider_normalized, default_model]
    end
    
    # If neither is specified, use AI_USER_MODEL or default
    ai_user_model = CONFIG["AI_USER_MODEL"] || "gpt-4.1"
    
    # Check if AI_USER_MODEL contains provider:model format
    if ai_user_model.include?(":")
      provider_name, model_name = ai_user_model.split(":", 2)
      return [provider_name.downcase, model_name]
    else
      # Default to OpenAI if no provider specified
      return ["openai", ai_user_model]
    end
  end

  def get_provider_helper(provider)
    # Create a temporary object that includes the appropriate helper
    case provider.downcase
    when "openai"
      Class.new { extend OpenAIHelper }.tap { |c| c.extend(OpenAIHelper) }
    when "claude", "anthropic"
      Class.new { extend ClaudeHelper }.tap { |c| c.extend(ClaudeHelper) }
    when "gemini", "google"
      Class.new { extend GeminiHelper }.tap { |c| c.extend(GeminiHelper) }
    when "mistral"
      Class.new { extend MistralHelper }.tap { |c| c.extend(MistralHelper) }
    when "ollama"
      Class.new { extend OllamaHelper }.tap { |c| c.extend(OllamaHelper) }
    when "cohere"
      Class.new { extend CohereHelper }.tap { |c| c.extend(CohereHelper) }
    when "perplexity"
      Class.new { extend PerplexityHelper }.tap { |c| c.extend(PerplexityHelper) }
    when "grok"
      Class.new { extend GrokHelper }.tap { |c| c.extend(GrokHelper) }
    when "deepseek"
      Class.new { extend DeepSeekHelper }.tap { |c| c.extend(DeepSeekHelper) }
    else
      raise "Unknown provider: #{provider}"
    end
  end

  def get_ollama_default_model
    # Try to get the first available Ollama model
    if defined?(OllamaHelper)
      models = OllamaHelper.list_models
      return models.first if models && !models.empty?
    end
    
    # Fallback to environment variable or default
    CONFIG["OLLAMA_DEFAULT_MODEL"] || "llama3.2"
  end
  
  def is_model_reasoning_based?(provider, model)
    return false if provider.nil? || model.nil?
    
    # Known reasoning models patterns
    reasoning_patterns = {
      # Only Gemini thinking models use reasoning_effort
      "gemini" => /thinking/i,
      # OpenAI o1/o3 models don't use reasoning_effort parameter
      # "openai" => /^o[13](-|$)/i,  # Commented out - o1/o3 don't use reasoning_effort
      # Mistral magistral models use reasoning_effort
      "mistral" => /^magistral(-|$)/i,
      # Add more patterns here as new reasoning models are released
      # "claude" => /reasoning-model-pattern/i,
    }
    
    # Check if the model matches known reasoning patterns for the provider
    pattern = reasoning_patterns[provider.downcase]
    return false unless pattern
    
    model.match?(pattern)
  end
end
