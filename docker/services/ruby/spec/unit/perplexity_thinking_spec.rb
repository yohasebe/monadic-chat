require "spec_helper"

RSpec.describe "Perplexity Thinking Content Extraction" do
  describe "Think tag extraction from fragments" do
    it "extracts thinking content from <think> tags" do
      fragment = "Some text <think>This is reasoning content</think> More text"

      thinking = []
      fragment.scan(/<think>(.*?)<\/think>/m) do |match|
        thinking << match[0].strip
      end

      expect(thinking).to eq(["This is reasoning content"])
    end

    it "handles multiple <think> tags in one fragment" do
      fragment = "<think>First thought</think> text <think>Second thought</think>"

      thinking = []
      fragment.scan(/<think>(.*?)<\/think>/m) do |match|
        thinking << match[0].strip
      end

      expect(thinking.length).to eq(2)
      expect(thinking[0]).to eq("First thought")
      expect(thinking[1]).to eq("Second thought")
    end

    it "handles multiline thinking content" do
      fragment = <<~TEXT
        <think>
        Step 1: Analyze the query
        Step 2: Search for information
        Step 3: Synthesize the answer
        </think>
      TEXT

      thinking = []
      fragment.scan(/<think>(.*?)<\/think>/m) do |match|
        thinking << match[0].strip
      end

      expect(thinking[0]).to include("Step 1", "Step 2", "Step 3")
    end

    it "handles fragments without <think> tags" do
      fragment = "Regular content without thinking"

      thinking = []
      fragment.scan(/<think>(.*?)<\/think>/m) do |match|
        thinking << match[0].strip
      end

      expect(thinking).to be_empty
    end

    it "filters out empty thinking content" do
      fragment = "<think>Valid content</think><think>  </think><think></think>"

      thinking = []
      fragment.scan(/<think>(.*?)<\/think>/m) do |match|
        text = match[0].strip
        thinking << text unless text.empty?
      end

      expect(thinking).to eq(["Valid content"])
    end
  end

  describe "Think tag removal from content" do
    it "removes <think> tags from final content" do
      content = "Answer: <think>My reasoning</think> The result is 42"

      processed = content.gsub(/<think>(.*?)<\/think>\s*/m, '')

      expect(processed).to eq("Answer: The result is 42")
    end

    it "preserves content before and after think tags" do
      content = "Before <think>thinking</think> middle <think>more thinking</think> after"

      processed = content.gsub(/<think>(.*?)<\/think>\s*/m, '')

      expect(processed).to eq("Before middle after")
    end

    it "handles content without think tags" do
      content = "Regular content"

      processed = content.gsub(/<think>(.*?)<\/think>\s*/m, '')

      expect(processed).to eq("Regular content")
    end
  end

  describe "Fragment-level tag removal" do
    it "removes complete tag pairs from fragment" do
      fragment = "Answer: <think>reasoning</think> The result"

      # First remove complete pairs
      processed = fragment.gsub(/<think>(.*?)<\/think>\s*/m, '')
      # Then remove any remaining partial tags
      processed = processed.gsub(/<\/?think>/, '')

      expect(processed).to eq("Answer: The result")
    end

    it "removes opening tag when split across fragments" do
      fragment = "Answer: <think>partial"

      # Remove complete pairs (none in this fragment)
      processed = fragment.gsub(/<think>(.*?)<\/think>\s*/m, '')
      # Remove partial tags
      processed = processed.gsub(/<\/?think>/, '')

      expect(processed).to eq("Answer: partial")
    end

    it "removes closing tag when split across fragments" do
      fragment = "thinking</think> The result"

      # Remove complete pairs (none in this fragment)
      processed = fragment.gsub(/<think>(.*?)<\/think>\s*/m, '')
      # Remove partial tags
      processed = processed.gsub(/<\/?think>/, '')

      expect(processed).to eq("thinking The result")
    end

    it "handles fragment with only opening tag" do
      fragment = "Answer: <think>"

      processed = fragment.gsub(/<think>(.*?)<\/think>\s*/m, '')
      processed = processed.gsub(/<\/?think>/, '')

      expect(processed).to eq("Answer: ")
    end

    it "handles fragment with only closing tag" do
      fragment = "</think> The result"

      processed = fragment.gsub(/<think>(.*?)<\/think>\s*/m, '')
      processed = processed.gsub(/<\/?think>/, '')

      expect(processed).to eq(" The result")
    end
  end

  describe "Citation preservation during thinking removal" do
    it "extracts citations from thinking blocks" do
      think_content = "Let me search [1] and check [2]"

      citations = think_content.scan(/\[(\d+)\]/).flatten

      expect(citations).to eq(["1", "2"])
    end

    it "handles thinking without citations" do
      think_content = "Just regular thinking without sources"

      citations = think_content.scan(/\[(\d+)\]/).flatten

      expect(citations).to be_empty
    end
  end

  describe "Thinking aggregation" do
    it "joins thinking blocks correctly" do
      thinking = ["First analysis", "Second analysis", "Final conclusion"]

      result = thinking.join("\n\n")

      expect(result).to eq("First analysis\n\nSecond analysis\n\nFinal conclusion")
    end

    it "handles empty thinking array" do
      thinking = []

      result = thinking.empty? ? nil : thinking.join("\n\n")

      expect(result).to be_nil
    end

    it "strips whitespace from joined thinking" do
      thinking = ["  Content with spaces  "]
      result = thinking.join("\n\n").strip

      expect(result).to eq("Content with spaces")
    end
  end

  describe "Final response structure" do
    it "includes thinking in message when available" do
      message = { "content" => "Final answer" }
      thinking_result = "Step 1\n\nStep 2"

      message["thinking"] = thinking_result.strip if thinking_result

      expect(message["thinking"]).to eq("Step 1\n\nStep 2")
      expect(message["content"]).to eq("Final answer")
    end

    it "does not include thinking field when nil" do
      message = { "content" => "Final answer" }
      thinking_result = nil

      message["thinking"] = thinking_result.strip if thinking_result

      expect(message.key?("thinking")).to be false
    end
  end
end
