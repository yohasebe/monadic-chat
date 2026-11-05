# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require_relative '../workspace/ids'
require_relative '../workspace/ledger'
require_relative '../utils/environment'

module Monadic
  module Workbench
    # Where a chat's workbench is kept between restarts: one folder per chat
    # in the state folder (workbench/<chat id>/), holding manifest.json and
    # the kept bytes (candidates/ and artifacts/). Only the server writes
    # here.
    #
    # The manifest is replaced whole: a fully written and synced copy is
    # renamed over it and the folder is synced, so a crash leaves the old
    # manifest or the new one. A manifest that cannot be read is reported
    # (Unreadable) and nothing is made from it.
    class Store
      DIRNAME = 'workbench'
      MANIFEST = 'manifest.json'
      SCHEMA = 1

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

      # The saved manifest, or nil when the chat has none.
      def load(chat_id)
        path = File.join(chat_dir(chat_id), MANIFEST)
        return nil unless File.file?(path)
        raise Unreadable, 'manifest is a link' if File.symlink?(path)

        data = JSON.parse(File.read(path))
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

      # Writes bytes to a new file at relative (a path of folders made by
      # the server under the chat's folder), settled. A file already there
      # is left as it is (Errno::EEXIST).
      def write_new(chat_id, relative, bytes)
        path = File.join(chat_dir(chat_id, make: true), relative)
        parent = File.dirname(path)
        made = []
        File.dirname(relative).split('/').reject { |p| p == '.' }.inject(chat_dir(chat_id)) do |at, part|
          step = File.join(at, part)
          made << at if make_dir(step)
          step
        end
        Monadic::Workspace::Ledger::Disk.create_exclusive(path, bytes)
        Monadic::Workspace::Ledger::Disk.sync_dir(parent)
        made.each { |dir| Monadic::Workspace::Ledger::Disk.sync_dir(dir) }
        path
      end

      def path(chat_id, relative)
        File.join(chat_dir(chat_id), relative)
      end

      def exists?(chat_id)
        File.file?(File.join(chat_dir(chat_id), MANIFEST))
      end

      # The bytes of the file at relative, read without following a link.
      def read(chat_id, relative)
        File.open(path(chat_id, relative), File::RDONLY | File::NOFOLLOW, binmode: true, &:read)
      end

      # Removes a candidate's folder (candidates/<id>/) and what is in it.
      def remove_candidate(chat_id, candidate_id)
        raise ArgumentError, 'invalid candidate id' unless candidate_id.to_s.match?(/\Ak_[a-f0-9]{20}\z/)

        dir = File.join(chat_dir(chat_id), 'candidates')
        FileUtils.rm_rf(File.join(dir, candidate_id))
        Monadic::Workspace::Ledger::Disk.sync_dir(dir) if File.directory?(dir)
      end

      private

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
