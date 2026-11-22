# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative '../workspace/ids'
require_relative '../workspace/ledger'
require_relative '../utils/environment'

module Monadic
  module Workbench
    # Where a chat's workbench is kept between restarts: one folder per chat
    # in the state folder (workbench/<chat id>/), holding manifest.json (and
    # the folders of the runs going on, JobOutput). Only the server writes
    # here. The images themselves are in the chat's folder of the shared
    # folder (Artifact).
    #
    # The manifest is replaced whole: a fully written and synced copy is
    # renamed over it and the folder is synced, so a crash leaves the old
    # manifest or the new one. A manifest that cannot be read is reported
    # (Unreadable) and nothing is made from it. A manifest of the earlier
    # form (LEGACY_SCHEMA, whose images were kept here) is read as no board:
    # a new one is made, and what that form left is not touched.
    class Store
      DIRNAME = 'workbench'
      MANIFEST = 'manifest.json'
      SCHEMA = 2
      LEGACY_SCHEMA = 1

      class Unreadable < StandardError; end

      def self.default
        new(File.join(Monadic::Utils::Environment.state_path, DIRNAME))
      end

      attr_reader :root

      def initialize(root)
        @root = root
      end

      # The chat's folder, made (0700) when asked to.
      def chat_dir(chat_id, make: false)
        raise ArgumentError, 'invalid chat id' unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        dir = File.join(@root, chat_id)
        if make
          make_dir(@root)
          make_dir(dir)
        end
        dir
      end

      # The saved manifest, or nil when the chat has none (or one of the
      # earlier form).
      def load(chat_id)
        path = File.join(chat_dir(chat_id), MANIFEST)
        return nil unless File.file?(path)
        raise Unreadable, 'manifest is a link' if File.symlink?(path)

        data = JSON.parse(File.read(path))
        return nil if legacy?(data, chat_id)
        unless data.is_a?(Hash) && data['schema'] == SCHEMA && data['chat_id'] == chat_id
          raise Unreadable, 'manifest is not of this form'
        end

        data
      rescue JSON::ParserError
        raise Unreadable, 'manifest is not JSON'
      end

      def save(chat_id, data)
        dir = chat_dir(chat_id, make: true)
        temp = File.join(dir, ".#{MANIFEST}.#{SecureRandom.hex(6)}")
        Monadic::Workspace::Ledger::Disk.create_exclusive(temp, JSON.generate(data.merge('schema' => SCHEMA, 'chat_id' => chat_id)))
        begin
          Monadic::Workspace::Ledger::Disk.replace(temp, File.join(dir, MANIFEST))
        rescue StandardError
          File.unlink(temp) rescue nil
          raise
        end
        Monadic::Workspace::Ledger::Disk.sync_dir(dir)
      end

      def exists?(chat_id)
        File.file?(File.join(chat_dir(chat_id), MANIFEST))
      end

      private

      # A manifest of the earlier form: its schema, its chat, and the
      # collections that form had.
      def legacy?(data, chat_id)
        data.is_a?(Hash) && data['schema'] == LEGACY_SCHEMA && data['chat_id'] == chat_id &&
          data['items'].is_a?(Hash) && data['operations'].is_a?(Hash)
      end

      # True when this call made the folder.
      def make_dir(dir)
        Dir.mkdir(dir, 0o700)
        true
      rescue Errno::EEXIST
        raise Errno::ENOTDIR, dir unless File.directory?(dir) && !File.symlink?(dir)

        false
      end
    end
  end
end
