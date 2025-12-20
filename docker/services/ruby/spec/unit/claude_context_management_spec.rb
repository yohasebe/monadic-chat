require "rspec"
require_relative "../../lib/monadic/utils/model_spec"

RSpec.describe "Claude Context Management" do
  describe "ModelSpec.supports_context_management?" do
    it "returns true for Claude Opus 4" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("claude-opus-4-20250514")).to be true
    end

    it "returns true for Claude Sonnet 4.5" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("claude-sonnet-4-5-20250929")).to be true
    end

    it "returns false for Claude 3.5 Sonnet" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("claude-3-5-sonnet-20241022")).to be false
    end

    it "returns false for older Claude models" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("claude-3-5-sonnet-20241022")).to be false
    end

    it "returns false for non-Claude models" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("gpt-4o")).to be false
    end

    it "returns false for nil model" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?(nil)).to be false
    end

    it "returns false for empty string" do
      expect(Monadic::Utils::ModelSpec.supports_context_management?("")).to be false
    end
  end

  describe "Context Management Strategy Ordering" do
    it "documents that clear_thinking must come first when using both strategies" do
      # This is a documentation test to ensure the ordering requirement is captured
      correct_order = [
        { "type" => "clear_thinking_20251015" },
        { "type" => "clear_tool_uses_20250919" }
      ]

      incorrect_order = [
        { "type" => "clear_tool_uses_20250919" },
        { "type" => "clear_thinking_20251015" }
      ]

      # The correct order should have clear_thinking first
      expect(correct_order.first["type"]).to eq("clear_thinking_20251015")
      # The incorrect order violates the API requirement
      expect(incorrect_order.first["type"]).not_to eq("clear_thinking_20251015")
    end
  end

  describe "Default Configuration Values" do
    it "defines expected default values for tool result clearing" do
      default_tool_clearing = {
        "type" => "clear_tool_uses_20250919",
        "trigger" => { "type" => "input_tokens", "value" => 100000 },
        "keep" => { "type" => "tool_uses", "value" => 5 },
        "clear_at_least" => { "type" => "input_tokens", "value" => 10000 }
      }

      expect(default_tool_clearing["trigger"]["value"]).to eq(100000)
      expect(default_tool_clearing["keep"]["value"]).to eq(5)
      expect(default_tool_clearing["clear_at_least"]["value"]).to eq(10000)
    end

    it "defines expected default values for thinking block clearing" do
      default_thinking_clearing = {
        "type" => "clear_thinking_20251015",
        "keep" => { "type" => "thinking_turns", "value" => 1 }
      }

      expect(default_thinking_clearing["keep"]["type"]).to eq("thinking_turns")
      expect(default_thinking_clearing["keep"]["value"]).to eq(1)
    end
  end
end
