# frozen_string_literal: true

require 'json'
require_relative 'base'

module Monadic
  module Library
    module Importers
      # TED Talk transcript importer (TCSE format).
      #
      # The transcripts in tcse store a Python-repr string of:
      #   "[{'text': '...', 'start': 12.56, 'duration': 3.28}, ...]"
      # We accept that, plain JSON arrays, or pre-parsed Ruby arrays.
      #
      # Optional caller-supplied options:
      #   speaker_id, speaker_label, external_id, title, language,
      #   license, publication_date, topics, duration_seconds, cite_as
      module TedTalk
        module_function

        DEFAULT_LICENSE = 'CC-BY-NC-ND-4.0'

        def can_import?(input)
          segments = parse_segments(input)
          return false unless segments.is_a?(Array) && !segments.empty?
          segments.all? { |s| s.is_a?(Hash) && (s['text'] || s[:text]) && (s.key?('start') || s.key?(:start)) }
        rescue StandardError
          false
        end

        def import(input, options = {})
          segments = parse_segments(input)
          raise ArgumentError, 'TED Talk import requires a transcript segments array' unless segments.is_a?(Array)

          speaker_id = options[:speaker_id] || options['speaker_id'] || 'speaker-1'
          speaker_label = options[:speaker_label] || options['speaker_label'] || options[:title] || options['title']

          metadata_options = options.dup
          metadata_options[:license] ||= metadata_options['license'] || DEFAULT_LICENSE

          messages = segments.each_with_index.map do |seg, idx|
            text = (seg['text'] || seg[:text]).to_s
            start_s = (seg['start'] || seg[:start]).to_f
            duration_s = (seg['duration'] || seg[:duration]).to_f
            {
              'id' => Base.message_id(idx),
              'speaker' => { 'id' => speaker_id },
              'text' => text,
              'timing' => {
                'offset_seconds' => start_s,
                'duration_seconds' => duration_s
              }
            }
          end

          participant = { 'id' => speaker_id, 'role' => 'narrator', 'description' => 'TED_speaker' }
          participant['label'] = speaker_label.to_s unless speaker_label.to_s.strip.empty?

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'ted-talk', options: metadata_options),
            'participants' => [participant],
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        # Accepts either a Ruby array, a JSON string, or a Python-repr
        # string. The Python-repr form uses single quotes and \xNN escapes
        # which JSON.parse rejects, so we normalise it before parsing.
        def parse_segments(input)
          return input if input.is_a?(Array)
          return nil unless input.is_a?(String)

          src = input.strip
          return nil if src.empty?

          # Try JSON first; if that fails, normalise Python-style quotes.
          begin
            return JSON.parse(src)
          rescue JSON::ParserError
            # fall through
          end

          normalised = python_repr_to_json(src)
          JSON.parse(normalised)
        rescue JSON::ParserError
          nil
        end

        # Convert a Python repr-of-list-of-dicts into JSON. Handles single
        # quotes, escaped single quotes inside text, True/False/None, and
        # the common case where TCSE transcripts contain literal newlines
        # inside string values via "\\n".
        def python_repr_to_json(src)
          # Replace boolean / None constants outside strings.
          tokens = []
          buf = +''
          in_str = false
          str_quote = nil
          i = 0
          while i < src.length
            ch = src[i]
            if in_str
              if ch == '\\' && i + 1 < src.length
                buf << ch << src[i + 1]
                i += 2
                next
              elsif ch == str_quote
                buf << '"'
                in_str = false
                str_quote = nil
                i += 1
                next
              elsif ch == '"'
                buf << '\\"'
                i += 1
                next
              else
                buf << ch
                i += 1
                next
              end
            else
              if ch == "'" || ch == '"'
                buf << '"'
                in_str = true
                str_quote = ch
                i += 1
                next
              else
                buf << ch
                i += 1
              end
            end
          end
          # Replace Python literals outside strings is best-effort: we ran
          # the loop with a single pass, so do final cheap substitutions.
          buf
            .gsub(/\bTrue\b/,  'true')
            .gsub(/\bFalse\b/, 'false')
            .gsub(/\bNone\b/,  'null')
        end
      end
    end
  end
end
