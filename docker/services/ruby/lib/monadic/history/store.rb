# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require 'sqlite3'

module Monadic
  module History
    # The conversation history: one SQLite file in the state folder
    # (history.sqlite3), written by this server only. The file and the ones
    # SQLite keeps beside it are readable by the owner only. A deleted chat
    # leaves a tombstone, so a late write for it does not bring it back, and
    # its pages are zeroed (secure_delete) and the log checkpointed. That
    # makes it unreadable through the app; it is not a promise that no copy
    # is left on the disk.
    class Store
      SCHEMA_VERSION = 1
      FILE_NAME = 'history.sqlite3'
      COMPANIONS = %w[-wal -shm -journal].freeze

      # Written by a newer version.
      class Newer < StandardError; end

      def self.default
        @default ||= new(File.join(Monadic::Utils::Environment.state_path, FILE_NAME))
      end

      def self.reset_default!
        @default = nil
      end

      attr_reader :path

      def initialize(path)
        @path = path
        @mutex = Mutex.new
        @db = nil
      end

      # Keeps the chat's payload as its newest revision. Returns the revision,
      # or nil when the chat was deleted.
      def save(chat_id, payload, app_name: nil, model: nil, headings: [nil, nil], now: Time.now)
        json = JSON.generate(payload)
        count = payload['messages'].length
        stamp = now.utc.iso8601
        synchronize do |db|
          db.transaction(:immediate) do
            next nil if db.get_first_value('SELECT 1 FROM deleted_chats WHERE chat_id = ?', [chat_id])

            revision = db.get_first_value('SELECT revision FROM history_chats WHERE chat_id = ?', [chat_id])
            if revision
              db.execute(<<~SQL, [app_name, model, headings[0], headings[1], stamp, revision + 1, count, json, chat_id])
                UPDATE history_chats SET app_name = ?, model = ?, heading_first = ?, heading_recent = ?,
                  updated_at = ?, revision = ?, message_count = ?, payload = ? WHERE chat_id = ?
              SQL
              revision + 1
            else
              db.execute(<<~SQL, [chat_id, app_name, model, headings[0], headings[1], stamp, stamp, 1, count, json])
                INSERT INTO history_chats (chat_id, app_name, model, heading_first, heading_recent,
                  created_at, updated_at, revision, message_count, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              SQL
              1
            end
          end
        end
      end

      def get(chat_id)
        synchronize do |db|
          row = db.get_first_row('SELECT * FROM history_chats WHERE chat_id = ?', [chat_id])
          row && row.merge('payload' => JSON.parse(row['payload']))
        end
      end

      # The list without the conversations themselves, newest first.
      def list(limit: 100, offset: 0)
        synchronize do |db|
          db.execute(<<~SQL, [limit, offset])
            SELECT chat_id, app_name, model, title_user, heading_first, heading_recent,
              created_at, updated_at, revision, message_count
            FROM history_chats ORDER BY updated_at DESC, chat_id LIMIT ? OFFSET ?
          SQL
        end
      end

      # Removes the chat and keeps a tombstone. Returns whether a row was removed.
      def delete(chat_id, now: Time.now)
        removed = synchronize do |db|
          db.transaction(:immediate) do
            db.execute('DELETE FROM history_chats WHERE chat_id = ?', [chat_id])
            changed = db.changes.positive?
            db.execute('INSERT OR IGNORE INTO deleted_chats (chat_id, deleted_at) VALUES (?, ?)', [chat_id, now.utc.iso8601])
            changed
          end
        end
        synchronize { |db| db.execute('PRAGMA wal_checkpoint(TRUNCATE)') }
        removed
      end

      def close
        @mutex.synchronize do
          @db&.close
          @db = nil
        end
      end

      private

      def synchronize
        @mutex.synchronize { yield(connection) }
      end

      def connection
        @db ||= open
      end

      def open
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        previous = File.umask(0o077)
        begin
          db = SQLite3::Database.new(@path, results_as_hash: true)
          db.busy_timeout = 5000
          db.execute('PRAGMA journal_mode = WAL')
          db.execute('PRAGMA secure_delete = ON')
          db.execute('PRAGMA temp_store = MEMORY')
          db.execute('PRAGMA synchronous = NORMAL')
          migrate!(db)
          tighten_permissions
          db
        ensure
          File.umask(previous)
        end
      end

      def migrate!(db)
        db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
        version = db.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")&.to_i
        raise Newer, "the history was written by a newer version (schema #{version})" if version && version > SCHEMA_VERSION
        return if version == SCHEMA_VERSION

        db.transaction(:immediate) do
          db.execute(<<~SQL)
            CREATE TABLE history_chats (
              chat_id TEXT PRIMARY KEY, app_name TEXT, model TEXT, title_user TEXT,
              heading_first TEXT, heading_recent TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              revision INTEGER NOT NULL, message_count INTEGER NOT NULL, payload TEXT NOT NULL)
          SQL
          db.execute('CREATE TABLE deleted_chats (chat_id TEXT PRIMARY KEY, deleted_at TEXT NOT NULL)')
          db.execute("INSERT INTO meta (key, value) VALUES ('schema_version', ?)", [SCHEMA_VERSION.to_s])
        end
      end

      def tighten_permissions
        ([@path] + COMPANIONS.map { |suffix| "#{@path}#{suffix}" }).each do |file|
          File.chmod(0o600, file) if File.exist?(file)
        end
      end
    end
  end
end
