# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require_relative 'ids'
require_relative 'server_owner'
require_relative 'ledger_schema'
require_relative '../utils/environment'

module Monadic
  module Workspace
    # The record of which chat owns which workspace folder. The folders say
    # what they are for people browsing the shared folder; this ledger is
    # what the server trusts. Paths are stored relative to the shared folder,
    # so the same ledger reads the same from the host and from the container.
    #
    # A JSON file guarded by a lock file: every change rereads the file under
    # an exclusive lock and replaces it by renaming a fully written copy, so
    # a crash mid-write leaves the previous ledger whole.
    #
    # A ledger of an earlier version is read in the current form without
    # being changed; the first change keeps its bytes as they were in
    # ledger.json.v1.bak (made and settled on disk before anything else) and
    # then saves the current version. Nothing is put back automatically:
    # going back to the backup loses what was recorded since.
    class Ledger
      SCHEMA_VERSION = LedgerSchema::VERSION
      FILE_NAME = 'ledger.json'

      class Conflict < StandardError; end
      # The ledger cannot be used: nothing is registered or removed then.
      class Unreadable < StandardError; end
      # Not JSON.
      class Syntax < Unreadable; end
      # JSON, but not of the ledger's form (LedgerSchema).
      class Shape < Unreadable; end
      # Written by a newer version.
      class Newer < Unreadable; end
      # The earlier version could not be kept before the upgrade; nothing
      # was changed.
      class NotUpgraded < Unreadable; end
      # A change was saved but may not be settled on disk: nothing more is
      # written to this ledger by this process (it is looked at again when
      # the server starts again).
      class Unsettled < Unreadable; end

      # Ledgers this process stopped writing (Unsettled), by path, for every
      # Ledger object of that path.
      @unsettled = {}
      @unsettled_mutex = Mutex.new

      def self.unsettled?(path)
        @unsettled_mutex.synchronize { @unsettled.key?(identity(path)) }
      end

      def self.unsettle!(path)
        @unsettled_mutex.synchronize { @unsettled[identity(path)] = true }
      end

      # The same ledger whatever path names it (a link to its folder, a
      # relative path, another spelling of its name where case does not
      # count): the real path of its folder and the name the folder holds it
      # under (the name as given while there is no file yet).
      def self.identity(path)
        full = File.expand_path(path)
        dir = File.realpath(File.dirname(full))
        name = File.basename(full)
        if File.exist?(full)
          held = Dir.children(dir).find { |entry| File.identical?(File.join(dir, entry), full) }
          name = held if held
        end
        File.join(dir, name)
      end

      def self.clear_unsettled!
        @unsettled_mutex.synchronize { @unsettled.clear }
      end

      # What the ledger does to the disk, in one place. Every failure is
      # passed on (a folder that cannot be synced is not taken as synced).
      module Disk
        module_function

        # Makes a new file with these bytes, settled. A file of that name
        # already there is left as it is (Errno::EEXIST); a file this call
        # made and could not finish is removed.
        def create_exclusive(path, bytes)
          file = File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
          begin
            file.write(bytes)
            file.flush
            file.fsync
          rescue StandardError
            file.close
            File.unlink(path) rescue nil
            raise
          ensure
            file.close unless file.closed?
          end
        end

        def sync_file(path)
          File.open(path, File::RDONLY) { |f| f.fsync }
        end

        def sync_dir(dir)
          File.open(dir, File::RDONLY) { |d| d.fsync }
        end

        def replace(from, to)
          File.rename(from, to)
        end
      end

      def self.default_path
        File.join(Monadic::Utils::Environment.state_path, FILE_NAME)
      end

      def self.default
        @default_mutex.synchronize do
          path = default_path
          @default = nil if @default && @default.path != path
          @default ||= new(path)
        end
      end

      @default_mutex = Mutex.new

      attr_reader :path

      def initialize(path)
        @path = path
        @lock_path = "#{path}.lock"
        @mutex = Mutex.new
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      end

      def schema_version
        read { |data| data['schema_version'] }
      end

      # Records a new workspace for a chat. A chat holds one workspace; a
      # second registration for the same chat, or a reused id or folder, is
      # refused rather than overwriting what is there.
      def register_workspace(chat_id:, workspace_id:, app_name:, relative_dir:, created_at: Time.now)
        raise ArgumentError, 'invalid chat id' unless Ids.valid?(:chat, chat_id)
        raise ArgumentError, 'invalid workspace id' unless Ids.valid?(:workspace, workspace_id)
        raise ArgumentError, 'relative_dir must be relative' if relative_dir.start_with?('/') || relative_dir.split('/').include?('..')

        write do |data|
          chats = data['chats']
          workspaces = data['workspaces']
          raise Conflict, 'chat already has a workspace' if chats.dig(chat_id, 'workspace_id')
          raise Conflict, 'workspace id already registered' if workspaces.key?(workspace_id)
          raise Conflict, 'folder already registered' if workspaces.values.any? { |w| w['relative_dir'] == relative_dir }

          stamp = created_at.utc.iso8601
          workspaces[workspace_id] = {
            'chat_id' => chat_id,
            'relative_dir' => relative_dir,
            'app_name' => app_name.to_s,
            'created_at' => stamp
          }
          chats[chat_id] = { 'workspace_id' => workspace_id, 'created_at' => stamp }
        end
        workspace(workspace_id)
      end

      ATTACHMENT_STATES = LedgerSchema::ATTACHMENT_STATES

      # An attachment is recorded before its file is written, as validating,
      # so a crash between the two leaves a record that reconcile! can fail
      # rather than a file nobody accounts for.
      def register_attachment(attachment_id:, chat_id:, workspace_id:, purpose:, original_name:,
                              relative_path:, created_at: Time.now)
        raise ArgumentError, 'invalid attachment id' unless Ids.valid?(:attachment, attachment_id)
        raise ArgumentError, 'relative_path must be relative' if relative_path.start_with?('/') || relative_path.split('/').include?('..')

        write do |data|
          raise Conflict, 'attachment id already registered' if data['attachments'].key?(attachment_id)
          unless data['workspaces'].dig(workspace_id, 'chat_id') == chat_id
            raise Conflict, 'workspace does not belong to this chat'
          end

          data['attachments'][attachment_id] = {
            'chat_id' => chat_id,
            'workspace_id' => workspace_id,
            'purpose' => purpose.to_s,
            'original_name' => original_name.to_s,
            'relative_path' => relative_path,
            'status' => 'validating',
            'created_at' => created_at.utc.iso8601
          }
        end
        attachment(attachment_id)
      end

      def update_attachment(attachment_id, status:, **fields)
        raise ArgumentError, "unknown state #{status}" unless ATTACHMENT_STATES.include?(status)

        write do |data|
          record = data['attachments'][attachment_id] or raise Conflict, 'unknown attachment'
          record['status'] = status
          fields.each { |key, value| record[key.to_s] = value }
        end
        attachment(attachment_id)
      end

      def attachment(attachment_id)
        read do |data|
          record = data['attachments'][attachment_id]
          record && record.transform_keys(&:to_sym).merge(attachment_id: attachment_id)
        end
      end

      # Attachments left validating by a stopped server never finished; they
      # are marked failed so nothing treats them as usable. Returns them.
      def reconcile_interrupted!
        return [] if !File.exist?(@path) || read { |data| data['attachments'].none? { |_, r| r['status'] == 'validating' } }

        write do |data|
          data['attachments'].select { |_, r| r['status'] == 'validating' }.map do |id, record|
            record['status'] = 'failed'
            record['failure'] = 'interrupted'
            record.transform_keys(&:to_sym).merge(attachment_id: id)
          end
        end
      end

      def workspace(workspace_id)
        read { |data| export(workspace_id, data['workspaces'][workspace_id]) }
      end

      # The workspaces and attachments as one consistent read, for a caller
      # that matches many folders against them (the shared folder's list).
      def snapshot
        read { |data| { workspaces: data['workspaces'], attachments: data['attachments'] } }
      end

      def workspace_for_chat(chat_id)
        read do |data|
          workspace_id = data['chats'].dig(chat_id, 'workspace_id')
          workspace_id && export(workspace_id, data['workspaces'][workspace_id])
        end
      end

      private

      def export(workspace_id, record)
        return nil unless record

        record.transform_keys(&:to_sym).merge(workspace_id: workspace_id)
      end

      def read
        locked(File::LOCK_SH) { yield load.first }
      end

      # Changes are made only by the server that holds the state folder
      # (ServerOwner), each one whole before that server stops.
      def write
        locked(File::LOCK_EX) do
          ServerOwner.writing do
            raise Unsettled, 'the last change to the ledger may not be on disk; restart Monadic Chat' if self.class.unsettled?(@path)

            data, version, raw = load
            result = yield data
            # A change that would leave the ledger out of form is not saved.
            checked_current(data)
            keep_earlier(raw) if raw && version < SCHEMA_VERSION
            save(data)
            result
          end
        end
      end

      # The mutex covers threads of this process; the lock file covers a
      # second process on the same machine. Between the container and the
      # host it is not relied on: one server holds the folder (ServerOwner).
      def locked(mode)
        @mutex.synchronize do
          File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
            lock.flock(mode)
            yield
          end
        end
      end

      # [data in the current form, the version on disk, the bytes on disk
      # (nil when there is no file yet)].
      def load
        raw = File.exist?(@path) ? File.binread(@path) : nil
        data, version = schema { LedgerSchema.check!(raw ? JSON.parse(raw) : {}) }
        [data, version, raw]
      rescue JSON::ParserError
        raise Syntax, 'ledger is not valid JSON'
      end

      def checked_current(data)
        schema { LedgerSchema.check_current!(data) }
      end

      def schema
        yield
      rescue LedgerSchema::Newer => e
        raise Newer, e.message
      rescue LedgerSchema::Shape => e
        raise Shape, "ledger is not of the expected form: #{e.message}"
      end

      # Keeps the bytes of the earlier version before the first change, and
      # settles them on disk; an existing backup with other bytes is left as
      # it is and these go under another name.
      def keep_earlier(raw)
        backup = "#{@path}.v1.bak"
        if File.exist?(backup) && File.binread(backup) == raw
          Disk.sync_file(backup)
        else
          backup = "#{@path}.v1.#{SecureRandom.hex(6)}.bak" if File.exist?(backup)
          Disk.create_exclusive(backup, raw)
        end
        Disk.sync_dir(File.dirname(@path))
      rescue SystemCallError, IOError
        raise NotUpgraded, 'the ledger could not be kept before its upgrade; nothing was changed'
      end

      def save(data)
        tmp = "#{@path}.#{SecureRandom.hex(6)}.tmp"
        # On failure it removes what it made, and only that.
        Disk.create_exclusive(tmp, JSON.pretty_generate(data))
        begin
          Disk.replace(tmp, @path)
        rescue StandardError
          File.unlink(tmp) rescue nil
          raise
        end
        begin
          Disk.sync_dir(File.dirname(@path))
        rescue SystemCallError, IOError
          self.class.unsettle!(@path)
          raise Unsettled, 'the last change to the ledger may not be on disk; restart Monadic Chat'
        end
      end
    end
  end
end
