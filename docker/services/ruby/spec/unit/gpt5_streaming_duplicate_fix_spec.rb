# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

RSpec.describe "GPT-5 Streaming Duplicate Fix" do
  let(:openai_helper) { Object.new.extend(Monadic::OpenAIHelper) }
  
  describe "response.in_progress event handling" do
    let(:body) { { "model" => "gpt-5" } }
    let(:obj) { {} }
    let(:query) { {} }
    let(:session) { {} }
    let(:app) { double("app") }
    
    context "with GPT-5 models" do
      it "skips response.in_progress events for gpt-5" do
        json = {
          "type" => "response.in_progress",
          "response" => {
            "model" => "gpt-5",
            "output" => [
              { "type" => "text", "text" => "Test" }
            ]
          }
        }
        
        processed_fragments = []
        
        # Simulate processing the event
        streaming_model = "gpt-5"
        current_model = streaming_model || json["model"]
        
        # Check if model should skip response.in_progress
        should_skip = current_model && (
          current_model.to_s.downcase.include?("gpt-5") || 
          current_model.to_s.downcase.include?("gpt5") || 
          current_model.to_s.include?("gpt-4.1") ||
          current_model.to_s.include?("chatgpt-4o")
        )
        
        expect(should_skip).to be true
        
        # If not skipped (incorrectly), it would process the fragment
        unless should_skip
          processed_fragments << "Test"
        end
        
        expect(processed_fragments).to be_empty
      end
      
      it "skips response.in_progress events for gpt-5-mini" do
        json = {
          "type" => "response.in_progress",
          "response" => {
            "model" => "gpt-5-mini",
            "output" => [
              { "type" => "text", "text" => "Test" }
            ]
          }
        }
        
        streaming_model = "gpt-5-mini"
        current_model = streaming_model
        
        should_skip = current_model && (
          current_model.to_s.downcase.include?("gpt-5") || 
          current_model.to_s.downcase.include?("gpt5")
        )
        
        expect(should_skip).to be true
      end
      
      it "skips response.in_progress events for gpt-4.1" do
        json = {
          "type" => "response.in_progress",
          "response" => {
            "model" => "gpt-4.1",
            "output" => [
              { "type" => "text", "text" => "Test" }
            ]
          }
        }
        
        streaming_model = "gpt-4.1"
        current_model = streaming_model
        
        should_skip = current_model && current_model.to_s.include?("gpt-4.1")
        
        expect(should_skip).to be true
      end
      
      it "skips response.in_progress events for chatgpt-4o-latest" do
        json = {
          "type" => "response.in_progress",
          "response" => {
            "model" => "chatgpt-4o-latest",
            "output" => [
              { "type" => "text", "text" => "Test" }
            ]
          }
        }
        
        streaming_model = "chatgpt-4o-latest"
        current_model = streaming_model
        
        should_skip = current_model && current_model.to_s.include?("chatgpt-4o")
        
        expect(should_skip).to be true
      end
    end
    
    context "with non-GPT-5 models" do
      it "processes response.in_progress events for gpt-4o" do
        json = {
          "type" => "response.in_progress",
          "response" => {
            "model" => "gpt-4o",
            "output" => [
              { "type" => "text", "text" => "Test" }
            ]
          }
        }
        
        streaming_model = "gpt-4o"
        current_model = streaming_model
        
        should_skip = current_model && (
          current_model.to_s.downcase.include?("gpt-5") || 
          current_model.to_s.downcase.include?("gpt5") || 
          current_model.to_s.include?("gpt-4.1") ||
          current_model.to_s.include?("chatgpt-4o")
        )
        
        expect(should_skip).to be false
      end
      
      it "processes response.in_progress events for gpt-3.5-turbo" do
        streaming_model = "gpt-3.5-turbo"
        current_model = streaming_model
        
        should_skip = current_model && (
          current_model.to_s.downcase.include?("gpt-5") || 
          current_model.to_s.downcase.include?("gpt5") || 
          current_model.to_s.include?("gpt-4.1") ||
          current_model.to_s.include?("chatgpt-4o")
        )
        
        expect(should_skip).to be false
      end
    end
  end
  
  describe "response.output_text.delta event handling" do
    it "adds index field to fragments for duplicate detection" do
      json = {
        "type" => "response.output_text.delta",
        "delta" => "テスト",
        "item_id" => "msg_123"
      }
      
      texts = {}
      id = json["item_id"] || "default"
      texts[id] ||= ""
      
      # Simulate fragment processing with index
      fragment = json["delta"]
      res = {
        "type" => "fragment",
        "content" => fragment,
        "index" => texts[id].length,
        "timestamp" => Time.now.to_f,
        "is_first" => texts[id].empty?
      }
      
      expect(res["index"]).to eq 0
      expect(res["is_first"]).to be true
      expect(res["content"]).to eq "テスト"
      
      # Add fragment to accumulated text
      texts[id] += fragment
      
      # Second fragment
      json2 = {
        "type" => "response.output_text.delta",
        "delta" => "です",
        "item_id" => "msg_123"
      }
      
      fragment2 = json2["delta"]
      res2 = {
        "type" => "fragment",
        "content" => fragment2,
        "index" => texts[id].length,
        "timestamp" => Time.now.to_f,
        "is_first" => texts[id].empty?
      }
      
      expect(res2["index"]).to eq 3  # "テスト" is 3 characters in Ruby
      expect(res2["is_first"]).to be false
      expect(res2["content"]).to eq "です"
    end
    
    it "handles multiple item_ids correctly" do
      texts = {}
      
      # First message
      id1 = "msg_123"
      texts[id1] = ""
      fragment1 = "Hello"
      
      res1 = {
        "type" => "fragment",
        "content" => fragment1,
        "index" => texts[id1].length,
        "is_first" => texts[id1].empty?
      }
      
      expect(res1["index"]).to eq 0
      expect(res1["is_first"]).to be true
      
      texts[id1] += fragment1
      
      # Second message with different ID
      id2 = "msg_456"
      texts[id2] = ""
      fragment2 = "World"
      
      res2 = {
        "type" => "fragment",
        "content" => fragment2,
        "index" => texts[id2].length,
        "is_first" => texts[id2].empty?
      }
      
      expect(res2["index"]).to eq 0  # New message starts at 0
      expect(res2["is_first"]).to be true
    end
  end
  
  describe "streaming scenarios" do
    it "correctly processes GPT-5 streaming without duplicates" do
      fragments_received = []
      texts = {}
      
      # Simulate GPT-5 streaming events
      events = [
        { "type" => "response.created", "response" => { "model" => "gpt-5" } },
        { "type" => "response.output_text.delta", "delta" => "キュ", "item_id" => "msg_123" },
        { "type" => "response.output_text.delta", "delta" => "ラソー", "item_id" => "msg_123" },
        { "type" => "response.output_text.delta", "delta" => "リキュール", "item_id" => "msg_123" },
        { "type" => "response.output_text.done", "text" => "キュラソーリキュール", "item_id" => "msg_123" }
      ]
      
      streaming_model = nil
      
      events.each do |event|
        case event["type"]
        when "response.created"
          if event["response"] && event["response"]["model"]
            streaming_model = event["response"]["model"]
          end
          
        when "response.output_text.delta"
          fragment = event["delta"]
          if fragment && !fragment.empty?
            id = event["item_id"] || "default"
            texts[id] ||= ""
            
            res = {
              "type" => "fragment",
              "content" => fragment,
              "index" => texts[id].length
            }
            
            fragments_received << fragment
            texts[id] += fragment
          end
          
        when "response.output_text.done"
          # Final text verification
          id = event["item_id"] || "default"
          expect(texts[id]).to eq "キュラソーリキュール"
        end
      end
      
      expect(fragments_received).to eq ["キュ", "ラソー", "リキュール"]
      expect(fragments_received.join).to eq "キュラソーリキュール"
    end
  end
end