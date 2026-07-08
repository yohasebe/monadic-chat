# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/mistral_helper'

# Relay-fidelity: Mistral "thinks out loud" before calling a tool, often
# emitting a training-data guess. That pre-tool text used to be prepended
# unconditionally to the final answer, gluing a stale guess in front of a
# tool-grounded result (e.g. "Ruby 3.4.1" ahead of a fresh "4.0.5"). The
# helper now keeps pre-tool content only as a fallback for an empty post-tool
# answer, and always clears it so it never bleeds into a later turn.
RSpec.describe 'MistralHelper relay fidelity (pre-tool content prepend)' do
  subject(:helper) do
    Class.new do
      include MistralHelper
    end.new
  end

  let(:obj) { { "model" => "mistral-medium-latest" } }

  def build(content_buffer:, session:)
    helper.send(
      :build_mistral_text_response,
      content_buffer, [], obj, session, "stop", nil, nil, nil
    )
  end

  it 'does not prepend the stale pre-tool guess to a real post-tool answer' do
    session = { messages: [], mistral_pre_tool_content: "The latest Ruby version is 3.4.1." }
    resp = build(content_buffer: "The latest Ruby version is 4.0.5.", session: session)
    content = resp[0]["choices"][0]["message"]["content"]
    expect(content).to eq("The latest Ruby version is 4.0.5.")
    expect(content).not_to include("3.4.1")
    expect(session[:mistral_pre_tool_content]).to be_nil
  end

  it 'falls back to pre-tool content only when the post-tool answer is empty' do
    session = { messages: [], mistral_pre_tool_content: "Partial answer before the tool ran." }
    resp = build(content_buffer: "", session: session)
    expect(resp[0]["choices"][0]["message"]["content"]).to eq("Partial answer before the tool ran.")
    expect(session[:mistral_pre_tool_content]).to be_nil
  end

  it 'leaves a normal answer untouched when there is no pre-tool content' do
    session = { messages: [] }
    resp = build(content_buffer: "A direct answer.", session: session)
    expect(resp[0]["choices"][0]["message"]["content"]).to eq("A direct answer.")
  end
end
