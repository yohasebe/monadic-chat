# frozen_string_literal: true

require 'spec_helper'

# send_query without a model must use the provider default from the SSOT,
# as the other vendor helpers do, instead of sending a null model.
RSpec.describe 'OllamaHelper#send_query default model' do
  let(:helper) { Class.new { include OllamaHelper }.new }

  def capture_body(options = { 'messages' => [{ 'role' => 'user', 'content' => 'hi' }] }, **kwargs)
    captured = nil
    response = double('res', status: double('status', success?: true),
                             body: JSON.generate('message' => { 'content' => 'ok' }))
    http = double('http')
    allow(http).to receive(:timeout).and_return(http)
    allow(http).to receive(:post) { |_uri, json:| captured = json; response }
    allow(HTTP).to receive(:headers).and_return(http)
    allow(OllamaHelper).to receive(:find_endpoint).and_return('http://localhost:11434/api')
    helper.send_query(options, **kwargs)
    captured
  end

  before do
    allow(SystemDefaults).to receive(:get_default_model).with('ollama').and_return('ssot-default-model')
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

  it 'keeps a model given in the options' do
    opts = { 'model' => 'option-model', 'messages' => [] }
    expect(capture_body(opts)['model']).to eq('option-model')
  end
end
