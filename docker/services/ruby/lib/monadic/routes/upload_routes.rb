# frozen_string_literal: false

# File upload routes: audio, documents, and web page fetching

ALLOWED_AUDIO_EXTS = %w[.mp3 .wav .m4a .ogg .flac .mid .midi].freeze

post "/upload_audio" do
  content_type :json
  if params["audioFile"]
    begin
      file_handler = params["audioFile"]["tempfile"]
      filename = File.basename(params["audioFile"]["filename"])
      ext = File.extname(filename).downcase
      unless ALLOWED_AUDIO_EXTS.include?(ext)
        file_handler.close
        return error_json("Unsupported file type: #{ext}")
      end
      user_data_dir = Monadic::Utils::Environment.data_path
      dest_path = File.join(user_data_dir, filename)
      File.open(dest_path, "wb") { |f| f.write(file_handler.read) }
      file_handler.close
      utf8_filename = filename.force_encoding("UTF-8")
      { success: true, filename: utf8_filename }.to_json
    rescue => e
      error_json("Upload failed: #{e.message}")
    end
  else
    error_json("No file selected")
  end
end

# Convert a document file to text
post "/document" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json

    if params["docFile"]
      begin
        doc_file_handler = params["docFile"]["tempfile"]
        # name the file based on datetime if no title is provided
        doc_label = params["docLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        # get filename from the file handler (basename prevents path traversal)
        filename = File.basename(params["docFile"]["filename"])

        user_data_dir = Monadic::Utils::Environment.data_path

        # Copy the file to user data directory
        doc_file_path = File.join(user_data_dir, filename)
        File.open(doc_file_path, "wb") do |f|
          f.write(doc_file_handler.read)
        end

        utf8_filename = File.basename(doc_file_path).force_encoding("UTF-8")
        doc_file_handler.close

        markdown = MonadicApp.doc2markdown(utf8_filename)

        # Check if we got any meaningful content
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
    else
      error_json("No file selected. Please choose a document file to convert.")
    end
  else
    # For regular form submissions, maintain original behavior
    if params["docFile"]
      doc_file_handler = params["docFile"]["tempfile"]
      # name the file based on datetime if no title is provided
      doc_label = params["docLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      # get filename from the file handler
      filename = params["docFile"]["filename"]

      user_data_dir = Monadic::Utils::Environment.data_path

      # Copy the file to user data directory
      doc_file_path = File.join(user_data_dir, filename)
      File.open(doc_file_path, "wb") do |f|
        f.write(doc_file_handler.read)
      end

      utf8_filename = File.basename(doc_file_path).force_encoding("UTF-8")
      doc_file_handler.close

      markdown = MonadicApp.doc2markdown(utf8_filename)

      doc_text = "Filename: " + utf8_filename + "\n---\n" + markdown
      if doc_label.to_s != ""
        "\n---\n" + doc_label + "\n---\n" + doc_text
      else
        "\n---\n" + doc_text
      end
    else
      session[:error] = "Error: No file selected. Please choose a document file to convert."
    end
  end
end

# Fetch the webpage content
post "/fetch_webpage" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json

    if params["pageURL"]
      begin
        url = params["pageURL"]
        url_decoded = CGI.unescape(url)
        label = params["urlLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

        # Web UI always uses Selenium for URL fetching
        # (Tavily is only used within Research Assistant apps)
        markdown = MonadicApp.fetch_webpage(url)

        # Check if we got any meaningful content
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
    else
      error_json("No URL provided")
    end
  else
    # For regular form submissions, use Selenium
    if params["pageURL"]
      url = params["pageURL"]
      url_decoded = CGI.unescape(url)
      label = params["urlLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

      # Web UI always uses Selenium for URL fetching
      markdown = MonadicApp.fetch_webpage(url)

      webpage_text = "URL: " + url_decoded + "\n---\n" + markdown
      if label.to_s != ""
        "---\n" + label + "\n---\n" + webpage_text
      else
        "---\n" + webpage_text
      end
    else
      session[:error] = "Error: No URL provided"
    end
  end
end
