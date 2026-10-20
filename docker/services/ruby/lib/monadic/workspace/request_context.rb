# frozen_string_literal: true

require 'set'
require_relative 'ids'

module Monadic
  module Workspace
    # One message the user sent, as the server accepted it: its request id,
    # the chat it belongs to, and the attachments a tool may use while it is
    # answered (the ones sent with this message and with earlier messages of
    # the same chat). Made when the message is accepted and fixed for the
    # whole answer, however many tools are called; it lives with the thread
    # that answers, not in the session, so a Reset or another tab cannot
    # change it.
    #
    # This set says which attachments a tool may take by id. It is not a
    # boundary for what is secret: code the model runs in the Python
    # container can read the whole shared folder.
    class RequestContext
      THREAD_KEY = :monadic_request_context

      attr_reader :request_id, :chat_id, :attachment_ids

      def initialize(chat_id:, attachment_ids: [], request_id: Ids.generate(:request))
        @request_id = request_id
        @chat_id = chat_id
        @attachment_ids = Set.new(attachment_ids).freeze
        freeze
      end

      def allows?(attachment_id)
        @attachment_ids.include?(attachment_id.to_s)
      end

      def self.current
        Thread.current[THREAD_KEY]
      end

      # Runs the block with context as the current one, and puts back what
      # was there before.
      def self.with(context)
        previous = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = context
        yield
      ensure
        Thread.current[THREAD_KEY] = previous
      end

      # For the thread that answers one message: set once, at its start.
      def self.enter(context)
        Thread.current[THREAD_KEY] = context
      end
    end
  end
end
