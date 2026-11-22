# frozen_string_literal: true

require 'json'
require_relative 'refused'
require_relative 'word_table'
require_relative 'words'

module Monadic
  module Utils
    module Privacy
      # What checks text sent, on a chat's behalf, against the words the chat
      # hides, wherever it is sent from.
      #
      # The session of a real chat is a Rack session object, not a Hash, so it
      # is read by key, never by class.
      module Outbound
        # Given as the session by a caller that does not act for a chat (the
        # MCP server, which has its own masking). Only this says so: a missing
        # session (nil) is refused, so one argument lost on the way to here
        # cannot send unmasked text.
        NOT_FOR_A_CHAT = :not_for_a_chat

        module_function

        # Raises Refused, so that nothing is sent, when the chat's session is
        # missing or cannot be read (such as an empty stand-in, given where
        # the session was not available).
        def chat_session!(session)
          return if session.equal?(NOT_FOR_A_CHAT)
          raise Refused, "the chat's session was not given" if session.nil?
          raise Refused, "the chat's session could not be read" unless chat_session?(session)
        end

        # Whether the chat has words to hide.
        def marked_terms?(session)
          !terms_of(session).empty?
        end

        # The active words of the chat's word table. Everything that checks
        # what is sent reads them here.
        def terms_of(session)
          return [] unless session.respond_to?(:key?) && Words.marked?(session)

          Words.active_of(session)
        end

        PLACEHOLDER = /<<[A-Z_]+_\d+>>/

        # Where a request body holds data rather than text: the base64 of an
        # image, audio or a file, at the places the vendors' APIs put an
        # attachment in a message. Only there is a value not read for words
        # (a short word would match base64 by chance). Inside a tool's
        # arguments or result, and inside decoded JSON, the same shapes are
        # someone's data and are read.
        TOOL_DATA_KEYS = %w[args arguments functionCall function_call functionResponse function_response
                            response output parameters tools tool_calls].freeze

        def attachment_zone?(path)
          path.each_with_index.none? do |key, i|
            TOOL_DATA_KEYS.include?(key.to_s) || (key.to_s == 'input' && i.positive?)
          end
        end

        def data_position?(path, ancestors, value)
          return false unless attachment_zone?(path)

          parent = ancestors[-1]
          block = ancestors[-2]
          type_of = ->(h) { h.is_a?(Hash) ? (h['type'] || h[:type]).to_s : '' }
          last = path[-1].to_s
          data_url = value.start_with?('data:')
          # Claude: { type: image|document, source: { type: base64, data } }
          return true if last == 'data' && path[-2].to_s == 'source' && type_of.(parent) == 'base64' &&
                         %w[image document].include?(type_of.(block))
          # OpenAI chat (and DeepSeek, Grok): { type: image_url, image_url: { url: "data:..." } }
          return true if last == 'url' && path[-2].to_s == 'image_url' && data_url && type_of.(block) == 'image_url'
          # Mistral: { type: image_url, image_url: "data:..." }
          return true if last == 'image_url' && data_url && type_of.(parent) == 'image_url'
          # OpenAI responses: { type: input_image, image_url: "data:..." }, { type: input_file, file_data }
          return true if last == 'image_url' && data_url && type_of.(parent) == 'input_image'
          return true if last == 'file_data' && type_of.(parent) == 'input_file'
          # Cohere: { type: image, image: "data:..." }
          return true if last == 'image' && data_url && type_of.(parent) == 'image'
          # OpenAI chat audio: { type: input_audio, input_audio: { data } }
          return true if last == 'data' && path[-2].to_s == 'input_audio' && type_of.(block) == 'input_audio'
          # Gemini: contents[].parts[] { inline_data | inlineData: { data } }
          return true if last == 'data' && %w[inline_data inlineData].include?(path[-2].to_s) &&
                         path[-3].is_a?(Integer) && path[-4].to_s == 'parts'
          # Ollama: a message's images: [base64, ...]
          return true if path[-1].is_a?(Integer) && path[-2].to_s == 'images' && block.is_a?(Hash) &&
                         (block.key?('role') || block.key?(:role))

          false
        end

        JSON_DEPTH = WordTable::JSON_DEPTH

        # A string that is JSON (an object, an array or a string value), as
        # what it decodes to; nil when it is not JSON (WordTable.json_value).
        # JSON nested too deeply to be read is Refused.
        def json_value(text)
          WordTable.json_value(text)
        rescue WordTable::TooLarge => e
          raise Refused, e.message
        end

        # Every string a request body holds, hash keys included, except data
        # at its known places. A string that is JSON (a tool's arguments, a
        # value saved as JSON) is also read as what it decodes to, so an
        # escaped word is found too; decoded content has no data places.
        def each_text(value, path = [], ancestors = [], decoded: 0, &block)
          case value
          when String
            return if decoded.zero? && data_position?(path, ancestors, value)

            yield value
            inner = json_value(value)
            unless inner.nil?
              raise Refused, 'a value is nested as JSON too deeply to be checked' if decoded >= JSON_DEPTH

              each_text(inner, [], [], decoded: decoded + 1, &block)
            end
          when Hash
            value.each do |k, v|
              yield k.to_s
              each_text(v, path + [k.to_s], ancestors + [value], decoded: decoded, &block)
            end
          when Array
            value.each_with_index { |v, i| each_text(v, path + [i], ancestors + [value], decoded: decoded, &block) }
          end
        end

        # Whether text still holds one of the words, placeholders aside (a
        # word such as "PERSON" is not found in <<PERSON_1>>).
        def holds_word?(text, words)
          plain = text.gsub(PLACEHOLDER, "\u0000")
          # A word is also found written as inside JSON ("A\"B" for A"B), as
          # when a JSON fragment sits in the middle of a text.
          words.any? { |w| plain.include?(w) || plain.include?(w.to_json[1..-2]) }
        end

        # The last check before anything leaves for another service: no word
        # the user marked may be anywhere in it. Nothing is rewritten here
        # (that would change tool names, settings and JSON the request
        # relies on); the words are masked where text is masked, and a
        # request that still holds one is refused.
        def check_no_marked_words!(session, payload)
          words = terms_of(session)
          return if words.empty?

          found = false
          each_text(payload) { |text| found ||= holds_word?(text, words) }
          return unless found

          raise Refused, 'a word marked to be masked is also in a part of the request that is not masked ' \
                         '(such as the system prompt, a tool or the app\'s settings); nothing was sent'
        end

        # Every string in a value (for a payload whose text keys are not known).
        def each_string(value, &block)
          case value
          when String then yield value
          when Array then value.each { |v| each_string(v, &block) }
          when Hash then value.each_value { |v| each_string(v, &block) }
          end
        end

        # How a hidden word is read out: by its placeholder's type and number
        # ("<<PERSON_1>>" as "PERSON 1").
        def spoken_label(type, number)
          "#{type.tr('_', ' ')} #{number}"
        end

        # text with each of the originals replaced by its label, where the
        # occurrences overlap replaced as one (the label of the longest
        # original there), so no character of an original is left out because
        # a longer one was replaced first. entries: [[original, label], ...]
        def replace_union(text, entries)
          spans = []
          entries.each do |original, label|
            next if original.to_s.empty?

            start = text.index(original)
            while start
              spans << [start, start + original.length, label, original.length]
              start = text.index(original, start + 1)
            end
          end
          # Never inside a placeholder already there (a word such as "PERSON"
          # is not replaced in <<PERSON_1>>).
          taken = []
          text.scan(PLACEHOLDER) { taken << [Regexp.last_match.begin(0), Regexp.last_match.end(0)] }
          spans.reject! { |s, e, _, _| taken.any? { |ts, te| s < te && e > ts } }
          return text if spans.empty?

          groups = []
          spans.sort_by { |s, e, _, len| [s, -len, e] }.each do |span|
            if groups.any? && span[0] < groups.last[:end]
              group = groups.last
              group[:end] = [group[:end], span[1]].max
              group[:label] = span[2] if span[3] > group[:len]
              group[:len] = [group[:len], span[3]].max
            else
              groups << { start: span[0], end: span[1], label: span[2], len: span[3] }
            end
          end
          out = +''
          cursor = 0
          groups.each do |g|
            out << text[cursor...g[:start]] << g[:label]
            cursor = g[:end]
          end
          out << text[cursor..]
        end

        # What a chat's session holds from its connection on (a stand-in for a
        # session that was not available holds none of them).
        CHAT_KEYS = %i[parameters messages chat_id _ws_generation].freeze

        # A session that belongs to a chat: readable by key, with any of them.
        def chat_session?(session)
          session.respond_to?(:key?) && session.respond_to?(:[]) &&
            CHAT_KEYS.any? { |key| session.key?(key) || session.key?(key.to_s) }
        end
      end
    end
  end
end
