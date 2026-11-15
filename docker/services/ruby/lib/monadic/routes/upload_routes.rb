# frozen_string_literal: false

# Routes that turn a document or a web page into text for the message

# Largest upload accepted, checked before the body is read (config.ru).
DOCUMENT_UPLOAD_MAX_BYTES = 200_000_000

# Convert a document file to text. Always returns JSON (see JSON routes
# in docs_dev/developer/anti_pattern_lints.md).
post "/document" do
  content_type :json

  return error_json("No file selected. Please choose a document file to convert.") unless params["docFile"]

  begin
    doc_file_handler = params["docFile"]["tempfile"]
    doc_label = params["docLabel"].to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    # basename prevents directory-traversal style filenames
    filename = File.basename(params["docFile"]["filename"])

    user_data_dir = Monadic::Utils::Environment.data_path
    doc_file_path = File.join(user_data_dir, filename)
    # Never through a link in its place (code a model runs could have made one)
    Monadic::Utils::SharedPathGuard.write_file!(doc_file_path, doc_file_handler.read, mode: "wb")

    utf8_filename = File.basename(doc_file_path).force_encoding("UTF-8")
    doc_file_handler.close

    markdown = MonadicApp.doc2markdown(utf8_filename)

    if markdown.to_s.strip.empty?
      return error_json("No content could be extracted from the document")
    end

    doc_text = "Filename: " + utf8_filename + "\n---\n" + markdown
    result = if doc_label.to_s != ""
              "\n---\n" + doc_label + "\n---\n" + doc_text
            else
              "\n---\n" + doc_text
            end

    { success: true, content: result }.to_json
  rescue => e
    error_json("Error processing document: #{e.message}")
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
