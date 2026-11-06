# frozen_string_literal: true

require 'json'
require_relative 'utils/environment'
require_relative 'shared_tools/browser_owner'
require_relative 'workspace/chats'
require_relative 'workspace/request_context'
require_relative 'workbench/channel'
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

    # Said to the tool that opened the browser when it is not on the work
    # screen.
    FULL_NOTE = 'The work screen is full, so this browser is not shown there. ' \
                'Once the user removes an item from the work screen, it is shown.'

    # The chat's browser has just opened: it is put on the chat's workbench
    # (the tab whose message opened it selects it), and the pages of the
    # tabs in that chat are told. Returns :full when every item of the
    # workbench is kept (the browser is put on once the user removes one),
    # otherwise nil.
    def browser_opened(chat)
      view = MonadicSharedTools::BrowserOwner.view(chat)
      return unless view

      placed = put_on_workbench(chat, view)

      event = { type: 'work_screen', event: 'browser_opened', browser: view.instance }
      event[:workbench] = 'full' if placed == :full
      message = JSON.generate(event)
      WebSocketHelper.live_tabs_for_chat(chat).each do |tab|
        WebSocketHelper.send_to_live_connection(tab, message, chat_id: chat)
      end
      placed == :full ? :full : nil
    end

    # A failure here never keeps the pages from being told. :full when the
    # workbench had no room.
    def put_on_workbench(chat, view)
      return unless Monadic::Workspace::Ids.valid?(:chat, chat)

      request = Monadic::Workspace::RequestContext.current
      origin = { actor: 'agent', source: 'browser', request_id: request&.request_id }
      if request && request.chat_id == chat
        origin[:tab] = request.tab
        origin[:generation] = request.generation
      end
      Monadic::Workbench::Board.for(chat).add_browser(instance: view.instance, origin: origin, epoch: view.epoch)
      Monadic::Workbench::Channel.changed(chat)
      :placed
    rescue Monadic::Workbench::Board::Refused => e
      Monadic::Utils::ExtraLogger.log { "[WorkScreen] The browser is not on the workbench: #{e.message}" }
      e.message.start_with?('the work screen is full') ? :full : nil
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[WorkScreen] The browser is not on the workbench: #{e.class}: #{e.message}" }
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

# A chat that stops holding its browser: its pages ask for the workbench
# again, where the browser's item now says it closed.
MonadicSharedTools::BrowserOwner.on_closed do |chat|
  Monadic::Workbench::Channel.changed(chat) if Monadic::Workspace::Ids.valid?(:chat, chat)
end
