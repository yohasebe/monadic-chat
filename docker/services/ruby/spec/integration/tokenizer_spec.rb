# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/utils/tokenizer'

RSpec.describe "Tokenizer Integration", type: :integration do
  let(:tokenizer) { Tokenizer.new }

  describe "Service availability" do
    it "is always available (native Ruby)" do
      expect(tokenizer.service_available?).to be true
    end
  end

  describe "Token counting with real tokenizer" do
    context "with English text" do
      it "counts tokens for simple text" do
        text = "Hello, world!"
        count = tokenizer.count_tokens(text)

        expect(count).to be_a(Integer)
        expect(count).to be > 0
        expect(count).to be < 10
      end

      it "counts more tokens for longer text" do
        short_text = "Hello"
        long_text = "Hello, this is a much longer text with many more words to tokenize."

        short_count = tokenizer.count_tokens(short_text)
        long_count = tokenizer.count_tokens(long_text)

        expect(long_count).to be > short_count
      end
    end

    context "with Japanese text" do
      it "counts tokens for Japanese characters" do
        text = "こんにちは、世界！"
        count = tokenizer.count_tokens(text)

        expect(count).to be_a(Integer)
        expect(count).to be > 0
      end

      it "handles mixed Japanese and English" do
        text = "Hello こんにちは World 世界"
        count = tokenizer.count_tokens(text)

        expect(count).to be_a(Integer)
        expect(count).to be > 4
      end
    end

    context "with special content" do
      it "counts tokens in code blocks" do
        code_text = <<~TEXT
          def hello_world():
              print("Hello, World!")
              return 42
        TEXT

        count = tokenizer.count_tokens(code_text)
        expect(count).to be > 10
      end

      it "handles Unicode and emojis" do
        text = "Hello 👋 World 🌍 Testing 🧪"
        count = tokenizer.count_tokens(text)

        expect(count).to be_a(Integer)
        expect(count).to be > 0
      end
    end

    context "with different encodings" do
      it "uses o200k_base encoding by default" do
        text = "Test text for encoding"
        default_count = tokenizer.count_tokens(text)
        explicit_count = tokenizer.count_tokens(text, "o200k_base")

        expect(default_count).to eq(explicit_count)
      end

      it "produces different counts with different encodings" do
        text = "The quick brown fox jumps over the lazy dog"

        o200k_count = tokenizer.count_tokens(text, "o200k_base")
        cl100k_count = tokenizer.count_tokens(text, "cl100k_base")

        expect(o200k_count).to be_a(Integer)
        expect(cl100k_count).to be_a(Integer)
      end
    end
  end

  describe "Token sequence operations" do
    it "tokenizes text into a sequence of integers" do
      text = "Hello, world!"
      tokens = tokenizer.get_tokens_sequence(text)

      expect(tokens).to be_a(Array)
      expect(tokens).not_to be_empty
      expect(tokens).to all(be_a(Integer))
    end

    it "decodes tokens back to text" do
      original = "Hello, world!"

      tokens = tokenizer.get_tokens_sequence(original)
      expect(tokens).to be_a(Array)

      decoded = tokenizer.decode_tokens(tokens)
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
        tokens = tokenizer.get_tokens_sequence(text)
        decoded = tokenizer.decode_tokens(tokens)
        expect(decoded).to eq(text), "Failed to preserve: #{text}"
      end
    end
  end

  describe "Caching behavior" do
    it "returns consistent counts for the same text" do
      text = "This is a test for caching behavior"

      counts = 5.times.map { tokenizer.count_tokens(text) }

      expect(counts.uniq.size).to eq(1)
    end

    it "caches results to improve performance" do
      text = "Performance test text"

      start1 = Time.now
      count1 = tokenizer.count_tokens(text)
      duration1 = Time.now - start1

      start2 = Time.now
      count2 = tokenizer.count_tokens(text)
      duration2 = Time.now - start2

      expect(count1).to eq(count2)
      if duration1 > 0.001
        expect(duration2).to be < (duration1 / 2)
      end
    end
  end

  describe "Error handling" do
    it "handles very long text gracefully" do
      long_text = "Lorem ipsum " * 10000

      expect {
        count = tokenizer.count_tokens(long_text)
        expect(count).to be_a(Integer)
        expect(count).to be > 1000
      }.not_to raise_error
    end

    it "handles empty text" do
      expect(tokenizer.count_tokens("")).to eq(0)
      expect(tokenizer.get_tokens_sequence("")).to eq([])
      expect(tokenizer.decode_tokens([])).to eq("")
    end

    it "handles nil gracefully" do
      expect { tokenizer.count_tokens(nil) }.not_to raise_error
    end
  end

  describe "Performance requirements" do
    it "processes reasonable text quickly" do
      text = "The quick brown fox jumps over the lazy dog. " * 100

      start_time = Time.now
      count = tokenizer.count_tokens(text)
      duration = Time.now - start_time

      expect(count).to be > 0
      expect(duration).to be < 1.0
    end
  end
end
