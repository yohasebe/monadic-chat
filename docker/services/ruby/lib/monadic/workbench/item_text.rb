# frozen_string_literal: true

require_relative 'file_item'
require_relative '../workspace/file_types'

module Monadic
  module Workbench
    # The text of a document on the work screen (a PDF, an Office document,
    # a text file), at the version the user's tab shows, for the user's
    # message (of), or for the AI's look at it (text_of): converted as a
    # document imported for a message is, and given only when the file was
    # that version before and after. What of reaches is the user's to send
    # or not.
    module ItemText
      EXTENSIONS = Monadic::Workspace::FileTypes::DOCUMENT.keys.freeze

      # Why there is no text (a short reason the page says).
      class Failed < StandardError; end

      module_function

      def document?(path)
        EXTENSIONS.include?(File.extname(path.to_s).downcase)
      end

      # The text of the item item_id of board at version sha256, as the
      # message takes it ("Filename: …" over the converted text). converter
      # gives the text of a file of the shared folder (its path).
      def of(board, item_id, sha256, converter:)
        entry = board.file_entry(item_id.to_s, sha256: sha256.to_s)
        "\n---\nFilename: #{entry['name']}\n---\n#{text_of(board, item_id, sha256, converter: converter)}"
      rescue Artifact::Changed
        raise Failed, 'changed'
      rescue Artifact::NotAllowed
        raise Failed, 'not_allowed'
      end

      # The converted text alone.
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
