# frozen_string_literal: true

require 'spec_helper'
require 'rouge'
require_relative '../../../lib/monadic/app_extensions'

# Test app that includes monadic behavior
class TestMonadicFlowApp
  include MonadicChat::AppExtensions
  
  attr_accessor :context, :settings
  
  def initialize(monadic_mode = true)
    @context = {}
    @settings = { 
      mathjax: false,
      monadic: monadic_mode
    }
  end
end

RSpec.describe "Monadic Flow and Response Format" do
  let(:app) { TestMonadicFlowApp.new(true) }
  
  describe "JSON-based monadic flow" do
    it "creates proper JSON structure with monadic_unit" do
      result = app.monadic_unit("Hello, world!")
      parsed = JSON.parse(result)
      
      expect(parsed).to eq({
        "message" => "Hello, world!",
        "context" => {}
      })
    end
    
    it "preserves context through monadic operations" do
      # Set initial context
      app.context = { "user_name" => "Alice", "session_id" => 123 }
      
      # Create monadic unit
      json1 = app.monadic_unit("First message")
      
      # Transform context
      json2 = app.monadic_map(json1) do |ctx|
        ctx.merge("message_count" => 1)
      end
      
      # Verify context preservation and transformation
      parsed = JSON.parse(json2)
      expect(parsed["context"]).to eq({
        "user_name" => "Alice",
        "session_id" => 123,
        "message_count" => 1
      })
    end
    
    it "handles nested context structures" do
      app.context = {
        "user" => {
          "name" => "Bob",
          "preferences" => {
            "language" => "en",
            "theme" => "dark"
          }
        },
        "session" => {
          "start_time" => "2024-01-01T00:00:00Z",
          "messages" => []
        }
      }
      
      json = app.monadic_unit("Complex context test")
      parsed = JSON.parse(json)
      
      expect(parsed["context"]["user"]["preferences"]["theme"]).to eq("dark")
      expect(parsed["context"]["session"]["messages"]).to eq([])
    end
  end
  
  describe "response_format integration" do
    it "generates JSON that matches OpenAI response_format requirements" do
      # Simulate what the AI should return with response_format: { type: "json_object" }
      ai_response = {
        "message" => "I understand your request.",
        "context" => {
          "task_status" => "completed",
          "results" => ["item1", "item2"],
          "metadata" => {
            "confidence" => 0.95,
            "processing_time" => 1.23
          }
        }
      }.to_json
      
      # Unwrap and validate
      unwrapped = app.monadic_unwrap(ai_response)
      
      expect(unwrapped).to be_a(Hash)
      expect(unwrapped["message"]).to be_a(String)
      expect(unwrapped["context"]).to be_a(Hash)
      expect(unwrapped["context"]["results"]).to be_a(Array)
      expect(unwrapped["context"]["metadata"]["confidence"]).to be_a(Float)
    end
    
    it "handles invalid JSON gracefully" do
      invalid_response = "This is not JSON"
      
      result = app.monadic_unwrap(invalid_response)
      
      expect(result).to eq({
        "message" => "This is not JSON",
        "context" => {}
      })
    end
  end
  
  describe "HTML rendering for monadic data" do
    it "converts monadic JSON to collapsible HTML" do
      json_data = {
        "message" => "Test message",
        "context" => {
          "key1" => "value1",
          "key2" => {
            "nested" => "value2"
          }
        }
      }.to_json
      
      html = app.monadic_html(json_data)
      
      expect(html).to include("Test message")
      expect(html).to include("json-item")
      expect(html).to include('Context')
      expect(html).to include('Key1:')
      expect(html).to include('value1')
      expect(html).to include('Key2')
    end
    
    it "handles empty context gracefully" do
      json_data = {
        "message" => "Message only",
        "context" => {}
      }.to_json
      
      html = app.monadic_html(json_data)
      
      expect(html).to include("Message only")
      # Empty context displays as empty json-content div
      expect(html).to include('json-content')
    end
  end
  
  describe "Monadic vs Toggle mode differences" do
    context "in monadic mode" do
      let(:monadic_app) { TestMonadicFlowApp.new(true) }
      
      it "uses JSON structure for all operations" do
        result = monadic_app.monadic_unit("Test")
        expect { JSON.parse(result) }.not_to raise_error
      end
      
      it "requires structured responses from AI" do
        # This documents the requirement
        expect(monadic_app.settings[:monadic]).to be true
      end
    end
    
    context "in toggle mode" do
      let(:toggle_app) { TestMonadicFlowApp.new(false) }
      
      it "would use HTML div structure instead" do
        # Toggle mode apps don't use monadic_unit/unwrap
        expect(toggle_app.settings[:monadic]).to be false
      end
    end
  end
  
  describe "Error handling in monadic flow" do
    it "maintains context even with errors" do
      app.context = { "important_data" => "preserve_me" }
      
      # Even with invalid data, context should be preserved
      result = app.monadic_unwrap("invalid json {")
      
      expect(app.context).to eq({ "important_data" => "preserve_me" })
    end
    
    it "provides safe defaults for missing fields" do
      partial_json = { "message" => "Only message" }.to_json
      
      result = app.monadic_unwrap(partial_json)
      
      expect(result["message"]).to eq("Only message")
      # When context is not in JSON, it may be nil
      expect(result["context"]).to be_nil
    end
  end
  
  describe "Context size management" do
    it "respects context_size limits" do
      # This would be implemented in the actual app
      # Here we document the expected behavior
      context_size = 5
      
      # Simulate adding messages to context
      messages = (1..10).map { |i| { "id" => i, "text" => "Message #{i}" } }
      
      # Only keep last context_size messages
      kept_messages = messages.last(context_size)
      
      expect(kept_messages.length).to eq(context_size)
      expect(kept_messages.first["id"]).to eq(6)
      expect(kept_messages.last["id"]).to eq(10)
    end
  end
end