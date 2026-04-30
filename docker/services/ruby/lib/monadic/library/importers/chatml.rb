# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # ChatML / OpenAI Messages format importer.
      #
      # Accepts either:
      #   - a bare array of {role, content} hashes
      #   - a request body Hash with "messages" key
      module ChatML
        module_function

        ROLE_MAP = {
          'user' => 'human',
          'assistant' => 'assistant',
          'system' => 'system',
          'tool' => 'other'
        }.freeze

        def can_import?(input)
          msgs = extract_messages(input)
          return false unless msgs.is_a?(Array) && !msgs.empty?
          msgs.all? do |m|
            (m['role'] || m[:role]).to_s.match?(/\A(user|assistant|system|tool)\z/) &&
              (m.key?('content') || m.key?(:content))
          end
        rescue StandardError
          false
        end

        def import(input, options = {})
          msgs = extract_messages(input)
          raise ArgumentError, 'ChatML import requires a messages array' unless msgs.is_a?(Array)

          participants_by_role = {}
          messages = msgs.each_with_index.map do |m, idx|
            role = (m['role'] || m[:role]).to_s
            speaker_role = ROLE_MAP.fetch(role, 'other')
            text = extract_text(m['content'] || m[:content])
            pid = participants_by_role[speaker_role] ||= Base.participant_id(speaker_role)
            {
              'id' => Base.message_id(idx),
              'speaker' => { 'id' => pid },
              'text' => text
            }
          end

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'imported-chatml', options: options),
            'participants' => participants_by_role.map { |role, id|
              { 'id' => id, 'role' => role, 'description' => role }
            },
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        def extract_messages(input)
          return input if input.is_a?(Array)
          return input['messages'] if input.is_a?(Hash) && input.key?('messages')
          return input[:messages] if input.is_a?(Hash) && input.key?(:messages)
          nil
        end

        # ChatML content can be a String or an array of content parts; we
        # collect text from text-type parts and ignore images / tool calls
        # at this phase.
        def extract_text(content)
          case content
          when String then content
          when Array
            content.filter_map { |part|
              next nil unless part.is_a?(Hash)
              if (part['type'] || part[:type]).to_s == 'text'
                part['text'] || part[:text]
              end
            }.join("\n").strip
          else
            content.to_s
          end
        end
      end
    end
  end
end
