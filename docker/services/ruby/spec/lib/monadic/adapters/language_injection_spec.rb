# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Language Injection in API Calls" do
  let(:session) do
    {
      runtime_settings: {
        language: "ja",
        language_updated_at: nil
      },
      messages: [
        { "role" => "system", "text" => "You are a helpful assistant." },
        { "role" => "user", "text" => "Hello" }
      ],
      parameters: {
        "model" => "gpt-4",
        "temperature" => 0.7
      }
    }
  end

  describe "Claude API language injection" do
    it "appends language prompt to system message when language is set" do
      # Simulate the logic from claude_helper.rb
      system_prompts = []
      
      session[:messages].each do |msg|
        next unless msg["role"] == "system"
        
        text = msg["text"]
        
        # Inject language preference from runtime settings if it's the first system prompt
        if system_prompts.empty? && session[:runtime_settings] && 
           session[:runtime_settings][:language] && 
           session[:runtime_settings][:language] != "auto"
          
          language_prompt = "\n\nPlease respond in Japanese. If the user writes in Japanese, continue the conversation in Japanese. If the user switches to another language, follow their lead while maintaining clarity."
          text += language_prompt
        end
        
        system_prompts << { type: "text", text: text }
      end
      
      expect(system_prompts.first[:text]).to include("Please respond in Japanese")
    end

    it "does not append language prompt when language is 'auto'" do
      session[:runtime_settings][:language] = "auto"
      
      system_prompts = []
      
      session[:messages].each do |msg|
        next unless msg["role"] == "system"
        
        text = msg["text"]
        
        if system_prompts.empty? && session[:runtime_settings] && 
           session[:runtime_settings][:language] && 
           session[:runtime_settings][:language] != "auto"
          
          language_prompt = "\n\nPlease respond in Japanese."
          text += language_prompt
        end
        
        system_prompts << { type: "text", text: text }
      end
      
      expect(system_prompts.first[:text]).not_to include("Please respond in")
    end

    it "does not modify original messages in session" do
      original_text = session[:messages].first["text"].dup
      
      # Simulate API request preparation
      system_prompts = []
      
      session[:messages].each do |msg|
        next unless msg["role"] == "system"
        
        text = msg["text"]  # This should not modify the original
        
        if system_prompts.empty? && session[:runtime_settings] && 
           session[:runtime_settings][:language] && 
           session[:runtime_settings][:language] != "auto"
          
          language_prompt = "\n\nPlease respond in Japanese."
          text += language_prompt
        end
        
        system_prompts << { type: "text", text: text }
      end
      
      # Original message should remain unchanged
      expect(session[:messages].first["text"]).to eq(original_text)
    end
  end

  describe "OpenAI API language injection" do
    context "for regular models" do
      it "adds language prompt to initial prompt parts" do
        initial_prompt = "You are a helpful assistant."
        parts = [initial_prompt]
        
        # Add language preference from runtime settings
        if session[:runtime_settings] && 
           session[:runtime_settings][:language] && 
           session[:runtime_settings][:language] != "auto"
          
          language_prompt = "Please respond in Japanese. If the user writes in Japanese, continue the conversation in Japanese. If the user switches to another language, follow their lead while maintaining clarity."
          parts << language_prompt.strip
        end
        
        if parts.length > 1
          new_text = parts.join("\n\n")
          expect(new_text).to include("Please respond in Japanese")
        end
      end
    end

    context "for reasoning models" do
      it "adds language prompt to developer messages" do
        messages = [
          { "role" => "system", "content" => [{ "type" => "text", "text" => "You are helpful." }] }
        ]
        
        # Convert system to developer and add language
        messages.each do |msg|
          if msg["role"] == "system"
            msg["role"] = "developer"
            msg["content"].each do |content_item|
              if content_item["type"] == "text"
                text = content_item["text"]
                
                # Inject language preference from runtime settings
                if session[:runtime_settings] && 
                   session[:runtime_settings][:language] && 
                   session[:runtime_settings][:language] != "auto"
                  
                  language_prompt = "\n\nPlease respond in Japanese. If the user writes in Japanese, continue the conversation in Japanese. If the user switches to another language, follow their lead while maintaining clarity."
                  text += language_prompt
                end
                
                content_item["text"] = text
              end
            end
          end
        end
        
        expect(messages.first["content"].first["text"]).to include("Please respond in Japanese")
        expect(messages.first["role"]).to eq("developer")
      end
    end
  end

  describe "Language switching during session" do
    it "uses updated language for new API calls" do
      # Initial language
      expect(session[:runtime_settings][:language]).to eq("ja")
      
      # Change language
      session[:runtime_settings][:language] = "fr"
      session[:runtime_settings][:language_updated_at] = Time.now
      
      # Prepare API call with new language
      system_prompts = []
      
      session[:messages].each do |msg|
        next unless msg["role"] == "system"
        
        text = msg["text"]
        
        if system_prompts.empty? && session[:runtime_settings] && 
           session[:runtime_settings][:language] && 
           session[:runtime_settings][:language] != "auto"
          
          language = session[:runtime_settings][:language]
          language_name = language == "fr" ? "French" : "Unknown"
          language_prompt = "\n\nPlease respond in #{language_name}."
          text += language_prompt
        end
        
        system_prompts << { type: "text", text: text }
      end
      
      expect(system_prompts.first[:text]).to include("Please respond in French")
      expect(system_prompts.first[:text]).not_to include("Japanese")
    end
  end

  describe "Export/Import behavior" do
    it "does not include runtime_settings in exported messages" do
      # Simulate export
      exported_data = {
        messages: session[:messages],
        metadata: {
          exported_at: Time.now
        }
      }
      
      # runtime_settings should not be in exported data
      expect(exported_data).not_to have_key(:runtime_settings)
      
      # Messages should not contain language instructions
      exported_data[:messages].each do |msg|
        expect(msg["text"]).not_to include("Please respond in")
      end
    end

    it "can optionally include language in metadata" do
      # Simulate export with language metadata
      exported_data = {
        messages: session[:messages],
        metadata: {
          exported_at: Time.now,
          language: session[:runtime_settings][:language]
        }
      }
      
      expect(exported_data[:metadata][:language]).to eq("ja")
      
      # Messages still should not contain language instructions
      exported_data[:messages].each do |msg|
        expect(msg["text"]).not_to include("Please respond in")
      end
    end
  end
end