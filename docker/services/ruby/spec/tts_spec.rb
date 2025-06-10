# frozen_string_literal: true

require "dotenv/load"
require "faye/websocket"
require "json"
require "net/http"
require_relative "./spec_helper"
require_relative "../lib/monadic/adapters/text_to_speech_helper"
require_relative "../lib/monadic/utils/interaction_utils"

# Mock HTTP library to allow proper testing
module HTTP
  class Response
    attr_reader :body, :status
    
    def initialize(status:, body:)
      @status = status
      @body = body
    end
    
    def each
      yield @body
    end
  end
  
  class Status
    def initialize(success)
      @success = success
    end
    
    def success?
      @success
    end
  end
  
  class Headers
    def post(url, options = {})
      # Return a mock response by default
      HTTP::Response.new(
        status: HTTP::Status.new(true),
        body: "mock_audio_data"
      )
    end
  end
  
  def self.headers(headers)
    client = self
    client.define_singleton_method(:timeout) do |*args|
      HTTP::Headers.new
    end
    client
  end
end

RSpec.describe MonadicHelper do
  include MonadicHelper
  
  # Create a test class that includes the MonadicHelper module
  class TestTTSClass
    include MonadicHelper
    
    # Mock settings object
    def settings
      settings_obj = {
        "api_key" => "test_openai_api_key",
        "elevenlabs_api_key" => "test_elevenlabs_api_key"
      }
      
      # Add methods to mocked settings
      settings_obj.define_singleton_method(:api_key) { settings_obj["api_key"] }
      settings_obj.define_singleton_method(:elevenlabs_api_key) { settings_obj["elevenlabs_api_key"] }
      
      settings_obj
    end
    
    # Mock send_command implementation
    def send_command(command:, container: nil)
      # Return the command to allow inspection in tests
      command
    end
  end
  
  # Constants needed for the tests
  before do
    stub_const("MonadicApp::SHARED_VOL", "/shared/vol")
    stub_const("MonadicApp::LOCAL_SHARED_VOL", "/local/shared/vol")
    stub_const("IN_CONTAINER", false)
  end
  
  let(:test_instance) { TestTTSClass.new }
  
  # Mock constants and configuration
  before do
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test_openai_api_key",
      "ELEVENLABS_API_KEY" => "test_elevenlabs_api_key",
      "TTS_DICT" => { "hello" => "hola", "world" => "mundo" }
    })
    
    # Allow HTTP.headers to spy on calls
    allow(HTTP).to receive(:headers).and_call_original
  end
  
  describe "TTS dictionary functionality" do
    it "contains the expected dictionary entries" do
      # Basic test to ensure dictionary entries exist
      expect(CONFIG["TTS_DICT"]["hello"]).to eq("hola")
      expect(CONFIG["TTS_DICT"]["world"]).to eq("mundo")
    end
    
    it "applies dictionary substitutions with the new implementation" do
      # Mock a text with dictionary entries to replace
      text = "hello world, hello"
      
      # Create a file double to capture the written content
      file_double = double('file')
      expect(file_double).to receive(:write) do |content|
        # Verify the substitution was applied correctly in the content being written
        expect(content).to eq("hola mundo, hola")
      end
      
      # Stub File.open to yield our file double
      allow(File).to receive(:open).and_yield(file_double)
      allow(File).to receive(:join).and_return("/mocked/path")
      
      # Call text_to_speech with our test text
      test_instance.text_to_speech(text: text)
    end
    
    it "handles longer patterns before shorter ones" do
      # Configure a dictionary with overlapping patterns
      complex_dict = {
        "hello" => "hola",
        "world" => "mundo",
        "hello world" => "hola mundo"
      }
      
      # Update the CONFIG constant for this test
      old_dict = CONFIG["TTS_DICT"]
      CONFIG["TTS_DICT"] = complex_dict
      
      # Create a file double to capture the written content
      file_double = double('file')
      expect(file_double).to receive(:write) do |content|
        # Verify the longer pattern was replaced first
        expect(content).to eq("hola mundo hola")
      end
      
      # Stub File.open to yield our file double
      allow(File).to receive(:open).and_yield(file_double)
      allow(File).to receive(:join).and_return("/mocked/path")
      
      # Call text_to_speech with text containing overlapping patterns
      test_instance.text_to_speech(text: "hello world hello")
      
      # Restore original dictionary
      CONFIG["TTS_DICT"] = old_dict
    end
  end
  
  describe "#list_providers_and_voices" do
    it "calls the tts_query.rb script" do
      # Expect send_command to be called with the correct arguments
      expect(test_instance).to receive(:send_command).with(
        hash_including(
          command: /tts_query\.rb --list/,
          container: "ruby"
        )
      )
      
      # Call the method
      test_instance.list_providers_and_voices
    end
  end
end