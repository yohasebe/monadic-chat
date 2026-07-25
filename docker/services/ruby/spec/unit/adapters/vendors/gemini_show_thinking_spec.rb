# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

# The "Show Thinking" toggle sends params["show_thinking"]. For Gemini chat
# requests it must control thinkingConfig.includeThoughts so the model's
# reasoning summary is (or is not) streamed back and rendered. The default is
# on; only an explicit false disables it. send_query (agent) paths intentionally
# never request thoughts and are not covered here.
RSpec.describe 'Gemini Show Thinking wiring' do
  let(:helper) { Class.new { include GeminiHelper }.new }

  # thinking_level branch (Gemini 3 reasoning models such as gemini-3.6-flash)
  def include_thoughts_for(show_thinking, model_name: 'gemini-3.6-flash')
    obj = { 'model' => model_name }
    obj['show_thinking'] = show_thinking unless show_thinking == :unset
    body = helper.send(:build_gemini_request_body,
                       obj: obj,
                       model_name: model_name,
                       session: { parameters: {} },
                       context: [],
                       temperature: nil,
                       max_tokens: 1000,
                       is_thinking_model: true,
                       thinking_level: 'low',
                       reasoning_effort: nil,
                       tool_capable: false,
                       system_message: nil)
    body.dig('generationConfig', 'thinkingConfig', 'includeThoughts')
  end

  it 'requests thoughts by default (toggle unset)' do
    expect(include_thoughts_for(:unset)).to be true
  end

  it 'requests thoughts when show_thinking is true' do
    expect(include_thoughts_for(true)).to be true
  end

  it 'omits thoughts when show_thinking is boolean false' do
    expect(include_thoughts_for(false)).to be false
  end

  it 'omits thoughts when show_thinking is the string "false"' do
    expect(include_thoughts_for('false')).to be false
  end

  it 'still sends a positive thinking budget (thinkingBudget:0 is rejected by the API)' do
    obj = { 'model' => 'gemini-3.6-flash', 'show_thinking' => false }
    body = helper.send(:build_gemini_request_body,
                       obj: obj, model_name: 'gemini-3.6-flash',
                       session: { parameters: {} }, context: [],
                       temperature: nil, max_tokens: 1000,
                       is_thinking_model: true, thinking_level: 'low',
                       reasoning_effort: nil, tool_capable: false, system_message: nil)
    expect(body.dig('generationConfig', 'thinkingConfig', 'thinkingBudget')).to be > 0
  end
end
