# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require 'monadic/shared_tools/library_search'

RSpec.describe MonadicSharedTools::LibrarySearch do
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:request_id) { "q_#{SecureRandom.hex(8)}" }
  let(:workbench) do
    Monadic::Workbench::Caller.new(chat_id: 'chat-1', epoch: 1, request_id: request_id, session: {}, tab: 't', generation: 1)
  end

  before do
    allow(Monadic::Workbench::Put).to receive(:run).and_return(path: 'conversations/c/workbench/library.md', shown: true)
    allow(Monadic::Workbench::Channel).to receive(:changed)
    allow(described_class).to receive(:default_store).and_return(store)
    allow(store).to receive(:embeddings)
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
    }
  end

  describe '.format_results' do
    it 'returns a no-result notice when hits is empty' do
      msg = described_class.format_results('alpha', [], described_class.reading_of('alpha', []))
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
      reading = described_class.reading_of('q', hits)
      out = described_class.format_results('q', hits, reading)
      expect(out).to include('Found 2 relevant passages')
      # Each passage is linked by its excerpt's id (mc:read:), so a reply
      # cites the very passage it was given.
      first, second = reading['excerpts'].map { |e| e['id'] }
      expect(out).to include("From [My TED Talk](mc:read:#{first}) (ted-talk)")
      expect(out).to include('score=0.876')
      expect(out).to include("From [(untitled)](mc:read:#{second}) (monadic-chat)")
      expect(out).not_to include('mc:conv:')
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
      out = described_class.format_results('q', hits, described_class.reading_of('q', hits))
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
    it 'follows the setting: on unless it is "false", whatever the session says' do
      stub_const('CONFIG', {})
      expect(described_class.session_enabled?({ parameters: {} })).to be true
      stub_const('CONFIG', { 'LIBRARY_IN_CHATS' => 'false' })
      expect(described_class.session_enabled?({ parameters: {} })).to be false
    end
  end

  describe '.list_text' do
    # The summaries as a store gives them, 256 a page in id order, with only
    # the fields asked for.
    def library_of(count)
      points = Array.new(count) do |i|
        { 'id' => i, 'payload' => { 'conversation_id' => format('c%04d', i), 'title' => "Entry #{i + 1}",
                                    'content_type' => 'pdf', 'source' => 'import', 'body' => 'x' * 10,
                                    'created_at' => format('2026-11-01T00:%02d:%02dZ', i / 60 % 60, i % 60) } }
      end
      allow(store).to receive(:scroll) do |limit:, offset:, with_payload:, **|
        start = offset || 0
        page = points[start, limit].map { |p| p.merge('payload' => p['payload'].slice(*with_payload)) }
        { points: page, next: start + limit < count ? start + limit : nil }
      end
    end

    it 'lists a page of titles, kinds, sources and dates, newest first, reading only those fields' do
      library_of(31)
      out = described_class.list_text(1)
      expect(out).to start_with('The Library holds 31 entries; page 1 of 2:')
      expect(out.lines[2]).to eq("- Entry 31 (pdf, import, 2026-11-01)\n")
      expect(described_class.list_text(2)).to include('- Entry 1 (pdf, import, 2026-11-01)')
      expect(store).to have_received(:scroll).with(hash_including(with_payload: Monadic::Library::Manager::ROW_FIELDS)).at_least(:once)
    end

    it 'counts and pages every entry of a Library past 500' do
      library_of(501)
      expect(described_class.list_text(1)).to start_with('The Library holds 501 entries; page 1 of 17:')
      expect(described_class.list_text(17).lines.count { |l| l.start_with?('- ') }).to eq(21)

      library_of(511)
      expect(described_class.list_text(18)).to include('page 18 of 18:', '- Entry 1 (')
      expect(described_class.list_text(19)).to start_with('No page 19: the Library holds 511 entries (18 pages).')
    end

    it 'says when the Library is empty' do
      library_of(0)
      expect(described_class.list_text(1)).to eq('The Library is empty.')
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
      host.instance_variable_set(:@session, { parameters: {} })
    end

    it 'invokes Retriever and returns formatted text' do
      canned = [{
        text: 'returned snippet', conversation_id: 'conv-1', turn_idx: 0,
        speaker_role: 'human', start_message_id: 'm-1', score: 0.9,
        conversation_title: 'T', conversation_source: 'ted-talk',
        conversation_language: 'en'
      }]
      host.instance_variable_set(:@session, {
        parameters: { 'app_name' => 'ChatOpenAI' }
      })
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with('how it works', hash_including(top_n: 3))
        .and_return(canned)
      out = host.library_search(query: 'how it works', workbench: workbench)
      expect(out).to include('Found 1 relevant passage')
      expect(out).to include('returned snippet')
    end

    it 'searches every entry, whatever app the session names' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with('q', hash_excluding(:app_name))
        .and_return([])
      host.library_search(query: 'q', workbench: workbench)
    end

    it 'clamps top_n into [1, 10]' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search)
        .with(anything, hash_including(top_n: 10))
      host.library_search(query: 'q', top_n: 99, workbench: workbench)
    end

    it 'returns a graceful error message when Retriever raises' do
      allow(Monadic::Library::Retriever).to receive(:cascade_search).and_raise(StandardError, 'boom')
      out = host.library_search(query: 'q', workbench: workbench)
      expect(out).to start_with('❌ Knowledge Base search failed')
      expect(out).to include('boom')
    end

    it 'says the Library is turned off, and neither searches nor lists, when the setting is off' do
      stub_const('CONFIG', { 'LIBRARY_IN_CHATS' => 'false' })
      expect(Monadic::Library::Retriever).not_to receive(:cascade_search)
      expect(Monadic::Library::Manager).not_to receive(:list_conversations)
      expect(host.library_search(query: 'q', workbench: workbench)).to eq(MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE)
      expect(host.library_list).to eq(MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE)
    end

    it 'falls back to Thread.current[:session] when @session is nil' do
      host.instance_variable_set(:@session, nil)
      Thread.current[:session] = { parameters: {} }
      begin
        expect(Monadic::Library::Retriever).to receive(:cascade_search).and_return([])
        host.library_search(query: 'q', workbench: workbench)
      ensure
        Thread.current[:session] = nil
      end
    end

    it 'accepts session: kwarg auto-injected by the vendor dispatcher' do
      # The vendor tool dispatcher inspects the method signature for a
      # :session parameter and auto-injects argument_hash[:session].
      host.instance_variable_set(:@session, nil)
      injected = { parameters: {} }
      expect(Monadic::Library::Retriever).to receive(:cascade_search).and_return([])
      host.library_search(query: 'q', session: injected, workbench: workbench)
    end

    it 'says the Library could not be listed when it cannot be reached, not that it is empty' do
      allow(Monadic::Library::Manager).to receive(:list_conversations).and_raise(Monadic::VectorStore::BackendError, 'down')
      expect(host.library_list).to eq('❌ The Library could not be listed: BackendError')
    end

    it 'declares :session in the method signature so dispatchers inject it' do
      params = MonadicSharedTools::LibrarySearch::Tools.instance_method(:library_search).parameters
      expect(params.map(&:last)).to include(:session)
    end
  end

  describe 'in a chat that hides its words with a word table' do
    let(:host) { Class.new { include MonadicSharedTools::LibrarySearch::Tools }.new }
    let(:words) { Monadic::Utils::Privacy::Words }
    let(:session) do
      { parameters: { 'app_name' => 'ChatOpenAI' } }
        .tap { |s| Monadic::Workspace::Chats.start_new!(s) }
    end

    before do
      words.start!(session).confirm!('Ada Lovelace', 'PERSON')
      allow(Monadic::Library::Retriever).to receive(:cascade_search).and_return([
        { text: 'Ada Lovelace wrote the notes', conversation_id: 'conv-1', turn_idx: 0, speaker_role: 'human',
          start_message_id: 'm-1', score: 0.9, conversation_title: 'T', conversation_source: 'chat',
          conversation_language: 'en' }
      ])
    end

    after { words::LOCK.synchronize { words::TABLES.clear } }

    it 'gives the passages as saved (they are hidden as the next request is sent)' do
      out = host.library_search(query: 'notes', session: session, workbench: workbench)
      expect(out).to include('Ada Lovelace wrote the notes')
    end
  end

  describe 'what is read is recorded and shown' do
    let(:host) { Class.new { include MonadicSharedTools::LibrarySearch::Tools }.new }
    let(:hit) do
      { text: "a   passage\nfrom the notes", conversation_id: 'conv-1', turn_idx: 2, speaker_role: 'human',
        start_message_id: 'm-1', score: 0.9, conversation_title: 'Notes', conversation_source: 'markdown:notes.md',
        conversation_language: 'en' }
    end

    before do
      host.instance_variable_set(:@session, { parameters: {} })
      allow(Monadic::Library::Retriever).to receive(:cascade_search).and_return([hit])
    end

    after { Monadic::Library::Readings.take(request_id) }

    it 'records the excerpts exactly as the model is given them, before giving them' do
      out = host.library_search(query: 'notes', workbench: workbench)
      record = Monadic::Library::Readings.take(request_id)[:records].first

      expect(record['query']).to eq('notes')
      excerpt = record['excerpts'].first
      expect(excerpt).to include('conversation_id' => 'conv-1', 'title' => 'Notes', 'source' => 'markdown:notes.md',
                                 'turn' => 2, 'text' => 'a passage from the notes')
      expect(out).to include("mc:read:#{excerpt['id']}", '> a passage from the notes')
    end

    it 'puts the excerpts on the work screen and records where' do
      host.library_search(query: 'notes', workbench: workbench)
      record = Monadic::Library::Readings.take(request_id)[:records].first

      expect(Monadic::Workbench::Put).to have_received(:run)
        .with(workbench, name: "library-#{record['id']}.md", content: a_string_including('a passage from the notes'))
      expect(record['path']).to eq('conversations/c/workbench/library.md')
    end

    it 'records a search that found nothing, and puts nothing on the work screen' do
      allow(Monadic::Library::Retriever).to receive(:cascade_search).and_return([])
      out = host.library_search(query: 'nothing', workbench: workbench)

      expect(out).to include('No matching passages')
      expect(Monadic::Library::Readings.take(request_id)[:records].first['excerpts']).to eq([])
      expect(Monadic::Workbench::Put).not_to have_received(:run)
    end

    it 'keeps the record when the copy cannot be put on the work screen' do
      allow(Monadic::Workbench::Put).to receive(:run).and_raise(Monadic::Workbench::Put::Refused, 'the chat changed')
      out = host.library_search(query: 'notes', workbench: workbench)

      expect(out).to include('a passage from the notes')
      expect(Monadic::Library::Readings.take(request_id)[:records].first).not_to have_key('path')
    end

    it 'searches nothing for a reply with no chat to record it in' do
      expect(host.library_search(query: 'notes', workbench: nil)).to eq(described_class::NO_RECORD_MESSAGE)
      expect(Monadic::Library::Retriever).not_to have_received(:cascade_search)
    end

    it 'gives the model nothing when the search cannot be recorded (the reply ended)' do
      Monadic::Library::Readings.take(request_id)
      out = host.library_search(query: 'notes', workbench: workbench)

      expect(out).to eq(described_class::NO_RECORD_MESSAGE)
      expect(out).not_to include('passage')
    end

    it 'takes the workbench from the server, never from the model' do
      params = MonadicSharedTools::LibrarySearch::Tools.instance_method(:library_search).parameters
      expect(params.map(&:last)).to include(:workbench)
      group = MonadicSharedTools::Registry::TOOL_GROUPS[:library_search]
      expect(group[:tools].first[:parameters].map { |p| p[:name] }).not_to include(:workbench)
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
      host.instance_variable_set(:@session, { parameters: {} })
    end

    it 'forwards a content_type filter to Retriever.cascade_search' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to eq({ must: [{ key: 'content_type', match: { value: 'pdf' } }] })
        []
      end
      host.library_search(query: 'q', content_type: 'pdf', workbench: workbench)
    end

    it 'forwards a source filter to Retriever.cascade_search' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to eq({ must: [{ key: 'source', match: { value: 'monadic-chat' } }] })
        []
      end
      host.library_search(query: 'q', source: 'monadic-chat', workbench: workbench)
    end

    it 'omits payload_filter (nil) when neither narrowing param is given' do
      expect(Monadic::Library::Retriever).to receive(:cascade_search) do |_q, **opts|
        expect(opts[:payload_filter]).to be_nil
        []
      end
      host.library_search(query: 'q', workbench: workbench)
    end
  end
end
