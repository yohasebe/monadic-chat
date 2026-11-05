# frozen_string_literal: true

require_relative 'board'
require_relative 'approvals'
require_relative 'view_tokens'
require_relative 'saver'
require_relative 'record'
require_relative 'asset_server'
require_relative 'offer'
require 'securerandom'
require_relative '../workspace/chats'
require_relative '../workspace/ids'
require_relative '../history/policy'

module Monadic
  module Workbench
    # What the main socket does for the workbench: the view a tab's page is
    # sent (the board with this connection's tokens), the user's operation
    # on an image (WORKBENCH_ACTION: save it to the shared folder, or remove
    # it from the board), and the record of a save in the message the image
    # belongs to. A tab's connection calls these with its own session, tab
    # id and generation; nothing here trusts what the page says about the
    # chat, the epoch or the image: the server's token holds them.
    module Channel
      module_function

      # The message for the tab's page: the board's snapshot, a token for
      # each image (to save or remove it, on this connection), and an
      # address for each image. A chat without a board gets an empty one,
      # or nil with only_existing (a connection's first view, marked
      # initial: what it shows is not new to the user). live gives the
      # generation of the
      # connection a tab has now: a connection a newer one replaced is sent
      # nothing.
      def view(session, tab:, generation:, live:, only_existing: false)
        return nil unless live.call(tab) == generation

        chat_id = chat_id_of(session) or return nil
        board = Board.existing(chat_id, private: private_chat?(session, chat_id))
        unless board
          return nil if only_existing

          return { 'type' => 'workbench', 'board' => empty_board(chat_id), 'approvals' => {}, 'assets' => {} }
        end

        snapshot = board.snapshot
        approvals = {}
        assets = {}
        snapshot[:items].each do |item|
          next unless item[:sha256]

          binding = { tab: tab, generation: generation, chat_id: chat_id, epoch: snapshot[:epoch], item_id: item[:id],
                      sha256: item[:sha256] }
          approvals[item[:id]] = Approvals.issue(**binding)
          assets[item[:id]] = AssetServer::PREFIX + ViewTokens.issue(**binding) unless board.private?
        end
        { 'type' => 'workbench', 'board' => snapshot, 'approvals' => approvals, 'assets' => assets,
          'initial' => only_existing }
      end

      # The user's operation on an image (save or remove), sent with the
      # token this connection was given for it, while it is still the tab's
      # connection (live, as for view). Returns the result for the page.
      def act(obj, session, tab:, generation:, recorder:, live:)
        operation_id = obj['operation_id']
        return refusal(operation_id, 'not_allowed') unless live.call(tab) == generation

        grant = Approvals.grant(obj['token'], tab: tab, generation: generation)
        chat_id = chat_id_of(session)
        # The epoch is checked by the board, with the operation.
        return refusal(operation_id, 'not_allowed') unless grant && grant.chat_id == chat_id && grant.item_id == obj['item_id']

        board = Board.for(chat_id, private: private_chat?(session, chat_id))
        status, operation = board.accept(item_id: grant.item_id, action: obj['action'], operation_id: operation_id,
                                         epoch: grant.epoch, sha256: grant.sha256)
        operation = Saver.run(board, operation['id'], recorder: recorder) if operation['action'] == 'save'
        { 'type' => 'workbench_result', 'operation_id' => operation['id'], 'item_id' => operation['item_id'],
          'status' => status.to_s, 'action' => operation['action'], 'state' => operation['state'],
          'name' => operation['final_name'] }
      rescue Board::Refused => e
        refusal(operation_id, e.message)
      rescue Saver::Failed, SystemCallError => e
        # Not saved: the same operation sent again goes on from the step
        # that failed.
        Monadic::Utils::ExtraLogger.log { "[Workbench] Save stopped: #{e.class}: #{e.message}" }
        { 'type' => 'workbench_result', 'operation_id' => operation_id, 'item_id' => obj['item_id'],
          'action' => obj['action'], 'status' => 'incomplete' }
      end

      # Records a saved image in the message it belongs to, when the
      # session is in the operation's chat. An image whose reply is still
      # running waits for that reply's message; one whose reply recorded no
      # message (it was cancelled, or the server restarted) gets a short
      # message of its own that records the save. A save is recorded in one
      # message only. False while it waits (another chat is open, or the
      # reply still runs): the save stays unfinished, and so does the image
      # (it cannot be removed meanwhile). sync keeps the tab's state and the
      # history up to date; deliver sends the page the record (or the new
      # message).
      def recorder_for(session, sync:, deliver:)
        lambda do |board:, operation:, artifact:|
          next false unless chat_id_of(session) == board.chat_id && !private_chat?(session, board.chat_id)

          messages = (session[:messages] ||= [])
          next true if messages.any? { |m| m.is_a?(Hash) && Array(m['artifacts']).any? { |e| e['id'] == artifact[:id] } }

          entry = Record.entry(artifact_id: artifact[:id], name: artifact[:name], sha256: artifact[:sha256],
                               content_type: artifact[:content_type], derived_from: artifact[:derived_from],
                               saved_at: artifact[:saved_at])
          item = board.item(operation['item_id'])
          mid = operation['mid'] || item&.dig('mid')
          message = mid && messages.find { |m| m.is_a?(Hash) && (m['mid'] || m[:mid]) == mid }
          if message
            Record.add!(message, entry)
            sync.call
            deliver.call({ 'type' => 'message_artifacts', 'chat_id' => board.chat_id, 'mid' => mid,
                           'artifacts' => message['artifacts'] })
          elsif Offer.in_flight?(item&.dig('origin', 'request_id'))
            next false
          else
            note = saved_note(session, entry)
            messages << note
            board.attach_note(operation['item_id'], note['mid']) if item
            sync.call
            deliver.call({ 'type' => 'html', 'content' => note })
          end
          true
        end
      end

      def saved_note(session, entry)
        params = session[:parameters] || session['parameters'] || {}
        { 'mid' => SecureRandom.hex(4), 'role' => 'assistant', 'text' => Offer.saved_note(entry['name']),
          'lang' => 'en', 'app_name' => params['app_name'], 'active' => true, 'artifacts' => [entry] }
      end

      # The reply of request_id was recorded as the message mid in the
      # session's chat, naming item_ids: what it put on the board is now
      # that message's. True when there was something.
      def reply_recorded(session, mid, request_id, item_ids)
        return false unless request_id && item_ids

        chat_id = chat_id_of(session)
        board = Monadic::Workspace::Ids.valid?(:chat, chat_id) && Board.existing(chat_id)
        attached = board ? !board.attach_reply(request_id, mid, item_ids).empty? : false
        # The reply is done once what it made has its message: a save
        # waiting for it is then recorded there, never in a note.
        Offer.done(request_id)
        attached
      end

      # Settles the session's chat's board (finish_unfinished). True when a
      # save was left unfinished (the board may have changed).
      def settle(session, recorder:)
        chat_id = chat_id_of(session)
        return false unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        board = Board.existing(chat_id, private: private_chat?(session, chat_id)) or return false
        unfinished = !board.unfinished_operations.empty?
        finish_unfinished(board, recorder)
        unfinished
      end

      # Takes on what a restart or a closed chat left unfinished, and gives
      # back to a message the record of each save the board holds (the
      # history may have missed one, as when its write failed, and an image
      # may have got its message after it was saved): the board is what
      # says what was saved.
      def finish_unfinished(board, recorder)
        board.unfinished_operations.each do |operation|
          Saver.run(board, operation['id'], recorder: recorder)
        rescue Saver::Failed, SystemCallError => e
          Monadic::Utils::ExtraLogger.log { "[Workbench] Unfinished save left: #{e.class}: #{e.message}" }
        end
        board.recorded_operations.each do |operation|
          recorder.call(board: board, operation: operation, artifact: Saver.artifact_of(board, operation))
        end
      end

      # The connection closed: its tokens stop working (the tab gets new
      # ones when it comes back).
      def connection_closed(tab, generation)
        Approvals.drop_connection(tab, generation)
        ViewTokens.drop_connection(tab, generation)
      end

      # The user left the chat: its tokens stop working.
      def chat_replaced(chat_id)
        return unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        Approvals.drop_chat(chat_id)
        ViewTokens.drop_chat(chat_id)
      end

      def chat_id_of(session)
        session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
      end

      def private_chat?(session, chat_id)
        policy = Monadic::History::Policy
        policy.private?(session) || policy.known_private?(chat_id)
      end

      def empty_board(chat_id)
        { board_id: nil, chat_id: chat_id, epoch: Monadic::Workspace::Chats.epoch(chat_id), revision: 0, items: [] }
      end

      def refusal(operation_id, reason)
        { 'type' => 'workbench_result', 'operation_id' => operation_id, 'status' => 'refused', 'reason' => reason }
      end
    end
  end
end

# A chat the user replaced: the tokens given for its workbench stop working.
Monadic::Workspace::Chats.on_change do |event, session|
  if event == :replaced
    Monadic::Workbench::Channel.chat_replaced(Monadic::Workbench::Channel.chat_id_of(session))
  end
end
