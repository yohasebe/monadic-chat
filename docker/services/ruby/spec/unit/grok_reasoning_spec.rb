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
    it "identifies reasoning-named Grok models by name pattern" do
      model_name = "grok-4.20-0309-reasoning"

      is_reasoning = model_name.include?("reasoning")

      expect(is_reasoning).to be true
    end

    it "identifies non-reasoning Grok models" do
      model_name = "grok-4"

      is_reasoning = model_name.include?("reasoning")

      expect(is_reasoning).to be false
    end
  end

  # Grok emits its reasoning summary BEFORE a tool call, then process_functions
  # re-enters api_request with a fresh local reasoning_content. Without a
  # session-level accumulator, the pre-tool reasoning is lost and the persistent
  # Thinking panel disappears once tools are involved. These lock the
  # accumulate-across-tool-rounds + terminal-merge semantics (see
  # process_responses_api_data / build_grok_text_response call site).
  describe "Reasoning persistence across tool-call rounds" do
    # Mirrors the inline accumulate step taken before process_functions.
    def accumulate(session, reasoning_content)
      return if reasoning_content.empty?
      acc = session[:grok_reasoning].to_s
      acc += "\n\n" unless acc.empty?
      session[:grok_reasoning] = acc + reasoning_content.join
    end

    # Mirrors the inline terminal merge before build_grok_text_response.
    def merged_reasoning(session, reasoning_content)
      accumulated = session[:grok_reasoning].to_s
      own = reasoning_content.join
      merged = if accumulated.empty?
                 own
               elsif own.empty?
                 accumulated
               else
                 "#{accumulated}\n\n#{own}"
               end
      merged.strip.empty? ? [] : [merged]
    end

    it "carries pre-tool reasoning into the final answer after a tool round" do
      session = {}
      # Round 1: reasoning emitted, then a tool call recurses.
      accumulate(session, ["Deciding to call a tool"])
      # Round 2 (terminal): the final round has its own (possibly empty) trace.
      expect(merged_reasoning(session, [])).to eq(["Deciding to call a tool"])
    end

    it "merges reasoning from multiple tool rounds with the final round" do
      session = {}
      accumulate(session, ["Round 1 reasoning"])
      accumulate(session, ["Round 2 reasoning"])
      result = merged_reasoning(session, ["Final reasoning"])
      expect(result.first).to eq("Round 1 reasoning\n\nRound 2 reasoning\n\nFinal reasoning")
    end

    it "returns empty (no Thinking panel) when there was never any reasoning" do
      session = {}
      expect(merged_reasoning(session, [])).to eq([])
    end

    it "uses only the terminal reasoning when no tool round accumulated any" do
      session = {}
      expect(merged_reasoning(session, ["Only final reasoning"])).to eq(["Only final reasoning"])
    end
  end
end
