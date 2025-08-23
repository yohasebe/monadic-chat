# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/language_config"

RSpec.describe "WebSocket RTL Language Support" do
  include WebSocketHelper
  
  let(:mock_channel) { double("channel") }
  let(:session) { {} }
  
  before do
    @channel = mock_channel
    allow(File).to receive(:open).and_return(double(puts: nil, close: nil))
    stub_const("MonadicApp::EXTRA_LOG_FILE", "/tmp/test.log")
    stub_const("CONFIG", { "EXTRA_LOGGING" => false })
  end
  
  describe "UPDATE_LANGUAGE message with RTL languages" do
    let(:update_message) do
      {
        "message" => "UPDATE_LANGUAGE",
        "new_language" => language_code
      }
    end
    
    context "when changing to Arabic (RTL)" do
      let(:language_code) { "ar" }
      
      it "sends language_updated message with rtl text direction" do
        session[:runtime_settings] = { language: "en" }
        
        expected_response = {
          "type" => "language_updated",
          "language" => "ar",
          "language_name" => "Arabic",
          "text_direction" => "rtl"
        }
        
        expect(@channel).to receive(:push).with(expected_response.to_json)
        
        # Simulate the UPDATE_LANGUAGE handler logic
        old_language = session[:runtime_settings][:language]
        new_language = update_message["new_language"]
        
        if old_language != new_language
          session[:runtime_settings][:language] = new_language
          session[:runtime_settings][:language_updated_at] = Time.now
          
          language_name = Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
          
          @channel.push({
            "type" => "language_updated",
            "language" => new_language,
            "language_name" => language_name,
            "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
          }.to_json)
        end
      end
    end
    
    context "when changing to Hebrew (RTL)" do
      let(:language_code) { "he" }
      
      it "sends language_updated message with rtl text direction" do
        session[:runtime_settings] = { language: "en" }
        
        expected_response = {
          "type" => "language_updated",
          "language" => "he",
          "language_name" => "Hebrew",
          "text_direction" => "rtl"
        }
        
        expect(@channel).to receive(:push).with(expected_response.to_json)
        
        new_language = update_message["new_language"]
        session[:runtime_settings][:language] = new_language
        
        language_name = Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
        
        @channel.push({
          "type" => "language_updated",
          "language" => new_language,
          "language_name" => language_name,
          "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
        }.to_json)
      end
    end
    
    context "when changing from RTL to LTR language" do
      let(:language_code) { "ja" }
      
      it "sends language_updated message with ltr text direction" do
        session[:runtime_settings] = { language: "ar" }
        
        expected_response = {
          "type" => "language_updated",
          "language" => "ja",
          "language_name" => "Japanese",
          "text_direction" => "ltr"
        }
        
        expect(@channel).to receive(:push).with(expected_response.to_json)
        
        new_language = update_message["new_language"]
        session[:runtime_settings][:language] = new_language
        
        language_name = Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
        
        @channel.push({
          "type" => "language_updated",
          "language" => new_language,
          "language_name" => language_name,
          "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
        }.to_json)
      end
    end
    
    context "when changing to auto" do
      let(:language_code) { "auto" }
      
      it "sends language_updated message with ltr text direction" do
        session[:runtime_settings] = { language: "ar" }
        
        expected_response = {
          "type" => "language_updated",
          "language" => "auto",
          "language_name" => "Automatic",
          "text_direction" => "ltr"
        }
        
        expect(@channel).to receive(:push).with(expected_response.to_json)
        
        new_language = update_message["new_language"]
        session[:runtime_settings][:language] = new_language
        
        language_name = if new_language == "auto"
                          "Automatic"
                        else
                          Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
                        end
        
        @channel.push({
          "type" => "language_updated",
          "language" => new_language,
          "language_name" => language_name,
          "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
        }.to_json)
      end
    end
  end
  
  describe "SYSTEM_PROMPT with RTL language" do
    it "sets RTL language in runtime_settings" do
      system_prompt_message = {
        "message" => "SYSTEM_PROMPT",
        "content" => "Test prompt",
        "interface_language" => "ar"
      }
      
      # Initialize runtime settings
      session[:runtime_settings] = {
        language: "auto",
        language_updated_at: nil
      }
      
      # Process language from SYSTEM_PROMPT
      interface_language = system_prompt_message["interface_language"]
      session[:runtime_settings][:language] = interface_language || "auto"
      
      expect(session[:runtime_settings][:language]).to eq("ar")
      expect(Monadic::Utils::LanguageConfig.text_direction(session[:runtime_settings][:language])).to eq("rtl")
    end
  end
end