# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # Speaker-labeled plain text importer.
      #
      # Format:
      #   Alice: Hello, how are you?
      #   Bob: Doing well, thanks.
      #     Continuation lines are indented or follow until the next "Name:" header.
      #   Alice: Great to hear.
      #
      # Each unique speaker label becomes a participant. By default they
      # are role "human"; override via options[:default_role] = "narrator"
      # for monologue corpora etc.
      module PlainText
        module_function

        # Match "Speaker Name:" at the start of a line, capturing the name
        # and the remainder of the line. Names may contain spaces, hyphens,
        # apostrophes, and dots, but must start with a letter to avoid
        # matching ordinary text colons (e.g. "URL: http://...").
        SPEAKER_LINE = /\A([A-Za-z][\w'.\- ]{0,63}?):\s?(.*)\z/.freeze

        def can_import?(input)
          return false unless input.is_a?(String) && !input.strip.empty?
          input.each_line.any? { |line| line.chomp.match?(SPEAKER_LINE) }
        rescue StandardError
          false
        end

        def import(input, options = {})
          raise ArgumentError, 'PlainText import requires a String input' unless input.is_a?(String)

          default_role = options[:default_role] || options['default_role'] || 'human'
          turns = parse_turns(input)
          raise ArgumentError, 'No speaker-labeled lines found' if turns.empty?

          participants = {}
          turns.each do |label, _text|
            participants[label] ||= Base.participant_id(label)
          end

          messages = turns.each_with_index.map do |(label, text), idx|
            {
              'id' => Base.message_id(idx),
              'speaker' => { 'id' => participants[label] },
              'text' => text
            }
          end

          participant_objs = participants.map do |label, pid|
            { 'id' => pid, 'label' => label, 'role' => default_role }
          end

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'plain-text', options: options),
            'participants' => participant_objs,
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        # Returns an array of [speaker_label, text] pairs preserving order.
        # Continuation lines (no leading "Name:") are appended to the
        # previous turn separated by a newline.
        def parse_turns(input)
          turns = []
          current = nil
          input.each_line do |raw|
            line = raw.chomp
            if (m = line.match(SPEAKER_LINE))
              turns << current if current
              current = [m[1].strip, m[2].to_s.strip]
            elsif current
              addition = line.strip
              current[1] = current[1].empty? ? addition : "#{current[1]}\n#{addition}" unless addition.empty?
            end
            # Lines before the first speaker header are silently ignored.
          end
          turns << current if current
          turns
        end
      end
    end
  end
end
