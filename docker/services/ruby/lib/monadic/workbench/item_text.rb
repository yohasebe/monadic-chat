# frozen_string_literal: true

require_relative 'file_item'
require_relative '../workspace/file_types'

module Monadic
  module Workbench
    # The text of a document on the work screen (a PDF, an Office document,
    # a text file) at a version, for the AI's look at it (text_of):
    # converted as a document imported for a message is, and given only
    # when the file was that version before and after.
    module ItemText
      EXTENSIONS = Monadic::Workspace::FileTypes::DOCUMENT.keys.freeze

      # Why there is no text (a short reason the page says).
      class Failed < StandardError; end

      module_function

      def document?(path)
        EXTENSIONS.include?(File.extname(path.to_s).downcase)
      end

      # The converted text.
      def text_of(board, item_id, sha256, converter:)
        entry = board.file_entry(item_id.to_s, sha256: sha256.to_s)
        raise Failed, 'not_a_document' unless document?(entry['path'])
        raise Failed, 'changed' unless FileItem.same_version?(entry)

        text = converter.call(entry['path']).to_s
        raise Failed, 'changed' unless FileItem.same_version?(entry)
        raise Failed, 'empty' if text.strip.empty?

        text
      rescue Artifact::Changed
        raise Failed, 'changed'
      rescue Artifact::NotAllowed
        raise Failed, 'not_allowed'
      end
    end
  end
end
