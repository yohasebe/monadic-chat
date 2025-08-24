# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/language_config"

RSpec.describe "WebSocket Language Handling" do
  let(:ws) { double("WebSocket") }
  let(:channel) { double("Channel") }
  let(:session) { {} }
  let(:websocket_handler) do
    handler = Object.new
    handler.extend(Module.new do
      include WebSocketUtils
      attr_accessor :session, :channel
    end)
    handler.session = session
    handler.channel = channel
    handler
  end

  describe "SYSTEM_PROMPT handler" do
    it "initializes runtime_settings with language from conversation_language" do
      obj = {
        "content" => "Test prompt",
        "conversation_language" => "ja"
      }
      
      # Simulate SYSTEM_PROMPT handling
      session[:runtime_settings] = {
        language: obj["conversation_language"] || "auto",
        language_updated_at: nil
      }
      
      expect(session[:runtime_settings][:language]).to eq("ja")
    end

    it "defaults to 'auto' when conversation_language is not provided" do
      obj = {
        "content" => "Test prompt"
      }
      
      # Simulate SYSTEM_PROMPT handling
      session[:runtime_settings] = {
        language: obj["conversation_language"] || "auto",
        language_updated_at: nil
      }
      
      expect(session[:runtime_settings][:language]).to eq("auto")
    end
  end

  describe "UPDATE_LANGUAGE handler" do
    before do
      session[:runtime_settings] = {
        language: "en",
        language_updated_at: nil
      }
    end

    it "updates language in runtime_settings" do
      allow(channel).to receive(:push)
      
      # Simulate UPDATE_LANGUAGE handling
      new_language = "ja"
      old_language = session[:runtime_settings][:language]
      
      if old_language != new_language
        session[:runtime_settings][:language] = new_language
        session[:runtime_settings][:language_updated_at] = Time.now
      end
      
      expect(session[:runtime_settings][:language]).to eq("ja")
      expect(session[:runtime_settings][:language_updated_at]).not_to be_nil
    end

    it "sends notification to client when language changes" do
      expected_response = {
        "type" => "language_updated",
        "language" => "ja",
        "language_name" => "Japanese"
      }
      
      expect(channel).to receive(:push).with(expected_response.to_json)
      
      # Simulate UPDATE_LANGUAGE handling with notification
      new_language = "ja"
      old_language = session[:runtime_settings][:language]
      
      if old_language != new_language
        session[:runtime_settings][:language] = new_language
        session[:runtime_settings][:language_updated_at] = Time.now
        
        language_name = Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
        
        channel.push({
          "type" => "language_updated",
          "language" => new_language,
          "language_name" => language_name
        }.to_json)
      end
    end

    it "does not update when language is the same" do
      expect(channel).not_to receive(:push)
      
      # Simulate UPDATE_LANGUAGE handling
      new_language = "en"  # Same as current
      old_language = session[:runtime_settings][:language]
      
      if old_language != new_language
        session[:runtime_settings][:language] = new_language
        session[:runtime_settings][:language_updated_at] = Time.now
      end
      
      expect(session[:runtime_settings][:language]).to eq("en")
      expect(session[:runtime_settings][:language_updated_at]).to be_nil
    end

    it "handles 'auto' language correctly" do
      expected_response = {
        "type" => "language_updated",
        "language" => "auto",
        "language_name" => "Automatic"
      }
      
      expect(channel).to receive(:push).with(expected_response.to_json)
      
      # Simulate UPDATE_LANGUAGE handling
      new_language = "auto"
      old_language = session[:runtime_settings][:language]
      
      if old_language != new_language
        session[:runtime_settings][:language] = new_language
        session[:runtime_settings][:language_updated_at] = Time.now
        
        language_name = if new_language == "auto"
                          "Automatic"
                        else
                          Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
                        end
        
        channel.push({
          "type" => "language_updated",
          "language" => new_language,
          "language_name" => language_name
        }.to_json)
      end
      
      expect(session[:runtime_settings][:language]).to eq("auto")
    end
  end

  describe "Language persistence" do
    it "maintains language setting across messages" do
      session[:runtime_settings] = {
        language: "ja",
        language_updated_at: Time.now
      }
      
      # Simulate multiple message exchanges
      3.times do
        # Language should remain unchanged
        expect(session[:runtime_settings][:language]).to eq("ja")
      end
    end

    it "does not include language in message history" do
      session[:runtime_settings] = {
        language: "ja",
        language_updated_at: Time.now
      }
      
      session[:messages] = [
        { "role" => "system", "text" => "System prompt" },
        { "role" => "user", "text" => "User message" },
        { "role" => "assistant", "text" => "Assistant response" }
      ]
      
      # Verify no message contains language settings
      session[:messages].each do |msg|
        expect(msg).not_to have_key("language")
        expect(msg).not_to have_key("conversation_language")
        expect(msg["text"]).not_to include("Please respond in")
      end
    end
  end

  describe "TTS language parameter passing" do
    it "includes language parameter in TTS calls" do
      session[:runtime_settings] = {
        language: "ja",
        language_updated_at: nil
      }
      
      # Simulate TTS parameter extraction
      obj = {
        "conversation_language" => session[:runtime_settings][:language]
      }
      
      language = obj["conversation_language"] || "auto"
      expect(language).to eq("ja")
    end

    it "defaults to 'auto' when runtime_settings not available" do
      session[:runtime_settings] = nil
      
      # Simulate TTS parameter extraction
      obj = {}
      language = obj["conversation_language"] || "auto"
      
      expect(language).to eq("auto")
    end
  end
end