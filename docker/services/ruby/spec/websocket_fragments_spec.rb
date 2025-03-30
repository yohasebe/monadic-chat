# frozen_string_literal: true

require "dotenv/load"
require "faye/websocket"
require "eventmachine"
require "json"
require "timeout"
require_relative "./spec_helper"
require_relative "../lib/monadic/utils/websocket"
require_relative "../lib/monadic/utils/interaction_utils"

# Load PragmaticSegmenter if it's not already defined
begin
  require "pragmatic_segmenter"
rescue LoadError
  # Create a stub if the actual gem isn't available
  module PragmaticSegmenter
    class Segmenter
      def initialize(text:)
        @text = text
      end
      
      def segment
        @text.to_s.split(". ").map { |s| s + "." }
      end
    end
  end
end

# Only define TokenizerMock if it doesn't exist yet
unless defined?(MonadicApp::TOKENIZER)
  module MonadicApp
    class TokenizerMock
      def count_tokens(text, encoding_name = nil)
        # Return token count proportional to text length for testing
        text.to_s.length
      end
      
      def get_encoding_name(model_name)
        "o200k_base"
      end
    end
    
    # Make these constants conditional
    unless defined?(TOKENIZER)
      TOKENIZER = TokenizerMock.new
    end
    
    unless defined?(AI_USER_INITIAL_PROMPT)
      AI_USER_INITIAL_PROMPT = "Default AI user prompt for testing"
    end
  end
end

