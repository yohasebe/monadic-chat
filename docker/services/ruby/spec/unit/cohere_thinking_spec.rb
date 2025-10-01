require "spec_helper"

RSpec.describe "Cohere Thinking Content Extraction" do
  describe "Content delta handling" do
    it "extracts thinking content from content delta" do
      # Simulate Cohere API response with thinking content
      delta = {
        "delta" => {
          "message" => {
            "content" => {
              "thinking" => "Let me analyze this problem step by step"
            }
          }
        }
      }

      content = delta.dig("delta", "message", "content")
      thinking = content["thinking"] if content

      expect(thinking).to eq("Let me analyze this problem step by step")
    end

    it "handles both thinking and text content simultaneously" do
      # Cohere can send both thinking and text in the same delta
      delta = {
        "delta" => {
          "message" => {
            "content" => {
              "thinking" => "Reasoning about the answer",
              "text" => "The answer is"
            }
          }
        }
      }

      content = delta.dig("delta", "message", "content")
      thinking = content["thinking"] if content
      text = content["text"] if content

      expect(thinking).to eq("Reasoning about the answer")
      expect(text).to eq("The answer is")
    end

    it "handles empty thinking content" do
      delta = {
        "delta" => {
          "message" => {
            "content" => {
              "thinking" => ""
            }
          }
        }
      }

      content = delta.dig("delta", "message", "content")
      thinking = content["thinking"] if content

      expect(thinking).to eq("")
      expect(thinking.strip.empty?).to be true
    end

    it "handles missing thinking field" do
      delta = {
        "delta" => {
          "message" => {
            "content" => {
              "text" => "Regular response without thinking"
            }
          }
        }
      }

      content = delta.dig("delta", "message", "content")
      thinking = content["thinking"] if content

      expect(thinking).to be_nil
    end
  end

  describe "Thinking content accumulation" do
    it "joins multiple thinking fragments correctly" do
      thinking_content = [
        "First, let's identify the problem",
        "Next, consider the constraints",
        "Finally, formulate the solution"
      ]

      result = thinking_content.join("\n\n")

      expect(result).to eq("First, let's identify the problem\n\nNext, consider the constraints\n\nFinally, formulate the solution")
    end

    it "handles empty thinking array" do
      thinking_content = []

      result = thinking_content.join("\n\n")

      expect(result).to eq("")
      expect(thinking_content.empty?).to be true
    end

    it "filters out empty thinking chunks" do
      thinking_content = []

      # Simulate accumulation with empty check
      ["Valid thinking", "", "  ", "More thinking"].each do |chunk|
        thinking_content << chunk unless chunk.strip.empty?
      end

      expect(thinking_content).to eq(["Valid thinking", "More thinking"])
    end
  end

  describe "Response message structure" do
    it "includes thinking in message when available" do
      message = { "content" => "Final answer" }
      thinking_content = ["Step 1", "Step 2"]

      message["thinking"] = thinking_content.join("\n\n") unless thinking_content.empty?

      expect(message["thinking"]).to eq("Step 1\n\nStep 2")
      expect(message["content"]).to eq("Final answer")
    end

    it "does not include thinking field when empty" do
      message = { "content" => "Final answer" }
      thinking_content = []

      message["thinking"] = thinking_content.join("\n\n") unless thinking_content.empty?

      expect(message.key?("thinking")).to be false
    end
  end

  describe "Model identification" do
    it "identifies Command A Reasoning model correctly" do
      model_name = "command-a-reasoning"

      is_thinking = model_name.include?("thinking") || model_name.include?("reasoning")

      expect(is_thinking).to be true
    end

    it "identifies non-reasoning models correctly" do
      model_name = "command-a"

      is_thinking = model_name.include?("thinking") || model_name.include?("reasoning")

      expect(is_thinking).to be false
    end
  end
end
