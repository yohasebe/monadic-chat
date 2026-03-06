require "spec_helper"

RSpec.describe "Grok Reasoning Content Extraction" do
  describe "Responses API reasoning_summary_text events" do
    it "extracts reasoning from reasoning_summary_text.delta event" do
      json = {
        "type" => "response.reasoning_summary_text.delta",
        "item_id" => "rs_123",
        "delta" => "Let me analyze this problem step by step"
      }

      reasoning_content = []
      delta = json["delta"]

      unless delta.to_s.strip.empty?
        reasoning_content << delta
      end

      expect(reasoning_content).to eq(["Let me analyze this problem step by step"])
    end

    it "handles multiple reasoning_summary_text.delta events" do
      deltas = [
        {
          "type" => "response.reasoning_summary_text.delta",
          "item_id" => "rs_123",
          "delta" => "First step: identify the problem"
        },
        {
          "type" => "response.reasoning_summary_text.delta",
          "item_id" => "rs_123",
          "delta" => "Second step: analyze constraints"
        },
        {
          "type" => "response.reasoning_summary_text.delta",
          "item_id" => "rs_123",
          "delta" => "Third step: formulate solution"
        }
      ]

      reasoning_content = []

      deltas.each do |event|
        delta = event["delta"]
        unless delta.to_s.strip.empty?
          reasoning_content << delta
        end
      end

      expect(reasoning_content.length).to eq(3)
      expect(reasoning_content[0]).to eq("First step: identify the problem")
      expect(reasoning_content[1]).to eq("Second step: analyze constraints")
      expect(reasoning_content[2]).to eq("Third step: formulate solution")
    end

    it "filters out empty reasoning deltas" do
      json = {
        "type" => "response.reasoning_summary_text.delta",
        "item_id" => "rs_123",
        "delta" => "  "
      }

      reasoning_content = []
      delta = json["delta"]

      unless delta.to_s.strip.empty?
        reasoning_content << delta
      end

      expect(reasoning_content).to be_empty
    end

    it "handles nil delta" do
      json = {
        "type" => "response.reasoning_summary_text.delta",
        "item_id" => "rs_123",
        "delta" => nil
      }

      reasoning_content = []
      delta = json["delta"]

      unless delta.to_s.strip.empty?
        reasoning_content << delta
      end

      expect(reasoning_content).to be_empty
    end
  end

  describe "Legacy reasoning_content delta handling (fallback)" do
    it "extracts reasoning_content from delta" do
      json = {
        "choices" => [
          {
            "delta" => {
              "reasoning_content" => "Let me analyze this problem step by step"
            }
          }
        ]
      }

      reasoning_content = []
      reasoning = json.dig("choices", 0, "delta", "reasoning_content")

      unless reasoning.to_s.strip.empty? || reasoning == "Thinking..."
        reasoning_content << reasoning
      end

      expect(reasoning_content).to eq(["Let me analyze this problem step by step"])
    end

    it "filters out 'Thinking...' placeholder text" do
      json = {
        "choices" => [
          {
            "delta" => {
              "reasoning_content" => "Thinking..."
            }
          }
        ]
      }

      reasoning_content = []
      reasoning = json.dig("choices", 0, "delta", "reasoning_content")

      unless reasoning.to_s.strip.empty? || reasoning == "Thinking..."
        reasoning_content << reasoning
      end

      expect(reasoning_content).to be_empty
    end

    it "filters out empty reasoning content" do
      json = {
        "choices" => [
          {
            "delta" => {
              "reasoning_content" => "  "
            }
          }
        ]
      }

      reasoning_content = []
      reasoning = json.dig("choices", 0, "delta", "reasoning_content")

      unless reasoning.to_s.strip.empty? || reasoning == "Thinking..."
        reasoning_content << reasoning
      end

      expect(reasoning_content).to be_empty
    end

    it "handles missing reasoning_content field" do
      json = {
        "choices" => [
          {
            "delta" => {
              "content" => "Regular response"
            }
          }
        ]
      }

      reasoning_content = []
      reasoning = json.dig("choices", 0, "delta", "reasoning_content")

      unless reasoning.to_s.strip.empty? || reasoning == "Thinking..."
        reasoning_content << reasoning
      end

      expect(reasoning_content).to be_empty
    end
  end

  describe "Reasoning content aggregation" do
    it "joins reasoning blocks correctly" do
      reasoning_content = [
        "First analysis",
        "Second analysis",
        "Final conclusion"
      ]

      result = reasoning_content.join("\n\n")

      expect(result).to eq("First analysis\n\nSecond analysis\n\nFinal conclusion")
    end

    it "handles empty reasoning array" do
      reasoning_content = []

      result = reasoning_content.empty? ? nil : reasoning_content.join("\n\n")

      expect(result).to be_nil
    end

    it "handles single reasoning block" do
      reasoning_content = ["Complete analysis in one block"]

      result = reasoning_content.join("\n\n")

      expect(result).to eq("Complete analysis in one block")
    end
  end

  describe "Final response structure" do
    it "includes reasoning_content in Responses API format" do
      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "The answer is 42"
          },
          "finish_reason" => "stop"
        }]
      }

      reasoning_texts = ["Step 1: Analyze", "Step 2: Conclude"]

      if reasoning_texts.any?
        response["choices"][0]["message"]["reasoning_content"] = reasoning_texts.join("\n\n")
      end

      expect(response["choices"][0]["message"]["reasoning_content"]).to eq("Step 1: Analyze\n\nStep 2: Conclude")
      expect(response["choices"][0]["message"]["content"]).to eq("The answer is 42")
    end

    it "includes thinking in message when reasoning_content available" do
      result = {
        "choices" => [
          {
            "message" => {
              "content" => "The answer is 42"
            }
          }
        ]
      }

      reasoning_content = ["Step 1: Analyze", "Step 2: Conclude"]

      if reasoning_content && !reasoning_content.empty?
        result["choices"][0]["message"]["thinking"] = reasoning_content.join("\n\n")
      end

      expect(result["choices"][0]["message"]["thinking"]).to eq("Step 1: Analyze\n\nStep 2: Conclude")
      expect(result["choices"][0]["message"]["content"]).to eq("The answer is 42")
    end

    it "does not include thinking field when reasoning_content empty" do
      result = {
        "choices" => [
          {
            "message" => {
              "content" => "The answer is 42"
            }
          }
        ]
      }

      reasoning_content = []

      if reasoning_content && !reasoning_content.empty?
        result["choices"][0]["message"]["thinking"] = reasoning_content.join("\n\n")
      end

      expect(result["choices"][0]["message"].key?("thinking")).to be false
    end

    it "does not include thinking field when reasoning_content nil" do
      result = {
        "choices" => [
          {
            "message" => {
              "content" => "The answer is 42"
            }
          }
        ]
      }

      reasoning_content = nil

      if reasoning_content && !reasoning_content.empty?
        result["choices"][0]["message"]["thinking"] = reasoning_content.join("\n\n")
      end

      expect(result["choices"][0]["message"].key?("thinking")).to be false
    end
  end

  describe "Model compatibility" do
    it "supports Grok 3 reasoning models" do
      model_name = "grok-4-1-fast-reasoning"

      is_reasoning = model_name.include?("reasoning")

      expect(is_reasoning).to be true
    end

    it "identifies non-reasoning Grok models" do
      model_name = "grok-4"

      is_reasoning = model_name.include?("reasoning")

      expect(is_reasoning).to be false
    end
  end
end
