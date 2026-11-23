# frozen_string_literal: true

require 'set'
require_relative 'ids'
require_relative '../turn_settings'

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

      # tab, generation: the tab and connection the message came from (the
      # workbench selects there what the answer shows), or nil.
      # observation: what the model is told of the work screen with this
      # message (Workbench::Observation, frozen), or nil.
      # settings: the settings the message is answered with
      # (Monadic::TurnSettings), or nil. parameters: the kept parameters of
      # the chat the message came in (the Hash itself): the settings are
      # those of a request made with these parameters, and of no other (a
      # tool that asks a model of its own makes its own).
      # picture: the picture of the work screen the message was sent with
      # (Workbench::Picture), or nil. selection: the text the user selected
      # in the work screen to send with it (Workbench::Selection), or nil.
      attr_reader :request_id, :chat_id, :attachment_ids, :tab, :generation, :observation, :settings, :picture,
                  :selection

      def initialize(chat_id:, attachment_ids: [], request_id: Ids.generate(:request), tab: nil, generation: nil,
                     observation: nil, settings: nil, parameters: nil, picture: nil, selection: nil)
        @request_id = request_id
        @picture = picture
        @selection = selection
        @settings = settings
        @parameters = parameters
        @chat_id = chat_id
        @tab = tab&.to_s
        @generation = generation
        @observation = observation
        @attachment_ids = Set.new(attachment_ids).freeze
        freeze
      end

      # The message's settings for a request made with the given parameters,
      # or nil when they are not the chat's own.
      def settings_for(parameters)
        @settings if @parameters.equal?(parameters)
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
