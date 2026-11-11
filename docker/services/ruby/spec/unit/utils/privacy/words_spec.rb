# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/library'
require_relative '../../../../lib/monadic/utils/privacy/words'
require_relative '../../../../lib/monadic/utils/privacy/egress_guard'
require_relative '../../../../lib/monadic/utils/websocket'

RSpec.describe Monadic::Utils::Privacy::Words do
  let(:outbound) { Monadic::Utils::Privacy::Outbound }
  let(:chats) { Monadic::Workspace::Chats }

  def new_chat
    { parameters: { 'app_name' => 'ChatOpenAI' } }.tap { |s| chats.start_new!(s) }
  end

  after { described_class::LOCK.synchronize { described_class::TABLES.clear } }

  describe "a chat's table" do
    it 'is the same table for every copy of the chat, and another for another chat' do
      session = new_chat
      table = described_class.start!(session)
      table.confirm!('Ada', 'PERSON')

      # As a tab is kept while it reconnects: each value copied on its own.
      copy = WebSocketHelper.deep_clone_each(chats.chat_state(session)).merge(chats::SESSION_KEY => session[chats::SESSION_KEY])
      expect(described_class.table(copy)).to be(table)
      described_class.table(copy).confirm!('Eve', 'PERSON')
      expect(table.revision).to eq(2)
      expect(outbound.terms_of(session)).to eq(%w[Ada Eve])

      other = new_chat
      expect(described_class.table(other)).to be_nil
      expect(described_class.start!(other)).not_to be(table)
    end

    it 'is the one the chat has when a copy made before it was started starts it again' do
      session = new_chat
      early = session.dup
      table = described_class.start!(session)
      table.confirm!('Ada', 'PERSON')
      expect(described_class.start!(early)).to be(table)
      expect(outbound.terms_of(session)).to eq(['Ada'])
    end

    it 'is refused for a mark that is there but is not an id of the chat' do
      [nil, 42, ''].each do |value|
        session = new_chat.merge(described_class::MARK_KEY => value)
        expect { described_class.table(session) }.to raise_error(outbound::Refused), value.inspect
        expect { outbound.terms_of(session) }.to raise_error(outbound::Refused), value.inspect
      end
      expect(described_class.table(new_chat)).to be_nil
    end

    it 'keeps the tables used last, and a chat whose table was dropped sends nothing' do
      stub_const("#{described_class}::LIMIT", 2)
      first = new_chat
      second = new_chat
      described_class.start!(first)
      described_class.start!(second)
      described_class.table(first)
      described_class.start!(new_chat)
      expect(described_class.table(first)).to be_a(Monadic::Utils::Privacy::WordTable)
      expect { described_class.table(second) }.to raise_error(outbound::Refused, /not available/)
    end

    it 'is gone with the chat when a new chat begins' do
      session = new_chat
      described_class.start!(session)
      chats.begin_new!(session)
      expect(described_class.table(session)).to be_nil
    end

    it 'sends nothing for a chat whose table is not here, or not its own' do
      session = new_chat
      described_class.start!(session)
      described_class::LOCK.synchronize { described_class::TABLES.clear }
      expect { described_class.table(session) }.to raise_error(outbound::Refused, /not available/)
      expect { outbound.terms_of(session) }.to raise_error(outbound::Refused)

      session[described_class::MARK_KEY] = 'chat_another'
      expect { described_class.table(session) }.to raise_error(outbound::Refused, /not this chat's/)
    end

    it "sends nothing for a chat that also holds the Privacy Filter's words or masking" do
      [{ _privacy_session_enabled: true },
       { _privacy_pipeline: Object.new },
       { monadic_state: { privacy: { terms: [{ text: 'Bob', type: 'PERSON' }] } } },
       { monadic_state: { privacy: { registry: { '<<PERSON_1>>' => 'Bob' } } } }].each do |legacy|
        session = new_chat
        expect { described_class.start!(session.merge(legacy)) }.to raise_error(outbound::Refused), legacy.inspect
        described_class.start!(session)
        expect { described_class.table(session.merge(legacy)) }.to raise_error(outbound::Refused, /two ways/), legacy.inspect
      end
      off = new_chat.merge(_privacy_session_enabled: false)
      expect(described_class.start!(off)).to be_a(Monadic::Utils::Privacy::WordTable)
    end

    it "is what the checks read as the chat's words, and the Privacy Filter's terms otherwise" do
      session = new_chat
      expect(outbound.marked_terms?(session)).to be(false)
      described_class.start!(session).confirm!('Ada', 'PERSON')
      expect(outbound.marked_terms?(session)).to be(true)
      expect { outbound.check_no_marked_words!(session, { 'text' => 'Ada' }) }.to raise_error(outbound::Refused)

      legacy = { monadic_state: { privacy: { terms: [{ text: 'Bob', type: 'PERSON' }] } } }
      expect(outbound.terms_of(legacy)).to eq(['Bob'])
    end
  end

  describe 'sending a request made with a snapshot' do
    let(:guard) { Monadic::Utils::Privacy::EgressGuard }

    it 'sends each attempt only while the table is still the snapshot\'s' do
      session = new_chat
      table = described_class.start!(session)
      table.confirm!('Ada', 'PERSON')
      snapshot = table.snapshot
      attempts = []
      described_class.sending(table, snapshot) do
        attempts << :first
        described_class.check_sending!
        table.confirm!('Eve', 'PERSON')
        expect { described_class.check_sending! }.to raise_error(outbound::Refused, /changed/)
        expect { guard.check!('api.openai.com') }.to raise_error(outbound::Refused, /changed/)
        # A host on this machine is not checked.
        expect { guard.check!('localhost') }.not_to raise_error
      end
      expect(attempts).to eq([:first])
      # Outside the block, nothing is checked.
      expect { described_class.check_sending! }.not_to raise_error
    end
  end

  describe 'sending without a table inside a send with one' do
    it 'keeps the outer check, whether the inner block ends or raises' do
      session = new_chat
      table = described_class.start!(session)
      described_class.sending(table, table.snapshot) do
        described_class.sending(nil, nil) { :done }
        begin
          described_class.sending(nil, nil) { raise ArgumentError }
        rescue ArgumentError
          nil
        end
        table.confirm!('Eve', 'PERSON')
        expect { described_class.check_sending! }.to raise_error(outbound::Refused)
      end
    end
  end

  describe 'putting a reply back' do
    after { described_class::LOCK.synchronize { described_class::REPLIES.clear } }

    # Notes a reply as answered with a snapshot that nothing else holds.
    def noted_reply(table)
      { 'choices' => [] }.tap { |reply| described_class.note_reply([reply], table.snapshot) }
    end

    it 'uses the words the request it answers was sent with, whatever was collected meanwhile' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      reply = noted_reply(table)
      table.confirm!('Eve', 'PERSON')
      GC.start(full_mark: true, immediate_sweep: true)
      described_class.note_reply([reply], table.snapshot)
      expect(described_class.restore_reply(reply, '<<PERSON_1>> and <<PERSON_2>>')).to eq('Ada and <<PERSON_2>>')
      # Put back once: the reply is not held after it.
      expect(described_class.restore_reply(reply, '<<PERSON_1>>')).to eq('<<PERSON_1>>')
      expect(described_class.restore_reply({ 'choices' => [] }, '<<PERSON_1>>')).to eq('<<PERSON_1>>')
      expect(described_class.note_reply([reply], nil)).to eq([reply])
    end

    it 'holds at most REPLY_LIMIT replies, dropping the oldest' do
      stub_const("#{described_class}::REPLY_LIMIT", 2)
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      first, second, third = Array.new(3) { noted_reply(table) }
      expect(described_class.restore_reply(first, '<<PERSON_1>>')).to eq('<<PERSON_1>>')
      expect(described_class.restore_reply(second, '<<PERSON_1>>')).to eq('Ada')
      expect(described_class.restore_reply(third, '<<PERSON_1>>')).to eq('Ada')
    end
  end

  describe 'a request and the reading of its reply' do
    it "notes the replies with the snapshot of the request that got them, a round of tool calls with its own" do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      outer = table.snapshot
      table.confirm!('Eve', 'PERSON')
      inner = table.snapshot
      table.confirm!('Bob', 'PERSON')
      final = { 'text' => 'final' }
      own = { 'text' => 'own' }

      replies = described_class.request do
        described_class.sent_with(outer)
        expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_2>>' }))
          .to eq(filepath: '<<PERSON_2>>')
        round = described_class.request do
          described_class.sent_with(inner)
          expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_2>>' }))
            .to eq(filepath: 'Eve')
          [final]
        end
        expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_2>>' }))
          .to eq(filepath: '<<PERSON_2>>')
        round + [own]
      end

      text = '<<PERSON_1>> <<PERSON_2>> <<PERSON_3>>'
      expect(replies).to eq([final, own])
      expect(described_class.restore_reply(final, text)).to eq('Ada Eve <<PERSON_3>>')
      expect(described_class.restore_reply(own, text)).to eq('Ada <<PERSON_2>> <<PERSON_3>>')
      expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_1>>' }))
        .to eq(filepath: '<<PERSON_1>>')
    end

    it "gives the Knowledge Base search its query with the chat's words, and nothing else of the call" do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      described_class.request do
        described_class.sent_with(table.snapshot)
        expect(described_class.tool_arguments('library_search', { 'query' => 'notes of <<PERSON_1>>', 'source' => '<<PERSON_1>>' }))
          .to eq('query' => 'notes of Ada', 'source' => '<<PERSON_1>>')
      end
    end

    it 'notes a reply returned on its own, not in an Array' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      reply = { 'text' => 'reply' }
      described_class.request do
        described_class.sent_with(table.snapshot)
        reply
      end
      expect(described_class.restore_reply(reply, '<<PERSON_1>>')).to eq('Ada')
    end

    it 'shows a reply as it is when it is marked so in a hidden request, whatever is noted for it later' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      outside = { 'text' => 'outside' }
      expect(described_class.as_is([outside])).to eq([outside])
      described_class.request do
        described_class.sent_with(table.snapshot)
        expect(described_class.restore_reply(outside, '<<PERSON_1>>')).to eq('<<PERSON_1>>')
        made = { 'text' => 'made' }
        described_class.request do
          described_class.sent_with(table.snapshot)
          described_class.as_is(made)
          [made]
        end
      end => [made]
      expect(described_class.restore_reply(made, 'literal <<PERSON_1>>')).to eq('literal <<PERSON_1>>')
    end

    it 'keeps a reply shown as it is after the snapshots noted for others dropped it, and a request around it returns it' do
      stub_const("#{described_class}::REPLY_LIMIT", 2)
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      raw = { 'text' => 'raw' }
      described_class.request do
        described_class.sent_with(table.snapshot)
        described_class.request do
          described_class.sent_with(table.snapshot)
          described_class.as_is(raw)
        end
        others = Array.new(3) { { 'text' => 'other' } }
        described_class.note_reply(others, table.snapshot)
        GC.start(full_mark: true, immediate_sweep: true)
        raw
      end
      expect(described_class.restore_reply(raw, 'literal <<PERSON_1>>')).to eq('literal <<PERSON_1>>')
    end

    it 'shows a reply as it is when it is marked so after the request that got it noted it' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      reply = { 'text' => 'reply' }
      described_class.request do
        described_class.sent_with(table.snapshot)
        described_class.request do
          described_class.sent_with(table.snapshot)
          reply
        end
        described_class.as_is(reply)
      end
      expect(described_class.restore_reply(reply, 'literal <<PERSON_1>>')).to eq('literal <<PERSON_1>>')
    end

    it 'leaves the request around it as it was when the block fails, and notes nothing outside one' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      described_class.sent_with(table.snapshot)
      expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_1>>' }))
        .to eq(filepath: '<<PERSON_1>>')
      described_class.request do
        described_class.sent_with(table.snapshot)
        expect { described_class.request { raise ArgumentError } }.to raise_error(ArgumentError)
        expect(described_class.tool_arguments('read_file_from_shared_folder', { filepath: '<<PERSON_1>>' }))
          .to eq(filepath: 'Ada')
        nil
      end
    end
  end

  describe "a tool's arguments" do
    it 'puts back only the exact placeholders of the places a tool reads, with the snapshot of the request being answered' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      snapshot = table.snapshot
      table.confirm!('Eve', 'PERSON')
      args = { filepath: '<<PERSON_1>>/<< PERSON_1 >>/<<PERSON_2>>/<<PERSON_9>>.txt' }
      expect(described_class.tool_arguments('read_file_from_shared_folder', args)).to eq(args)
      described_class.request do
        described_class.sent_with(snapshot)
        expect(described_class.tool_arguments('read_file_from_shared_folder', args))
          .to eq(filepath: 'Ada/<< PERSON_1 >>/<<PERSON_2>>/<<PERSON_9>>.txt')
        expect(described_class.tool_arguments('list_files_in_shared_folder', { 'directory' => '<<PERSON_1>>' }))
          .to eq('directory' => 'Ada')
        written = { filepath: '<<PERSON_1>>.txt', content: '<<PERSON_1>>' }
        expect(described_class.tool_arguments('write_file_to_shared_folder', written)).to eq(written)
        expect(described_class.tool_arguments('run_code', { code: '<<PERSON_1>>' })).to eq(code: '<<PERSON_1>>')
        expect(described_class.tool_arguments('show_on_workbench', { path: 42 })).to eq(path: 42)
      end
    end

    it 'puts back both names a PDF reading tool takes its file by, and only for that tool' do
      table = described_class.start!(new_chat)
      table.confirm!('Ada', 'PERSON')
      described_class.request do
        described_class.sent_with(table.snapshot)
        expect(described_class.tool_arguments('fetch_text_from_pdf', { file: '<<PERSON_1>>.pdf' }))
          .to eq(file: 'Ada.pdf')
        expect(described_class.tool_arguments('fetch_text_from_pdf', { pdf: '<<PERSON_1>>.pdf' }))
          .to eq(pdf: 'Ada.pdf')
        expect(described_class.tool_arguments('fetch_text_from_office', { pdf: '<<PERSON_1>>.pdf' }))
          .to eq(pdf: '<<PERSON_1>>.pdf')
        expect(described_class.tool_arguments('fetch_text_from_file', { pdf: '<<PERSON_1>>.pdf' }))
          .to eq(pdf: '<<PERSON_1>>.pdf')
      end
    end
  end

  describe 'marks a chat with a table receives' do
    let(:host) do
      Class.new { include WebSocketHelper }.new.tap do |h|
        allow(h).to receive(:send_or_broadcast)
        allow(h).to receive(:sync_session_state!)
      end
    end

    before { allow(host).to receive(:get_session_params).and_return({ 'app_name' => 'ChatOpenAI' }) }

    it 'keeps the brackets of what a person writes as plain text' do
      session = new_chat.merge(messages: [])
      table = described_class.start!(session)
      host.send(:handle_ws_sample, nil, { 'content' => 'Ask ⟦Ada⟧ at ⟦Acme|org⟧', 'role' => 'user' }, session)
      expect(session[:messages].last['text']).to eq('Ask ⟦Ada⟧ at ⟦Acme|org⟧')
      expect(table.active_words).to be_empty
    end

    it 'refuses a system message or edit that holds a word the chat hides' do
      errors = []
      allow(host).to receive(:send_error) { |msg, _id, extra = {}| errors << extra.merge('message' => msg) }
      session = new_chat.merge(messages: [{ 'mid' => 's1', 'role' => 'system', 'text' => 'Be brief.' }])
      described_class.start!(session).confirm_all!([%w[Ada PERSON]])
      host.send(:handle_ws_sample, nil, { 'content' => 'Call me Ada', 'role' => 'system' }, session)
      Thread.current[:rack_session] = session
      host.handle_edit_message(nil, { 'mid' => 's1', 'content' => 'Call me Ada' })

      expect(session[:messages].map { |m| m['text'] }).to eq(['Be brief.'])
      expect(errors).to all(include('not_accepted' => true, 'message' => a_string_including('system message')))
      expect(errors.size).to eq(2)
      expect(errors.last).to include('edit_refused' => true, 'mid' => 's1')
    ensure
      Thread.current[:rack_session] = nil
    end

    it 'refuses a system message while the table cannot be read' do
      errors = []
      allow(host).to receive(:send_error) { |msg, *| errors << msg }
      session = new_chat.merge(messages: [])
      described_class.start!(session)
      allow(described_class).to receive(:table).and_raise(Monadic::Utils::Privacy::Outbound::Refused, 'lost')
      host.send(:handle_ws_sample, nil, { 'content' => 'Be brief.', 'role' => 'system' }, session)
      expect(session[:messages]).to be_empty
      expect(errors.size).to eq(1)
    end
  end

  describe 'suggesting a title' do
    let(:sent) { [] }
    let(:reply) { ['<<PERSON_1>> and the "Acme" deal, a long account of a meeting held over several days'] }
    let(:instance) do
      bodies = sent
      replies = reply
      Class.new do
        define_method(:settings) { { 'group' => 'OpenAI', 'display_name' => 'Chat' } }
        define_method(:send_query) do |body, model:|
          Monadic::Utils::Privacy::Words.check_sending!
          bodies << body
          replies.first
        end
      end.new
    end
    let(:session) { new_chat }
    let(:table) { described_class.start!(session).tap { |t| t.confirm!('Ada Augusta Lovelace', 'PERSON') } }

    before do
      stub_const('APPS', { 'ChatOpenAI' => instance })
      stub_const('CONFIG', { 'OPENAI_API_KEY' => 'sk-test' })
      allow(::SystemDefaults).to receive(:get_default_model).with('openai').and_return('gpt-test')
    end

    def suggest(messages)
      Monadic::Library::TitleSuggester.suggest(messages: messages, app_name: 'ChatOpenAI', session: session, words: table)
    end

    it 'sends the messages with the words hidden, and gives the title with them put back, then cut' do
      title = suggest([{ 'role' => 'user', 'text' => 'Ada Augusta Lovelace wrote <<PERSON_1>> in her notes.' }])
      prompt = sent.last['messages'].last['content'].to_s
      expect(prompt).to include('<<PERSON_1>> wrote ‹‹PERSON_1›› in her notes.')
      expect(prompt).not_to include('Ada Augusta Lovelace')
      # The placeholder is shorter than the word: the title is cut after the
      # word is put back, so it is within the limit and holds the whole word.
      expect(title).to start_with('Ada Augusta Lovelace and the')
      expect(title.length).to be <= Monadic::Library::TitleSuggester::MAX_LENGTH
    end

    it 'sends nothing when the table changes while the request is sent' do
      changing = Class.new do
        define_method(:settings) { { 'group' => 'OpenAI', 'display_name' => 'Chat' } }
        define_method(:send_query) do |_body, model:|
          Monadic::Utils::Privacy::Words.table(Thread.current[:words_spec_session]).confirm!('Eve', 'PERSON')
          Monadic::Utils::Privacy::Words.check_sending!
          'never'
        end
      end.new
      stub_const('APPS', { 'ChatOpenAI' => changing })
      Thread.current[:words_spec_session] = session
      table
      expect(suggest([{ 'role' => 'user', 'text' => 'Ada Augusta Lovelace' }])).to be_nil
    ensure
      Thread.current[:words_spec_session] = nil
    end

    it "sends nothing when the app's own text holds a word" do
      table.confirm!('Suggest', 'PERSON')
      expect(suggest([{ 'role' => 'user', 'text' => 'hello' }])).to be_nil
      expect(sent).to be_empty
    end
  end

  describe 'the end of a chat whose table is not here' do
    it 'keeps nothing for it, and does not stop the chat from ending' do
      session = new_chat
      described_class.start!(session)
      described_class::LOCK.synchronize { described_class::TABLES.clear }
      expect { Monadic::Utils::Privacy::EgressGuard.chat_ended(session) }.not_to raise_error
    end
  end
end
