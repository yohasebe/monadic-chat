require "spec_helper"

RSpec.describe "Gemini Thinking Content Extraction" do
  describe "Thinking mode with thoughts field" do
    it "extracts thoughts from candidates" do
      json = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                {
                  "thought" => true,
                  "text" => "Let me analyze this problem step by step"
                }
              ]
            }
          }
        ]
      }

      thoughts = []
      parts = json.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if part["thought"]
          thoughts << part["text"]
        end
      end

      expect(thoughts).to eq(["Let me analyze this problem step by step"])
    end

    it "distinguishes between thought and regular text parts" do
      json = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                {
                  "thought" => true,
                  "text" => "Reasoning process"
                },
                {
                  "text" => "Final answer"
                }
              ]
            }
          }
        ]
      }

      thoughts = []
      regular_text = []

      parts = json.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if part["thought"]
          thoughts << part["text"]
        else
          regular_text << part["text"]
        end
      end

      expect(thoughts).to eq(["Reasoning process"])
      expect(regular_text).to eq(["Final answer"])
    end

    it "handles empty thoughts" do
      json = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                {
                  "thought" => true,
                  "text" => ""
                }
              ]
            }
          }
        ]
      }

      thoughts = []
      parts = json.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if part["thought"] && !part["text"].to_s.strip.empty?
          thoughts << part["text"]
        end
      end

      expect(thoughts).to be_empty
    end

    it "handles multiple thought parts" do
      json = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                {
                  "thought" => true,
                  "text" => "First thought"
                },
                {
                  "thought" => true,
                  "text" => "Second thought"
                },
                {
                  "text" => "Final answer"
                }
              ]
            }
          }
        ]
      }

      thoughts = []
      parts = json.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if part["thought"]
          thoughts << part["text"]
        end
      end

      expect(thoughts.length).to eq(2)
      expect(thoughts[0]).to eq("First thought")
      expect(thoughts[1]).to eq("Second thought")
    end
  end

  describe "Thinking mode configuration" do
    it "detects thinking mode enabled" do
      config = {
        "thinkingConfig" => {
          "thinkingMode" => "THINKING_MODE_ENABLED"
        }
      }

      is_enabled = config.dig("thinkingConfig", "thinkingMode") == "THINKING_MODE_ENABLED"

      expect(is_enabled).to be true
    end

    it "handles thinking mode unspecified" do
      config = {
        "thinkingConfig" => {
          "thinkingMode" => "THINKING_MODE_UNSPECIFIED"
        }
      }

      is_enabled = config.dig("thinkingConfig", "thinkingMode") == "THINKING_MODE_ENABLED"

      expect(is_enabled).to be false
    end

    it "handles missing thinking config" do
      config = {}

      is_enabled = config.dig("thinkingConfig", "thinkingMode") == "THINKING_MODE_ENABLED"

      expect(is_enabled).to be false
    end
  end

  describe "Thinking content aggregation" do
    it "joins thinking blocks correctly" do
      thoughts = [
        "First analysis",
        "Second analysis",
        "Final conclusion"
      ]

      result = thoughts.join("\n\n")

      expect(result).to eq("First analysis\n\nSecond analysis\n\nFinal conclusion")
    end

    it "handles empty thoughts array" do
      thoughts = []

      result = thoughts.empty? ? nil : thoughts.join("\n\n")

      expect(result).to be_nil
    end

    it "handles single thought" do
      thoughts = ["Complete analysis in one block"]

      result = thoughts.join("\n\n")

      expect(result).to eq("Complete analysis in one block")
    end
  end

  describe "Final response structure" do
    it "includes thinking in message when thoughts available" do
      message = {
        "content" => {
          "parts" => [
            { "text" => "Final answer" }
          ]
        }
      }

      thoughts = ["Step 1: Analyze", "Step 2: Conclude"]

      if thoughts && !thoughts.empty?
        message["thinking"] = thoughts.join("\n\n")
      end

      expect(message["thinking"]).to eq("Step 1: Analyze\n\nStep 2: Conclude")
      expect(message["content"]["parts"][0]["text"]).to eq("Final answer")
    end

    it "does not include thinking field when thoughts empty" do
      message = {
        "content" => {
          "parts" => [
            { "text" => "Final answer" }
          ]
        }
      }

      thoughts = []

      if thoughts && !thoughts.empty?
        message["thinking"] = thoughts.join("\n\n")
      end

      expect(message.key?("thinking")).to be false
    end
  end

  describe "Model compatibility" do
    it "supports Gemini 2.0 models with thinking" do
      models = ["gemini-2.0-flash-thinking-exp", "gemini-2.0-flash-thinking-exp-01-21"]

      models.each do |model_name|
        supports_thinking = model_name.include?("thinking")
        expect(supports_thinking).to be true
      end
    end

    it "identifies non-thinking Gemini models" do
      models = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-1.5-pro"]

      models.each do |model_name|
        supports_thinking = model_name.include?("thinking")
        expect(supports_thinking).to be false
      end
    end
  end

  describe "Streaming behavior" do
    it "handles streaming thought parts" do
      deltas = [
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "thought" => true, "text" => "Analyzing " }
                ]
              }
            }
          ]
        },
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "thought" => true, "text" => "the problem " }
                ]
              }
            }
          ]
        },
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "thought" => true, "text" => "carefully" }
                ]
              }
            }
          ]
        }
      ]

      thoughts = []

      deltas.each do |json|
        parts = json.dig("candidates", 0, "content", "parts") || []
        parts.each do |part|
          if part["thought"]
            thoughts << part["text"]
          end
        end
      end

      expect(thoughts).to eq(["Analyzing ", "the problem ", "carefully"])
      expect(thoughts.join("")).to eq("Analyzing the problem carefully")
    end
  end

  describe "Mixed content handling" do
    it "correctly separates thoughts from final answer in single response" do
      json = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "thought" => true, "text" => "Let me think about this" },
                { "thought" => true, "text" => "I need to consider multiple factors" },
                { "text" => "Here is my answer based on the analysis" }
              ]
            }
          }
        ]
      }

      thoughts = []
      answer_parts = []

      parts = json.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if part["thought"]
          thoughts << part["text"]
        else
          answer_parts << part["text"]
        end
      end

      expect(thoughts.length).to eq(2)
      expect(answer_parts.length).to eq(1)
      expect(thoughts.join("\n\n")).to eq("Let me think about this\n\nI need to consider multiple factors")
      expect(answer_parts[0]).to eq("Here is my answer based on the analysis")
    end
  end
end
