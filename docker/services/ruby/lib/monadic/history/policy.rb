# frozen_string_literal: true

module Monadic
  module History
    # Whether a chat may be kept in the history. A Private chat is never
    # written: not its text, title, context or anything else of it.
    #
    # The decision is the server's and stays for the chat. It does not follow
    # the Privacy Filter's health: a filter that is down or switched off does
    # not make a chat that used it a normal one. Asking for the Privacy
    # Filter marks the chat Private at once (whether or not the filter is
    # up), and a chat with any other trace of it (words were marked, a
    # registry or a pipeline was built) is Private too.
    module Policy
      SESSION_KEY = :_history_policy
      PRIVATE = 'private'

      module_function

      def private?(session)
        return true if stored(session) == PRIVATE
        return false unless privacy_traces?(session)

        # Kept for the rest of the chat; a new chat drops it (it is not one of
        # the keys Workspace::Chats keeps across chats).
        session[SESSION_KEY] = PRIVATE
        true
      end

      def mark_private!(session)
        session[SESSION_KEY] = PRIVATE
      end

      def stored(session)
        session[SESSION_KEY] || session[SESSION_KEY.to_s]
      end

      def privacy_traces?(session)
        return true if session[:_privacy_session_enabled] == true || session['_privacy_session_enabled'] == true
        return true if session[:_privacy_pipeline] || session['_privacy_pipeline']

        state = session[:monadic_state] || session['monadic_state']
        privacy = state.is_a?(Hash) ? (state[:privacy] || state['privacy']) : nil
        return false unless privacy.is_a?(Hash)

        %i[terms registry].any? do |key|
          value = privacy[key] || privacy[key.to_s]
          value.respond_to?(:empty?) && !value.empty?
        end
      end
    end
  end
end
