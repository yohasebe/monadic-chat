# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # Anthropic Messages API importer. Accepts either:
      #   - a bare array of {role, content} hashes (content may be string or array)
      #   - a request body { "system": "...", "messages": [...] }
      #
      # Differences from ChatML:
      #   - "system" is at the top level (not inside messages)
      #   - "content" may be an array of typed blocks (text / image / tool_use / tool_result)
      module AnthropicMessages
        module_function

        ROLE_MAP = {
          'user' => 'human',
          'assistant' => 'assistant'
        }.freeze

        def can_import?(input)
          msgs = extract_messages(input)
          return false unless msgs.is_a?(Array) && !msgs.empty?
          msgs.all? { |m| %w[user assistant].include?((m['role'] || m[:role]).to_s) }
        rescue StandardError
          false
        end

        def import(input, options = {})
          msgs = extract_messages(input)
          raise ArgumentError, 'Anthropic import requires a messages array' unless msgs.is_a?(Array)

          system_text = extract_system(input)
          participants = {}
          messages = []

          if system_text && !system_text.strip.empty?
            participants['system'] = Base.participant_id('system')
            messages << {
              'id' => Base.message_id(messages.size),
              'speaker' => { 'id' => participants['system'] },
              'text' => system_text
            }
          end

          msgs.each do |m|
            role = (m['role'] || m[:role]).to_s
            mapped = ROLE_MAP[role] or next
            participants[mapped] ||= Base.participant_id(mapped)
            text = extract_text(m['content'] || m[:content])
            messages << {
              'id' => Base.message_id(messages.size),
              'speaker' => { 'id' => participants[mapped] },
              'text' => text
            }
          end

          participant_objs = participants.map do |role_key, pid|
            role = role_key == 'system' ? 'system' : role_key
            { 'id' => pid, 'role' => role, 'description' => role_key }
          end

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'imported-anthropic', options: options),
            'participants' => participant_objs,
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        def extract_messages(input)
          return input if input.is_a?(Array)
          if input.is_a?(Hash)
            return input['messages'] if input.key?('messages')
            return input[:messages] if input.key?(:messages)
          end
          nil
        end

        def extract_system(input)
          return nil unless input.is_a?(Hash)
          input['system'] || input[:system]
        end

        def extract_text(content)
          case content
          when String then content
          when Array
            content.filter_map { |part|
              next nil unless part.is_a?(Hash)
              type = (part['type'] || part[:type]).to_s
              part['text'] || part[:text] if type == 'text'
            }.join("\n").strip
          else
            content.to_s
          end
        end
      end
    end
  end
end
