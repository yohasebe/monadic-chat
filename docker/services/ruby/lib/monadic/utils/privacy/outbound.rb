# frozen_string_literal: true

require 'json'

module Monadic
  module Utils
    module Privacy
      # The Privacy Filter for text sent, on a chat's behalf, somewhere other
      # than the chat's own model call: a second opinion, the context
      # extraction, a title suggestion, speech. The chat's own call masks
      # through its pipeline; these places must use the same one, and must
      # not send unmasked text when they cannot be sure the filter is off.
      #
      # The session of a real chat is a Rack session object, not a Hash, so it
      # is read by key, never by class.
      module Outbound
        class Refused < StandardError; end

        # Given as the session by a caller that does not act for a chat (the
        # MCP server, which has its own masking). Only this says so: a missing
        # session (nil) is refused, so one argument lost on the way to here
        # cannot send unmasked text.
        NOT_FOR_A_CHAT = :not_for_a_chat

        module_function

        # The pipeline to mask with, or nil when nothing is to be masked
        # (NOT_FOR_A_CHAT, or a chat with the filter off). Raises Refused, so
        # that nothing is sent, when the filter is on but its pipeline is not
        # there, or when the chat's session is missing or cannot be read (such
        # as an empty stand-in, given where the session was not available).
        def pipeline!(session)
          return nil if session.equal?(NOT_FOR_A_CHAT)
          raise Refused, "the chat's session was not given" if session.nil?
          raise Refused, "the chat's session could not be read" unless chat_session?(session)

          pipeline = session[:_privacy_pipeline] || rebuild(session)
          return pipeline if pipeline
          raise Refused, "the Privacy Filter is on, but its masking is not available" if session[:_privacy_session_enabled] == true
          raise Refused, "words were marked to be masked in this chat, but the Privacy Filter is off" if marked_terms?(session)

          nil
        end

        # Whether the user marked words to mask in this chat. They stay
        # protected after the Privacy Filter is turned off: nothing is sent
        # for the chat until it is on again (or the chat is reset).
        def marked_terms?(session)
          return false unless session.respond_to?(:key?)

          state = session[:monadic_state]
          privacy = state.is_a?(Hash) ? (state[:privacy] || state['privacy']) : nil
          terms = privacy.is_a?(Hash) ? (privacy[:terms] || privacy['terms']) : nil
          terms.is_a?(Array) && !terms.empty?
        end

        def terms_of(session)
          return [] unless marked_terms?(session)

          state = session[:monadic_state]
          privacy = state[:privacy] || state['privacy']
          (privacy[:terms] || privacy['terms']).map { |t| t[:text] || t['text'] }.compact
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

        JSON_DEPTH = 5

        # A string that is JSON (an object, an array or a string value), as
        # what it decodes to; nil when it is not JSON.
        def json_value(text)
          return nil unless text.lstrip.start_with?('{', '[', '"')

          JSON.parse(text)
        rescue JSON::ParserError
          nil
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

        # A chat with the filter on whose pipeline is not built yet (a tab
        # that reconnected or imported a conversation: a pipeline holds the
        # session it was built for, so it is not carried over) gets one built
        # for this session, as the chat's own call would build it, keeping
        # the registry the session holds. nil when the app does not use the
        # filter or it cannot be built; the caller then refuses.
        def rebuild(session)
          return nil unless session[:_privacy_session_enabled] == true

          app_name = (session[:parameters] || {})["app_name"]
          settings = defined?(APPS) && APPS[app_name] ? APPS[app_name].settings : nil
          return nil unless settings && settings.dig(:privacy, :enabled) == true

          require_relative 'pipeline'
          require_relative 'presidio_backend'
          session[:_privacy_pipeline] = Pipeline.new(backend: PresidioBackend.new, config: settings[:privacy], session: session)
        rescue StandardError
          nil
        end

        # The text as the chat's model would get it (placeholders for what the
        # filter masks), with the chat's own pipeline so the placeholders
        # match the chat's. Raises when masking fails; callers send nothing.
        def mask(text, pipeline, role)
          return text if text.nil? || text.to_s.empty?

          require_relative 'types'
          masked = pipeline.before_send_to_llm(RawMessage.new(text.to_s, role, {})).text
          # The same last check as a chat's own request: no word the user
          # marked leaves unmasked.
          state = pipeline.respond_to?(:registry_state) ? pipeline.registry_state : nil
          words = (state.is_a?(Hash) ? Array(state[:terms]) : []).map { |t| t[:text] || t['text'] }.compact
          if words.any?
            # Read as the request check reads (JSON in the text decoded too).
            found = false
            each_text(masked.to_s) { |text| found ||= holds_word?(text, words) }
            raise Refused, 'a word marked to be masked would have been sent unmasked' if found
          end

          masked
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
