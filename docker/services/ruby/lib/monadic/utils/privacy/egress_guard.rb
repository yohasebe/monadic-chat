# frozen_string_literal: true

require 'ipaddr'
require 'json'
require 'stringio'
require 'uri'
require_relative 'outbound'
require_relative '../../workspace/chats'

module Monadic
  module Utils
    module Privacy
      # The one place every request leaves Monadic Chat's server for another
      # service: the clients themselves (the http gem, Net::HTTP and the
      # WebSocket client). While a chat has words the user marked for the
      # Privacy Filter, no request to a service outside this computer carries
      # one of them, however the request was put together (a chat's model, a
      # helper, speech, a tool). Checking at each place a request is built
      # missed what was added after the check; this checks what is sent.
      #
      # What is read: the address (path and query), a JSON, form or text
      # body, a multipart form's part headers (field and file names) and text
      # fields, and every text message on a WebSocket. What is not: the
      # contents of uploaded files and audio, headers, and requests made by
      # other programs (scripts run in the containers). Nothing is read for a
      # request to this computer, or while no chat has marked words.
      #
      # The words are those of the chat the request is made for: the chat
      # whose connection the work started in (CHAT_KEY in Fiber storage, which
      # every thread and fiber started from there inherits), or the chat set
      # for the thread. A request that belongs to no chat (the MCP server used
      # on its own, the app starting) is not checked for marked words.
      # Requests to the services on this computer (the Privacy container that
      # does the masking, the embeddings service, a local model) are not
      # checked.
      module EgressGuard
        REFUSED = 'a word marked to be masked in a chat would have been sent to another service; nothing was sent'

        # This computer, and the Docker containers Monadic Chat runs (by
        # their compose service and container names).
        LOCAL_NAMES = %w[localhost host.docker.internal].freeze
        CONTAINER_NAME = /\A(?:[a-z]+_service|monadic-chat-[a-z0-9-]+-container)\z/

        module_function

        def local_host?(host)
          name = host.to_s.downcase.delete_prefix('[').delete_suffix(']')
          return false if name.empty?
          return true if LOCAL_NAMES.include?(name) || name.end_with?('.localhost') || CONTAINER_NAME.match?(name)

          address = IPAddr.new(name)
          address = address.native if address.ipv4_mapped?
          address.loopback? || address.to_s == '0.0.0.0'
        rescue IPAddr::Error
          false
        end

        CHAT_KEY = :monadic_chat_session

        # The chat work is done for: the session and the chat it was in when
        # the work began. Reset and switching apps start a new chat in the
        # same session; work of the chat that ended (a second opinion still
        # running) is still checked for that chat's words.
        Scope = Struct.new(:session, :chat_id)

        # The words of chats that have ended, by chat id (the newest kept).
        ENDED_LIMIT = 500
        @ended = {}
        @ended_lock = Mutex.new

        # Marks the work that follows as done for the chat the session is in
        # now (threads and fibers started later inherit it). Set when a
        # connection opens and whenever its session starts a chat.
        def for_chat(session)
          Fiber[CHAT_KEY] = session ? Scope.new(session, session[Monadic::Workspace::Chats::SESSION_KEY]) : nil
        end

        # A chat's words, kept when it ends. Joined with what was kept before
        # (a session copy may end the same chat again with fewer words).
        def chat_ended(session)
          id = session[Monadic::Workspace::Chats::SESSION_KEY]
          return unless id

          list = Outbound.terms_of(session)
          @ended_lock.synchronize do
            @ended[id] = ((@ended.delete(id) || []) | list).freeze
            @ended.shift while @ended.size > ENDED_LIMIT
          end
        end

        def words
          scope = Fiber[CHAT_KEY]
          return terms_now(Thread.current[:rack_session]) unless scope

          return terms_now(scope.session) if scope.chat_id.nil?

          # A Reset keeps the chat's words before it clears the session and
          # gives it a new id, so whichever of these this read falls between,
          # the words kept for the chat are joined to what the session holds.
          # The chat id is read again after the words: only when it is the
          # same chat before and after are the session's words that chat's.
          current = scope_chat?(scope) ? terms_now(scope.session) : nil
          kept = @ended_lock.synchronize { @ended[scope.chat_id] }
          return current | (kept || []) if current && scope_chat?(scope)

          kept ||
            raise(Outbound::Refused, 'the chat this request was made for has ended and its marked words are not known; nothing was sent')
        end

        def scope_chat?(scope)
          scope.session[Monadic::Workspace::Chats::SESSION_KEY] == scope.chat_id
        end

        def terms_now(session)
          session ? Outbound.terms_of(session).uniq : []
        end

        # Refused (nothing is sent) when a marked word is in what a request to
        # an outside host carries. parts (and what the block gives, read only
        # when there is something to check): strings and parsed values; a
        # string that is JSON is read as what it decodes to.
        def check!(host, *parts)
          return if local_host?(host)

          list = words
          return if list.empty?

          parts += Array(yield) if block_given?
          found = false
          parts.each do |part|
            # JSON is read as its values, so data at its known places (an
            # image, a document) is left alone.
            value = part.is_a?(String) ? Outbound.json_value(part) || part : part
            Outbound.each_text(value) { |text| found ||= Outbound.holds_word?(text, list) }
            break if found
          end
          raise Outbound::Refused, REFUSED if found
        end

        # The path and query of an address, as written and decoded (a word
        # in a query is written with %XX or +).
        def address_texts(uri)
          uri = URI.parse(uri.to_s) unless uri.is_a?(URI::Generic)
          raw = [uri.path, uri.query].compact.join('?')
          decoded = begin
            URI.decode_www_form_component(raw)
          rescue ArgumentError
            raw
          end
          [raw, decoded]
        end

        # The text a body holds, by its content type: a string (JSON, a form,
        # plain text; bytes are not read), a multipart form (see
        # multipart_texts), and a StringIO (read from where it stands, which is
        # where it is left). A file sent as the body is an upload and is not
        # read; any other stream is refused rather than sent unread.
        def body_texts(body, content_type = nil)
          type = content_type.to_s
          case body
          when nil then []
          when Hash, Array then [body]
          when String then string_texts(body, type)
          else
            if defined?(::HTTP::FormData::Multipart) && body.is_a?(::HTTP::FormData::Multipart)
              string_texts(body.to_s, body.content_type) # to_s reads it and rewinds it
            elsif defined?(::HTTP::FormData::Urlencoded) && body.is_a?(::HTTP::FormData::Urlencoded)
              string_texts(body.to_s, 'application/x-www-form-urlencoded')
            elsif body.is_a?(::File)
              []
            elsif body.is_a?(StringIO)
              position = body.pos
              text = body.read.to_s
              body.seek(position)
              string_texts(text, type)
            else
              raise Outbound::Refused, 'a request body that cannot be read could not be checked; nothing was sent'
            end
          end
        end

        def string_texts(bytes, type)
          return multipart_texts(bytes, type) if type.downcase.start_with?('multipart/')

          text = text_of(bytes)
          text ? [text, form_decoded(text)].compact : []
        end

        # A string as text, or nil when it is bytes rather than text.
        def text_of(string)
          return string if string.encoding == Encoding::UTF_8 && string.valid_encoding?

          text = string.dup.force_encoding(Encoding::UTF_8)
          text.valid_encoding? ? text : nil
        end

        def form_decoded(text)
          return nil unless text.include?('=') && !text.lstrip.start_with?('{', '[')

          URI.decode_www_form_component(text)
        rescue ArgumentError
          nil
        end

        MULTIPART_DEPTH = 3
        MULTIPART_UNREADABLE = 'a multipart request could not be read to be checked; nothing was sent'

        # A multipart body as sent (RFC 2046, RFC 7578), split at its
        # delimiter lines: each part's headers (the field name, a file's name,
        # also as filename*), and the contents of each part that is not a
        # file, decoded as its Content-Transfer-Encoding says; a part that is
        # itself multipart is read the same way. A file's contents are not
        # read. Anything this cannot read is refused rather than sent unread.
        def multipart_texts(bytes, type, depth = 0)
          match = type.match(/;\s*boundary=(?:"([^"]+)"|([^;\s]+))/i)
          raise Outbound::Refused, MULTIPART_UNREADABLE unless match && depth <= MULTIPART_DEPTH

          boundary = match[1] || match[2]
          # A delimiter line: the boundary, then the end of the line (or "--"
          # for the last one); the boundary only begins a line in a file.
          delimiter = Regexp.new("\\r\\n--#{Regexp.escape(boundary)}(?=(?:--)?[ \\t]*(?:\\r\\n|\\z))")
          sections = ("\r\n".b + bytes.b).split(delimiter, -1)
          raise Outbound::Refused, MULTIPART_UNREADABLE unless sections.size >= 2 && sections.last.start_with?('--')

          sections[1...-1].flat_map { |section| part_texts(section, depth) }
        end

        def part_texts(section, depth)
          rest = section.sub(/\A[ \t]*\r\n/n, '')
          raise Outbound::Refused, MULTIPART_UNREADABLE if rest == section # a delimiter line ends with CRLF

          head, content = rest.start_with?("\r\n") ? ['', rest[2..]] : rest.split("\r\n\r\n", 2)
          head_text = text_of(head)
          raise Outbound::Refused, MULTIPART_UNREADABLE if content.nil? || head_text.nil?

          headers = part_headers(head_text)
          params = header_params(headers['content-disposition'].to_s)
          texts = [head_text, *params.except('filename*').values] # names as decoded too
          texts << extended_value(params['filename*']) if params.key?('filename*')
          return texts.compact if params.key?('filename') || params.key?('filename*') # a file

          body = transfer_decoded(content, headers['content-transfer-encoding'])
          inner = headers['content-type'].to_s
          if inner.downcase.start_with?('multipart/')
            texts.concat(multipart_texts(body, inner, depth + 1))
          else
            texts << text_of(body)
          end
          texts.compact
        end

        # name (lower case) => value, continuation lines unfolded.
        def part_headers(text)
          text.gsub(/\r\n[ \t]+/, ' ').split("\r\n").each_with_object({}) do |line, headers|
            name, value = line.split(':', 2)
            raise Outbound::Refused, MULTIPART_UNREADABLE if value.nil?

            headers[name.strip.downcase] = value.strip
          end
        end

        # The parameters of a header value (form-data; name="a"; filename="b"),
        # name (lower case) => value; a quoted value is read as one, so a name
        # holding "filename=" is not taken for a file.
        def header_params(value)
          value.scan(/;\s*([^=;\s]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]*))/).to_h do |name, quoted, plain|
            [name.downcase, quoted ? quoted.gsub(/\\(.)/, '\1') : plain.strip]
          end
        end

        # An RFC 8187 value (UTF-8''%53ecret.txt), decoded.
        def extended_value(value)
          encoded = value.to_s.split("'", 3).last.to_s
          text_of(URI.decode_www_form_component(encoded.gsub('+', '%2B')))
        rescue ArgumentError
          raise Outbound::Refused, MULTIPART_UNREADABLE
        end

        def transfer_decoded(content, encoding)
          case encoding.to_s.strip.downcase
          when '', '7bit', '8bit', 'binary' then content
          when 'base64' then content.unpack1('m')
          when 'quoted-printable' then content.unpack1('M')
          else raise Outbound::Refused, MULTIPART_UNREADABLE
          end
        end

        # A WebSocket text message, but not the audio it streams (base64
        # chunks would hold a short word by chance).
        def frame_texts(text)
          value = Outbound.json_value(text)
          return [text] if value.nil?

          [strip_audio(value)]
        end

        def strip_audio(value)
          return value unless value.is_a?(Hash)

          if value['type'] == 'input_audio_buffer.append'
            value.except('audio')
          elsif value.dig('realtimeInput', 'audio').is_a?(Hash)
            audio = value['realtimeInput']['audio'].except('data')
            value.merge('realtimeInput' => value['realtimeInput'].merge('audio' => audio))
          else
            value
          end
        end

        # The hooks wrap each client's own method (an alias on the class
        # rather than a prepended module, so the method is still the class's
        # own, as the rest of the code and its tests expect). For the http
        # gem this is perform: the request as sent, after the client's
        # default options and on every redirect.
        def install!
          return if @installed

          require 'http'
          require 'net/http'
          HTTP::Client.class_eval do
            alias_method :monadic_unguarded_perform, :perform

            def perform(req, options)
              guard = Monadic::Utils::Privacy::EgressGuard
              guard.check!(req.uri.host) do
                guard.address_texts(req.uri) + guard.body_texts(req.body.source, req.headers['Content-Type'])
              end
              monadic_unguarded_perform(req, options)
            end
          end
          Net::HTTP.class_eval do
            alias_method :monadic_unguarded_request, :request

            def request(req, body = nil, &block)
              guard = Monadic::Utils::Privacy::EgressGuard
              guard.check!(address) do
                sent = body || req.body || req.body_stream
                # A form set with set_form: its text values and file names
                # (a file's contents are not read).
                fields = Array(req.instance_variable_get(:@body_data)).flat_map do |field|
                  Array(field).flat_map { |item| item.is_a?(Hash) ? item.values : [item] }.grep(String)
                end
                guard.address_texts(req.path) + guard.body_texts(sent, req['content-type']) + fields
              end
              monadic_unguarded_request(req, body, &block)
            end
          end
          install_websocket!
          Monadic::Workspace::Chats.on_change do |event, session|
            event == :ending ? chat_ended(session) : for_chat(session)
          end
          @installed = true
        end

        # Each connection a WebSocket client opens checks its address, and
        # every text message it sends, against the host it was opened to.
        def install_websocket!
          require 'async/websocket/client'
          Async::WebSocket::Client.class_eval do
            alias_method :monadic_unguarded_connect, :connect

            def connect(authority, path, handler: Async::WebSocket::Connection, **options, &block)
              guard = Monadic::Utils::Privacy::EgressGuard
              host = authority.to_s.sub(/:\d+\z/, '')
              guard.check!(host) { guard.address_texts(path) }
              guarded = Class.new(handler) do
                define_method(:send_text) do |buffer, **opts|
                  guard.check!(host) { guard.frame_texts(buffer.to_s) }
                  super(buffer, **opts)
                end
              end
              monadic_unguarded_connect(authority, path, handler: guarded, **options, &block)
            end
          end
        rescue LoadError
          nil
        end
      end
    end
  end
end
