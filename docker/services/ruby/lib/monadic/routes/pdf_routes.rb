# frozen_string_literal: false

# PDF storage routes (local Qdrant + multilingual-e5-base only).

# API: PDF storage status — reports whether the local store has any docs.
get "/api/pdf_storage_status" do
  content_type :json
  begin
    local_present = begin
      store = pdf_store_for(session)
      store ? store.any_docs? : false
    rescue StandardError
      false
    end
    { success: true, mode: 'local', local_present: local_present }.to_json
  rescue StandardError => e
    status 500
    error_json(e.message)
  end
end

# Upload a PDF file (local Qdrant storage via Monadic::Pdf::Store)
post "/pdf" do
  content_type :json

  return error_json("No file selected. Please choose a PDF file to upload.") unless params["pdfFile"]

  begin
    # `appName` from the form takes priority because the session may not be
    # hydrated yet if UPDATE_PARAMS has not fired before the upload.
    app_name = params["appName"].to_s
    store = if app_name.empty?
              pdf_store_for(session)
            else
              pdf_store_for(app_name)
            end
    return error_json("Database connection not available") unless store

    pdf_file_handler = params["pdfFile"]["tempfile"]
    temp_file = Tempfile.new("temp_pdf")
    temp_file.binmode
    temp_file.write(pdf_file_handler.read)
    temp_file.rewind
    pdf_file_handler.close

    pdf = PDF2Text.new(path: temp_file.path, max_tokens: 800, separator: "\n", overwrap_lines: 2)
    pdf.extract
    temp_file.close
    temp_file.unlink

    return error_json("No text could be extracted from the PDF file") if pdf.split_text.empty?

    doc_data = { items: 0, metadata: {} }
    items_data = []
    pdf.split_text.each do |i|
      title = if params["pdfTitle"].to_s != ""
                params["pdfTitle"]
              else
                params["pdfFile"]["filename"]
              end
      doc_data[:title] = title
      doc_data[:items] += 1
      items_data << { text: i["text"], metadata: { tokens: i["tokens"] } }
    end

    # Embeddings are computed locally via the embeddings_service container
    # so no provider API key is required for the store_embeddings call.
    store.store_embeddings(doc_data, items_data)
    { success: true, filename: params["pdfFile"]["filename"] }.to_json
  rescue Monadic::VectorStore::BackendError => e
    error_json("Vector store error: #{e.message}")
  rescue Monadic::Embeddings::ClientError => e
    error_json("Embeddings service error: #{e.message}")
  rescue => e
    error_json("Error processing PDF: #{e.class.name} - #{e.message}")
  end
end
