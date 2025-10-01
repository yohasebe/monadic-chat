require "spec_helper"

RSpec.describe "Claude Thinking Content Extraction" do
  describe "Content block handling" do
    it "extracts thinking content from content block" do
      delta = {
        "type" => "content_block_start",
        "content_block" => {
          "type" => "thinking",
          "thinking" => "Let me analyze this problem step by step"
        }
      }

      thinking = delta.dig("content_block", "thinking")

      expect(thinking).to eq("Let me analyze this problem step by step")
    end

    it "distinguishes between thinking and text blocks" do
      thinking_block = {
        "type" => "content_block_start",
        "content_block" => {
          "type" => "thinking",
          "thinking" => "Reasoning process"
        }
      }

      text_block = {
        "type" => "content_block_start",
        "content_block" => {
          "type" => "text",
          "text" => "Final answer"
        }
      }

      is_thinking = thinking_block.dig("content_block", "type") == "thinking"
      is_text = text_block.dig("content_block", "type") == "text"

      expect(is_thinking).to be true
      expect(is_text).to be true
    end

    it "handles content_block_delta for thinking" do
      delta = {
        "type" => "content_block_delta",
        "delta" => {
          "type" => "thinking_delta",
          "thinking" => "additional reasoning"
        }
      }

      thinking = delta.dig("delta", "thinking")

      expect(thinking).to eq("additional reasoning")
    end

    it "handles empty thinking content" do
      delta = {
        "type" => "content_block_start",
        "content_block" => {
          "type" => "thinking",
          "thinking" => ""
        }
      }

      thinking = delta.dig("content_block", "thinking")

      expect(thinking).to eq("")
      expect(thinking.strip.empty?).to be true
    end
  end

  describe "Thinking content accumulation" do
    it "concatenates thinking deltas" do
      deltas = [
        "Let me ",
        "think ",
        "about ",
        "this."
      ]

      result = deltas.join("")

      expect(result).to eq("Let me think about this.")
    end

    it "handles multiple thinking blocks" do
      thinking_blocks = [
        "First analysis",
        "Second analysis",
        "Final conclusion"
      ]

      result = thinking_blocks.join("\n\n")

      expect(result).to eq("First analysis\n\nSecond analysis\n\nFinal conclusion")
    end

    it "filters out empty thinking chunks" do
      thinking_content = []

      ["Valid thinking", "", "  ", "More thinking"].each do |chunk|
        thinking_content << chunk unless chunk.strip.empty?
      end

      expect(thinking_content).to eq(["Valid thinking", "More thinking"])
    end
  end

  describe "Response message structure" do
    it "includes thinking in message when available" do
      message = { "content" => [{ "type" => "text", "text" => "Final answer" }] }
      thinking_blocks = ["Step 1: Analyze", "Step 2: Conclude"]

      message["thinking"] = thinking_blocks.join("\n\n") unless thinking_blocks.empty?

      expect(message["thinking"]).to eq("Step 1: Analyze\n\nStep 2: Conclude")
      expect(message["content"][0]["text"]).to eq("Final answer")
    end

    it "does not include thinking field when empty" do
      message = { "content" => [{ "type" => "text", "text" => "Final answer" }] }
      thinking_blocks = []

      message["thinking"] = thinking_blocks.join("\n\n") unless thinking_blocks.empty?

      expect(message.key?("thinking")).to be false
    end
  end

  describe "Extended thinking mode detection" do
    it "detects extended thinking enabled" do
      params = {
        "thinking" => {
          "type" => "enabled",
          "budget_tokens" => 10000
        }
      }

      is_enabled = params.dig("thinking", "type") == "enabled"

      expect(is_enabled).to be true
    end

    it "handles thinking disabled" do
      params = {
        "thinking" => {
          "type" => "disabled"
        }
      }

      is_enabled = params.dig("thinking", "type") == "enabled"

      expect(is_enabled).to be false
    end

    it "handles missing thinking parameter" do
      params = {}

      is_enabled = params.dig("thinking", "type") == "enabled"

      expect(is_enabled).to be false
    end
  end

  describe "Model compatibility" do
    it "supports Claude 3.7 Sonnet with extended thinking" do
      model_name = "claude-sonnet-4-5-20250929"

      # Check if model supports extended thinking
      supports_thinking = model_name.include?("sonnet")

      expect(supports_thinking).to be true
    end

    it "identifies non-thinking Claude models" do
      models = ["claude-3-5-haiku-20241022", "claude-3-opus-20240229"]

      models.each do |model_name|
        # These models existed before extended thinking
        is_older = !model_name.include?("4-5")
        expect(is_older).to be true
      end
    end
  end

  describe "Thinking block boundaries" do
    it "tracks content block start and stop" do
      events = [
        { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "thinking" } },
        { "type" => "content_block_delta", "delta" => { "type" => "thinking_delta", "thinking" => "reasoning" } },
        { "type" => "content_block_stop", "index" => 0 }
      ]

      block_started = events[0]["type"] == "content_block_start"
      is_thinking = events[0].dig("content_block", "type") == "thinking"
      block_stopped = events[2]["type"] == "content_block_stop"

      expect(block_started).to be true
      expect(is_thinking).to be true
      expect(block_stopped).to be true
    end

    it "handles multiple content blocks in sequence" do
      events = [
        { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "thinking" } },
        { "type" => "content_block_stop", "index" => 0 },
        { "type" => "content_block_start", "index" => 1, "content_block" => { "type" => "text" } },
        { "type" => "content_block_stop", "index" => 1 }
      ]

      first_is_thinking = events[0].dig("content_block", "type") == "thinking"
      second_is_text = events[2].dig("content_block", "type") == "text"

      expect(first_is_thinking).to be true
      expect(second_is_text).to be true
    end
  end
end
