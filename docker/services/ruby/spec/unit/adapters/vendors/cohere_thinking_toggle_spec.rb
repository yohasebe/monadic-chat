# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/cohere_helper'

# Some Cohere reasoning models (e.g. command-a-plus) do not emit
# content.thinking deltas; their reasoning arrives as tool_plan on tool
# rounds. That path used to be dropped from the final message, so the
# persistent thinking toggle disappeared whenever tools were involved. The
# helper now accumulates tool_plan across rounds (session key
# :cohere_tool_plan_reasoning) and uses it as a fallback for message["thinking"]
# when content.thinking is empty.
RSpec.describe 'CohereHelper thinking toggle persistence' do
  subject(:helper) do
    Class.new do
      include CohereHelper
    end.new
  end

  def build(thinking_content:, session:)
    helper.send(
      :build_cohere_text_response,
      result: "The latest version is 4.0.5.",
      obj: { "model" => "command-a-plus" },
      finish_reason: "complete",
      thinking_content: thinking_content,
      fragment_sequence: 0,
      usage_input_tokens: nil,
      usage_output_tokens: nil,
      usage_total_tokens: nil,
      session: session
    )
  end

  it 'surfaces accumulated tool_plan as thinking when content.thinking is empty' do
    session = { cohere_tool_plan_reasoning: "I should search the web for the latest release." }
    resp = build(thinking_content: [], session: session)
    expect(resp[0]["choices"][0]["message"]["thinking"]).to include("search the web")
  end

  it 'prefers content.thinking over tool_plan when both are present' do
    session = { cohere_tool_plan_reasoning: "internal tool plan" }
    resp = build(thinking_content: ["genuine reasoning trace"], session: session)
    expect(resp[0]["choices"][0]["message"]["thinking"]).to eq("genuine reasoning trace")
  end

  it 'sets no thinking key when neither source has content' do
    resp = build(thinking_content: [], session: {})
    expect(resp[0]["choices"][0]["message"]).not_to have_key("thinking")
  end

  # command-a-plus (a reasoning model) returns 422 INVALID_TOOL_GENERATION when
  # `thinking: {type: "disabled"}` is sent alongside tools. Verified live:
  # dropping the thinking key (Cohere default) succeeds.
  describe '#drop_incompatible_thinking! (422 guard)' do
    let(:tools) { [{ "type" => "function", "function" => { "name" => "request_tool" } }] }

    it 'drops thinking:disabled when tools are present' do
      body = { "tools" => tools, "thinking" => { "type" => "disabled" } }
      helper.send(:drop_incompatible_thinking!, body)
      expect(body).not_to have_key("thinking")
    end

    it 'keeps thinking:disabled when there are no tools' do
      body = { "thinking" => { "type" => "disabled" } }
      helper.send(:drop_incompatible_thinking!, body)
      expect(body["thinking"]).to eq("type" => "disabled")
    end

    it 'leaves thinking:enabled untouched even with tools' do
      body = { "tools" => tools, "thinking" => { "type" => "enabled" } }
      helper.send(:drop_incompatible_thinking!, body)
      expect(body["thinking"]).to eq("type" => "enabled")
    end

    it 'is a no-op when there is no thinking key' do
      body = { "tools" => tools }
      expect { helper.send(:drop_incompatible_thinking!, body) }.not_to raise_error
      expect(body).not_to have_key("thinking")
    end
  end
end
