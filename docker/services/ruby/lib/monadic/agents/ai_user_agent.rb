# frozen_string_literal: true

require_relative "../utils/system_defaults"

# AI User Agent
# Handles the generation of simulated user responses in conversations
module AIUserAgent
  # Process AI User request to generate a user message
  # @param session [Hash] The session information containing message history
  # @param params [Hash] Parameters for AI User generation
  # @return [Hash] The result of AI User generation
  def process_ai_user(session, params)
    # Check for required parameters and provide fallback
    provider = params["ai_user_provider"]
    if provider.nil? || provider.empty?
      provider = "openai" # Default provider fallback
    end
    
    # Provider details are logged to dedicated log files
    
    # Get conversation history
    max_history = 5
    conversation_messages = session[:messages].reject { |m| m["role"] == "system" }.last(max_history)
    
    # Format conversation history as text
    conversation_text = format_conversation(conversation_messages, params["monadic"])
    
    # Create system message with instruction
    instruction = "Based on the conversation history above, generate the next natural response from the user."
    system_message = "#{MonadicApp::AI_USER_INITIAL_PROMPT}\n\nConversation History:\n\n#{conversation_text}\n\n#{instruction}"
    
    # Find appropriate chat app for this provider
    chat_app = find_chat_app_for_provider(provider)
    
    # Return error if no suitable app found
    if !chat_app
      return { 
        "type" => "error", 
        "content" => "No compatible chat app found for provider: #{provider}"
      }
    end
    
    # Get app instance and force model based on provider (ignore inherited model)
    app_instance = chat_app[1]
    
    # Skip app_instance.settings["model"] to avoid inheriting main conversation model
    # and directly use our provider-specific model
    model = default_model_for_provider(provider)
    
    # Model details are logged to dedicated log files
    
    # Create conversation context for the API
    context = []
    conversation_messages.each do |m|
      context << {
        "role" => m["role"],
        "content" => extract_content(m["text"], params["monadic"])
      }
    end
    
    # For Perplexity, we'll use a simplified approach
    # The actual message formatting will be handled by perplexity_helper.rb using the ai_user_system_message
    if provider == "perplexity"
      # We don't need to do complex formatting here anymore 
      # Just ensure we have the conversation context in the system message
      # The helper will handle the rest
      context = []
    end
    
    # Add system message at the beginning (some APIs handle this differently)
    # Handle system message based on provider
    if provider == "anthropic"
      system_option = { "system" => system_message }
      # Don't add to context for Anthropic
    elsif provider == "perplexity"
      system_option = {}
      # For Perplexity, add as first user message since they require last message to be user
      context.unshift({ "role" => "user", "content" => "System instructions: " + system_message })
    else
      system_option = {}
      # For other providers like OpenAI, use standard "system" role
      # Note: Cohere helper will convert roles properly in its send_query method
      context.unshift({ "role" => "system", "content" => system_message })
    end
    
    # Instead of sending all previous messages, we'll only use the system message which contains
    # all the necessary context and instructions
    
    # Create a focused message array with just system message that contains all context
    focused_messages = []
    
    # Add system message - use either the specialized format for Anthropic or standard format for others
    if provider == "anthropic"
      # For Anthropic, we need at least one user message
      # Add a simple prompt to trigger the AI user response
      focused_messages << { 
        "role" => "user", 
        "content" => "Based on the conversation context provided in the system message, what would be the most natural next response from the user?" 
      }
    else
      # For other providers, add as a system message
      focused_messages << { "role" => "system", "content" => system_message }
    end
    
    # Prepare options for the API call with provider-specific settings
    # Compose request options. Avoid forcing temperature for models that disallow sampling.
    options = {
      "messages" => focused_messages,
      "ai_user_system_message" => system_message,
      "model" => model
    }.merge(system_option)
    begin
      # Only add temperature when model spec indicates it's not a reasoning/Responses API model
      allow_sampling = !Monadic::Utils::ModelSpec.is_reasoning_model?(model) && !Monadic::Utils::ModelSpec.responses_api?(model)
      options["temperature"] = 0.7 if allow_sampling
    rescue StandardError
      # On spec lookup failure, omit temperature to be safe
    end

    # If the model supports reasoning_effort, set a default value from spec so that
    # AI User behavior aligns with the assistant model display.
    begin
      effort_cfg = Monadic::Utils::ModelSpec.get_reasoning_effort_options(model)
      if effort_cfg && effort_cfg[:options].is_a?(Array) && !effort_cfg[:options].empty?
        default_effort = effort_cfg[:default]
        default_effort = effort_cfg[:options].first unless effort_cfg[:options].include?(default_effort)
        options["reasoning_effort"] = default_effort
      end
    rescue StandardError
      # If lookup fails, skip setting reasoning_effort
    end

    # Anthropic: if model supports thinking but no reasoning_effort is present, set a default label
    begin
      if provider.to_s.downcase.include?("anthropic") && Monadic::Utils::ModelSpec.supports_thinking?(model)
        options["reasoning_effort"] ||= "medium"
      end
    rescue StandardError
      # Ignore lookup errors
    end

    # Gemini (Google): set a reasonable default when thinking is supported
    begin
      if provider.to_s.downcase.include?("gemini") && Monadic::Utils::ModelSpec.supports_thinking?(model)
        # If can_disable is true, prefer 'low'; otherwise 'medium'
        tb = Monadic::Utils::ModelSpec.get_thinking_budget(model)
        default_effort = (tb && tb["can_disable"]) ? "low" : "medium"
        options["reasoning_effort"] ||= default_effort
      end
    rescue StandardError
    end

    # xAI (Grok): prefer low by default (helper maps minimal->low internally)
    begin
      if provider.to_s.downcase.include?("grok") || provider.to_s.downcase.include?("xai")
        options["reasoning_effort"] ||= "low"
      end
    rescue StandardError
    end

    # Perplexity: if spec exposes reasoning_effort, use its default; else prefer 'low'
    begin
      if provider.to_s.downcase.include?("perplexity")
        eff = Monadic::Utils::ModelSpec.get_reasoning_effort_options(model)
        if eff && eff[:options].is_a?(Array) && !eff[:options].empty?
          defv = eff[:default]
          options["reasoning_effort"] ||= (eff[:options].include?(defv) ? defv : eff[:options].first)
        else
          options["reasoning_effort"] ||= "low"
        end
      end
    rescue StandardError
    end

    # Cohere: if model is a thinking/reasoning variant, enable reasoning path
    begin
      if provider.to_s.downcase.include?("cohere")
        # Prefer enabling for reasoning models; helper will map appropriately
        options["reasoning_effort"] ||= "enabled"
      end
    rescue StandardError
    end

    # DeepSeek: enable reasoning content by default for reasoner models; omit temperature later in helper
    begin
      if provider.to_s.downcase.include?("deepseek")
        options["reasoning_content"] ||= "enabled"
      end
    rescue StandardError
    end
    
    # Call the API
    begin
      # Debug logging for diagnostics
      if CONFIG && CONFIG['EXTRA_LOGGING'] == 'true'
        begin
          log_dir = File.join(Dir.home, 'monadic', 'log')
          FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
          File.open(File.join(log_dir, 'ai_user_debug.log'), 'a') do |f|
            f.puts("[#{Time.now}] provider=#{provider} model=#{model.inspect}")
          end
        rescue
          # ignore logging failures
        end
      end
      # Send query to get AI user response with explicit model parameter
      result = app_instance.send_query(options, model: model)
      
      # Check for provider-specific error patterns
      if result.is_a?(String) && (result.start_with?("ERROR:") || result.start_with?("Error:"))
        return {
          "type" => "error",
          "content" => result
        }
      end
      
      # Process result
      if result.is_a?(String) && !result.empty?
        # Success
        return {
          "type" => "ai_user",
          "content" => result.strip,
          "finished" => true
        }
      else
        # Error or empty response
        return {
          "type" => "error",
          "content" => "Failed to generate AI User response"
        }
      end
    rescue => e
      # Exception with detailed error message
      return {
        "type" => "error",
        "content" => "AI User error with provider #{provider}, model #{model}: #{e.message}"
      }
    end
  end
  
  private
  
  # Format conversation history as text
  # @param messages [Array] The messages to format
  # @param monadic [Boolean] Whether monadic mode is enabled
  # @return [String] Formatted conversation text
  def format_conversation(messages, monadic)
    text = ""
    messages.each do |m|
      role = m["role"] == "user" ? "User" : "Assistant"
      content = extract_content(m["text"], monadic)
      text = text.dup << "#{role}: #{content}\n\n"
    end
    text
  end
  
  # Extract content from message, handling monadic mode
  # @param text [String] The message text
  # @param monadic [Boolean] Whether monadic mode is enabled
  # @return [String] The extracted content
  def extract_content(text, monadic)
    return text unless monadic

    begin
      parsed = JSON.parse(text)
      parsed["message"] || parsed["response"] || text
    rescue JSON::ParserError
      text
    end
  end
  
  # Find a Chat app that matches the provider
  # @param provider [String] Provider name
  # @return [Array, nil] [key, app_instance] or nil if not found or API_KEY is missing
  def find_chat_app_for_provider(provider)
    return nil unless provider
    return nil unless defined?(APPS)
    
    # Provider name mapping
    provider_keywords = case provider.to_s.downcase
      when "openai" then ["openai"]
      when "anthropic" then ["anthropic", "claude"]
      when "cohere" then ["cohere"]
      when "gemini" then ["gemini", "google"]
      when "mistral" then ["mistral"]
      when "grok" then ["grok", "xai"]
      when "perplexity" then ["perplexity"]
      when "deepseek" then ["deepseek"]
      else [provider.to_s.downcase]
    end
    
    # Check if the required API key exists for the provider
    has_api_key = case provider.to_s.downcase
      when "openai" then !(CONFIG["OPENAI_API_KEY"]).nil? && !(CONFIG["OPENAI_API_KEY"]).empty?
      when "anthropic" then !(CONFIG["ANTHROPIC_API_KEY"]).nil? && !(CONFIG["ANTHROPIC_API_KEY"]).empty?
      when "cohere" then !(CONFIG["COHERE_API_KEY"]).nil? && !(CONFIG["COHERE_API_KEY"]).empty?
      when "gemini" then !(CONFIG["GEMINI_API_KEY"]).nil? && !(CONFIG["GEMINI_API_KEY"]).empty?
      when "mistral" then !(CONFIG["MISTRAL_API_KEY"]).nil? && !(CONFIG["MISTRAL_API_KEY"]).empty?
      when "grok" then !(CONFIG["XAI_API_KEY"]).nil? && !(CONFIG["XAI_API_KEY"]).empty?
      when "perplexity" then !(CONFIG["PERPLEXITY_API_KEY"]).nil? && !(CONFIG["PERPLEXITY_API_KEY"]).empty?
      when "deepseek" then !(CONFIG["DEEPSEEK_API_KEY"]).nil? && !(CONFIG["DEEPSEEK_API_KEY"]).empty?
      else false
    end
    
    # Return nil if API key is missing
    return nil unless has_api_key
    
    # Find matching app
    APPS.each do |key, app|
      next unless app.respond_to?(:settings) && app.settings["group"]
      
      app_group = app.settings["group"].to_s.downcase.strip
      app_name = app.settings["display_name"]
      
      # Check if any keyword is included in the app group
      if provider_keywords.any? { |keyword| app_group.to_s.include?(keyword) } && 
         app_name == "Chat"
        return [key, app]
      end
    end
    
    nil
  end
  
  # Get default model for provider
  # @param provider [String] Provider name
  # @return [String] Default model name
  def default_model_for_provider(provider)
    # Provider details are logged to dedicated log files
    provider_downcase = provider.to_s.downcase
    
    # Get model from SystemDefaults with provider mapping
    if provider_downcase.include?("anthropic") || provider_downcase.include?("claude")
      SystemDefaults.get_default_model('anthropic')
    elsif provider_downcase.include?("openai") || provider_downcase.include?("gpt")
      SystemDefaults.get_default_model('openai')
    elsif provider_downcase.include?("cohere") || provider_downcase.include?("command")
      SystemDefaults.get_default_model('cohere')
    elsif provider_downcase.include?("gemini") || provider_downcase.include?("google")
      SystemDefaults.get_default_model('gemini')
    elsif provider_downcase.include?("mistral")
      SystemDefaults.get_default_model('mistral')
    elsif provider_downcase.include?("grok") || provider_downcase.include?("xai")
      SystemDefaults.get_default_model('xai')
    elsif provider_downcase.include?("perplexity")
      SystemDefaults.get_default_model('perplexity')
    elsif provider_downcase.include?("deepseek")
      SystemDefaults.get_default_model('deepseek')
    else
      # Fallback to OpenAI default model
      SystemDefaults.get_default_model('openai')
    end
  end
end
