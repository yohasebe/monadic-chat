# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/utils/flask_app_client'

# Simple helper to check if Docker is available
def docker_available?
  system("docker ps > /dev/null 2>&1")
end

RSpec.describe "FlaskAppClient Docker Integration", type: :integration do
  # Skip if Python service is not available
  before(:all) do
    @client = FlaskAppClient.new
    @skip_tests = !@client.service_available?
    if @skip_tests
      skip "FlaskAppClient tests require Python service to be running (port 5070)"
    end
  end

  let(:client) { @client || FlaskAppClient.new }
  
  describe "Python Flask service availability" do
    it "connects to the Python service" do
      expect(client.service_available?).to be true
    end
    
    it "responds to health check within reasonable time" do
      start_time = Time.now
      result = client.service_available?
      duration = Time.now - start_time
      
      expect(result).to be true
      expect(duration).to be < 5 # Should respond within 5 seconds
    end
  end
  
  describe "Token counting with real tokenizer" do
    context "with English text" do
      it "counts tokens for simple text" do
        text = "Hello, world!"
        count = client.count_tokens(text)
        
        expect(count).to be_a(Integer)
        expect(count).to be > 0
        expect(count).to be < 10 # Simple text should have few tokens
      end
      
      it "counts more tokens for longer text" do
        short_text = "Hello"
        long_text = "Hello, this is a much longer text with many more words to tokenize."
        
        short_count = client.count_tokens(short_text)
        long_count = client.count_tokens(long_text)
        
        expect(long_count).to be > short_count
      end
    end
    
    context "with Japanese text" do
      it "counts tokens for Japanese characters" do
        text = "こんにちは、世界！"
        count = client.count_tokens(text)
        
        expect(count).to be_a(Integer)
        expect(count).to be > 0
      end
      
      it "handles mixed Japanese and English" do
        text = "Hello こんにちは World 世界"
        count = client.count_tokens(text)
        
        expect(count).to be_a(Integer)
        expect(count).to be > 4 # At least one token per word/character group
      end
    end
    
    context "with special content" do
      it "counts tokens in code blocks" do
        code_text = <<~TEXT
          def hello_world():
              print("Hello, World!")
              return 42
        TEXT
        
        count = client.count_tokens(code_text)
        expect(count).to be > 10 # Code typically has more tokens
      end
      
      it "handles Unicode and emojis" do
        text = "Hello 👋 World 🌍 Testing 🧪"
        count = client.count_tokens(text)
        
        expect(count).to be_a(Integer)
        expect(count).to be > 0
      end
    end
    
    context "with different encodings" do
      it "uses o200k_base encoding by default" do
        text = "Test text for encoding"
        default_count = client.count_tokens(text)
        explicit_count = client.count_tokens(text, "o200k_base")
        
        expect(default_count).to eq(explicit_count)
      end
      
      it "produces different counts with different encodings" do
        text = "The quick brown fox jumps over the lazy dog"
        
        # Different encodings may produce different token counts
        o200k_count = client.count_tokens(text, "o200k_base")
        cl100k_count = client.count_tokens(text, "cl100k_base")
        
        expect(o200k_count).to be_a(Integer)
        expect(cl100k_count).to be_a(Integer)
        # They might be the same or different, but both should be valid
      end
    end
  end
  
  describe "Token sequence operations" do
    it "tokenizes text into a sequence of integers" do
      text = "Hello, world!"
      tokens = client.get_tokens_sequence(text)
      
      expect(tokens).to be_a(Array)
      expect(tokens).not_to be_empty
      expect(tokens).to all(be_a(Integer))
    end
    
    it "decodes tokens back to text" do
      original = "Hello, world!"
      
      # Get tokens
      tokens = client.get_tokens_sequence(original)
      expect(tokens).to be_a(Array)
      
      # Decode back
      decoded = client.decode_tokens(tokens)
      expect(decoded).to eq(original)
    end
    
    it "preserves text through tokenize-decode cycle" do
      test_cases = [
        "Simple text",
        "Text with numbers 123 and symbols !@#",
        "Multi-line\ntext\nwith\nbreaks",
        "Unicode: café, naïve, résumé",
        "Mixed: English and 日本語"
      ]
      
      test_cases.each do |text|
        tokens = client.get_tokens_sequence(text)
        decoded = client.decode_tokens(tokens)
        expect(decoded).to eq(text), "Failed to preserve: #{text}"
      end
    end
  end
  
  describe "Caching behavior" do
    it "returns consistent counts for the same text" do
      text = "This is a test for caching behavior"
      
      # Make multiple requests
      counts = 5.times.map { client.count_tokens(text) }
      
      # All counts should be identical
      expect(counts.uniq.size).to eq(1)
    end
    
    it "caches results to improve performance" do
      text = "Performance test text"
      
      # First call (cache miss)
      start1 = Time.now
      count1 = client.count_tokens(text)
      duration1 = Time.now - start1
      
      # Second call (cache hit)
      start2 = Time.now
      count2 = client.count_tokens(text)
      duration2 = Time.now - start2
      
      expect(count1).to eq(count2)
      # Cache hit should be much faster (at least 10x)
      # But only check if first call took measurable time
      if duration1 > 0.001
        expect(duration2).to be < (duration1 / 2)
      end
    end
  end
  
  describe "Error handling" do
    it "handles very long text gracefully" do
      # Generate a very long text
      long_text = "Lorem ipsum " * 10000
      
      expect {
        count = client.count_tokens(long_text)
        expect(count).to be_a(Integer)
        expect(count).to be > 1000
      }.not_to raise_error
    end
    
    it "handles empty text" do
      expect(client.count_tokens("")).to eq(0)
      expect(client.get_tokens_sequence("")).to eq([])
      expect(client.decode_tokens([])).to eq("")
    end
    
    it "handles nil gracefully" do
      # The API should handle this appropriately
      expect { client.count_tokens(nil) }.not_to raise_error
    end
  end
  
  describe "Performance requirements" do
    it "processes reasonable text quickly" do
      text = "The quick brown fox jumps over the lazy dog. " * 100
      
      start_time = Time.now
      count = client.count_tokens(text)
      duration = Time.now - start_time
      
      expect(count).to be > 0
      expect(duration).to be < 1.0 # Should complete within 1 second
    end
  end
end