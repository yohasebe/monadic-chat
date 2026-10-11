# frozen_string_literal: true

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

          nil
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
          pipeline.before_send_to_llm(RawMessage.new(text.to_s, role, {})).text
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
