# frozen_string_literal: true

# PDF management handlers for WebSocket connections.
# Handles listing, deleting, and bulk-deleting PDF documents
# stored in the PGVector database.

module WebSocketHelper
  private def handle_ws_pdf_titles(connection)
    send_to_client(connection, {
      "type" => "pdf_titles",
      "content" => list_pdf_titles
    })
  end

  private def handle_ws_delete_pdf(connection, obj, session)
    title = obj["contents"]
    res = EMBEDDINGS_DB.delete_by_title(title)
    if res
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "#{title} deleted successfully" })
      # Invalidate caches for mode/presence
      begin
        session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[Cleanup] Cache version bump failed: #{e.message}" }
      end
    else
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}" })
    end
  end

  private def handle_ws_delete_all_pdfs(connection, session)
    begin
      titles = EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
      titles.each do |t|
        EMBEDDINGS_DB.delete_by_title(t)
      end
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "All local PDFs deleted" })
      send_to_client(connection, { "type" => "pdf_titles", "content" => [] })
      begin
        session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[Cleanup] Cache version bump failed: #{e.message}" }
      end
    rescue StandardError => e
      send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error clearing PDFs: #{e.message}" })
    end
  end
end