RSpec.describe "WebSocket Fragment Processing" do
  include WebSocketHelper
  include InteractionUtils
  
  # Create a test class that includes the WebSocketHelper module
  class TestWebSocketClass
    include WebSocketHelper
    include InteractionUtils
    
    attr_accessor :session, :channel
    
    def initialize(channel = nil)
      @session = { 
        messages: [],
        parameters: {
          "model" => "gpt-4o",
          "max_input_tokens" => 4000,
          "context_size" => 10,
          "app_name" => "Chat",
          "tts_provider" => "openai-tts",
          "tts_voice" => "alloy"
        }
      }
      @channel = channel
    end
    
    # Helper methods needed for testing
    def markdown_to_html(text)
      "<p>#{text}</p>"
    end
    
    def detect_language(text)
      "en"
    end
    
    # Mock settings object
    def settings
      # Create a dynamic object that responds to api_key
      settings_obj = {
        "api_key" => "test_api_key",
        "elevenlabs_api_key" => "test_elevenlabs_api_key"
      }
      
      # Add methods dynamically
      settings_obj.define_singleton_method(:api_key) { settings_obj["api_key"] }
      settings_obj.define_singleton_method(:elevenlabs_api_key) { settings_obj["elevenlabs_api_key"] }
      
      settings_obj
    end
  end
  
  # Create a mock app for testing
  class MockApp
    attr_accessor :settings
    
    def initialize
      @settings = {
        "model" => "gpt-4o",
        "models" => ["gpt-4o", "gpt-3.5-turbo"],
        "display_name" => "Test App",
        "monadic" => false,
        "toggles" => false
      }
    end
    
    def api_request(role, session, &block)
      # Simulate streaming responses
      block.call({"type" => "fragment", "content" => "This is "})
      block.call({"type" => "fragment", "content" => "a test "})
      block.call({"type" => "fragment", "content" => "response."})
      
      # Return completed response
      [{
        "choices" => [{
          "message" => {
            "content" => "This is a test response.",
            "role" => "assistant"
          }
        }]
      }]
    end
    
    def monadic_html(text)
      "<div class='monadic-format'>#{text}</div>"
    end
  end
  
  # Setup mocks
  let(:mock_channel) do
    channel = double('EventMachine::Channel')
    allow(channel).to receive(:push)
    allow(channel).to receive(:subscribe).and_return(1)
    allow(channel).to receive(:unsubscribe)
    channel
  end
  
  let(:mock_ws) do
    ws = double('WebSocket')
    allow(ws).to receive(:send)
    allow(ws).to receive(:on)
    allow(ws).to receive(:rack_response).and_return([200, {}, ['OK']])
    ws
  end
  
  let(:test_instance) { TestWebSocketClass.new(mock_channel) }
  
  # Setup test environment
  before do
    # Set up APPS constant with our mock app
    stub_const("APPS", {"Chat" => MockApp.new})
    
    # Set up CONFIG constant
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test_api_key",
      "ELEVENLABS_API_KEY" => "test_elevenlabs_api_key",
      "STT_MODEL" => "gpt-4o-transcribe"
    })
    
    # Mock EventMachine
    allow(EventMachine).to receive(:run).and_yield
    
    # Mock WebSocket
    allow(Faye::WebSocket).to receive(:new).and_return(mock_ws)
    
    # Mock WebSocket event handlers
    allow(mock_ws).to receive(:on) do |event_type, &block|
      if event_type == :message
        @message_handler = block
      elsif event_type == :open
        @open_handler = block
      elsif event_type == :close
        @close_handler = block
      end
    end
    
    # Mock SecureRandom
    allow(SecureRandom).to receive(:hex).and_return("abcd1234")
  end
  
  describe "#handle_audio_message" do
    let(:audio_obj) {{
      "content" => Base64.encode64("fake audio data"),
      "format" => "webm",
      "lang_code" => "en"
    }}
    
    before do
      # Mock stt_api_request
      allow(test_instance).to receive(:stt_api_request).and_return({
        "text" => "Transcribed text",
        "logprobs" => [{"logprob" => -0.5}]
      })
      
      # Mock get_stt_model
      allow(test_instance).to receive(:get_stt_model).and_return("gpt-4o-transcribe")
    end
    
    it "processes audio content and returns transcription" do
      # Check that process_transcription is called with correct parameters
      expect(test_instance).to receive(:process_transcription).with(
        mock_ws, 
        an_instance_of(String), 
        "webm", 
        "en", 
        "gpt-4o-transcribe"
      )
      
      test_instance.handle_audio_message(mock_ws, audio_obj)
    end
    
    it "sends error message when content is nil" do
      # Test with empty content
      empty_obj = {"content" => nil}
      expect(test_instance.channel).to receive(:push).with(/"type":"error"/)
      
      test_instance.handle_audio_message(mock_ws, empty_obj)
    end
  end
  
  describe "token counting basic functionality" do
    it "sets thread type for token counting" do
      text = "This is a test for token counting"
      thread = test_instance.initialize_token_counting(text)
      
      # Verify thread was created with correct type
      expect(thread).to be_a(Thread)
      thread.join # Wait for thread to complete
    end
    
    it "correctly handles nil or empty text in token counting" do
      expect(test_instance.initialize_token_counting(nil)).to be_nil
      expect(test_instance.initialize_token_counting("")).to be_nil
    end
    
    it "uses token count result in check_past_messages" do
      # Set up test data
      Thread.current[:token_count_result] = 42
      
      # Add a message to session
      test_instance.session[:messages] = [
        {"role" => "user", "text" => "Test message", "active" => true}
      ]
      
      # Run check_past_messages
      result = test_instance.check_past_messages({"max_input_tokens" => 1000, "context_size" => 10})
      
      # Clean up
      Thread.current[:token_count_result] = nil
      
      # Expect count_total_input_tokens to exist in result
      expect(result).to have_key(:count_total_input_tokens)
    end
  end
  
  describe "handling elevenlabs provider" do
    let(:elevenlabs_message) {{
      "message" => "TTS",
      "provider" => "elevenlabs",
      "elevenlabs_voice" => "test_voice_id",
      "text" => "This is a test for ElevenLabs TTS",
      "speed" => "1.0",
      "response_format" => "mp3"
    }}
    
    before do
      # Make sure we test both paths - elevenlabs and standard
      allow(test_instance).to receive(:tts_api_request).and_return({
        "type" => "audio", 
        "content" => "base64_audio_data"
      })
    end
    
    it "correctly identifies elevenlabs provider and sets voice parameter" do
      # Expect tts_api_request to be called with elevenlabs provider and correct voice
      expect(test_instance).to receive(:tts_api_request).with(
        "This is a test for ElevenLabs TTS",
        hash_including(
          provider: "elevenlabs",
          voice: "test_voice_id"
        )
      )
      
      # Call the handler
      test_instance.send(:websocket_handler, {})
      @message_handler.call(double('event', data: elevenlabs_message.to_json))
    end
  end
  
  # This class has basic tests only 
  # More comprehensive tests are in tts_spec.rb
  
end