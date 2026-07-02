# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"

# Regression tests for configure_claude_thinking's non-adaptive budget math.
# Anthropic rejects thinking budgets under 1024 tokens, and headless callers
# (e.g. the MCP capability layer) can pass small max_tokens values that drive
# the ratio-based budgets below that minimum. These specs pin the floor and
# the xhigh/max -> deepest-tier mapping.
RSpec.describe "ClaudeHelper#configure_claude_thinking budget floor" do
  let(:host) { Class.new { include ClaudeHelper }.new }

  # claude-sonnet-4-5-20250929 is the catalog's non-adaptive thinking model,
  # which exercises the ratio-based budget branch.
  NON_ADAPTIVE_MODEL = "claude-sonnet-4-5-20250929"

  def configure(effort:, max_tokens:)
    obj = { "model" => NON_ADAPTIVE_MODEL, "reasoning_effort" => effort }
    host.send(:configure_claude_thinking, obj, NON_ADAPTIVE_MODEL, max_tokens, "TestApp")
  end

  it "floors a ratio-derived budget at Anthropic's 1024-token minimum" do
    # low @ 1500 -> 750 without the floor; the API would reject that with 400.
    config = configure(effort: "low", max_tokens: 1500)
    expect(config[:thinking_enabled]).to be true
    expect(config[:budget_tokens]).to eq(1024)
  end

  it "disables thinking when max_tokens cannot fit the minimum budget" do
    config = configure(effort: "low", max_tokens: 1000)
    expect(config[:thinking_enabled]).to be false
    expect(config[:budget_tokens]).to be_nil
  end

  it "keeps normal budgets untouched above the floor" do
    config = configure(effort: "medium", max_tokens: 8000)
    expect(config[:budget_tokens]).to eq((8000 * 0.7).to_i)
  end

  it "maps xhigh/max to the deepest non-adaptive tier, not the low-equivalent else arm" do
    high  = configure(effort: "high",  max_tokens: 100_000)[:budget_tokens]
    xhigh = configure(effort: "xhigh", max_tokens: 100_000)[:budget_tokens]
    max   = configure(effort: "max",   max_tokens: 100_000)[:budget_tokens]
    expect(xhigh).to eq(high)
    expect(max).to eq(high)
    expect(xhigh).to be > configure(effort: "medium", max_tokens: 100_000)[:budget_tokens]
  end
end
