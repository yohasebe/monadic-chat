# frozen_string_literal: true

require_relative '../shared_tools/browser_owner'
require_relative '../workspace/chats'

module Monadic
  module WorkScreen
    # What showing or capturing a chat's browser is bound to: the tab's live
    # connection, the chat it is in, the chat's epoch, the browser instance
    # and its Selenium session, and the window the tools act on.
    BrowserBinding = Struct.new(:tab, :generation, :chat, :epoch, :instance, :session, :window) do
      # Why the binding no longer holds now (:connection, :chat, :replaced,
      # :browser_closed, or :window when only the window changed), or nil.
      # view: the chat's browser as BrowserOwner sees it now.
      def broken(view = MonadicSharedTools::BrowserOwner.view(chat))
        return :connection unless WebSocketHelper.live_generation(tab) == generation

        session_now = WebSocketHelper.live_session(tab)
        return :chat unless session_now && session_now[Monadic::Workspace::Chats::SESSION_KEY] == chat
        return :replaced unless Monadic::Workspace::Chats.epoch(chat) == epoch
        return :browser_closed unless view && view.epoch == epoch && view.instance == instance && view.session == session
        return :window unless view.window == window

        nil
      end
    end
  end
end
