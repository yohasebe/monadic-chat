# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/utils/extra_logger'
require 'monadic/utils/model_spec'
require_relative '../../../../lib/monadic/utils/websocket'
require 'monadic/utils/websocket/sts_stream_handler'
require 'monadic/utils/container_dependencies'

RSpec.describe 'Live Conversation library_search tool' do
  let(:entry) { WebSocketHelper::STS_TOOLS.fetch('library_search') }
  let(:deps) { Monadic::Utils::ContainerDependencies }

  it 'is offered only when both Qdrant and the embeddings service are running' do
    allow(deps).to receive(:container_running?).with(:qdrant).and_return(true)
    allow(deps).to receive(:container_running?).with(:embeddings).and_return(false)
    expect(entry[:available?].call('openai', {})).to be false

    allow(deps).to receive(:container_running?).with(:embeddings).and_return(true)
    expect(entry[:available?].call('openai', {})).to be true
  end

  it 'runs the shared search with the toggle turned on and the app name kept' do
    hit = { 'text' => 'passage', 'title' => 'Doc', 'score' => 0.9 }
    captured = nil
    allow(MonadicSharedTools::LibrarySearch).to receive(:default_store).and_return(double('store'))
    allow(Monadic::Library::Retriever).to receive(:cascade_search) do |query, **kw|
      captured = [query, kw]
      [hit]
    end
    allow(MonadicSharedTools::LibrarySearch).to receive(:format_results).and_return('formatted')
    allow(MonadicSharedTools::LibrarySearch).to receive(:apply_privacy) { |out, _s| out }

    session = { parameters: { 'app_name' => 'LiveConversationOpenAI' } }
    result = entry[:call].call({ 'query' => 'apples', 'top_n' => 2 }, session)

    expect(result).to eq('formatted')
    expect(captured[0]).to eq('apples')
    expect(captured[1][:top_n]).to eq(2)
  end
end
