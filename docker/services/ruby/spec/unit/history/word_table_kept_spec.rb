# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'securerandom'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket'
require_relative '../../../lib/monadic/utils/container_dependencies'

# A chat that hides its words with a table goes on hiding them when it comes
# back: from the history, or from a file it was saved to.
RSpec.describe 'A chat word table kept with the chat' do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:table_class) { Monadic::Utils::Privacy::WordTable }
  let(:refused) { Monadic::Utils::Privacy::Outbound::Refused }
  let(:ids) { Monadic::Workspace::Ids }
  let(:dir) { Dir.mktmpdir('word-table-kept') }
  let(:store) { Monadic::History::Store.new(File.join(dir, 'history.sqlite3')) }
  let(:word) { 'Ada Lovelace' }
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= []
      end

      def send_to_client(_connection, payload)
        sent << payload
      end
    end.new
  end

  around do |example|
    saved = ENV['MONADIC_HISTORY']
    ENV['MONADIC_HISTORY'] = 'true'
    example.run
  ensure
    store.close
    FileUtils.rm_rf(dir)
    saved ? ENV['MONADIC_HISTORY'] = saved : ENV.delete('MONADIC_HISTORY')
    Thread.current[:websocket_session_id] = nil
    Thread.current[:rack_session] = nil
    words::LOCK.synchronize { words::TABLES.clear }
  end

  before do
    allow(Monadic::History::Store).to receive(:default).and_return(store)
    allow(WebSocketHelper).to receive(:send_to_session)
    allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
    allow(host).to receive(:prepare_apps_data).and_return({})
  end

  def chat(text: "About #{word}.")
    { chat_id: ids.generate(:chat), _ws_generation: 1,
      messages: [{ 'mid' => 'm1', 'role' => 'user', 'text' => text }],
      parameters: { 'app_name' => 'ChatOpenAI', 'model' => 'gpt-x' } }
  end

  def marked_chat(*hidden)
    session = chat
    table = words.start!(session)
    hidden.each { |w| table.confirm!(w, 'PERSON') }
    [session, table]
  end

  def forget_tables
    words::LOCK.synchronize { words::TABLES.clear }
  end

  def payload_of(session)
    store.get(session[:chat_id])['payload']
  end

  def resume(chat_id)
    tab = "tab-#{SecureRandom.hex(4)}"
    session = { chat_id: ids.generate(:chat), _ws_generation: WebSocketHelper.claim_session_state(tab),
                messages: [], parameters: {} }
    Thread.current[:websocket_session_id] = tab
    Thread.current[:rack_session] = session
    obj = { 'chat_id' => chat_id }
    host.send(:handle_ws_history_resume, nil, obj, session, host.send(:history_resume_refusal, obj, session))
    expect(host.sent.last).to include('type' => 'history_resumed', 'success' => true)
    session
  end

  def export(session, **options)
    host.send(:handle_ws_privacy_export, :conn, session, { 'encrypt' => false, 'content' => 'restored' }.merge(options.transform_keys(&:to_s)))
    host.sent.last
  end

  def file_of(reply)
    expect(reply['type']).to eq('privacy_export_data')
    JSON.parse(Base64.strict_decode64(reply['content_base64']))
  end

  describe 'in the history' do
    it 'brings the table back when the chat is resumed and no table is held any more' do
      session, table = marked_chat(word)
      placeholder = table.apply(word)
      Monadic::History.record(session, store: store)
      forget_tables

      resumed = resume(session[:chat_id])

      expect(words.table(resumed).apply("Hi #{word}")).to eq("Hi #{placeholder}")
    end

    it 'keeps the placeholders given and the numbers used, not only the active words' do
      session, table = marked_chat(word, 'Grace Hopper')
      table.disable!('Grace Hopper')
      before = table.to_h
      Monadic::History.record(session, store: store)
      forget_tables

      expect(words.table(resume(session[:chat_id])).to_h).to eq(before)
    end

    it 'keeps the mark of a chat whose table has no word yet' do
      session, = marked_chat
      Monadic::History.record(session, store: store)
      forget_tables

      resumed = resume(session[:chat_id])

      expect(words.marked?(resumed)).to be(true)
      expect(words.table(resumed).active_words).to be_empty
    end

    it 'prefers the table held for the chat to the one saved' do
      session, table = marked_chat(word)
      Monadic::History.record(session, store: store)
      table.confirm!('Grace Hopper', 'PERSON')

      expect(words.active_of(resume(session[:chat_id]))).to contain_exactly(word, 'Grace Hopper')
    end

    it 'sends nothing for a resumed chat whose saved table cannot be read' do
      session, = marked_chat(word)
      Monadic::History.record(session, store: store)
      forget_tables
      broken = payload_of(session).merge('word_table' => { 'schema' => 99 })
      store.save(session[:chat_id], broken)

      resumed = resume(session[:chat_id])

      expect(words.marked?(resumed)).to be(true)
      expect { words.table(resumed) }.to raise_error(refused)
    end

    it 'leaves the saved table when none is held at the time of a later save' do
      session, = marked_chat(word)
      Monadic::History.record(session, store: store)
      saved = payload_of(session)['word_table']
      forget_tables

      Monadic::History.record(session, store: store)

      expect(payload_of(session)['word_table']).to eq(saved)
    end

    it 'keeps the mark of a chat that lost its table before it was ever saved' do
      session, = marked_chat(word)
      forget_tables
      Monadic::History.record(session, store: store)

      resumed = resume(session[:chat_id])

      expect(words.marked?(resumed)).to be(true)
      expect { words.table(resumed) }.to raise_error(refused)
    end

    it 'writes the table held for the chat also from a copy of its session made before the table began' do
      session, = marked_chat(word)
      copy = session.reject { |key, _| key == words::MARK_KEY }

      Monadic::History.record(copy, store: store)

      expect(payload_of(session)['word_table']['active'].map { |e| e['word'] }).to eq([word])
    end

    it 'saves the table as it is when the save is written, not when it was begun' do
      session, table = marked_chat(word)
      allow(store).to receive(:save).and_wrap_original do |original, *args, **options|
        table.confirm!('Grace Hopper', 'PERSON')
        original.call(*args, **options)
      end

      Monadic::History.record(session, store: store)

      expect(payload_of(session)['word_table']['active'].map { |e| e['word'] }).to contain_exactly(word, 'Grace Hopper')
    end

    context 'with a known secret' do
      let(:secret) { 'known-secret-value' }

      before { allow(Monadic::Utils::SecretRedactor).to receive(:secret_values).and_return([secret]) }

      it 'does not save a word to hide that holds it, and the chat taken back sends nothing' do
        session, = marked_chat(word, "x#{secret}")
        Monadic::History.record(session, store: store)

        expect(JSON.generate(payload_of(session))).not_to include(secret)
        forget_tables
        resumed = resume(session[:chat_id])

        expect(words.marked?(resumed)).to be(true)
        expect { words.table(resumed) }.to raise_error(refused)
      end

      it 'goes on hiding the word while the table is held' do
        session, = marked_chat("x#{secret}")
        Monadic::History.record(session, store: store)

        expect(words.active_of(resume(session[:chat_id]))).to eq(["x#{secret}"])
      end

      it 'leaves out a word no longer hidden that holds it, and the table stays readable' do
        session, table = marked_chat(word, "x#{secret}", 'Grace Hopper')
        table.disable!("x#{secret}")
        table.keep!("kept-#{secret}")
        Monadic::History.record(session, store: store)

        expect(JSON.generate(payload_of(session))).not_to include(secret)
        forget_tables
        expect(words.active_of(resume(session[:chat_id]))).to contain_exactly(word, 'Grace Hopper')
      end
    end

    it 'keeps the mark of a saved chat whose table is null, also through a save from a copy without the mark' do
      session, = marked_chat(word)
      Monadic::History.record(session, store: store)
      forget_tables
      store.save(session[:chat_id], payload_of(session).merge('word_table' => nil))

      Monadic::History.record(session.reject { |key, _| key == words::MARK_KEY }, store: store)
      expect(payload_of(session)).to have_key('word_table')

      store.save(session[:chat_id], payload_of(session).merge('word_table' => nil))
      resumed = resume(session[:chat_id])

      expect(words.marked?(resumed)).to be(true)
      expect { words.table(resumed) }.to raise_error(refused)
    end

    it 'adds nothing for a chat that does not hide its words with a table' do
      session = chat
      Monadic::History.record(session, store: store)

      expect(payload_of(session)).not_to have_key('word_table')
      expect(words.marked?(resume(session[:chat_id]))).to be(false)
    end
  end

  describe 'in a file' do
    def import(file)
      imported = { messages: [{ 'role' => 'user', 'text' => "About #{word}." }], parameters: { 'app_name' => 'ChatOpenAI' } }
      table = words.file_table(file, imported)
      imported[:word_table] = table if table
      tab = "tab-#{SecureRandom.hex(4)}"
      token = WebSocketHelper.stage_import(tab, imported)
      session = { chat_id: ids.generate(:chat), _ws_generation: WebSocketHelper.claim_session_state(tab),
                  messages: [], parameters: {} }
      Thread.current[:websocket_session_id] = tab
      Thread.current[:rack_session] = session
      host.send(:handle_ws_import_apply, nil, { 'token' => token }, session, WebSocketHelper.take_import(tab, token))
      expect(host.sent.last).to include('type' => 'import_result', 'success' => true)
      session
    end

    it 'carries the table in a restored file, and the imported chat hides its words with a table of its own' do
      session, table = marked_chat(word)
      placeholder = table.apply(word)

      imported = import(file_of(export(session)))

      expect(imported[:chat_id]).not_to eq(session[:chat_id])
      expect(imported).not_to have_key(:word_table)
      expect(words.table(imported).apply(word)).to eq(placeholder)
      words.table(imported).confirm!('Grace Hopper', 'PERSON')
      expect(table.active_words.map { |e| e[:word] }).to eq([word])
    end

    it 'carries the mark of a chat with an empty table' do
      session, = marked_chat
      imported = import(file_of(export(session)))

      expect(words.table(imported).active_words).to be_empty
    end

    it 'carries the table inside an encrypted restored file' do
      session, = marked_chat(word)
      reply = export(session, encrypt: true, passphrase: 'a passphrase for the file')
      envelope = JSON.parse(Base64.strict_decode64(reply['content_base64']))

      plain = Monadic::Utils::Privacy::ExportCipher.decrypt(envelope: envelope, passphrase: 'a passphrase for the file')

      expect(JSON.parse(plain)['word_table']['active'].map { |e| e['word'] }).to eq([word])
      expect(reply['content_base64']).not_to include(Base64.strict_encode64(word))
    end

    it 'masks a shared file with the active words, and carries no table' do
      session, table = marked_chat(word)
      table.confirm!('Grace Hopper', 'PERSON')
      table.disable!('Grace Hopper')
      Monadic::Workspace::ChatContext.restore!(session, { 'topics' => [{ 'text' => "On #{word}", 'turn' => 1 }] })

      raw = Base64.strict_decode64(export(session, content: 'masked')['content_base64'])

      expect(raw).not_to include(word)
      expect(raw).not_to include('Grace Hopper')
      file = JSON.parse(raw)
      expect(file).not_to have_key('word_table')
      expect(file['messages'].first['text']).to eq("About #{table.apply(word)}.")
      expect(words.marked?(import(file))).to be(false)
    end

    it 'writes no file for a chat whose table is not here' do
      session, = marked_chat(word)
      forget_tables

      %w[restored masked].each do |content|
        expect(export(session, content: content)).to include('type' => 'privacy_export_error', 'error' => 'export_failed')
      end
    end

    it 'refuses a file whose table cannot be read' do
      expect { words.file_table({ 'word_table' => { 'schema' => 1, 'mapping' => 'x' } }, {}) }
        .to raise_error(table_class::Invalid)
      expect { words.file_table({ 'word_table' => {} }, {}) }.to raise_error(table_class::Invalid)
    end

    it 'refuses a file that holds a table and the state of the Privacy Filter' do
      data = table_class.new.to_h
      imported = { monadic_state: { privacy: { registry: { '<<PERSON_1>>' => word }, terms: [] } }, _privacy_session_enabled: true }

      expect { words.file_table({ 'word_table' => data }, imported) }.to raise_error(table_class::Invalid, /two ways/)
    end

    it 'reads nothing from a file without a table' do
      expect(words.file_table({ 'messages' => [] }, {})).to be_nil
    end

    # The /load route of the app, booted in a child process with its own HOME
    # as the other route specs are.
    it 'is staged for the tab by the import route, which refuses a table it cannot read' do
      probe = <<~'RUBY'
        require "rack"
        require "rack/mock_request"
        require "json"
        app, = Rack::Builder.parse_file("config.ru")
        table = Monadic::Utils::Privacy::WordTable.new
        table.confirm!("Ada Lovelace", "PERSON")
        base = { "parameters" => { "app_name" => "ChatOpenAI" }, "messages" => [{ "role" => "user", "text" => "hello", "mid" => "m1" }] }
        post = lambda do |file|
          body = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"c.json\"\r\n" \
                 "Content-Type: application/json\r\n\r\n#{file.to_json}\r\n" \
                 "--B\r\nContent-Disposition: form-data; name=\"tab_id\"\r\n\r\ntab-probe\r\n--B--\r\n"
          JSON.parse(Rack::MockRequest.new(app).post("http://localhost:4567/load", input: body,
                                                     "CONTENT_TYPE" => "multipart/form-data; boundary=B",
                                                     "HTTP_HOST" => "localhost:4567", "HTTP_ORIGIN" => "http://localhost:4567").body)
        end
        staged = post.call(base.merge("word_table" => table.to_h))
        imported = WebSocketHelper.take_import("tab-probe", staged["import_token"])
        broken = post.call(base.merge("word_table" => { "schema" => 99 }))
        mixed = post.call(base.merge("word_table" => table.to_h, "terms" => [{ "text" => "Grace Hopper", "type" => "PERSON" }]))
        puts({ "words" => imported[:word_table]["active"].map { |e| e["word"] }, "broken" => broken, "mixed" => mixed }.to_json)
      RUBY
      root = File.expand_path('../../..', __dir__)
      out = Dir.mktmpdir('word-table-load') do |home|
        stdout, stderr, status = Open3.capture3({ 'HOME' => home }, RbConfig.ruby, '-e', probe, chdir: root)
        raise "probe failed: #{stderr.lines.last(15).join}" unless status.success?

        JSON.parse(stdout.lines.last)
      end

      expect(out['words']).to eq([word])
      expect(out['broken'].to_s).to include('word table could not be read')
      expect(out['mixed'].to_s).to include('two ways')
    end
  end
end
