# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'securerandom'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/history'

RSpec.describe Monadic::History do
  let(:dir) { Dir.mktmpdir('history-spec') }
  let(:store) { Monadic::History::Store.new(File.join(dir, 'history.sqlite3')) }
  let(:chat_key) { Monadic::Workspace::Chats::SESSION_KEY }
  let(:fake_key) { "sk-test-#{SecureRandom.hex(16)}" }

  around do |example|
    saved = ENV.to_h.slice('MONADIC_HISTORY', 'OPENAI_API_KEY')
    ENV['MONADIC_HISTORY'] = 'true'
    ENV['OPENAI_API_KEY'] = fake_key
    example.run
  ensure
    store.close
    FileUtils.rm_rf(dir)
    %w[MONADIC_HISTORY OPENAI_API_KEY].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  def session_with(text, **extra)
    {
      chat_key => Monadic::Workspace::Ids.generate(:chat),
      messages: [
        { 'mid' => 'm1', 'role' => 'user', 'text' => text, 'html' => '<p>x</p>', 'thinking' => 'secret plan',
          'images' => [{ 'data' => 'data:image/png;base64,AAAA' }], 'unknown_field' => 'nope',
          'attachments' => [{ 'attachment_id' => 'att_1', 'purpose' => 'video', 'relative_path' => 'x/y.mp4' }] },
        { 'mid' => 'm2', 'role' => 'assistant', 'text' => 'an answer' }
      ],
      parameters: { 'app_name' => 'ChatOpenAI', 'model' => 'gpt-x', 'api_key' => 'nope', 'unknown' => 'nope' }
    }.merge(extra)
  end

  # Every byte of the history file and the files SQLite keeps beside it.
  def stored_bytes
    Dir.glob(File.join(dir, '*')).map { |f| File.binread(f) }.join
  end

  describe 'Store' do
    it 'keeps the file and its companions readable by the owner only' do
      store.save('chat_a', { 'messages' => [] })
      files = Dir.glob(File.join(dir, 'history.sqlite3*'))
      expect(files).not_to be_empty
      expect(files.map { |f| File.stat(f).mode & 0o777 }.uniq).to eq([0o600])
    end

    it 'leaves no bytes of a deleted chat in the history files' do
      marker = "MARK#{SecureRandom.hex(16)}"
      store.save('chat_a', { 'messages' => [{ 'text' => marker }] })
      store.save('chat_b', { 'messages' => [{ 'text' => 'kept' }] })
      store.delete('chat_a')
      store.close
      expect(stored_bytes).not_to include(marker)
      expect(stored_bytes).to include('kept')
    end

    it 'counts revisions, lists without payloads, and keeps a deleted chat deleted' do
      expect(store.save('chat_a', { 'messages' => [{}] }, headings: %w[first recent])).to eq(1)
      expect(store.save('chat_a', { 'messages' => [{}, {}] })).to eq(2)
      expect(store.list.first).to include('chat_id' => 'chat_a', 'revision' => 2, 'message_count' => 2)
      expect(store.list.first).not_to have_key('payload')
      expect(store.delete('chat_a')).to be(true)
      expect(store.get('chat_a')).to be_nil
      expect(store.save('chat_a', { 'messages' => [] })).to be_nil
    end

    it 'refuses a history written by a newer version' do
      store.save('chat_a', { 'messages' => [] })
      store.close
      db = SQLite3::Database.new(store.path)
      db.execute("UPDATE meta SET value = '99' WHERE key = 'schema_version'")
      db.close
      expect { described_class::Store.new(store.path).list }.to raise_error(described_class::Store::Newer)
    end
  end

  describe 'Serializer' do
    it 'keeps only the listed fields and removes known secrets' do
      payload = described_class::Serializer.payload(session_with("my key is #{fake_key} and op://Vault/Item/field"))
      message = payload['messages'].first
      expect(message.keys).to contain_exactly('mid', 'role', 'text', 'attachments')
      expect(message['attachments']).to eq([{ 'attachment_id' => 'att_1', 'purpose' => 'video' }])
      expect(message['text']).not_to include(fake_key)
      expect(message['text']).not_to include('op://')
      expect(payload['parameters']).to eq('app_name' => 'ChatOpenAI', 'model' => 'gpt-x')
    end

    it 'keeps nothing for a chat with no user words yet' do
      expect(described_class::Serializer.payload({ messages: [{ 'role' => 'system', 'text' => 'p' }] })).to be_nil
    end

    it 'takes headings from the first and the latest user messages' do
      payload = { 'messages' => [{ 'role' => 'user', 'text' => 'Plan a trip' }, { 'role' => 'assistant', 'text' => 'ok' },
                                 { 'role' => 'user', 'text' => "Now the slides\n```code```" }] }
      expect(described_class::Serializer.headings(payload)).to eq(['Plan a trip', 'Now the slides'])
    end
  end

  describe 'Policy' do
    it 'treats a chat with Privacy Filter traces as Private for the rest of the chat' do
      session = session_with('hi', _privacy_session_enabled: true)
      expect(described_class::Policy.private?(session)).to be(true)
      session[:_privacy_session_enabled] = false # the filter went down
      expect(described_class::Policy.private?(session)).to be(true)
    end

    it 'treats marked words or a registry as Private' do
      expect(described_class::Policy.private?(session_with('hi', monadic_state: { privacy: { terms: ['Taro'] } }))).to be(true)
      expect(described_class::Policy.private?(session_with('hi', monadic_state: { privacy: { registry: { 'a' => 'b' } } }))).to be(true)
      expect(described_class::Policy.private?(session_with('hi'))).to be(false)
    end
  end

  describe '.record' do
    it 'writes nothing while the history is off' do
      ENV['MONADIC_HISTORY'] = 'false'
      expect(described_class.record(session_with('hello'), store: store)).to be_nil
      expect(Dir.glob(File.join(dir, '*'))).to be_empty
    end

    # A marker in a Private chat must be found nowhere in the history files;
    # the same marker in a normal chat is found (so the scan does look).
    it 'leaves no trace of a Private chat, while a normal chat is kept' do
      marker = "MARK#{SecureRandom.hex(16)}"
      described_class.record(session_with("private #{marker}", _privacy_session_enabled: true), store: store)
      store.close
      expect(stored_bytes).not_to include(marker)

      described_class.record(session_with("normal #{marker}"), store: store)
      store.close
      expect(stored_bytes).to include(marker)
    end

    it 'removes what was kept of a chat that becomes Private' do
      marker = "MARK#{SecureRandom.hex(16)}"
      session = session_with("before #{marker}")
      expect(described_class.record(session, store: store)).to eq(1)
      session[:_privacy_session_enabled] = true
      expect(described_class.record(session, store: store)).to be_nil
      expect(store.get(session[chat_key])).to be_nil
      store.close
      expect(stored_bytes).not_to include(marker)
    end
  end
end
