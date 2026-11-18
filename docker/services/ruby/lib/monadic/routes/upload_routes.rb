# frozen_string_literal: false

# Routes that turn a document or a web page into text for the message

# Largest upload accepted, checked before the body is read (config.ru).
DOCUMENT_UPLOAD_MAX_BYTES = 200_000_000

# Converts a document to text for a message; always returns JSON (see JSON
# routes in docs_dev/developer/anti_pattern_lints.md). The document is kept
# as an attachment of the chat the page belongs to (its inputs/ folder),
# fixed by UploadContext before the body is read; nothing is written at the
# top of the shared folder.
post "/document" do
  content_type :json

  chat_id = request.env[Monadic::Workspace::UploadContext::CHAT_KEY]
  unless Monadic::Workspace::Ids.valid?(:chat, chat_id)
    return error_json("This page is no longer connected. Reload the page and import the document again.")
  end

  upload = params["docFile"]
  return error_json("No file selected. Please choose a document file to convert.") unless upload.is_a?(Hash) && upload[:tempfile]

  begin
    doc_label = params["docLabel"].to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    record = Monadic::Workspace::Attachments.accept!(
      chat_id: chat_id,
      app_name: request.env[Monadic::Workspace::UploadContext::APP_KEY],
      purpose: "document",
      original_name: upload[:filename].to_s,
      source: upload[:tempfile]
    )
    name = record[:original_name].to_s.dup.force_encoding("UTF-8").scrub

    markdown = MonadicApp.doc2markdown(record[:relative_path])

    if markdown.to_s.strip.empty?
      return error_json("No content could be extracted from the document")
    end

    doc_text = "Filename: " + name + "\n---\n" + markdown
    result = if doc_label.to_s != ""
              "\n---\n" + doc_label + "\n---\n" + doc_text
            else
              "\n---\n" + doc_text
            end

    { success: true, content: result }.to_json
  rescue Monadic::Workspace::FileTypes::Rejected, Monadic::Workspace::Attachments::Unusable => e
    error_json(e.message)
  rescue Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Ledger::Unreadable
    error_json("The chat folder is not available. Check the shared folder and try again.")
  rescue => e
    error_json("Error processing document: #{e.message}")
  ensure
    upload[:tempfile].close! if upload.is_a?(Hash) && upload[:tempfile].respond_to?(:close!)
  end
end

# Fetch the webpage content
post "/fetch_webpage" do
  content_type :json

  return error_json("No URL provided") unless params["pageURL"]

  begin
    url = params["pageURL"]
    url_decoded = CGI.unescape(url)
    label = params["urlLabel"].to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    # Web UI always uses Selenium for URL fetching (Tavily is only
    # exposed inside Research Assistant apps).
    markdown = MonadicApp.fetch_webpage(url)

    if markdown.to_s.strip.empty?
      return error_json("No content could be extracted from the webpage")
    end

    webpage_text = "URL: " + url_decoded + "\n---\n" + markdown
    result = if label.to_s != ""
              "---\n" + label + "\n---\n" + webpage_text
            else
              "---\n" + webpage_text
            end

    { success: true, content: result }.to_json
  rescue => e
    error_json("Error fetching webpage: #{e.message}")
  end
end
