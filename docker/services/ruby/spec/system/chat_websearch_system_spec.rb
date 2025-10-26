# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Chat Apps Web Search Configuration", type: :system do
  let(:chat_apps) do
    ["ChatOpenAI", "ChatClaude", "ChatGemini", "ChatMistral", 
     "ChatCohere", "ChatPerplexity", "ChatGrok", "ChatDeepSeek", "ChatOllama"]
  end

  describe "Web search enablement" do
    it "verifies all Chat apps have web search feature configuration" do
      chat_apps.each do |app_name|
        provider = app_name.gsub("Chat", "").downcase
        
        # Skip if provider not configured
        next unless provider_configured?(provider)
        
        app_file = find_app_file(app_name, provider)
        expect(app_file).not_to be_nil, "#{app_name} app file not found"
        
        content = File.read(app_file)
        
        # Check for features block
        expect(content).to match(/features\s+do/), "#{app_name} missing features block"
        
        # Extract features block
        features_match = content.match(/features\s+do\s*(.*?)\s*end/m)
        expect(features_match).not_to be_nil, "#{app_name} features block not properly formed"
        
        features_content = features_match[1]
        
        # Check websearch setting based on provider capabilities
        if features_content.match(/websearch\s+(true|false)/)
          websearch_enabled = features_content.match(/websearch\s+(true|false)/)[1] == "true"

          # Native providers: openai, perplexity, grok, xai, gemini, google, claude, anthropic
          provider_normalized = provider.downcase
          has_native_support = ['openai', 'perplexity', 'grok', 'xai', 'gemini', 'google', 'claude', 'anthropic'].include?(provider_normalized)

          expected_value = has_native_support

          expect(websearch_enabled).to eq(expected_value),
            "#{app_name} should have websearch #{expected_value} (provider: #{provider}, native support: #{has_native_support})"

          # System prompt should still mention web search capability
          expect(content).to match(/web\s+search|current\s+events|recent\s+information/i),
            "#{app_name} should mention web search capability in prompt"
        else
          # If websearch is not explicitly set, it defaults to false
          puts "#{app_name}: websearch not explicitly set (defaults to false)"
        end
      end
    end
  end

  describe "System prompt appropriateness" do
    it "ensures Chat apps have balanced prompts for general chat with web search" do
      chat_apps.each do |app_name|
        provider = app_name.gsub("Chat", "").downcase
        next unless provider_configured?(provider)
        
        app_file = find_app_file(app_name, provider)
        next unless app_file
        
        content = File.read(app_file)
        
        # Extract system prompt
        prompt_match = content.match(/system_prompt\s+<<~\w+\s*(.*?)\s*^\s*\w+$/m)
        next unless prompt_match
        
        prompt = prompt_match[1]
        
        # Check for balanced approach (not too research-focused like Research Assistant)
        # Even with websearch false, prompts should mention the capability
        expect(prompt).not_to match(/professional research assistant/i),
          "#{app_name} should remain a general chat app, not a research specialist"
        
        # Should mention web search is available when needed
        expect(prompt).to match(/web\s+search|when\s+needed/i),
          "#{app_name} should mention web search is available when user enables it"
      end
    end
  end

  describe "Tools configuration" do
    it "ensures Chat apps with websearch have proper tools block" do
      chat_apps.each do |app_name|
        provider = app_name.gsub("Chat", "").downcase
        next unless provider_configured?(provider)
        
        app_file = find_app_file(app_name, provider)
        next unless app_file
        
        content = File.read(app_file)
        
        # Check for tools block existence
        expect(content).to match(/tools\s+do/), "#{app_name} missing tools block"
        
        # If websearch is enabled, tools block can be empty (native search)
        # or contain custom tools
      end
    end
  end

  private

  def provider_configured?(provider)
    key_mapping = {
      "openai" => "OPENAI_API_KEY",
      "claude" => "ANTHROPIC_API_KEY",
      "gemini" => "GEMINI_API_KEY",
      "mistral" => "MISTRAL_API_KEY",
      "cohere" => "COHERE_API_KEY",
      "perplexity" => "PERPLEXITY_API_KEY",
      "grok" => "XAI_API_KEY",
      "deepseek" => "DEEPSEEK_API_KEY",
      "ollama" => nil  # No API key needed
    }
    
    api_key = key_mapping[provider]
    return true if api_key.nil?  # Ollama doesn't need API key
    
    !ENV[api_key].nil? || !CONFIG[api_key].nil?
  end

  def find_app_file(app_name, provider)
    # Try different naming patterns
    patterns = [
      "apps/chat/chat_#{provider}.mdsl",
      "apps/chat/#{app_name.downcase}.mdsl",
      "apps/chat/chat_#{provider}.rb"
    ]
    
    patterns.each do |pattern|
      file_path = File.join(File.dirname(__FILE__), "../../", pattern)
      return file_path if File.exist?(file_path)
    end
    
    nil
  end
end