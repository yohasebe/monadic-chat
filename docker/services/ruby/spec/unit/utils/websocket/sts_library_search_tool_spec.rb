# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'securerandom'
require 'monadic/utils/extra_logger'
require 'monadic/utils/model_spec'
require_relative '../../../../lib/monadic/utils/websocket'
require 'monadic/utils/websocket/sts_stream_handler'
require 'monadic/utils/container_dependencies'

RSpec.describe "Live Conversation's Library tools" do
  let(:entry) { WebSocketHelper::STS_TOOLS.fetch('library_search') }
  let(:deps) { Monadic::Utils::ContainerDependencies }

  it 'is offered only when both Qdrant and the embeddings service are running' do
    allow(deps).to receive(:container_running?).with(:qdrant).and_return(true)
    allow(deps).to receive(:container_running?).with(:embeddings).and_return(false)
    expect(entry[:available?].call('openai', {})).to be false

    allow(deps).to receive(:container_running?).with(:embeddings).and_return(true)
    expect(entry[:available?].call('openai', {})).to be true
  end

  it 'offers neither tool while the setting is off, though the session carries the old switch on and the services run' do
    stub_const('CONFIG', { 'LIBRARY_IN_CHATS' => 'false' })
    allow(deps).to receive(:container_running?).and_return(true)
    session = { parameters: { 'library_rag_enabled' => true } }

    %w[library_search library_list].each do |name|
      expect(WebSocketHelper::STS_TOOLS.fetch(name)[:available?].call('openai', session)).to be false
    end
    expect(Monadic::Library::Retriever).not_to receive(:cascade_search)
    expect(Monadic::Library::Manager).not_to receive(:list_conversations)
    expect(entry[:call].call({ 'query' => 'q' }, session, {})).to eq(MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE)
    expect(WebSocketHelper::STS_TOOLS.fetch('library_list')[:call].call({}, session, {}))
      .to eq(MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE)
  end

  it 'lists the Library through the shared list' do
    allow(MonadicSharedTools::LibrarySearch).to receive(:list_text).with(2).and_return('page two')
    expect(WebSocketHelper::STS_TOOLS.fetch('library_list')[:call].call({ 'page' => 2 }, {}, {})).to eq('page two')
  end

  it 'records what it reads, so it takes the turn as a writer of the work screen' do
    expect(entry[:records]).to be true
  end

  it 'runs the shared search for the turn it records the search for' do
    hit = { text: 'passage', conversation_id: 'conv-1', conversation_title: 'Doc', score: 0.9 }
    captured = nil
    allow(MonadicSharedTools::LibrarySearch).to receive(:default_store).and_return(double('store'))
    allow(Monadic::Library::Retriever).to receive(:cascade_search) do |query, **kw|
      captured = [query, kw]
      [hit]
    end
    allow(Monadic::Workbench::Put).to receive(:run).and_return(path: 'conversations/c/workbench/library.md', shown: true)
    allow(Monadic::Workbench::Channel).to receive(:changed)
    request_id = "q_#{SecureRandom.hex(8)}"
    workbench = Monadic::Workbench::Caller.new(chat_id: 'chat-1', epoch: 1, request_id: request_id, session: {},
                                               tab: 't', generation: 1)

    session = { parameters: { 'app_name' => 'LiveConversationOpenAI' } }
    result = entry[:call].call({ 'query' => 'apples', 'top_n' => 2 }, session, { workbench: workbench })

    expect(result).to include('passage')
    expect(captured[0]).to eq('apples')
    expect(captured[1][:top_n]).to eq(2)
    expect(Monadic::Library::Readings.take(request_id)[:records].first['query']).to eq('apples')
  end
end
