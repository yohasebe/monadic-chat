# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"

# Text DeepSeek writes before a tool call, in thinking mode: every message of
# the model's after the user's last one goes back with its reasoning.
RSpec.describe "DeepSeek text before a tool call" do
  let(:helper) do
    Class.new { include DeepSeekHelper }.new.tap do |h|
      allow(h).to receive(:deepseek_thinking_on?).and_return(true)
      allow(h).to receive(:markdown_to_html) { |text, **| text }
      allow(h).to receive(:detect_language).and_return("en")
    end
  end
  let(:call) { { "id" => "c1", "type" => "function", "function" => { "name" => "some_tool", "arguments" => "{}" } } }
  let(:tools) { { "call_0" => { "choices" => [{ "message" => { "tool_calls" => [call] } }] } } }
  let(:reply) { { "choices" => [{ "message" => { "content" => "I will draw it.", "reasoning_content" => "They want a graph." } }] } }
  let(:session) do
    { parameters: { "app_name" => "SpecApp", "model" => "m", "context_size" => "10" }, call_depth_per_turn: 0,
      messages: [{ "role" => "system", "text" => "S" }, { "role" => "user", "text" => "Draw", "mid" => "u1" }] }
  end

  def dispatch(text_result)
    given = nil
    allow(helper).to receive(:process_functions) { |_app, _session, _tools, context, _depth| given = context.dup }
    helper.send(:dispatch_deepseek_tool_results, tools, text_result, "tool_calls", session[:parameters], session, "SpecApp", 0) { |_| }
    given
  end

  it "puts the text, its reasoning and the call in one message, and keeps the text with its reasoning" do
    expect(dispatch(reply)).to eq([{ "role" => "assistant", "content" => "I will draw it.", "tool_calls" => [call],
                                    "reasoning_content" => "They want a graph." }])
    kept = session[:messages].last
    expect(kept).to include("role" => "assistant", "text" => "I will draw it.", "reasoning_content" => "They want a graph.")
    expect(session[:deepseek_round_text_mids]).to eq([kept["mid"]])
  end

  it "sends a call with no text before it as it did" do
    only_reasoning = { "choices" => [{ "message" => { "content" => "", "reasoning_content" => "Thinking." } }] }
    expect(dispatch(only_reasoning)).to eq([{ "role" => "assistant", "content" => nil, "tool_calls" => [call],
                                             "reasoning_content" => "Thinking." }])
    expect(session[:messages].size).to eq(2)
    expect(session[:deepseek_round_text_mids]).to be_nil
  end

  describe "the requests after the round" do
    let(:sent) { [] }

    before do
      stub_const("APPS", { "SpecApp" => double("app", settings: {}) })
      stub_const("CONFIG", { "DEEPSEEK_API_KEY" => "k" })
      allow(helper).to receive(:sleep)
      allow(helper).to receive(:configure_deepseek_tools)
      allow(helper).to receive(:configure_deepseek_reasoning)
      allow(helper).to receive(:observation_for).and_return(nil)
      allow(helper).to receive(:strip_inactive_image_data)
      allow(helper).to receive(:with_workbench_looks) { |returns, *_rest, **_kw| returns }
      allow(helper).to receive(:execute_deepseek_api_call) do |_headers, body, *_rest|
        sent << body["messages"]
        [{ "choices" => [{ "message" => { "content" => "Done" } }] }]
      end
      allow(Monadic::Utils::SystemPromptInjector).to receive(:augment) { |base_prompt:, **| base_prompt }
      dispatch(reply)
      session[:parameters]["function_returns"] = [
        { "role" => "assistant", "content" => "I will draw it.", "tool_calls" => [call], "reasoning_content" => "They want a graph." },
        { "role" => "tool", "tool_call_id" => "c1", "content" => "drawn" }
      ]
    end

    def roles_and_reasoning(messages)
      messages.map { |m| [m["role"], m["content"], m["reasoning_content"]] }
    end

    it "sends the round's text once, with the call" do
      helper.api_request("tool", session, call_depth: 1) { |_| }
      expect(roles_and_reasoning(sent.last)).to eq([["system", "S", nil], ["user", "Draw", nil],
                                                    ["assistant", "I will draw it.", "They want a graph."],
                                                    ["tool", "drawn", nil]])
      expect(sent.last[2]["tool_calls"]).to eq([call])
    end

    it "sends the turn's earlier rounds before a new round's call" do
      second = { "id" => "c2", "type" => "function", "function" => { "name" => "other_tool", "arguments" => "{}" } }
      later = { "call_0" => { "choices" => [{ "message" => { "tool_calls" => [second] } }] } }
      given = nil
      allow(helper).to receive(:process_functions) { |_app, _session, _tools, context, _depth| given = context.dup }
      helper.send(:dispatch_deepseek_tool_results, later, { "choices" => [{ "message" => { "content" => "" } }] },
                  "tool_calls", session[:parameters], session, "SpecApp", 1) { |_| }
      expect(given.map { |m| [m["role"], m["tool_call_id"] || m["tool_calls"]&.first&.dig("id")] })
        .to eq([%w[assistant c1], %w[tool c1], %w[assistant c2]])
    end

    it "starts a new turn without the rounds of the turn before" do
      helper.api_request("user", session, call_depth: 0) { |_| }
      expect(session[:parameters]).not_to have_key("function_returns")
      expect(session[:deepseek_round_text_mids]).to be_nil
      expect(sent.last.map { |m| m["role"] }).to eq(%w[system user assistant])
      expect(sent.last.last).to include("content" => "I will draw it.", "reasoning_content" => "They want a graph.")
      expect(sent.last.last).not_to have_key("tool_calls")
    end
  end
end
