# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require 'sqlite3'

module Monadic
  module History
    # The conversation history: one SQLite file in the state folder
    # (history.sqlite3), written by this server only. The file is created
    # readable by the owner only, and SQLite gives the files it keeps beside
    # it the same mode. A chat that is deleted or Private leaves a tombstone,
    # so a late write for it does not bring it back. Removed rows are zeroed
    # (secure_delete) and the log is checkpointed; a checkpoint that a reader
    # holds up is tried again later. That makes the text unreadable through
    # the app; it is not a promise that no copy is left on the disk.
    class Store
      SCHEMA_VERSION = 1
      FILE_NAME = 'history.sqlite3'
      COMPANIONS = %w[-wal -shm -journal].freeze
      BUSY_TIMEOUT_MS = 5000

      # Written by a newer version.
      class Newer < StandardError; end

      # The state folder is inside the shared folder, which the app serves.
      class Exposed < StandardError; end

      def self.default
        @default ||= begin
          state = Monadic::Utils::Environment.state_path
          refuse_inside_shared_folder!(state)
          new(File.join(state, FILE_NAME))
        end
      end

      def self.reset_default!
        @default = nil
      end

      def self.refuse_inside_shared_folder!(state)
        data = Monadic::Utils::Environment.shared_volume
        return unless File.directory?(state) && File.directory?(data)

        real_state = File.realpath(state)
        real_data = File.realpath(data)
        return unless real_state == real_data || real_state.start_with?("#{real_data}/")

        raise Exposed, 'the state folder is inside the shared folder'
      end

      attr_reader :path

      def initialize(path, busy_timeout_ms: BUSY_TIMEOUT_MS)
        @path = path
        @busy_timeout_ms = busy_timeout_ms
        @mutex = Mutex.new
        @db = nil
        @checkpoint_pending = false
      end

      # Keeps the chat's payload as its newest revision. Returns the revision,
      # or nil when the chat is deleted or Private, or when `generation` (the
      # connection that wrote it) is older than the one that wrote last.
      def save(chat_id, payload, generation: nil, app_name: nil, model: nil, headings: [nil, nil], now: Time.now)
        json = JSON.generate(payload)
        count = payload['messages'].length
        stamp = now.utc.iso8601
        synchronize do |db|
          db.transaction(:immediate) do
            next nil if db.get_first_value('SELECT 1 FROM deleted_chats WHERE chat_id = ?', [chat_id])

            row = db.get_first_row('SELECT revision, generation FROM history_chats WHERE chat_id = ?', [chat_id])
            if row
              next nil if generation && row['generation'] && generation < row['generation']

              revision = row['revision'] + 1
              db.execute(<<~SQL, [app_name, model, headings[0], headings[1], stamp, revision, [generation, row['generation']].compact.max, count, json, chat_id])
                UPDATE history_chats SET app_name = ?, model = ?, heading_first = ?, heading_recent = ?,
                  updated_at = ?, revision = ?, generation = ?, message_count = ?, payload = ? WHERE chat_id = ?
              SQL
              revision
            else
              db.execute(<<~SQL, [chat_id, app_name, model, headings[0], headings[1], stamp, stamp, 1, generation, count, json])
                INSERT INTO history_chats (chat_id, app_name, model, heading_first, heading_recent,
                  created_at, updated_at, revision, generation, message_count, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              SQL
              1
            end
          end
        end
      end

      def get(chat_id)
        synchronize(create: false) do |db|
          row = db.get_first_row('SELECT * FROM history_chats WHERE chat_id = ?', [chat_id])
          row && row.merge('payload' => JSON.parse(row['payload']))
        end
      end

      # The list without the conversations themselves, newest first.
      def list(limit: 100, offset: 0)
        synchronize(create: false) do |db|
          db.execute(<<~SQL, [limit, offset])
            SELECT chat_id, app_name, model, title_user, heading_first, heading_recent,
              created_at, updated_at, revision, message_count
            FROM history_chats ORDER BY updated_at DESC, chat_id LIMIT ? OFFSET ?
          SQL
        end || []
      end

      # Removes the chat and keeps a tombstone, so nothing of it is written
      # again. Returns whether a row was removed.
      def delete(chat_id, now: Time.now)
        remove_row(chat_id) do |db|
          db.execute('INSERT OR IGNORE INTO deleted_chats (chat_id, deleted_at) VALUES (?, ?)', [chat_id, now.utc.iso8601])
        end
      end

      # Removes the chat's row without a tombstone: the chat has nothing left
      # to keep for now (its user messages were removed), and what it says
      # next is kept again. Does not create the file. Returns whether a row
      # was removed.
      def clear(chat_id)
        return false unless File.exist?(@path)

        remove_row(chat_id)
      end

      # Whether a checkpoint after a removal is still waiting for a reader.
      def checkpoint_pending?
        @checkpoint_pending
      end

      def close
        @mutex.synchronize do
          checkpoint(@db) if @db && @checkpoint_pending
          @db&.close
          @db = nil
        end
      end

      private

      def remove_row(chat_id)
        synchronize do |db|
          removed = db.transaction(:immediate) do
            db.execute('DELETE FROM history_chats WHERE chat_id = ?', [chat_id])
            changed = db.changes.positive?
            yield(db) if block_given?
            changed
          end
          @checkpoint_pending = true if removed
          removed
        end
      end

      # With create: false, yields nothing (and returns nil) while there is
      # no history file yet, instead of creating one to read from.
      def synchronize(create: true)
        @mutex.synchronize do
          next nil unless create || @db || File.exist?(@path)

          db = connection
          result = yield(db)
          checkpoint(db) if @checkpoint_pending
          result
        end
      end

      # PRAGMA wal_checkpoint reports in its first column whether a reader
      # kept it from finishing; it is tried again after the next use.
      def checkpoint(db)
        busy, = db.get_first_row('PRAGMA wal_checkpoint(TRUNCATE)')&.values
        @checkpoint_pending = busy.to_i != 0
      end

      def connection
        @db ||= open
      end

      def open
        create_file
        db = SQLite3::Database.new(@path, results_as_hash: true)
        begin
          # Waits by sleeping in Ruby, which lets the server's other tasks
          # run; busy_timeout would hold the interpreter while it waits.
          db.busy_handler_timeout = @busy_timeout_ms
          db.execute('PRAGMA journal_mode = WAL')
          db.execute('PRAGMA secure_delete = ON')
          db.execute('PRAGMA temp_store = MEMORY')
          db.execute('PRAGMA synchronous = NORMAL')
          migrate!(db)
          tighten_permissions
          db
        rescue StandardError
          db.close
          raise
        end
      end

      # Creates the file readable by the owner only before SQLite opens it,
      # and narrows an existing file before anything is read or written.
      def create_file
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.open(@path, File::WRONLY | File::CREAT, 0o600) { nil }
        tighten_permissions
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
              revision INTEGER NOT NULL, generation INTEGER, message_count INTEGER NOT NULL, payload TEXT NOT NULL)
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
