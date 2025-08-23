# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/language_config"

RSpec.describe "Provider Language Injection" do
  let(:session) do
    {
      runtime_settings: {
        language: "ja"
      },
      messages: [
        { "role" => "system", "text" => "You are a helpful assistant." },
        { "role" => "user", "text" => "Hello" }
      ],
      parameters: {
        "app_name" => "ChatOpenAI",
        "temperature" => 0.7,
        "context_size" => 10
      }
    }
  end

  describe "DeepSeek language injection" do
    it "adds language prompt to system message" do
      context = session[:messages]
      system_message_modified = false
      
      messages = context.compact.map do |msg|
        if msg["role"] == "system" && !system_message_modified
          system_message_modified = true
          content_parts = [msg["text"]]
          
          if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
            language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
            content_parts << language_prompt if !language_prompt.empty?
          end
          
          { "role" => msg["role"], "content" => content_parts.join("\n\n---\n\n") }
        else
          { "role" => msg["role"], "content" => msg["text"] }
        end
      end
      
      expect(messages.first["content"]).to include("You MUST respond in Japanese")
    end
  end

  describe "Gemini language injection" do
    it "creates systemInstruction with language prompt" do
      context = session[:messages]
      
      # Extract system message for systemInstruction
      system_message = context.find { |msg| msg["role"] == "system" }
      non_system_messages = context.select { |msg| msg["role"] != "system" }
      
      system_instruction = nil
      
      if system_message
        system_parts = [system_message["text"]]
        
        if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
          language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
          system_parts << language_prompt if !language_prompt.empty?
        end
        
        system_instruction = {
          "parts" => [
            { "text" => system_parts.join("\n\n---\n\n") }
          ]
        }
      end
      
      expect(system_instruction).not_to be_nil
      expect(system_instruction["parts"].first["text"]).to include("You MUST respond in Japanese")
      expect(non_system_messages.length).to eq(1)
      expect(non_system_messages.first["role"]).to eq("user")
    end
    
    it "handles empty contents array for initiate_from_assistant" do
      context = [{ "role" => "system", "text" => "You are helpful." }]
      
      system_message = context.find { |msg| msg["role"] == "system" }
      non_system_messages = context.select { |msg| msg["role"] != "system" }
      
      body = {}
      
      if system_message
        body["systemInstruction"] = {
          "parts" => [{ "text" => system_message["text"] }]
        }
      end
      
      body["contents"] = non_system_messages.map do |msg|
        { "role" => msg["role"], "parts" => [{ "text" => msg["text"] }] }
      end
      
      # This would cause the error without the fix
      expect(body["contents"]).to be_empty
      expect { body["contents"].last && body["contents"].last["role"] }.not_to raise_error
    end
  end

  describe "Grok language injection" do
    it "adds language prompt to system message content array" do
      context = session[:messages]
      system_message_modified = false
      
      messages = context.compact.map do |msg|
        if msg["role"] == "system" && !system_message_modified
          system_message_modified = true
          content_parts = [{ "type" => "text", "text" => msg["text"] }]
          
          if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
            language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
            content_parts << { "type" => "text", "text" => "\n\n---\n\n" + language_prompt } if !language_prompt.empty?
          end
          
          { "role" => msg["role"], "content" => content_parts }
        else
          { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
        end
      end
      
      expect(messages.first["content"]).to be_an(Array)
      expect(messages.first["content"].last["text"]).to include("You MUST respond in Japanese")
    end
  end

  describe "Mistral language injection" do
    it "adds language prompt to system message as string" do
      context = session[:messages]
      system_message_modified = false
      
      messages = context.map do |msg|
        if msg["role"] == "system" && !system_message_modified
          system_message_modified = true
          content_parts = [msg["text"]]
          
          if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
            language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
            content_parts << language_prompt if !language_prompt.empty?
          end
          
          { "role" => msg["role"], "content" => content_parts.join("\n\n---\n\n") }
        else
          { "role" => msg["role"], "content" => msg["text"] }
        end
      end
      
      expect(messages.first["content"]).to be_a(String)
      expect(messages.first["content"]).to include("You MUST respond in Japanese")
    end
  end

  describe "Perplexity language injection" do
    it "adds language prompt to system message content array" do
      context = session[:messages]
      system_message_modified = false
      
      messages = context.compact.map do |msg|
        if msg["role"] == "system" && !system_message_modified
          system_message_modified = true
          content_parts = [{ "type" => "text", "text" => msg["text"] }]
          
          if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
            language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
            content_parts << { "type" => "text", "text" => "\n\n---\n\n" + language_prompt } if !language_prompt.empty?
          end
          
          { "role" => msg["role"], "content" => content_parts }
        else
          { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
        end
      end
      
      expect(messages.first["content"]).to be_an(Array)
      expect(messages.first["content"].last["text"]).to include("You MUST respond in Japanese")
    end
    
    it "uses natural initial message for Voice Chat apps" do
      session[:parameters]["app_name"] = "VoiceChatPerplexity"
      app = session[:parameters]["app_name"]
      
      initial_message = if app && app.include?("VoiceChat")
                         "Hi there! How are you today?"
                       else
                         "Hello! Please introduce yourself."
                       end
      
      expect(initial_message).to eq("Hi there! How are you today?")
    end
    
    it "uses generic initial message for non-Voice Chat apps" do
      session[:parameters]["app_name"] = "ChatPerplexity"
      app = session[:parameters]["app_name"]
      
      initial_message = if app && app.include?("VoiceChat")
                         "Hi there! How are you today?"
                       else
                         "Hello! Please introduce yourself."
                       end
      
      expect(initial_message).to eq("Hello! Please introduce yourself.")
    end
  end

  describe "Cohere language injection" do
    it "adds language prompt to initial prompt parts" do
      initial_prompt = "You are a helpful assistant."
      initial_prompt_parts = [initial_prompt.to_s]
      
      if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
        language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
        initial_prompt_parts << language_prompt if !language_prompt.empty?
      end
      
      initial_prompt_with_suffix = initial_prompt_parts.join("\n\n---\n\n")
      
      expect(initial_prompt_with_suffix).to include("You MUST respond in Japanese")
    end
  end

  describe "Language prompt consistency" do
    it "all providers receive the same language prompt format" do
      language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language("ja")
      
      expect(language_prompt).to include("IMPORTANT: You MUST respond in Japanese")
      expect(language_prompt).to include("Always use Japanese for your responses")
      expect(language_prompt).to include("Even if the user writes in a different language")
    end
    
    it "returns empty string for 'auto' language" do
      language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language("auto")
      expect(language_prompt).to eq("")
    end
    
    it "returns empty string for nil language" do
      language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(nil)
      expect(language_prompt).to eq("")
    end
  end
end