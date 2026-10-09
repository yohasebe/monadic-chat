# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require_relative 'ids'
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
    class Ledger
      SCHEMA_VERSION = 1
      FILE_NAME = 'ledger.json'

      class Conflict < StandardError; end
      class Unreadable < StandardError; end

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

      ATTACHMENT_STATES = %w[validating ready failed].freeze

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
        locked(File::LOCK_SH) { yield load }
      end

      def write
        locked(File::LOCK_EX) do
          data = load
          result = yield data
          save(data)
          result
        end
      end

      # The mutex covers threads of this process; the lock file covers a
      # second process (the server run from the host while a container runs).
      def locked(mode)
        @mutex.synchronize do
          File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
            lock.flock(mode)
            yield
          end
        end
      end

      def load
        data = File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
        raise Unreadable, 'ledger is not a JSON object' unless data.is_a?(Hash)

        version = data['schema_version'] || SCHEMA_VERSION
        raise Unreadable, "ledger schema #{version} is newer than this version understands" if version > SCHEMA_VERSION

        data['schema_version'] = version
        data['chats'] ||= {}
        data['workspaces'] ||= {}
        data['attachments'] ||= {}
        data
      rescue JSON::ParserError
        raise Unreadable, 'ledger is not valid JSON'
      end

      def save(data)
        tmp = "#{@path}.#{SecureRandom.hex(6)}.tmp"
        File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
          f.write(JSON.pretty_generate(data))
          f.flush
          f.fsync
        end
        File.rename(tmp, @path)
      ensure
        File.unlink(tmp) if tmp && File.exist?(tmp)
      end
    end
  end
end
