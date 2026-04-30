# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require 'monadic/shared_tools/library_search'

RSpec.describe MonadicSharedTools::LibrarySearch do
  let(:store) { instance_double(Monadic::Library::Store) }

  before do
    allow(described_class).to receive(:default_store).and_return(store)
    allow(store).to receive(:embeddings)
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
    }
  end

  describe '.format_results' do
    it 'returns a no-result notice when hits is empty' do
      msg = described_class.format_results('alpha', [])
      expect(msg).to include('No matching passages')
      expect(msg).to include('"alpha"')
    end

    it 'renders each hit with citation, score, and snippet' do
      hits = [
        {
          text: 'The first relevant passage that the search returned.',
          conversation_id: 'conv-1', turn_idx: 4, speaker_role: 'narrator',
          start_message_id: 'm-1-4', score: 0.876,
          conversation_title: 'My TED Talk', conversation_source: 'ted-talk',
          conversation_language: 'en'
        },
        {
          text: 'A second hit, ranked lower.',
          conversation_id: 'conv-2', turn_idx: 0, speaker_role: 'human',
          start_message_id: 'm-2-0', score: 0.701,
          conversation_title: nil, conversation_source: 'monadic-chat',
          conversation_language: 'en'
        }
      ]
      out = described_class.format_results('q', hits)
      expect(out).to include('Found 2 relevant passages')
      expect(out).to include('From "My TED Talk" (ted-talk, conversation_id: conv-1)')
      expect(out).to include('score=0.876')
      expect(out).to include('From "(untitled)" (monadic-chat, conversation_id: conv-2)')
    end

    it 'truncates very long snippets to 480 chars with an ellipsis' do
      long_text = 'x' * 1000
      hits = [{
        text: long_text, conversation_id: 'c', turn_idx: 0, speaker_role: 'human',
        start_message_id: 'm', score: 0.5, conversation_title: 't',
        conversation_source: 's', conversation_language: 'en'
      }]
      out = described_class.format_results('q', hits)
      expect(out).to include('…')
      expect(out.lines.find { |l| l.include?('xxx') }.length).to be < 600
    end
  end

  describe '.available?' do
    let(:embeddings) { instance_double(Monadic::Embeddings::Client) }

    it 'is true when the embeddings service responds healthy' do
      allow(Monadic::Embeddings).to receive(:default_client).and_return(embeddings)
      allow(embeddings).to receive(:respond_to?).with(:health).and_return(true)
      allow(embeddings).to receive(:health).and_return(true)
      expect(described_class.available?).to be true
    end

    it 'is false when health probe raises' do
      allow(Monadic::Embeddings).to receive(:default_client).and_return(embeddings)
      allow(embeddings).to receive(:respond_to?).with(:health).and_return(true)
      allow(embeddings).to receive(:health).and_raise(StandardError, 'down')
      expect(described_class.available?).to be false
    end

    it 'is false when health returns false' do
      allow(Monadic::Embeddings).to receive(:default_client).and_return(embeddings)
      allow(embeddings).to receive(:respond_to?).with(:health).and_return(true)
      allow(embeddings).to receive(:health).and_return(false)
      expect(described_class.available?).to be false
    end
  end

  describe MonadicSharedTools::LibrarySearch::Tools do
    let(:host) do
      Class.new { include MonadicSharedTools::LibrarySearch::Tools }.new
    end

    before do
      allow(Monadic::Library::Retriever).to receive(:cascade_search)
        .and_return([
          {
            text: 'returned snippet', conversation_id: 'conv-1', turn_idx: 0,
            speaker_role: 'human', start_message_id: 'm-1', score: 0.9,
            conversation_title: 'T', conversation_source: 'ted-talk',
            conversation_language: 'en'
          }
        ])
    end

    it 'invokes Retriever with scope :external and returns formatted text' do
      canned = [{
        text: 'returned snippet', conversation_id: 'conv-1', turn_idx: 0,
        speaker_role: 'human', start_message_id: 'm-1', score: 0.9,
        conversation_title: 'T', conversation_source: 'ted-talk',
        conversation_language: 'en'
      }]
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with('how it works', hash_including(scope: :external, top_n: 3))
        .and_return(canned)
      out = host.library_search(query: 'how it works')
      expect(out).to include('Found 1 relevant passage')
      expect(out).to include('returned snippet')
    end

    it 'clamps top_n into [1, 10]' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with(anything, hash_including(top_n: 10))
      host.library_search(query: 'q', top_n: 99)
    end

    it 'returns a graceful error message when Retriever raises' do
      allow(Monadic::Library::Retriever).to receive(:cascade_search).and_raise(StandardError, 'boom')
      out = host.library_search(query: 'q')
      expect(out).to start_with('❌ Knowledge Base search failed')
      expect(out).to include('boom')
    end
  end

  describe 'Registry registration' do
    it 'registers :library_search as a conditional tool group' do
      group = MonadicSharedTools::Registry::TOOL_GROUPS[:library_search]
      expect(group).not_to be_nil
      expect(group[:module_name]).to eq('MonadicSharedTools::LibrarySearch')
      expect(group[:visibility]).to eq('conditional')
      expect(group[:tools].first[:name]).to eq('library_search')
      expect(group[:tools].first[:parameters].map { |p| p[:name] })
        .to contain_exactly(:query, :top_n)
    end
  end
end
