# frozen_string_literal: true

require 'json'
require_relative 'board'
require_relative 'approvals'
require_relative 'view_tokens'
require_relative 'artifact'
require_relative 'asset_server'
require_relative 'offer'
require_relative '../workspace/chats'
require_relative '../workspace/ids'
require_relative '../history/policy'

module Monadic
  module Workbench
    # What the main socket does for the workbench: the view a tab's page is
    # sent (the board with this connection's tokens and what the tab has
    # selected), the user's removal of an item from the board
    # (WORKBENCH_ACTION), a file of the shared folder the user opens on it
    # (WORKBENCH_OPEN), the item the tab selects (WORKBENCH_SELECT), and an
    # address to save a copy of an image elsewhere (WORKBENCH_DOWNLOAD). A tab's connection
    # calls these with its own session, tab id and generation; nothing here
    # trusts what the page says about the chat, the epoch or the image: the
    # server's token and the ledger hold them.
    module Channel
      module_function

      # The message for the tab's page: the board's snapshot, a token for
      # each image (to remove it, on this connection), and an address for
      # each image whose file is the one recorded. A chat without a board
      # gets an empty one; initial (a connection's first view) marks the view
      # so: what it shows is not new to the user. live
      # gives the generation of the connection a tab has now: a connection a
      # newer one replaced is sent nothing.
      def view(session, tab:, generation:, live:, initial: false)
        return nil unless live.call(tab) == generation

        chat_id = chat_id_of(session) or return nil
        board = Board.existing(chat_id, private: private_chat?(session, chat_id))
        # A chat without a board gets an empty one (no board is made for
        # it). A connection's first view says so too: a page that still
        # shows another chat's board (the app restarted and this tab's chat
        # is new) lets it go.
        unless board
          return { 'type' => 'workbench', 'board' => empty_board(chat_id), 'approvals' => {}, 'assets' => {},
                   'renders' => {}, 'selected' => nil, 'initial' => initial }
        end

        snapshot = board.snapshot
        approvals = {}
        assets = {}
        renders = {}
        snapshot[:items].each do |item|
          next unless item[:version]

          binding = { tab: tab, generation: generation, chat_id: chat_id, epoch: snapshot[:epoch] }
          approvals[item[:id]] = Approvals.issue(**binding, item_id: item[:id], sha256: item[:version])
          next if item[:status] != 'ok' || !item[:sha256]

          source = item[:kind] == 'file' ? { item_id: item[:id] } : { artifact_id: item[:artifact_id] }
          next if board.private? && !source[:item_id]

          assets[item[:id]] = AssetServer::PREFIX + ViewTokens.issue(**binding, **source, sha256: item[:sha256])
          next unless item[:render] && item[:size].to_i <= Monadic::Workspace::SharedFolderPreview::RENDER_LIMIT

          renders[item[:id]] = AssetServer::PREFIX + ViewTokens.issue(**binding, **source, sha256: item[:sha256],
                                                                                         purpose: :render)
        end
        selected, serial = board.selection(tab: tab, generation: generation)
        { 'type' => 'workbench', 'board' => snapshot, 'approvals' => approvals, 'assets' => assets,
          'renders' => renders, 'selected' => selected, 'selection_serial' => serial, 'initial' => initial }
      end

      # The user's removal of an image from the board, sent with the token
      # this connection was given for it, while it is still the tab's
      # connection (live, as for view). The file stays in the shared folder.
      # Returns the result for the page.
      def act(obj, session, tab:, generation:, live:)
        operation_id = obj['operation_id']
        return refusal(operation_id, 'not_allowed') unless live.call(tab) == generation

        grant = Approvals.grant(obj['token'], tab: tab, generation: generation)
        chat_id = chat_id_of(session)
        # The epoch is checked by the board, with the operation.
        return refusal(operation_id, 'not_allowed') unless grant && grant.chat_id == chat_id && grant.item_id == obj['item_id']

        board = Board.for(chat_id, private: private_chat?(session, chat_id))
        status, operation = board.accept(item_id: grant.item_id, action: obj['action'], operation_id: operation_id,
                                         epoch: grant.epoch, sha256: grant.sha256)
        { 'type' => 'workbench_result', 'operation_id' => operation['id'], 'item_id' => operation['item_id'],
          'status' => status.to_s, 'action' => operation['action'], 'state' => operation['state'] }
      rescue Board::Refused => e
        refusal(operation_id, e.message)
      end

      # The user opens a file of the shared folder (path, as the Shared
      # Folder panel names it; sha256, the version a message's record names,
      # when opened from it) on the workbench, from this tab: it is
      # added (or, at the same version, found) and this tab selects it.
      # The connection does not wait for a turn to read the file: when
      # other files are being read, the page is told (busy) at once.
      def open_file(obj, session, tab:, generation:, live:)
        path = obj['path']
        return open_refusal(path, 'not_allowed') unless live.call(tab) == generation

        chat_id = chat_id_of(session) or return open_refusal(path, 'not_allowed')
        # A message's record names the version it showed: only that one opens.
        sha256 = obj['sha256']
        return open_refusal(path, 'not_allowed') unless sha256.nil? || (sha256.is_a?(String) && sha256.match?(/\A\h{64}\z/))

        board = Board.for(chat_id, private: private_chat?(session, chat_id))
        item, added = board.add_file(path: path, origin: { actor: :user, source: :panel, tab: tab, generation: generation },
                                     epoch: Monadic::Workspace::Chats.epoch(chat_id), wait: 0, sha256: sha256)
        # Added, or found again (what it says of the file may have changed).
        changed(chat_id)
        { 'type' => 'workbench_opened', 'path' => item.dig('file', 'path'), 'item_id' => item['id'], 'added' => added }
      rescue Board::Refused => e
        open_refusal(path, e.message)
      rescue FileItem::Busy
        open_refusal(path, 'busy')
      end

      # The item this tab's page shows now (or nil for none). The page is
      # told what was taken: an item no longer on the board is refused. The
      # answer carries the page's number for the selection (seq), so that
      # the page can tell the answer to its latest one.
      def select(obj, session, tab:, generation:, live:)
        item_id = obj['item_id']
        seq = obj['seq'].is_a?(Integer) ? obj['seq'] : nil
        return select_result(nil, nil, 'not_allowed', seq) unless live.call(tab) == generation

        chat_id = chat_id_of(session) or return select_result(nil, nil, 'not_allowed', seq)
        board = Board.existing(chat_id, private: private_chat?(session, chat_id))
        return select_result(nil, nil, item_id ? 'no such item' : nil, seq) unless board

        select_result(*board.choose(tab: tab, generation: generation, item_id: item_id), nil, seq)
      rescue Board::Refused => e
        select_result(*(board ? board.selection(tab: tab, generation: generation) : [nil, nil]), e.message, seq)
      end

      # An address from which this connection's page saves a copy of an
      # image of the chat (on the board or not: a message's record names it
      # too), for a short time. Refused for another chat's image, a Private
      # chat, or a connection a newer one replaced. Whether the file is
      # still the one recorded is checked when the page asks for it.
      def download(obj, session, tab:, generation:, live:)
        artifact_id = obj['artifact_id']
        return download_refusal(artifact_id, 'not_allowed') unless live.call(tab) == generation

        chat_id = chat_id_of(session)
        return download_refusal(artifact_id, 'not_allowed') if !chat_id || private_chat?(session, chat_id)

        record = Artifact.record_of(artifact_id, chat_id: chat_id)
        token = ViewTokens.issue(tab: tab, generation: generation, chat_id: chat_id,
                                 epoch: Monadic::Workspace::Chats.epoch(chat_id), artifact_id: artifact_id,
                                 sha256: record[:sha256], purpose: :download)
        { 'type' => 'workbench_download', 'artifact_id' => artifact_id, 'url' => AssetServer::PREFIX + token,
          'name' => File.basename(record[:copy_path]) }
      rescue Artifact::NotAllowed
        download_refusal(artifact_id, 'not_allowed')
      end

      # The reply of request_id was recorded as the message mid in the
      # session's chat, naming item_ids: what it put on the board is now
      # that message's. True when there was something.
      def reply_recorded(session, mid, request_id, item_ids)
        return false unless request_id && item_ids

        chat_id = chat_id_of(session)
        board = Monadic::Workspace::Ids.valid?(:chat, chat_id) && Board.existing(chat_id)
        attached = board ? !board.attach_reply(request_id, mid, item_ids).empty? : false
        Offer.done(request_id)
        attached
      end

      # Something on the chat's board changed outside a page's request (a
      # tool showed a file): the chat's tabs are told, and each asks for
      # its view (WORKBENCH_VIEW) on its own connection.
      def changed(chat_id)
        return unless defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:live_tabs_for_chat)

        message = JSON.generate(type: 'workbench_changed')
        WebSocketHelper.live_tabs_for_chat(chat_id).each do |tab|
          WebSocketHelper.send_to_live_connection(tab, message, chat_id: chat_id)
        end
      end

      # The connection closed: its tokens stop working (the tab gets new
      # ones when it comes back).
      def connection_closed(tab, generation, session = nil)
        Approvals.drop_connection(tab, generation)
        ViewTokens.drop_connection(tab, generation)
        chat_id = session && chat_id_of(session)
        Board.existing(chat_id)&.drop_selection(tab, generation) if Monadic::Workspace::Ids.valid?(:chat, chat_id)
      end

      # The user left the chat: its tokens stop working.
      def chat_replaced(chat_id)
        return unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        Approvals.drop_chat(chat_id)
        ViewTokens.drop_chat(chat_id)
      end

      # The tab's connection left chat_id: what it selected there goes.
      def selection_left(chat_id, tab, generation)
        return unless tab && Monadic::Workspace::Ids.valid?(:chat, chat_id)

        Board.existing(chat_id)&.drop_selection(tab, generation)
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

      def open_refusal(path, reason)
        { 'type' => 'workbench_opened', 'path' => path, 'status' => 'refused', 'reason' => reason }
      end

      # serial: the number of the tab's selection now (Board#selection).
      def select_result(item_id, serial, reason, seq = nil)
        { 'type' => 'workbench_selected', 'item_id' => item_id, 'serial' => serial,
          'status' => reason ? 'refused' : 'accepted', 'reason' => reason, 'seq' => seq }.compact
      end

      def download_refusal(artifact_id, reason)
        { 'type' => 'workbench_download', 'artifact_id' => artifact_id, 'status' => 'refused', 'reason' => reason }
      end
    end
  end
end

# A chat the user replaced: the tokens given for its workbench stop working,
# and what the connection that left it selected there no longer counts.
Monadic::Workspace::Chats.on_change do |event, session|
  if event == :replaced
    chat_id = Monadic::Workbench::Channel.chat_id_of(session)
    Monadic::Workbench::Channel.chat_replaced(chat_id)
    Monadic::Workbench::Channel.selection_left(chat_id, Thread.current[:websocket_session_id], session[:_ws_generation])
  end
end
