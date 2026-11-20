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

RSpec.describe 'OllamaHelper#send_query output limit' do
  let(:helper) { Class.new { include OllamaHelper }.new }

  def capture_body(options)
    captured = nil
    response = double('res', status: double('status', success?: true),
                             body: JSON.generate('message' => { 'content' => 'ok' }))
    http = double('http')
    allow(http).to receive(:timeout).and_return(http)
    allow(http).to receive(:post) { |_uri, json:| captured = json; response }
    allow(HTTP).to receive(:headers).and_return(http)
    allow(OllamaHelper).to receive(:find_endpoint).and_return('http://localhost:11434/api')
    helper.send_query(options, model: 'local-model')
    captured
  end

  it 'sends the output limit as options.num_predict' do
    body = capture_body('messages' => [], 'max_tokens' => 800, 'max_completion_tokens' => 800)
    expect(body['options']).to eq('num_predict' => 800)
    expect(body).not_to include('max_tokens', 'max_completion_tokens')
  end

  it 'keeps the options given with it' do
    body = capture_body('messages' => [], 'max_tokens' => 100, 'options' => { 'temperature' => 0.2 })
    expect(body['options']).to eq('num_predict' => 100, 'temperature' => 0.2)
  end

  it 'adds no options without a limit' do
    expect(capture_body('messages' => [])).not_to have_key('options')
  end
end
