# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# The advisor tool is sent only with an advisor the executor accepts
# (model_spec.js advisor_models); without the list it is sent as configured.
RSpec.describe 'Claude advisor pairing' do
  let(:helper) { Class.new { include ClaudeHelper }.new }
  let(:app) { 'SpecAdvisorApp' }

  before do
    stub_const('APPS', { app => Struct.new(:settings).new({ advisor_tool: { model: 'spec-advisor' } }) })
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
      .with('spec-strict-executor', 'advisor_models').and_return(%w[spec-other-advisor])
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
      .with('spec-open-executor', 'advisor_models').and_return(nil)
  end

  def advisor_tools(model)
    body = { 'model' => model }
    helper.send(:add_claude_advisor_tool, body, app)
    Array(body['tools']).select { |t| t['type'] == 'advisor_20260301' }
  end

  it 'leaves the tool out when the executor does not accept the advisor' do
    expect(advisor_tools('spec-strict-executor')).to be_empty
  end

  it 'sends the configured advisor when the executor lists no advisors' do
    expect(advisor_tools('spec-open-executor').map { |t| t['model'] }).to eq(['spec-advisor'])
  end

  def system_after(model)
    body = { 'model' => model, 'system' => [{ type: 'text', text: 'You have access to an `advisor` tool.' }] }
    2.times { helper.send(:add_claude_advisor_tool, body, app) }
    body['system'].map { |block| block[:text] }
  end

  it 'tells the model once that the advisor is not there when the tool is left out' do
    expect(system_after('spec-strict-executor')).to eq(['You have access to an `advisor` tool.', ClaudeHelper::ADVISOR_UNAVAILABLE])
  end

  it 'adds nothing to the prompt when the tool is sent' do
    expect(system_after('spec-open-executor')).to eq(['You have access to an `advisor` tool.'])
  end
end
