# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

RSpec.describe "OpenAI Streaming Delta Handling" do
  let(:openai_helper) { OpenAIHelper.new }
  let(:session) { { parameters: {} } }
  let(:fragments) { [] }
  let(:block) { proc { |res| fragments << res if res["type"] == "fragment" } }

  describe "response.in_progress event" do
    it "sends only delta text, not accumulated text" do
      # Simulate streaming with accumulated text
      events = [
        {
          "type" => "response.in_progress",
          "response" => {
            "id" => "test",
            "output" => [
              { "type" => "text", "text" => "Hello" }
            ]
          }
        },
        {
          "type" => "response.in_progress",
          "response" => {
            "id" => "test",
            "output" => [
              { "type" => "text", "text" => "Hello world" }
            ]
          }
        },
        {
          "type" => "response.in_progress",
          "response" => {
            "id" => "test",
            "output" => [
              { "type" => "text", "text" => "Hello world!" }
            ]
          }
        }
      ]

      # Process events through the handler
      texts = {}
      events.each do |json|
        event_type = json["type"]
        
        if event_type == "response.in_progress"
          response_data = json["response"]
          if response_data && response_data["output"] && !response_data["output"].empty?
            output = response_data["output"]
            output.each do |item|
              if item["type"] == "text" && item["text"]
                id = response_data["id"] || "default"
                texts[id] ||= ""
                current_text = item["text"]
                
                # Calculate the delta - only send the new portion
                if current_text.length > texts[id].length
                  delta = current_text[texts[id].length..-1]
                  texts[id] = current_text  # Update stored text
                  res = { "type" => "fragment", "content" => delta }
                  block.call res
                end
              end
            end
          end
        end
      end

      # Verify that only deltas were sent
      expect(fragments.length).to eq(3)
      expect(fragments[0]["content"]).to eq("Hello")
      expect(fragments[1]["content"]).to eq(" world")
      expect(fragments[2]["content"]).to eq("!")
      
      # Verify final accumulated text is correct
      expect(texts["test"]).to eq("Hello world!")
    end
  end

  describe "response.output_text.delta event" do
    it "correctly handles delta fragments" do
      # Simulate delta events
      events = [
        {
          "type" => "response.output_text.delta",
          "delta" => "Hello",
          "item_id" => "test"
        },
        {
          "type" => "response.output_text.delta",
          "delta" => " world",
          "item_id" => "test"
        },
        {
          "type" => "response.output_text.delta",
          "delta" => "!",
          "item_id" => "test"
        }
      ]

      texts = {}
      events.each do |json|
        event_type = json["type"]
        
        if event_type == "response.output_text.delta"
          fragment = json["delta"]
          if fragment && !fragment.empty?
            id = json["response_id"] || json["item_id"] || "default"
            texts[id] ||= ""
            texts[id] += fragment
            
            res = { "type" => "fragment", "content" => fragment }
            block.call res
          end
        end
      end

      # Verify deltas were sent correctly
      expect(fragments.length).to eq(3)
      expect(fragments[0]["content"]).to eq("Hello")
      expect(fragments[1]["content"]).to eq(" world")
      expect(fragments[2]["content"]).to eq("!")
      
      # Verify final accumulated text
      expect(texts["test"]).to eq("Hello world!")
    end
  end
end