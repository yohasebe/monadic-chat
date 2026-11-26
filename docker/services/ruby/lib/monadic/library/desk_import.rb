# frozen_string_literal: true

require 'securerandom'
require 'stringio'
require_relative 'manager'
require_relative 'file_importer'
require_relative 'import_tracker'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Library
    # A document on the work screen kept in the Library, as the version the
    # user's tab shows (item and sha256): its bytes, read and checked
    # against that version, are copied for the import (library/imports/ of
    # the shared folder, as an upload is) and imported (Manager.import_file),
    # and the copy goes when the import ends.
    module DeskImport
      class Refused < StandardError; end

      module_function

      # Starts the import in a thread of its own; returns its ImportTracker id.
      def start(board, item_id, sha256, store: Store.new)
        entry = board.file_entry(item_id, sha256: sha256)
        name = File.basename(entry['path'].to_s)
        raise Refused, 'not_importable' unless FileImporter.importable?(name)
        raise Refused, 'too_large' if entry['size'].to_i > FileImporter::MAX_BYTES

        bytes = board.file_read(item_id, sha256: sha256, limit: FileImporter::MAX_BYTES)[:bytes]
        copy = write_copy(name, bytes)
        import_id = ImportTracker.create
        ImportTracker.update(import_id, filename: name, upload_bytes: bytes.bytesize)
        Thread.new { run(import_id, store, copy, name) }
        import_id
      end

      def run(import_id, store, copy, name)
        Thread.current.report_on_exception = false
        result = Manager.import_file(store: store, path: copy, filename: name,
                                     options: { title: File.basename(name, '.*') },
                                     on_stage: ->(stage) { ImportTracker.update(import_id, stage: stage.to_s) })
        ImportTracker.update(import_id, stage: 'done', finished_at: Time.now, conversation_id: result[:conversation_id],
                                        counts: result[:counts].transform_keys(&:to_s))
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
