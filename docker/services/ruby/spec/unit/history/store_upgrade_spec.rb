# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/history/store'

RSpec.describe Monadic::History::Store do
  around do |example|
    Dir.mktmpdir('history-upgrade-spec') do |dir|
      @path = File.join(dir, 'history.sqlite3')
      @store = described_class.new(@path)
      example.run
    ensure
      @store.close
    end
  end

  def database
    db = SQLite3::Database.new(@path)
    yield db
  ensure
    db&.close
  end

  def expect_indexed_order
    database do |db|
      plan = db.execute('EXPLAIN QUERY PLAN SELECT chat_id FROM history_chats ORDER BY last_activity_at DESC, chat_id LIMIT 10').flatten.join(' ')
      expect(plan).to include('USING COVERING INDEX')
      expect(plan).not_to include('TEMP B-TREE')
      expect(db.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")).to eq('1')
    end
  end

  it 'indexes a new database and lists equal timestamps by chat ID' do
    %w[c_b c_a].each { |id| @store.save(id, { 'messages' => [] }, now: Time.utc(2025, 1, 1)) }
    @store.save('c_new', { 'messages' => [] }, now: Time.utc(2025, 1, 2))
    expect(@store.list.map { |row| row['chat_id'] }).to eq(%w[c_new c_a c_b])
    expect_indexed_order
    @store.close
    expect(@store.list(limit: 1, offset: 1).map { |row| row['chat_id'] }).to eq(['c_a'])
  end

  it 'gives a file made without the index its index on open, changing no record' do
    database do |db|
      db.execute_batch(<<~SQL)
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO meta VALUES ('schema_version', '1');
        CREATE TABLE history_chats (
          chat_id TEXT PRIMARY KEY, app_name TEXT, model TEXT, title_user TEXT,
          heading_first TEXT, heading_recent TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          last_activity_at TEXT NOT NULL, revision INTEGER NOT NULL, owner_tab TEXT, generation INTEGER,
          message_count INTEGER NOT NULL, search_text TEXT, payload TEXT NOT NULL);
        CREATE TABLE deleted_chats (chat_id TEXT PRIMARY KEY, deleted_at TEXT NOT NULL);
      SQL
      stamp = Time.utc(2025, 1, 1).iso8601
      db.execute('INSERT INTO history_chats (chat_id, created_at, updated_at, last_activity_at, revision, message_count, payload) VALUES (?, ?, ?, ?, ?, ?, ?)',
                 ['c_kept', stamp, stamp, stamp, 3, 0, '{"messages":[]}'])
      db.execute('INSERT INTO deleted_chats VALUES (?, ?)', ['c_deleted', stamp])
    end
    expect(@store.list.map { |row| row['chat_id'] }).to eq(['c_kept'])
    expect(@store.get('c_kept')).to include('revision' => 3, 'payload' => { 'messages' => [] })
    expect(@store.save('c_deleted', { 'messages' => [] })).to be_nil
    expect_indexed_order
    @store.close
    expect(@store.list.size).to eq(1)
    @store.close
    # The code that made the file reads it as before: same version, same tables.
    database do |db|
      expect(db.execute('SELECT chat_id, revision FROM history_chats')).to eq([['c_kept', 3]])
      expect(db.execute('SELECT chat_id FROM deleted_chats').flatten).to eq(['c_deleted'])
    end
  end

  it 'refuses a newer schema without changing its version' do
    database do |db|
      db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      db.execute("INSERT INTO meta VALUES ('schema_version', '2')")
    end
    expect { @store.list }.to raise_error(described_class::Newer)
    database { |db| expect(db.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")).to eq('2') }
  end
end
