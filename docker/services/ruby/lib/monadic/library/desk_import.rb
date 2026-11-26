# frozen_string_literal: true

require 'securerandom'
require 'stringio'
require_relative 'manager'
require_relative 'file_importer'
require_relative 'import_tracker'
require_relative 'conversation_draft'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Library
    # A document on the work screen kept in the Library, as the version the
    # user's tab shows (item and sha256): its bytes, read and checked
    # against that version, are copied for the import (library/imports/ of
    # the shared folder, as an upload is) and imported (Manager.import_file),
    # and the copy goes when the import ends.
    #
    # A conversation record (an item ConversationDraft put, which names its
    # chat) is kept as one: only from an app that lets its chats be kept,
    # titled as the user names it (else by its first heading), and naming
    # its chat; one keep of a chat at a time (in_progress). When records of
    # that chat are in the Library already, the user chooses (Choose):
    # update one of them (its id is kept; refused when it changed since it
    # was offered, checked again as it is written) or keep this one besides.
    module DeskImport
      class Refused < StandardError; end

      # Records of the chat are in the Library: the user chooses.
      class Choose < StandardError
        attr_reader :records

        def initialize(records)
          @records = records
          super('choose')
        end
      end

      TITLE_CHARS = 200

      @keeping = {}
      @keeping_lock = Mutex.new

      module_function

      # Starts the import in a thread of its own; returns its ImportTracker id.
      # app_name: the app of the chat it is kept from (the server's).
      # title: the user's name for a record. choice: nil, 'new', or
      # { 'update' => conversation_id, 'seen' => the record's revision when
      # it was offered }.
      def start(board, item_id, sha256, app_name: nil, title: nil, choice: nil, store: Store.new)
        entry = board.file_entry(item_id, sha256: sha256)
        name = File.basename(entry['path'].to_s)
        raise Refused, 'not_importable' unless FileImporter.importable?(name)
        raise Refused, 'too_large' if entry['size'].to_i > FileImporter::MAX_BYTES

        bytes = board.file_read(item_id, sha256: sha256, limit: FileImporter::MAX_BYTES)[:bytes]
        options = { title: File.basename(name, '.*') }
        target = nil
        source = nil
        started = false
        if (draft = board.item(item_id)&.dig('draft'))
          raise Refused, 'not_saved_by_app' unless ConversationDraft.app_allows?(app_name)

          options = record_options(bytes, name, draft['source_chat_id'], title)
          raise Refused, 'in_progress' unless hold(draft['source_chat_id'].to_s)

          source = draft['source_chat_id'].to_s
          target = target_of(store, source, choice)
        end
        copy = write_copy(name, bytes)
        import_id = ImportTracker.create
        ImportTracker.update(import_id, filename: name, upload_bytes: bytes.bytesize)
        Thread.new do
          run(import_id, store, copy, name, options, target)
        ensure
          release(source) if source
        end
        started = true
        import_id
      ensure
        release(source) if source && !started
      end

      def hold(source)
        @keeping_lock.synchronize { @keeping[source] ? false : (@keeping[source] = true) }
      end

      def release(source)
        @keeping_lock.synchronize { @keeping.delete(source) }
      end

      # The title of a record: the user's (at most TITLE_CHARS), else its
      # first heading as kept (a line `# …`), else its file's name.
      def record_options(bytes, name, source_chat_id, title = nil)
        given = title.to_s.strip[0, TITLE_CHARS].to_s
        heading = bytes.dup.force_encoding('UTF-8').scrub[/^#[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$/, 1].to_s.strip
        chosen = [given, heading, File.basename(name, '.*')].find { |t| !t.empty? }
        { title: chosen, content_type: 'conversation', source: 'monadic-chat', source_chat_id: source_chat_id.to_s }
      end

      # The entry to update, or nil for a new one.
      def target_of(store, source_chat_id, choice)
        return nil if choice == 'new'

        records = store.records_from_chat(source_chat_id)
        return nil if records.empty? && choice.nil?
        raise Choose, records unless choice.is_a?(Hash) && choice['update']

        record = records.find { |r| r[:conversation_id] == choice['update'].to_s }
        raise Refused, 'record_missing' unless record
        raise Refused, 'record_changed' unless record[:revision].to_s == choice['seen'].to_s

        { id: record[:conversation_id], revision: record[:revision].to_s }
      end

      def run(import_id, store, copy, name, options = { title: File.basename(name, '.*') }, target = nil)
        Thread.current.report_on_exception = false
        on_stage = ->(stage) { ImportTracker.update(import_id, stage: stage.to_s) }
        result = if target
                   Manager.replace_file(store: store, conversation_id: target[:id], revision: target[:revision],
                                        path: copy, filename: name, options: options, on_stage: on_stage)
                 else
                   Manager.import_file(store: store, path: copy, filename: name, options: options, on_stage: on_stage)
                 end
        ImportTracker.update(import_id, stage: 'done', finished_at: Time.now, conversation_id: result[:conversation_id],
                                        counts: result[:counts].transform_keys(&:to_s),
                                        updated: result[:updated] ? true : nil, leftover: result[:leftover] ? true : nil)
      rescue Manager::Changed
        ImportTracker.update(import_id, stage: 'error', finished_at: Time.now, error: 'record_changed')
      rescue StandardError => e
        ImportTracker.update(import_id, stage: 'error', finished_at: Time.now, error: e.class.name.split('::').last)
      ensure
        (Monadic::Utils::SharedPathGuard.delete_file!(copy) rescue nil)
      end

      def write_copy(name, bytes)
        dir = File.join(Monadic::Utils::Environment.data_path, 'library', 'imports')
        Monadic::Utils::SharedPathGuard.mkdir_p!(dir)
        copy = File.join(dir, "#{Time.now.to_i}_#{SecureRandom.hex(4)}_#{name}")
        Monadic::Utils::SharedPathGuard.write_file!(copy, StringIO.new(bytes), replace: false)
        copy
      end
    end
  end
end
