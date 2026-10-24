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
      TITLE_LIMIT = 120

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
      # or nil when the write is not taken: the chat is deleted or Private,
      # another tab has it (it was resumed there), or `generation` is older
      # than that of the tab's connection that wrote last. The time of the
      # last activity moves only when the number of messages changes, so a
      # Session Context that arrives later does not reorder the list.
      def save(chat_id, payload, tab: nil, generation: nil, app_name: nil, model: nil, headings: [nil, nil],
               search_text: nil, now: Time.now)
        json = JSON.generate(payload)
        count = payload['messages'].length
        stamp = now.utc.iso8601
        synchronize do |db|
          db.transaction(:immediate) do
            next nil if db.get_first_value('SELECT 1 FROM deleted_chats WHERE chat_id = ?', [chat_id])

            row = db.get_first_row('SELECT revision, generation, owner_tab, message_count, last_activity_at FROM history_chats WHERE chat_id = ?', [chat_id])
            if row
              next nil unless writer?(row, tab, generation)

              revision = row['revision'] + 1
              activity = row['message_count'] == count ? row['last_activity_at'] : stamp
              db.execute(<<~SQL, [app_name, model, headings[0], headings[1], stamp, activity, revision, tab || row['owner_tab'], newest(generation, row, tab), count, search_text, json, chat_id])
                UPDATE history_chats SET app_name = ?, model = ?, heading_first = ?, heading_recent = ?,
                  updated_at = ?, last_activity_at = ?, revision = ?, owner_tab = ?, generation = ?,
                  message_count = ?, search_text = ?, payload = ? WHERE chat_id = ?
              SQL
              revision
            else
              db.execute(<<~SQL, [chat_id, app_name, model, headings[0], headings[1], stamp, stamp, stamp, 1, tab, generation, count, search_text, json])
                INSERT INTO history_chats (chat_id, app_name, model, heading_first, heading_recent,
                  created_at, updated_at, last_activity_at, revision, owner_tab, generation, message_count,
                  search_text, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              SQL
              1
            end
          end
        end
      end

      # Gives the chat to `tab` (it is resumed there): from now on only that
      # tab's connections write it, the one given and newer ones. Returns the
      # chat as get does, or nil when there is none to resume.
      def claim(chat_id, tab:, generation:)
        synchronize(create: false) do |db|
          db.transaction(:immediate) do
            next nil if db.get_first_value('SELECT 1 FROM deleted_chats WHERE chat_id = ?', [chat_id])

            db.execute('UPDATE history_chats SET owner_tab = ?, generation = ? WHERE chat_id = ?', [tab, generation, chat_id])
            next nil unless db.changes.positive?

            row = db.get_first_row('SELECT * FROM history_chats WHERE chat_id = ?', [chat_id])
            row.except('search_text').merge('payload' => JSON.parse(row['payload']))
          end
        end
      end

      # The user's own name for the chat; nil or blank gives the headings back.
      def rename(chat_id, title)
        title = title.to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, TITLE_LIMIT]
        synchronize(create: false) do |db|
          db.execute('UPDATE history_chats SET title_user = ? WHERE chat_id = ?', [title.empty? ? nil : title, chat_id])
          db.changes.positive?
        end || false
      end

      def get(chat_id)
        synchronize(create: false) do |db|
          row = db.get_first_row('SELECT * FROM history_chats WHERE chat_id = ?', [chat_id])
          row && row.except('search_text').merge('payload' => JSON.parse(row['payload']))
        end
      end

      # The list without the conversations themselves, the latest activity
      # first. `query` matches the name, the headings and the messages' text.
      def list(limit: 100, offset: 0, query: nil)
        where = ''
        args = []
        unless query.to_s.strip.empty?
          like = "%#{query.to_s.strip.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
          where = "WHERE title_user LIKE ? ESCAPE '\\' OR heading_first LIKE ? ESCAPE '\\' " \
                  "OR heading_recent LIKE ? ESCAPE '\\' OR search_text LIKE ? ESCAPE '\\'"
          args = [like] * 4
        end
        synchronize(create: false) do |db|
          db.execute(<<~SQL, args + [limit, offset])
            SELECT chat_id, app_name, model, title_user, heading_first, heading_recent,
              created_at, updated_at, last_activity_at, revision, message_count
            FROM history_chats #{where} ORDER BY last_activity_at DESC, chat_id LIMIT ? OFFSET ?
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

      # A tab writes the chat it has (a row from before tabs were recorded
      # has none); within the tab, a connection older than the one that
      # wrote last does not.
      def writer?(row, tab, generation)
        owner = row['owner_tab']
        return false if tab && owner && owner != tab
        return true if tab && owner.nil?
        return true unless generation && row['generation']

        generation >= row['generation']
      end

      def newest(generation, row, tab)
        tab && row['owner_tab'].nil? ? generation : [generation, row['generation']].compact.max
      end

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
              last_activity_at TEXT NOT NULL, revision INTEGER NOT NULL, owner_tab TEXT, generation INTEGER,
              message_count INTEGER NOT NULL, search_text TEXT, payload TEXT NOT NULL)
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
