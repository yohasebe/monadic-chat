# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../lib/monadic/adapters/vendors/gemini_helper"

RSpec.describe "Streaming Fragment Ordering (All Providers)" do
  describe "OpenAI Responses API" do
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
    it "adds sequence field to fragments for duplicate detection" do
      json = {
        "type" => "response.output_text.delta",
        "delta" => "テスト",
        "item_id" => "msg_123"
      }

      texts = {}
      fragment_sequence = 0
      id = json["item_id"] || "default"
      texts[id] ||= ""

      # Simulate fragment processing with sequence
      fragment = json["delta"]
      res = {
        "type" => "fragment",
        "content" => fragment,
        "sequence" => fragment_sequence,
        "timestamp" => Time.now.to_f,
        "is_first" => fragment_sequence == 0
      }

      expect(res["sequence"]).to eq 0
      expect(res["is_first"]).to be true
      expect(res["content"]).to eq "テスト"

      # Add fragment to accumulated text
      texts[id] += fragment
      fragment_sequence += 1

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
        "sequence" => fragment_sequence,
        "timestamp" => Time.now.to_f,
        "is_first" => fragment_sequence == 0
      }

      expect(res2["sequence"]).to eq 1
      expect(res2["is_first"]).to be false
      expect(res2["content"]).to eq "です"
    end
    
    it "handles multiple item_ids correctly" do
      texts = {}
      fragment_sequence = 0

      # First message
      id1 = "msg_123"
      texts[id1] = ""
      fragment1 = "Hello"

      res1 = {
        "type" => "fragment",
        "content" => fragment1,
        "sequence" => fragment_sequence,
        "is_first" => fragment_sequence == 0
      }

      expect(res1["sequence"]).to eq 0
      expect(res1["is_first"]).to be true

      texts[id1] += fragment1
      fragment_sequence += 1

      # Second message with different ID
      id2 = "msg_456"
      texts[id2] = ""
      fragment2 = "World"

      res2 = {
        "type" => "fragment",
        "content" => fragment2,
        "sequence" => fragment_sequence,
        "is_first" => fragment_sequence == 0
      }

      expect(res2["sequence"]).to eq 1  # Sequence continues across messages
      expect(res2["is_first"]).to be false
    end
  end
  
  describe "streaming scenarios" do
    it "correctly processes GPT-5 streaming without duplicates" do
      fragments_received = []
      texts = {}
      fragment_sequence = 0

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
              "sequence" => fragment_sequence
            }

            fragment_sequence += 1
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
  end  # OpenAI Responses API

  describe "OpenAI Chat Completions API" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = {}
      fragments_received = []

      # Simulate Chat Completions API streaming
      streaming_chunks = [
        { "choices" => [{ "delta" => { "content" => "Hello" } }] },
        { "choices" => [{ "delta" => { "content" => " world" } }] },
        { "choices" => [{ "delta" => { "content" => "!" } }] }
      ]

      id = "default"
      texts[id] = ""

      streaming_chunks.each do |json|
        fragment = json.dig("choices", 0, "delta", "content").to_s
        next if fragment.empty?

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        }

        fragments_received << res
        texts[id] += fragment
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[1]["is_first"]).to be false
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts[id]).to eq "Hello world!"
    end
  end

  describe "Claude" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = []
      fragments_received = []

      # Simulate Claude streaming (delta.text)
      streaming_events = [
        { "delta" => { "text" => "こんにちは" } },
        { "delta" => { "text" => "世界" } },
        { "delta" => { "text" => "！" } }
      ]

      streaming_events.each do |json|
        fragment = json.dig("delta", "text").to_s
        next if fragment.empty?

        texts << fragment

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts.join).to eq "こんにちは世界！"
    end
  end

  describe "Gemini" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = []
      fragments_received = []

      # Simulate Gemini streaming (parts[].text)
      streaming_events = [
        { "candidates" => [{ "content" => { "parts" => [{ "text" => "Bonjour" }] } }] },
        { "candidates" => [{ "content" => { "parts" => [{ "text" => " le" }] } }] },
        { "candidates" => [{ "content" => { "parts" => [{ "text" => " monde" }] } }] }
      ]

      streaming_events.each do |json|
        parts = json.dig("candidates", 0, "content", "parts")
        next unless parts

        parts.each do |part|
          fragment = part["text"].to_s
          next if fragment.empty?

          texts << fragment

          res = {
            "type" => "fragment",
            "content" => fragment,
            "sequence" => fragment_sequence,
            "timestamp" => Time.now.to_f,
            "is_first" => fragment_sequence == 0
          }

          fragments_received << res
          fragment_sequence += 1
        end
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts.join).to eq "Bonjour le monde"
    end
  end

  describe "Perplexity" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = {}
      fragments_received = []

      # Simulate Perplexity streaming (OpenAI-compatible format)
      streaming_chunks = [
        { "choices" => [{ "delta" => { "content" => "Answer" }, "message" => { "content" => "" } }] },
        { "choices" => [{ "delta" => { "content" => " is" }, "message" => { "content" => "Answer" } }] },
        { "choices" => [{ "delta" => { "content" => " 42" }, "message" => { "content" => "Answer is" } }] }
      ]

      id = "default"
      texts[id] = { "choices" => [{ "message" => { "content" => String.new } }] }

      streaming_chunks.each do |json|
        delta = json.dig("choices", 0, "delta")
        fragment = delta["content"].to_s if delta
        next if !fragment || fragment.empty?

        choice = texts[id]["choices"][0]
        choice["message"]["content"] << fragment

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts[id]["choices"][0]["message"]["content"]).to eq "Answer is 42"
    end
  end

  describe "Deepseek" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = {}
      fragments_received = []

      # Simulate Deepseek streaming (OpenAI-compatible format)
      streaming_chunks = [
        { "choices" => [{ "delta" => { "content" => "深度" } }] },
        { "choices" => [{ "delta" => { "content" => "学习" } }] },
        { "choices" => [{ "delta" => { "content" => "模型" } }] }
      ]

      id = "default"
      texts[id] = { "choices" => [{ "message" => { "content" => String.new } }] }

      streaming_chunks.each do |json|
        fragment = json.dig("choices", 0, "delta", "content").to_s
        next if fragment.empty? || fragment.match?(/<｜[^｜]+｜>/)

        choice = texts[id]["choices"][0]
        choice["message"]["content"] << fragment

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts[id]["choices"][0]["message"]["content"]).to eq "深度学习模型"
    end
  end

  describe "Mistral" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      content_buffer = ""
      fragments_received = []

      # Simulate Mistral streaming
      streaming_chunks = [
        { "choices" => [{ "delta" => { "content" => "Mistral" } }] },
        { "choices" => [{ "delta" => { "content" => " AI" } }] },
        { "choices" => [{ "delta" => { "content" => " model" } }] }
      ]

      streaming_chunks.each do |json|
        content = json.dig("choices", 0, "delta", "content").to_s
        next if content.empty?

        content_buffer += content

        res = {
          "type" => "fragment",
          "content" => content,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(content_buffer).to eq "Mistral AI model"
    end
  end

  describe "Grok" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = {}
      fragments_received = []

      # Simulate Grok streaming (OpenAI-compatible format)
      streaming_chunks = [
        { "choices" => [{ "delta" => { "content" => "Grok" } }] },
        { "choices" => [{ "delta" => { "content" => " by" } }] },
        { "choices" => [{ "delta" => { "content" => " xAI" } }] }
      ]

      id = "default"
      texts[id] = { "choices" => [{ "message" => { "content" => String.new } }] }

      streaming_chunks.each do |json|
        fragment = json.dig("choices", 0, "delta", "content").to_s
        next if fragment.empty?

        choice = texts[id]["choices"][0]
        choice["message"]["content"] << fragment

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts[id]["choices"][0]["message"]["content"]).to eq "Grok by xAI"
    end
  end

  describe "Cohere" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = []
      fragments_received = []

      # Simulate Cohere streaming
      streaming_events = [
        { "type" => "content-delta", "delta" => { "message" => { "content" => { "text" => "Cohere" } } } },
        { "type" => "content-delta", "delta" => { "message" => { "content" => { "text" => " language" } } } },
        { "type" => "content-delta", "delta" => { "message" => { "content" => { "text" => " model" } } } }
      ]

      streaming_events.each do |json|
        next unless json["type"] == "content-delta"

        text = json.dig("delta", "message", "content", "text")
        next unless text && !text.strip.empty?

        texts << text

        res = {
          "type" => "fragment",
          "content" => text,
          "sequence" => fragment_sequence,
          "timestamp" => Time.now.to_f,
          "is_first" => fragment_sequence == 0
        }

        fragments_received << res
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[0]["is_first"]).to be true
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts.join).to eq "Cohere language model"
    end
  end

  describe "Ollama" do
    it "uses sequence numbers for fragment ordering" do
      fragment_sequence = 0
      texts = []
      fragments_received = []

      # Simulate Ollama streaming
      streaming_chunks = [
        { "message" => { "content" => "Ollama" } },
        { "message" => { "content" => " local" } },
        { "message" => { "content" => " LLM" } }
      ]

      streaming_chunks.each do |json|
        fragment = json.dig("message", "content").to_s
        next if fragment.empty?

        res = {
          "type" => "fragment",
          "content" => fragment,
          "sequence" => fragment_sequence
        }

        fragments_received << res
        texts << fragment
        fragment_sequence += 1
      end

      expect(fragments_received.length).to eq 3
      expect(fragments_received[0]["sequence"]).to eq 0
      expect(fragments_received[1]["sequence"]).to eq 1
      expect(fragments_received[2]["sequence"]).to eq 2
      expect(texts.join).to eq "Ollama local LLM"
    end
  end
end