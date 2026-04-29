# frozen_string_literal: true

# PDF management handlers for WebSocket connections.
# Handles listing, deleting, and bulk-deleting PDF documents stored in the
# local Qdrant store via Monadic::Pdf::Store. All operations are scoped to
# the session's current app — the frontend may pass an explicit app_name
# in the message body, which takes precedence over the session-derived
# value (the session may not be hydrated yet on the very first request).

module WebSocketHelper
  private def resolve_pdf_store(obj, session)
    explicit = obj.is_a?(Hash) ? obj["app_name"].to_s : ""
    explicit.empty? ? pdf_store_for(session) : pdf_store_for(explicit)
  end

  private def handle_ws_pdf_titles(connection, obj, session)
    store = resolve_pdf_store(obj, session)
    titles = store ? store.list_titles.map { |t| t[:title] } : []
    send_to_client(connection, { "type" => "pdf_titles", "content" => titles })
  rescue StandardError => e
    send_to_client(connection, { "type" => "pdf_titles", "content" => [] })
    Monadic::Utils::ExtraLogger.log { "[PDF] list_titles failed: #{e.class}: #{e.message}" }
  end

  private def handle_ws_delete_pdf(connection, obj, session)
    title = obj["contents"]
    store = resolve_pdf_store(obj, session)
    deleted_count = 0
    if store
      docs = store.list_titles.select { |d| d[:title] == title }
      docs.each do |d|
        store.delete_doc(d[:doc_id])
        deleted_count += 1
      end
    end

    if deleted_count.positive?
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "#{title} deleted successfully" })
    else
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}" })
    end
  rescue StandardError => e
    send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}: #{e.message}" })
  end

  private def handle_ws_delete_all_pdfs(connection, obj, session)
    store = resolve_pdf_store(obj, session)
    store.clear_all if store
    send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "All local PDFs deleted" })
    send_to_client(connection, { "type" => "pdf_titles", "content" => [] })
  rescue StandardError => e
    send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error clearing PDFs: #{e.message}" })
  end
end
