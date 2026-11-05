# frozen_string_literal: true

require 'json'
require_relative '../workspace/request_context'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # Who called a tool that can put something on the workbench: the chat
    # and its epoch when the reply began, and the request (the user's turn)
    # the reply answers. Made by the server where it runs a tool for a
    # chat's reply, from what the reply runs under (the chat scope a
    # connection sets, Monadic::Utils::Privacy::EgressGuard, and the
    # request's RequestContext), never from the tool's arguments.
    #
    # A tool that takes a workbench: argument gets one; a model cannot give
    # it (an argument of that name is dropped). nil when the reply has no
    # such context: the tool then refuses rather than save elsewhere.
    Caller = Struct.new(:chat_id, :epoch, :request_id, :session, keyword_init: true) do
      def self.current(session)
        scope = Fiber[Monadic::Utils::Privacy::EgressGuard::CHAT_KEY] if defined?(Monadic::Utils::Privacy::EgressGuard)
        request = Monadic::Workspace::RequestContext.current
        return nil unless scope&.chat_id && scope.epoch && request && request.chat_id == scope.chat_id
        return nil unless session && session[Monadic::Workspace::Chats::SESSION_KEY] == scope.chat_id

        new(chat_id: scope.chat_id, epoch: scope.epoch, request_id: request.request_id, session: session)
      end

      # Gives the tool method its caller when it takes one.
      def self.inject!(argument_hash, method_obj, session)
        argument_hash.delete(:workbench)
        return argument_hash unless method_obj&.parameters&.any? { |_type, name| name == :workbench }

        argument_hash[:workbench] = current(session)
        argument_hash
      end
    end

    # What a tool returns when it has put an image on the workbench: the
    # reply's work is done and it ends here (the server runs no other tool
    # of the turn and asks the model nothing more). What happens to the
    # image (an edit, a save, its removal) the user decides later.
    Offered = Struct.new(:chat_id, :request_id, :item_id, :name, keyword_init: true) do
      # Whether this is for the reply running now in session's chat.
      def for?(session)
        request = Monadic::Workspace::RequestContext.current
        chat_id == session[Monadic::Workspace::Chats::SESSION_KEY] && request&.request_id == request_id
      end

      # The tool's result as the model's history keeps it.
      def to_s
        JSON.generate('status' => Offered::STATUS, 'name' => name,
                      'note' => 'The image is in the work screen; the user may save it to the shared folder there.')
      end

      # The result given to each tool call of the turn that was not run.
      def self.not_executed
        JSON.generate('not_executed' => 'the reply ended with an image in the work screen')
      end
    end
    Offered::STATUS = 'shown_in_work_screen'
  end
end
