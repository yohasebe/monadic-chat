require "spec_helper"

RSpec.describe "Mistral Thinking Content Extraction" do
  describe "New format thinking chunks (v2507/2509)" do
    it "extracts thinking text from structured JSON format" do
      # Simulate new format thinking chunk
      delta = {
        "type" => "thinking",
        "thinking" => [
          {
            "type" => "text",
            "text" => "First chunk of thinking"
          },
          {
            "type" => "text",
            "text" => " continued here"
          }
        ]
      }

      # Extract thinking text using filter_map
      thinking_text = delta["thinking"].filter_map do |chunk|
        if chunk.is_a?(Hash) && chunk["type"] == "text"
          chunk["text"]
        end
      end.join

      expect(thinking_text).to eq("First chunk of thinking continued here")
    end

    it "handles empty thinking array" do
      delta = {
        "type" => "thinking",
        "thinking" => []
      }

      thinking_text = delta["thinking"].filter_map do |chunk|
        if chunk.is_a?(Hash) && chunk["type"] == "text"
          chunk["text"]
        end
      end.join

      expect(thinking_text).to eq("")
    end

    it "skips non-text type entries" do
      delta = {
        "type" => "thinking",
        "thinking" => [
          {
            "type" => "text",
            "text" => "Valid text"
          },
          {
            "type" => "other",
            "text" => "Should be skipped"
          },
          {
            "type" => "text",
            "text" => " More valid text"
          }
        ]
      }

      thinking_text = delta["thinking"].filter_map do |chunk|
        if chunk.is_a?(Hash) && chunk["type"] == "text"
          chunk["text"]
        end
      end.join

      expect(thinking_text).to eq("Valid text More valid text")
    end
  end

  describe "Old format thinking tags (v2506)" do
    it "extracts thinking from <think> tags" do
      content = "Some text <think>This is my reasoning process</think> More text"

      thinking_matches = content.scan(/<think>(.*?)<\/think>/m)
      thinking = thinking_matches.map { |match| match[0].strip }

      expect(thinking).to eq(["This is my reasoning process"])
    end

    it "extracts multiple thinking blocks" do
      content = "<think>First thought</think> Text <think>Second thought</think>"

      thinking_matches = content.scan(/<think>(.*?)<\/think>/m)
      thinking = thinking_matches.map { |match| match[0].strip }

      expect(thinking.length).to eq(2)
      expect(thinking[0]).to eq("First thought")
      expect(thinking[1]).to eq("Second thought")
    end

    it "removes thinking tags from content" do
      content = "Answer: <think>My reasoning here</think> The final answer is 42"

      final_content = content.gsub(/<think>.*?<\/think>/m, '')

      expect(final_content).to eq("Answer:  The final answer is 42")
    end

    it "supports both <think> and <thinking> tags" do
      content = "<think>First</think> and <thinking>Second</thinking>"

      think_matches = content.scan(/<think>(.*?)<\/think>/m)
      thinking_matches = content.scan(/<thinking>(.*?)<\/thinking>/m)
      all_thinking = (think_matches + thinking_matches).map { |match| match[0].strip }

      expect(all_thinking.length).to eq(2)
      expect(all_thinking).to include("First", "Second")
    end

    it "handles multiline thinking content" do
      content = <<~TEXT
        <think>
        Step 1: Analyze the problem
        Step 2: Consider options
        Step 3: Choose best approach
        </think>
        Final answer
      TEXT

      thinking_matches = content.scan(/<think>(.*?)<\/think>/m)
      thinking = thinking_matches.map { |match| match[0].strip }

      expect(thinking[0]).to include("Step 1", "Step 2", "Step 3")
    end
  end

  describe "Thinking array aggregation" do
    it "joins multiple thinking chunks correctly" do
      thinking = ["First chunk", "Second chunk", "Third chunk"]

      result = thinking.join("\n\n")

      expect(result).to eq("First chunk\n\nSecond chunk\n\nThird chunk")
    end

    it "handles empty thinking array" do
      thinking = []

      result = thinking.join("\n\n")

      expect(result).to eq("")
    end
  end
end
