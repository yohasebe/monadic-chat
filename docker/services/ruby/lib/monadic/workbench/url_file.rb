# frozen_string_literal: true

require 'uri'
require 'socket'
require 'stringio'
require_relative 'file_item'
require_relative 'channel'
require_relative '../utils/http_client'
require_relative '../utils/public_address'
require_relative '../workspace/attachments'

module Monadic
  module Workbench
    # An address the user opens on the work screen that serves a PDF: the
    # server takes the PDF and puts it on the work screen as a file of the
    # chat (kept in its inputs/ folder, as a file the user puts there from
    # the computer). Anything else is opened in the chat's browser.
    #
    # The address is asked for once (GET, no cookies or credentials). It is a
    # PDF when the answer says application/pdf or its body starts with
    # %PDF-; otherwise the answer is let go after its first bytes. Only
    # http and https addresses whose host is public (PublicAddress) are
    # asked, a redirect included, and at most REDIRECTS redirects are
    # followed; an address that is not asked goes to the browser. The
    # connection goes to the address that was checked (the name is not
    # looked up again), and the whole answer is read within DEADLINE.
    module UrlFile
      class Failed < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      REDIRECTS = 3
      CONNECT_TIMEOUT = 10
      READ_TIMEOUT = 30
      WRITE_TIMEOUT = 10
      DEADLINE = 120
      CHUNK = 64 * 1024
      MAGIC = '%PDF-'.b
      NAME_BYTES = 120
      FALLBACK_NAME = 'document.pdf'

      module_function

      # The address's PDF on the work screen: { 'as_file' => true, 'item_id' => }
      # or { 'as_file' => true, 'error' => } when it could not be put there;
      # nil when it is not a PDF (the browser opens it). Raises Failed
      # (unreachable, too_large) when the address answers with nothing usable.
      def put(url, session, tab:, generation:, live:, fetcher: method(:fetch))
        chat_id = Channel.chat_id_of(session)
        return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        fetched = fetcher.call(url, limit: FileItem.most_for(FALLBACK_NAME))
        return nil unless fetched.is_a?(Hash)
        return { 'as_file' => true, 'error' => 'not_allowed' } unless Channel.chat_id_of(session) == chat_id

        record = Monadic::Workspace::Attachments.accept!(
          chat_id: chat_id, app_name: session.dig(:parameters, 'app_name').to_s, purpose: 'workbench',
          original_name: fetched[:name], source: StringIO.new(fetched[:bytes])
        )
        opened = Channel.open_attachment({ 'attachment_id' => record[:attachment_id] }, session,
                                         tab: tab, generation: generation, live: live)
        return { 'as_file' => true, 'item_id' => opened['item_id'] } if opened['status'] == 'accepted'

        { 'as_file' => true, 'error' => opened['reason'] == 'too_large' ? 'too_large' : 'open_failed' }
      rescue Monadic::Workspace::FileTypes::Rejected, Monadic::Workspace::Attachments::Unusable,
             Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Ledger::Unreadable
        { 'as_file' => true, 'error' => 'open_failed' }
      end

      # { name:, bytes: } for a PDF of at most limit bytes, or :browser.
      # client: what asks, given the address to connect to
      # (Monadic::Utils::HttpClient by default); check: the public addresses
      # of a host, or PublicAddress::Refused for a host not to be asked.
      def fetch(url, limit:, client: method(:client), check: Monadic::Utils::PublicAddress.method(:check!))
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
        (REDIRECTS + 1).times do
          uri = web_uri(url) or return :browser
          begin
            addresses = Array(check.call(uri.host))
          rescue Monadic::Utils::PublicAddress::Refused
            return :browser
          end
          return :browser if addresses.empty?

          response = ask(client, addresses, uri, deadline)
          begin
            if [301, 302, 303, 307, 308].include?(response.code)
              location = header(response, 'Location')
              return :browser if location.empty?

              url = URI.join(uri, location).to_s
              next
            end
            return :browser unless (200..299).cover?(response.code)

            return read_pdf(response, uri, limit, deadline)
          ensure
            close(response)
          end
        end
        :browser
      rescue URI::Error
        :browser
      rescue HTTP::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
        raise Failed, 'unreachable'
      end

      # The answer from the first of the checked addresses that can be
      # reached (an IPv6 address without an IPv6 route is passed over).
      def ask(client, addresses, uri, deadline)
        addresses.each_with_index do |address, index|
          raise Failed, 'unreachable' if index.positive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          return client.call(address).get(uri.to_s)
        rescue HTTP::ConnectionError, HTTP::ConnectTimeoutError, SystemCallError, SocketError
          raise if index == addresses.length - 1
        end
      end

      def client(address)
        Asker.new(address)
      end

      # Asks with the connection made to address (TLS still checks the
      # host's name).
      class Asker
        def initialize(address)
          @socket_class = Class.new(TCPSocket) do
            define_singleton_method(:open) { |_host, port, *_rest| TCPSocket.open(address, port) }
          end
        end

        def get(url)
          Monadic::Utils::HttpClient.rest(connect: CONNECT_TIMEOUT, read: READ_TIMEOUT, write: WRITE_TIMEOUT)
                                    .headers('Accept' => 'application/pdf, */*;q=0.8')
                                    .get(url, socket_class: @socket_class)
        end
      end

      def web_uri(url)
        uri = URI.parse(url.to_s)
        uri if %w[http https].include?(uri.scheme&.downcase) && uri.host && !uri.host.empty? && uri.userinfo.nil?
      end

      # The body, while it is a PDF: by its type, or by its first bytes.
      def read_pdf(response, uri, limit, deadline)
        by_type = header(response, 'Content-Type').split(';').first.to_s.strip.casecmp?('application/pdf')
        raise Failed, 'too_large' if by_type && header(response, 'Content-Length').to_i > limit

        bytes = +''.b
        while (chunk = response.body.readpartial(CHUNK))
          bytes << chunk.b
          return :browser if !by_type && bytes.bytesize >= MAGIC.bytesize && !bytes.start_with?(MAGIC)
          raise Failed, 'too_large' if bytes.bytesize > limit
          raise Failed, 'unreachable' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        end
        return :browser unless by_type || bytes.start_with?(MAGIC)

        { name: file_name(header(response, 'Content-Disposition'), uri), bytes: bytes }
      end

      # The name the answer gives (Content-Disposition), or the address's
      # last part, made a file name that ends in .pdf.
      def file_name(disposition, uri)
        name = disposition_name(disposition)
        name = URI.decode_www_form_component(File.basename(uri.path.to_s)) if name.to_s.strip.empty?
        name = name.to_s.dup.force_encoding(Encoding::UTF_8)
        name = name.scrub('') unless name.valid_encoding?
        name = name.split(%r{[/\\]}).last.to_s.gsub(/[\p{Cc}\p{Cf}]/, '').strip.sub(/\A\.+/, '')
        stem = name.sub(/\.pdf\z/i, '')
        stem = stem.byteslice(0, NAME_BYTES - 4).scrub('') if stem.bytesize > NAME_BYTES - 4
        stem.empty? ? FALLBACK_NAME : "#{stem}.pdf"
      rescue ArgumentError
        FALLBACK_NAME
      end

      def disposition_name(disposition)
        text = disposition.to_s
        extended = text[/filename\*\s*=\s*[^']*'[^']*'([^;]+)/i, 1]
        return URI.decode_www_form_component(extended.strip) if extended

        text[/filename\s*=\s*"([^"]*)"/i, 1] || text[/filename\s*=\s*([^;]+)/i, 1]&.strip
      end

      def header(response, name)
        Array(response.headers[name]).first.to_s
      end

      def close(response)
        connection = response.respond_to?(:connection) ? response.connection : nil
        connection.close if connection.respond_to?(:close)
      rescue StandardError
        nil
      end
    end
  end
end
