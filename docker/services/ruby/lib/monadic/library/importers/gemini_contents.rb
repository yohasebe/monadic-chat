# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # Gemini Generative Language API "contents" format importer.
      # Accepts either:
      #   - a bare array of {role, parts:[{text}]} hashes
      #   - a request body { "system_instruction": {...}, "contents": [...] }
      #
      # Gemini uses role "user" / "model" (not "assistant").
      module GeminiContents
        module_function

        ROLE_MAP = {
          'user' => 'human',
          'model' => 'assistant'
        }.freeze

        def can_import?(input)
          contents = extract_contents(input)
          return false unless contents.is_a?(Array) && !contents.empty?
          contents.all? do |c|
            role = (c['role'] || c[:role]).to_s
            parts = c['parts'] || c[:parts]
            %w[user model].include?(role) && parts.is_a?(Array)
          end
        rescue StandardError
          false
        end

        def import(input, options = {})
          contents = extract_contents(input)
          raise ArgumentError, 'Gemini import requires a contents array' unless contents.is_a?(Array)

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

          contents.each do |c|
            role = (c['role'] || c[:role]).to_s
            mapped = ROLE_MAP[role] or next
            participants[mapped] ||= Base.participant_id(mapped)
            text = extract_text(c['parts'] || c[:parts])
            messages << {
              'id' => Base.message_id(messages.size),
              'speaker' => { 'id' => participants[mapped] },
              'text' => text
            }
          end

          participant_objs = participants.map do |role_key, pid|
            { 'id' => pid, 'role' => role_key, 'description' => role_key }
          end

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'imported-gemini', options: options),
            'participants' => participant_objs,
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        def extract_contents(input)
          return input if input.is_a?(Array)
          if input.is_a?(Hash)
            return input['contents'] if input.key?('contents')
            return input[:contents] if input.key?(:contents)
          end
          nil
        end

        def extract_system(input)
          return nil unless input.is_a?(Hash)
          si = input['system_instruction'] || input[:system_instruction]
          return nil unless si.is_a?(Hash)
          extract_text(si['parts'] || si[:parts]) if si['parts'] || si[:parts]
        end

        def extract_text(parts)
          return parts.to_s unless parts.is_a?(Array)
          parts.filter_map { |p|
            next nil unless p.is_a?(Hash)
            p['text'] || p[:text]
          }.join("\n").strip
        end
      end
    end
  end
end
