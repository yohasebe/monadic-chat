# frozen_string_literal: true

require_relative '../../workbench/channel'
require_relative '../../workbench/look'
require_relative '../../workbench/look/record'
require_relative '../../workbench/document'
require_relative '../../workbench/picture'
require_relative '../../workbench/edit_inputs'
require_relative '../../library/readings'
require_relative '../../workbench/item_text'
require_relative '../../workbench/sent'
require_relative '../tool_image_utils'
require_relative '../../workbench/point'
require_relative '../../workbench/whiteboard'

# The workbench over the main socket (Monadic::Workbench::Channel): the
# view a page is sent, the user's removal of an item from the board, a file
# the user opens on it, an address the user opens in the chat's browser, the
# item a tab selects, and the address to save a copy of an image, always for this connection's tab,
# generation and chat, and sent back to this connection only. All of it
# runs in the connection's own loop, one message after another.
module WebSocketHelper
  # The generation of the connection a tab has now: an operation or a view
  # goes only to that connection, not to one a newer connection replaced.
  WORKBENCH_LIVE = ->(tab) { WebSocketHelper.live_generation(tab) }
  Monadic::Workbench::Board.live = WORKBENCH_LIVE
  # A look asks the page of the tab's connection what its work screen shows.
  Monadic::Workbench::Capture.transport = lambda do |tab, generation, chat_id, json|
    WebSocketHelper.send_to_connection(tab, generation, json, chat_id: chat_id)
  end
  Monadic::Workbench::Point.transport = Monadic::Workbench::Capture.transport

  WORKBENCH_URL_MAX = 2000

  # What starts the chat's browser for an address the user opens: the
  # browser tools' own start. Built when first used, since this file loads
  # before MonadicApp is defined.
  def self.page_browser_host
    @page_browser_host ||= Class.new(MonadicApp) { include MonadicSharedTools::WebAutomation }
  end

  # The user opens an address (http or https) in the chat's browser on the
  # work screen. The browser starts as it does for the browser tools, for
  # this tab's chat, in a thread of its own; the page is told how it went.
  private def handle_ws_workbench_open_url(connection, obj, session)
    url = obj['url'].to_s.strip
    reply = { 'type' => 'workbench_open_url' }
    unless url.length <= WORKBENCH_URL_MAX && url.match?(/\A#{URI::DEFAULT_PARSER.make_regexp(%w[http https])}\z/)
      return send_to_client(connection, reply.merge('success' => false, 'error' => 'invalid_url'))
    end
    unless MonadicSharedTools::WebAutomation.available?
      %i[python selenium].each do |service|
        Monadic::Utils::ContainerDependencies.start_service_async(service, reason: 'opening a page on the work screen')
      end
      return send_to_client(connection, reply.merge('success' => false, 'error' => 'browser_starting'))
    end

    tab = Thread.current[:websocket_session_id]
    Thread.new do
      Thread.current[:websocket_session_id] = tab
      Thread.current[:rack_session] = session
      result = WebSocketHelper.page_browser_host.new.start_browser(url: url)
      opened = result.is_a?(Hash) && result[:success] == true
      send_or_broadcast(reply.merge('success' => opened, 'error' => opened ? nil : 'open_failed').to_json, tab)
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Workbench] Page not opened: #{e.class}" }
      send_or_broadcast(reply.merge('success' => false, 'error' => 'open_failed').to_json, tab)
    end
    nil
  end

  # The text of a document on the work screen (its item and the version the
  # tab shows) for the user's message (Workbench::ItemText), converted in a
  # thread of its own (in the Python container, started when it is not
  # running) and given to this connection only, or why there is none.
  private def handle_ws_workbench_item_text(connection, obj, session)
    reply = { 'type' => 'workbench_item_text', 'item_id' => obj['item_id'].to_s,
              'request' => obj['request'].is_a?(Integer) ? obj['request'] : nil }
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    board = chat_id && WORKBENCH_LIVE.call(tab) == generation && Monadic::Workbench::Board.existing(chat_id)
    return send_to_client(connection, reply.merge('error' => 'not_allowed')) unless board

    unless Monadic::Utils::ContainerDependencies.container_running?(:python)
      Monadic::Utils::ContainerDependencies.start_service_async(:python, reason: 'taking the text of a document')
      return send_to_client(connection, reply.merge('error' => 'converter_starting'))
    end

    Thread.new do
      text = Monadic::Workbench::ItemText.of(board, obj['item_id'], obj['sha256'],
                                             converter: ->(path) { MonadicApp.doc2markdown(path) })
      send_to_client(connection, reply.merge('content' => text))
    rescue Monadic::Workbench::ItemText::Failed => e
      send_to_client(connection, reply.merge('error' => e.message))
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Workbench] Text not taken: #{e.class}" }
      send_to_client(connection, reply.merge('error' => 'failed'))
    end
    nil
  end

  # The page asks for the picture of the work screen a message was sent with
  # (WORKBENCH_PICTURE, its id): sent to this connection only, and only for a
  # message of the session's chat that names it.
  private def handle_ws_workbench_picture(connection, obj, session)
    id = obj['picture_id'].to_s
    reply = { 'type' => 'workbench_picture', 'picture_id' => id }
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    named = Array(session[:messages]).find do |m|
      m.is_a?(Hash) && m['role'] == 'user' && m['workbench_picture'].is_a?(Hash) && m['workbench_picture']['id'] == id
    end
    # Kept with the chat's workbench, or, as it was sent, in its folder (a
    # chat taken from a file has only that).
    sha256 = named && named['workbench_picture']['sha256']
    bytes = named && chat_id ? Monadic::Workbench::Picture.read(chat_id, id) : nil
    bytes ||= Monadic::Workbench::Sent.read(chat_id, sha256) if chat_id && sha256
    return send_to_client(connection, reply.merge('found' => false)) unless bytes

    send_to_client(connection, reply.merge('found' => true, 'data' => "data:image/png;base64,#{Base64.strict_encode64(bytes)}"))
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Picture not sent: #{e.class}" }
    send_to_client(connection, reply.merge('found' => false))
  end

  # An image of the work screen a message of this tab's chat sent (its mid
  # and the image's sha256, which the message must name: Sent.named_by),
  # as kept in the chat's folder: to this connection only.
  private def handle_ws_workbench_sent_image(connection, obj, session)
    mid = obj['mid'].to_s
    sha256 = obj['sha256'].to_s
    reply = { 'type' => 'workbench_sent_image', 'mid' => mid, 'sha256' => sha256 }
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    message = Array(session[:messages]).find { |m| m.is_a?(Hash) && m['mid'].to_s == mid && !mid.empty? }
    sent = Monadic::Workbench::Sent
    bytes = message && chat_id && sent.named_by([message]).include?(sha256) ? sent.read(chat_id, sha256) : nil
    return send_to_client(connection, reply.merge('found' => false)) unless bytes

    type = Monadic::Utils::ToolImageUtils.image_media_type(bytes)
    send_to_client(connection, reply.merge('found' => true, 'data' => "data:#{type};base64,#{Base64.strict_encode64(bytes)}"))
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Sent image not given: #{e.class}" }
    send_to_client(connection, reply.merge('found' => false))
  end

  # initial: the connection's first view (marked so: what it shows is not
  # new to the user). It is sent also for a chat without a board, so that a
  # page still showing another chat's board lets it go.
  def send_workbench_view(connection, session, initial: false)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    return unless WORKBENCH_LIVE.call(tab) == generation

    view = workbench_timed('view') do
      Monadic::Workbench::Channel.view(session, **workbench_connection(session), live: WORKBENCH_LIVE,
                                                initial: initial)
    end
    workbench_deliver(connection).call(view) if view
  rescue Monadic::Workbench::Store::Unreadable => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Board not shown: #{e.message}" }
  end

  # The reply's message was recorded: what the reply offered (the items
  # its final message names) becomes that message's, and the page is sent
  # the board.
  def workbench_reply_recorded(connection, session, mid, request_id, item_ids)
    return unless Monadic::Workbench::Channel.reply_recorded(session, mid, request_id, item_ids)

    send_workbench_view(connection, session)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Board not sent after the reply: #{e.class}: #{e.message}" }
  end

  # The looks of the reply to request_id (Look::Ledger#records), let go
  # as the reply is recorded; nil when it looked at nothing.
  def workbench_looks_of_reply(session, request_id)
    ledger = request_id && Monadic::Workbench::Look::Ledger.take(request_id)
    return nil unless ledger && ledger.chat_id == session[Monadic::Workspace::Chats::SESSION_KEY]

    Monadic::Workbench::Look::Record.clean(ledger.records)
  end

  # A reply ended without its message: the images of the work screen its
  # image edits sent are kept on the user's message of the request, in the
  # session they were sent from, while it is still in that chat.
  def workbench_edits_without_reply(request_id)
    entry = Monadic::Workbench::EditInputs.take(request_id)
    session = entry && entry[:session]
    return unless session.respond_to?(:[]) && session[Monadic::Workspace::Chats::SESSION_KEY] == entry[:chat_id]

    records = Monadic::Workbench::EditInputs.clean(entry[:records])
    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    turn[Monadic::Workbench::EditInputs::KEY] = records if turn && records
  end

  # A reply ended without its message: what it read from the Library is
  # kept on the user's message of the request, in the session it was read
  # for, while it is still in that chat.
  def library_readings_without_reply(request_id)
    entry = Monadic::Library::Readings.take(request_id)
    session = entry && entry[:session]
    return unless session.respond_to?(:[]) && session[Monadic::Workspace::Chats::SESSION_KEY] == entry[:chat_id]

    records = Monadic::Library::Readings.clean(entry[:records])
    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    turn[Monadic::Library::Readings::KEY] = records if turn && records
  end

  # A reply ended without its message: what it looked at in the work
  # screen (and how far that went) is kept on the user's message of the
  # request, in the session the looks were made for (the thread that ends
  # the reply may have none), and the page draws it there. Nothing when
  # that session is in another chat now.
  def workbench_looks_without_reply(request_id, ws_session_id)
    ledger = Monadic::Workbench::Look::Ledger.take(request_id)
    session = ledger&.session
    return unless session && session[Monadic::Workspace::Chats::SESSION_KEY] == ledger.chat_id

    records = Monadic::Workbench::Look::Record.clean(ledger.records)
    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    return unless turn && records

    turn["workbench_looks"] = records
    send_or_broadcast({ "type" => "workbench_looks", "mid" => turn["mid"], "looks" => records }.to_json, ws_session_id)
    # Saved now, as any change of the chat is (the tab's connection and the
    # history's rules decide), not left for the next one: the reply may
    # have ended with the connection.
    saved_as(session, ledger.tab || ws_session_id) { sync_session_state! }
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Looks not kept after the reply: #{e.class}: #{e.message}" }
  end

  # Runs the block as the work of session's tab (what sync_session_state!
  # reads), from a thread that may be another's.
  def saved_as(session, tab)
    was = [Thread.current[:rack_session], Thread.current[:websocket_session_id]]
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = tab
    yield
  ensure
    Thread.current[:rack_session], Thread.current[:websocket_session_id] = was
  end

  def handle_ws_workbench_action(connection, obj, session)
    result = workbench_timed('operation') do
      Monadic::Workbench::Channel.act(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session)
  end

  # A file the user opens on the workbench: the result, then the board.
  def handle_ws_workbench_open(connection, obj, session)
    result = workbench_timed('open') do
      Monadic::Workbench::Channel.open_file(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session) unless result['status'] == 'refused'
  end

  # An entry of the Library opened on the work screen by the user.
  def handle_ws_workbench_open_library(connection, obj, session)
    result = workbench_timed('open_library') do
      Monadic::Workbench::Channel.open_library(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session) unless result['status'] == 'refused'
  end

  # The earlier versions of a document's sections (Workbench::Document),
  # for the work screen to list.
  def handle_ws_workbench_versions(connection, obj, session)
    path = obj['path'].to_s
    versions = Monadic::Workbench::Document.versions(session, path)
    workbench_deliver(connection).call({ 'type' => 'workbench_versions', 'path' => path, 'versions' => versions })
  end

  def handle_ws_workbench_open_attachment(connection, obj, session)
    result = workbench_timed('open_attachment') do
      Monadic::Workbench::Channel.open_attachment(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session) unless result['status'] == 'refused'
  end

  # A new whiteboard for this tab's chat (on an image of its work screen
  # when the page names one, at the version it showed), or the board of one
  # saved as the page drew it (Workbench::Whiteboard). The page is told how it went, with
  # the item and its version; the board's other tabs are told it changed.
  def handle_ws_workbench_whiteboard(connection, obj, session)
    reply = { 'type' => 'workbench_whiteboard', 'request' => obj['request'].is_a?(Integer) ? obj['request'] : nil }
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    chat_id = Monadic::Workbench::Channel.chat_id_of(session)
    unless chat_id && WORKBENCH_LIVE.call(tab) == generation
      return send_to_client(connection, reply.merge('status' => 'refused', 'reason' => 'not_allowed'))
    end

    whiteboard = Monadic::Workbench::Whiteboard
    origin = { actor: :user, source: :panel, tab: tab, generation: generation }
    epoch = Monadic::Workspace::Chats.epoch(chat_id)
    app_name = session.dig(:parameters, 'app_name').to_s
    item = if obj['message'] == 'WORKBENCH_WHITEBOARD_NEW' && obj['item_id'].is_a?(String)
             whiteboard.create_on(chat_id, item_id: obj['item_id'], version: obj['version'].to_s, app_name: app_name,
                                           origin: origin, epoch: epoch)
           elsif obj['message'] == 'WORKBENCH_WHITEBOARD_NEW'
             whiteboard.create(chat_id, app_name: app_name, origin: origin, epoch: epoch)
           else
             whiteboard.save(chat_id, item_id: obj['item_id'], version: obj['version'], data: obj['data'],
                                      app_name: app_name, origin: origin, epoch: epoch)
           end
    send_to_client(connection, reply.merge('status' => 'saved', 'item_id' => item['id'],
                                           'version' => item.dig('file', 'sha256')))
    send_workbench_view(connection, session)
  rescue Monadic::Workbench::Whiteboard::Refused, Monadic::Workbench::Board::Refused => e
    send_to_client(connection, reply.merge('status' => 'refused', 'reason' => e.message))
  rescue Monadic::Workbench::FileItem::Busy
    send_to_client(connection, reply.merge('status' => 'refused', 'reason' => 'busy'))
  rescue Monadic::Workspace::Folders::Unavailable, Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] whiteboard not saved: #{e.class}" }
    send_to_client(connection, reply.merge('status' => 'refused', 'reason' => 'unwritable'))
  end

  def handle_ws_workbench_select(connection, obj, session)
    result = Monadic::Workbench::Channel.select(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    workbench_deliver(connection).call(result)
  end

  def handle_ws_workbench_download(connection, obj, session)
    result = Monadic::Workbench::Channel.download(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    workbench_deliver(connection).call(result)
  end

  private

  def workbench_timed(what)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Monadic::Utils::ExtraLogger.log { "[Workbench] #{what} took #{ms} ms" } if ms >= 50
  end

  def workbench_connection(session)
    { tab: Thread.current[:websocket_session_id], generation: session[:_ws_generation] }
  end

  # To this connection; without one (a reply recorded outside a connection's
  # loop), to the tab.
  def workbench_deliver(connection)
    tab = Thread.current[:websocket_session_id]
    connection ? ->(message) { send_to_client(connection, message) } : ->(message) { send_or_broadcast(message.to_json, tab) }
  end
end
