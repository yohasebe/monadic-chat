# frozen_string_literal: true

require 'spec_helper'

# send_query without a model must use the provider default from the SSOT,
# as the other vendor helpers do, instead of a model written in the helper.
RSpec.describe 'DeepSeekHelper#send_query default model' do
  let(:helper) { Class.new { include DeepSeekHelper }.new }

  def capture_body(**kwargs)
    captured = nil
    status = double('status', success?: true, code: 200)
    res = double('res', status: status,
                        body: JSON.generate('choices' => [{ 'message' => { 'content' => 'ok' } }]))
    allow(HTTP).to receive(:headers).and_return(double('http'))
    allow(helper).to receive(:post_json_with_retries) { |_h, _u, body, **| captured = body; res }
    stub_const('CONFIG', CONFIG.merge('DEEPSEEK_API_KEY' => 'test-key'))
    helper.send_query({ 'messages' => [{ 'role' => 'user', 'content' => 'hi' }] }, **kwargs)
    captured
  end

  before do
    allow(SystemDefaults).to receive(:get_default_model).with('deepseek').and_return('ssot-default-model')
  end

  it 'uses the SSOT default when no model is given' do
    expect(capture_body['model']).to eq('ssot-default-model')
  end

  it 'uses the SSOT default when the model is nil or blank' do
    expect(capture_body(model: nil)['model']).to eq('ssot-default-model')
    expect(capture_body(model: ' ')['model']).to eq('ssot-default-model')
  end

  it 'keeps a model that is given' do
    expect(capture_body(model: 'chosen-model')['model']).to eq('chosen-model')
  end
end
