# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/utils/flask_app_client"
require_relative "../../lib/monadic/app"

RSpec.describe "Token counting integration" do
  let(:tokenizer) { FlaskAppClient.new }
  
  describe "MonadicApp tokenizer integration" do
    before do
      # Ensure MonadicApp has a tokenizer instance
      MonadicApp.const_set(:TOKENIZER, tokenizer) unless defined?(MonadicApp::TOKENIZER)
    end
    
    it "provides a global tokenizer instance" do
      expect(MonadicApp::TOKENIZER).to be_a(FlaskAppClient)
    end
  end
  
  describe "Token counting for different text types" do
    before do
      # Mock the Python service to return predictable results
      allow(tokenizer).to receive(:post_request) do |endpoint, body|
        case endpoint
        when "count_tokens"
          # Simple mock: count words as tokens for testing
          word_count = body[:text].split.size
          { "number_of_tokens" => word_count }
        when "get_tokens_sequence"
          # Return mock token IDs
          words = body[:text].split
          tokens = words.map.with_index { |_, i| 1000 + i }
          { "tokens_sequence" => tokens.join(",") }
        else
          nil
        end
      end
    end
    
    context "with English text" do
      it "counts tokens correctly" do
        text = "Hello, this is a test message."
        expect(tokenizer.count_tokens(text)).to eq(6)
      end
    end
    
    context "with Japanese text" do
      it "counts tokens for Japanese characters" do
        text = "こんにちは、これはテストメッセージです。"
        # In real implementation, this would use proper tokenization
        expect(tokenizer.count_tokens(text)).to be_a(Integer)
      end
    end
    
    context "with mixed content" do
      it "handles text with code blocks" do
        text = <<~TEXT
          Here is some code:
          ```ruby
          def hello
            puts "Hello, world!"
          end
          ```
          And some more text.
        TEXT
        
        expect(tokenizer.count_tokens(text)).to be > 0
      end
      
      it "handles text with special characters" do
        text = "Special chars: @#$%^&*() 😀🎉 <html></html>"
        expect(tokenizer.count_tokens(text)).to be > 0
      end
    end
  end
  
  describe "Token sequence operations" do
    before do
      allow(tokenizer).to receive(:post_request) do |endpoint, body|
        case endpoint
        when "get_tokens_sequence"
          { "tokens_sequence" => "100,200,300" }
        when "decode_tokens"
          { "original_text" => "Hello world!" }
        else
          nil
        end
      end
    end
    
    it "can tokenize and decode back to original text" do
      original = "Hello world!"
      
      # Get tokens
      tokens = tokenizer.get_tokens_sequence(original)
      expect(tokens).to eq([100, 200, 300])
      
      # Decode back
      decoded = tokenizer.decode_tokens(tokens)
      expect(decoded).to eq("Hello world!")
    end
  end
  
  describe "Different encoding support" do
    it "supports o200k_base encoding (default)" do
      allow(tokenizer).to receive(:post_request).with(
        "count_tokens",
        hash_including(encoding_name: "o200k_base")
      ).and_return({ "number_of_tokens" => 5 })
      
      expect(tokenizer.count_tokens("test text")).to eq(5)
    end
    
    it "supports cl100k_base encoding" do
      allow(tokenizer).to receive(:post_request).with(
        "count_tokens",
        hash_including(encoding_name: "cl100k_base")
      ).and_return({ "number_of_tokens" => 4 })
      
      expect(tokenizer.count_tokens("test text", "cl100k_base")).to eq(4)
    end
    
    it "supports p50k_base encoding" do
      allow(tokenizer).to receive(:post_request).with(
        "count_tokens",
        hash_including(encoding_name: "p50k_base")
      ).and_return({ "number_of_tokens" => 6 })
      
      expect(tokenizer.count_tokens("test text", "p50k_base")).to eq(6)
    end
  end
  
  describe "Error handling" do
    context "when Python service is unavailable" do
      before do
        allow(tokenizer).to receive(:post_request).and_return(nil)
      end
      
      it "gracefully handles token counting failure" do
        expect(tokenizer.count_tokens("test")).to be_nil
      end
      
      it "gracefully handles tokenization failure" do
        expect(tokenizer.get_tokens_sequence("test")).to be_nil
      end
      
      it "gracefully handles decoding failure" do
        expect(tokenizer.decode_tokens([100, 200])).to be_nil
      end
    end
  end
end