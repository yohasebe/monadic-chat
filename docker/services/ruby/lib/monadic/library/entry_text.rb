# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'manager'
require_relative 'store'
require_relative 'originals'
require_relative 'file_importer'

module Monadic
  module Library
    # The text of a Library entry as the work screen shows it and the AI
    # reads it: what it holds, part by part (each part under the speaker or
    # the section it is), and its version, the SHA-256 of that text (the
    # same text gives the same version, whatever the entry is called).
    module EntryText
      class Missing < StandardError; end
      class Incomplete < StandardError; end
      class Changed < StandardError; end

      # How an entry is shown on the work screen, from its kept original:
      # a PDF as it is, a Markdown or code file as its text, anything else
      # (an Office document, an entry with no original) as the entry's
      # text. The office types are said so the AI can be given the file.
      CONTENT_TYPES = {
        'pdf' => 'application/pdf',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
      }.freeze

      LIMIT = 2 * 1024 * 1024

      module_function

      # { id:, title:, text:, version:, original: } of the entry, read now.
      # Missing when the entry is gone; Incomplete when its text was not
      # kept whole (too long to keep as it is).
      def of(conversation_id, store: Store.new)
        record = Manager.get_conversation_messages(store: store, conversation_id: conversation_id.to_s)
        raise Missing, 'the entry is not in the Library' unless record

        messages = record[:messages]
        raise Incomplete, record[:skipped_reason].to_s if !messages.is_a?(Array) || messages.empty?

        text = text_of(messages, record[:participants])[0, LIMIT]
        { id: record[:conversation_id], title: record[:title].to_s, text: text,
          version: Digest::SHA256.hexdigest(text), original: store.original_of(conversation_id) }
      end

      # How the entry is shown and read: { preview:, source:, version:,
      # original:, content_type: }. source 'original': the kept file is
      # shown (its SHA-256 is the version); 'text': the entry's text is.
      def shown(entry)
        original = entry[:original]
        ext = original && original['extension'].to_s.downcase
        if original && (ext == 'pdf' || FileImporter::MARKDOWN_EXTS.include?(ext) ||
                        (FileImporter.importable?("x.#{ext}") && !FileImporter::OFFICE_EXTS.include?(ext)))
          { preview: ext == 'pdf' ? 'pdf' : 'text', source: 'original', version: original['sha256'],
            original: original['sha256'], content_type: CONTENT_TYPES[ext] }.compact
        else
          { preview: 'text', source: 'text', version: entry[:version], original: original&.dig('sha256'),
            content_type: original ? CONTENT_TYPES[ext] : nil }.compact
        end
      end

      # The bytes of an entry as it is shown (record: the board's item
      # record: id, source, version), read now and only at that version:
      # the kept file while the entry still names it, or the entry's text.
      # Missing, Changed, Incomplete as they say.
      def bytes_for(record, store: Store.new)
        if record['source'] == 'original'
          raise Missing, 'the entry is not in the Library' unless Manager.get_conversation_details(store: store, conversation_id: record['id'])
          raise Changed, 'the entry names another file' unless store.original_of(record['id'])&.dig('sha256') == record['version']

          begin
            Originals.read(record['version'])
          rescue Originals::Missing
            raise Missing, 'the kept file is gone'
          rescue Originals::Changed
            raise Changed, 'the kept file changed'
          end
        else
          entry = of(record['id'], store: store)
          raise Changed, 'the entry changed' unless entry[:version] == record['version']

          entry[:text].b
        end
      end

      # The kept original of an Office entry (record['original']), checked
      # as bytes_for checks one, for the AI to be given the file; nil when
      # there is none.
      def original_for(record, store: Store.new)
        sha256 = record['original'] or return nil
        return nil unless store.original_of(record['id'])&.dig('sha256') == sha256

        Originals.read(sha256)
      rescue Originals::Missing, Originals::Changed
        nil
      end

      # The parts in order: a speaker's role over what they said, or the
      # text alone for a document's sections.
      def text_of(messages, participants)
        roles = Array(participants).each_with_object({}) { |p, h| h[p['id']] = p['role'] if p.is_a?(Hash) }
        parts = messages.filter_map do |message|
          next unless message.is_a?(Hash)

          body = message['text'].to_s.strip
          next if body.empty?

          role = roles[message.dig('speaker', 'id')]
          %w[human assistant].include?(role) ? "[#{role == 'human' ? 'User' : 'Assistant'}]\n#{body}" : body
        end
        "#{parts.join("\n\n")}\n"
      end
    end
  end
end
