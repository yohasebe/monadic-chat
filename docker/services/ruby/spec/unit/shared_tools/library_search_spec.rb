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

    it 'renders each hit with a markdown link citation, score, and snippet' do
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
      # Citations use markdown links with the in-app `mc:conv:` URL
      # scheme so frontend click intercept can open the Viewer modal.
      expect(out).to include('From [My TED Talk](mc:conv:conv-1) (ted-talk)')
      expect(out).to include('score=0.876')
      expect(out).to include('From [(untitled)](mc:conv:conv-2) (monadic-chat)')
      # The trailing instruction tells the LLM to keep the links intact
      # when summarising — required so RAG citations stay clickable.
      expect(out).to match(/keep the markdown links/i)
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

  describe '.session_enabled?' do
    it 'is true when the parameter flag is truthy' do
      session = { parameters: { 'library_rag_enabled' => true } }
      expect(described_class.session_enabled?(session)).to be true
    end

    it 'accepts string-keyed parameters too' do
      session = { 'parameters' => { 'library_rag_enabled' => true } }
      expect(described_class.session_enabled?(session)).to be true
    end

    it 'is false when the flag is missing' do
      session = { parameters: {} }
      expect(described_class.session_enabled?(session)).to be false
    end

    it 'is false on a nil session (early-boot or unauthenticated)' do
      expect(described_class.session_enabled?(nil)).to be false
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
      # Inject a session with the per-session RAG toggle ON. Without
      # this, library_search returns the disabled-toggle message early
      # and the Retriever stub never runs.
      host.instance_variable_set(:@session, { parameters: { 'library_rag_enabled' => true } })
    end

    it 'invokes Retriever with the resolved app_name and returns formatted text' do
      canned = [{
        text: 'returned snippet', conversation_id: 'conv-1', turn_idx: 0,
        speaker_role: 'human', start_message_id: 'm-1', score: 0.9,
        conversation_title: 'T', conversation_source: 'ted-talk',
        conversation_language: 'en'
      }]
      host.instance_variable_set(:@session, {
        parameters: { 'library_rag_enabled' => true, 'app_name' => 'ChatOpenAI' }
      })
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with('how it works', hash_including(app_name: 'ChatOpenAI', top_n: 3))
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

    it 'short-circuits with the disabled-toggle message when the session flag is OFF' do
      host.instance_variable_set(:@session, { parameters: { 'library_rag_enabled' => false } })
      expect(Monadic::Library::Retriever).not_to receive(:cascade_search)
      out = host.library_search(query: 'q')
      expect(out).to eq(MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE)
    end

    it 'falls back to Thread.current[:session] when @session is nil' do
      host.instance_variable_set(:@session, nil)
      Thread.current[:session] = { parameters: { 'library_rag_enabled' => true } }
      begin
        expect(Monadic::Library::Retriever).to receive(:cascade_search).and_return([])
        host.library_search(query: 'q')
      ensure
        Thread.current[:session] = nil
      end
    end

    it 'accepts session: kwarg auto-injected by the vendor dispatcher' do
      # The vendor tool dispatcher inspects the method signature for a
      # :session parameter and auto-injects argument_hash[:session].
      # Without this kwarg the gate would always read nil even after the
      # UI toggle has been flipped on. Regression guard.
      host.instance_variable_set(:@session, nil)
      injected = { parameters: { 'library_rag_enabled' => true } }
      expect(Monadic::Library::Retriever).to receive(:cascade_search).and_return([])
      host.library_search(query: 'q', session: injected)
    end

    it 'declares :session in the method signature so dispatchers inject it' do
      params = MonadicSharedTools::LibrarySearch::Tools.instance_method(:library_search).parameters
      expect(params.map(&:last)).to include(:session)
    end

    it 'masks PII in the formatted result when Privacy Filter is active' do
      # Knowledge Base entries are stored unmasked. When PF is on, the
      # tool result must pass through the same Privacy Pipeline that
      # masks user-role messages so library_search cannot become a
      # back-channel that leaks PII to the LLM.
      pipeline = double('pipeline', enabled?: true)
      expect(pipeline).to receive(:before_send_to_llm) do |raw|
        # Sanity: the snippet text reaches the pipeline as a tool-role
        # message so backends can route it correctly.
        expect(raw.role).to eq('tool')
        expect(raw.text).to include('returned snippet')
        Monadic::Utils::Privacy::MaskedMessage.new('MASKED RESULT', 'tool', {})
      end
      host.instance_variable_set(:@session, {
        parameters: { 'library_rag_enabled' => true, 'app_name' => 'ChatOpenAI' },
        _privacy_pipeline: pipeline
      })
      out = host.library_search(query: 'q')
      expect(out).to eq('MASKED RESULT')
    end

    it 'returns the formatted result unchanged when Privacy Filter is inactive' do
      pipeline = double('pipeline', enabled?: false)
      expect(pipeline).not_to receive(:before_send_to_llm)
      host.instance_variable_set(:@session, {
        parameters: { 'library_rag_enabled' => true },
        _privacy_pipeline: pipeline
      })
      out = host.library_search(query: 'q')
      expect(out).to include('Found 1 relevant passage')
    end

    it 'falls back to raw output when the privacy pipeline raises' do
      pipeline = double('pipeline', enabled?: true)
      allow(pipeline).to receive(:before_send_to_llm).and_raise(StandardError, 'boom')
      host.instance_variable_set(:@session, {
        parameters: { 'library_rag_enabled' => true },
        _privacy_pipeline: pipeline
      })
      out = host.library_search(query: 'q')
      expect(out).to include('Found 1 relevant passage')
    end
  end

  describe 'Registry registration' do
    it 'registers :library_search pointing to the Tools mixin module' do
      group = MonadicSharedTools::Registry::TOOL_GROUPS[:library_search]
      expect(group).not_to be_nil
      expect(group[:module_name]).to eq('MonadicSharedTools::LibrarySearch::Tools')
      expect(group[:visibility]).to eq('conditional')
      expect(group[:tools].first[:name]).to eq('library_search')
      expect(group[:tools].first[:parameters].map { |p| p[:name] })
        .to contain_exactly(:query, :top_n, :content_type, :source)
    end
  end

  describe '.build_payload_filter' do
    it 'returns nil when neither content_type nor source is provided' do
      expect(MonadicSharedTools::LibrarySearch.build_payload_filter).to be_nil
    end

    it 'normalises blank values to nil so an empty string does not collapse the result set' do
      expect(MonadicSharedTools::LibrarySearch.build_payload_filter(content_type: '', source: '   ')).to be_nil
    end

    it 'builds a content_type-only filter' do
      filter = MonadicSharedTools::LibrarySearch.build_payload_filter(content_type: 'pdf')
      expect(filter).to eq({ must: [{ key: 'content_type', match: { value: 'pdf' } }] })
    end

    it 'builds a source-only filter' do
      filter = MonadicSharedTools::LibrarySearch.build_payload_filter(source: 'monadic-chat')
      expect(filter).to eq({ must: [{ key: 'source', match: { value: 'monadic-chat' } }] })
    end

    it 'AND-combines content_type and source clauses' do
      filter = MonadicSharedTools::LibrarySearch.build_payload_filter(
        content_type: 'conversation', source: 'ted-talk'
      )
      expect(filter).to eq({
        must: [
          { key: 'content_type', match: { value: 'conversation' } },
          { key: 'source', match: { value: 'ted-talk' } }
        ]
      })
    end
  end

  describe 'library_search filter pass-through' do
    let(:host) do
      Class.new { include MonadicSharedTools::LibrarySearch::Tools }.new
    end

    before do
      host.instance_variable_set(:@session, { parameters: { 'library_rag_enabled' => true } })
    end

    it 'forwards a content_type filter to Retriever.cascade_search' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to eq({ must: [{ key: 'content_type', match: { value: 'pdf' } }] })
        []
      end
      host.library_search(query: 'q', content_type: 'pdf')
    end

    it 'forwards a source filter to Retriever.cascade_search' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to eq({ must: [{ key: 'source', match: { value: 'monadic-chat' } }] })
        []
      end
      host.library_search(query: 'q', source: 'monadic-chat')
    end

    it 'omits payload_filter (nil) when neither narrowing param is given' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to be_nil
        []
      end
      host.library_search(query: 'q')
    end
  end
end
