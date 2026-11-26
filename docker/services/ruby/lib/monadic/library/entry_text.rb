# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'manager'
require_relative 'store'

module Monadic
  module Library
    # The text of a Library entry as the work screen shows it and the AI
    # reads it: what it holds, part by part (each part under the speaker or
    # the section it is), and its version, the SHA-256 of that text (the
    # same text gives the same version, whatever the entry is called).
    module EntryText
      class Missing < StandardError; end
      class Incomplete < StandardError; end

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
