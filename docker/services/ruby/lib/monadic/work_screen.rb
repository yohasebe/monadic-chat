# frozen_string_literal: true

require 'json'
require_relative 'utils/environment'
require_relative 'shared_tools/browser_owner'
require_relative 'workspace/chats'
require_relative 'work_screen/tokens'
require_relative 'work_screen/cdp'
require_relative 'work_screen/stream'

module Monadic
  # The work screen: the page of a tab watches its chat's browser, as the
  # browser draws it (a CDP screencast relayed by this server). View only.
  #
  # The page asks its chat socket for a pass (WORK_SCREEN_TOKEN) and opens
  # /work-screen with it (Stream). The chat socket tells the page when the
  # chat's browser opens (browser_opened), apart from watching it.
  module WorkScreen
    SELENIUM = 'selenium_service:4444'

    module_function

    # Selenium is reached from the Ruby container only; the server run on
    # the host (development) has no work screen.
    def available?
      Monadic::Utils::Environment.in_container?
    end

    def cdp_url(session_id)
      "ws://#{SELENIUM}/session/#{session_id}/se/cdp"
    end

    # The chat's browser has just opened: the pages of the tabs in that chat
    # are told (they show the work screen).
    def browser_opened(chat)
      view = MonadicSharedTools::BrowserOwner.view(chat)
      return unless view

      message = JSON.generate(type: 'work_screen', event: 'browser_opened', browser: view.instance)
      WebSocketHelper.live_tabs_for_chat(chat).each do |tab|
        WebSocketHelper.send_to_live_connection(tab, message, chat_id: chat)
      end
    end

    # The work screen socket of a request (the route upgrades it).
    def serve(env)
      Async::WebSocket::Adapters::Rack.open(env) do |connection|
        Stream.new(Socket.new(connection)).run
      end
    end

    # What Stream reads and writes: text messages.
    class Socket
      CLOSE_LIMIT = 2

      def initialize(connection)
        @connection = connection
      end

      # A close frame is tried for CLOSE_LIMIT seconds; the connection is
      # closed either way.
      def close
        Async::Task.current.with_timeout(CLOSE_LIMIT) { @connection.close }
      rescue StandardError
        nil
      end

      def read
        @connection.read&.to_str
      end

      def write(text)
        @connection.write(text)
        @connection.flush
      end
    end
  end
end
