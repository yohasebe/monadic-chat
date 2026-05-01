# frozen_string_literal: false

# Knowledge Base file-import routes.
#
# POST /library/import — receives a Markdown / Code / PDF / Office file
# upload and ingests it into the Library as a single conversation. The
# Browse modal's "Import file" button posts here. Plays the same role
# for KB ingestion that LIBRARY_SAVE plays for the current chat session,
# but with file content instead of in-memory messages.

require 'tempfile'
require 'monadic/library'

# Cap each upload at 100 MiB. Larger files would block the Falcon worker
# during read+extract+embed (synchronous pipeline) and risk filling the
# imports/ directory. Override with LIBRARY_IMPORT_MAX_BYTES if a power
# user needs to bypass the limit.
LIBRARY_IMPORT_MAX_BYTES = (ENV.fetch('LIBRARY_IMPORT_MAX_BYTES', (100 * 1024 * 1024).to_s)).to_i

post "/library/import" do
  content_type :json

  return error_json("No file selected. Please choose a file to upload.") unless params["libraryFile"]

  file = params["libraryFile"]
  filename = File.basename(file["filename"].to_s)
  return error_json("Missing filename") if filename.empty?

  # Reject oversized uploads up front so we never write them to disk or
  # spawn the python extractor on something we will not finish.
  upload_size = begin
    file["tempfile"].size
  rescue StandardError
    nil
  end
  if upload_size && upload_size > LIBRARY_IMPORT_MAX_BYTES
    mb = (LIBRARY_IMPORT_MAX_BYTES / 1024.0 / 1024.0).round(0)
    return error_json("File exceeds the #{mb} MB import limit. Split the document or raise LIBRARY_IMPORT_MAX_BYTES.")
  end

  # File imports are knowledge artifacts that the user typically wants
  # accessible from any app, so they default to the "Global" scope. The
  # UI can still pass `libraryScopeApp` (e.g. an app class name) when
  # the caller wants the import scoped to one particular app.
  scope_app = params["libraryScopeApp"].to_s.strip
  scope_app = Monadic::Library::Store::SCOPE_GLOBAL if scope_app.empty?

  options = {}
  options[:title] = params["libraryTitle"].to_s unless params["libraryTitle"].to_s.strip.empty?
  options[:license] = params["libraryLicense"].to_s unless params["libraryLicense"].to_s.strip.empty?

  # Persist the upload under the shared volume so the python container
  # can read it via the same `/monadic/data` mount.
  data_root = Monadic::Utils::Environment.data_path
  imports_dir = File.join(data_root, 'library', 'imports')
  FileUtils.mkdir_p(imports_dir)
  dest_path = File.join(imports_dir, "#{Time.now.to_i}_#{SecureRandom.hex(4)}_#{filename}")

  begin
    File.open(dest_path, 'wb') { |f| f.write(file["tempfile"].read) }
  ensure
    file["tempfile"].close rescue nil
  end

  begin
    conversation = Monadic::Library::FileImporter.build_conversation(
      path: dest_path, filename: filename, options: options
    )
    store = Monadic::Library::Store.new
    result = Monadic::Library::Manager.import_conversation(
      store: store, conversation: conversation, scope_app: scope_app
    )
    {
      success: true,
      filename: filename,
      conversation_id: result[:conversation_id],
      scope_app: scope_app,
      counts: result[:counts].each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    }.to_json
  rescue Monadic::Library::FileImporter::UnsupportedFormatError => e
    error_json(e.message)
  rescue Monadic::Library::FileImporter::ExtractionError => e
    error_json("Extraction failed: #{e.message}")
  rescue ArgumentError => e
    error_json(e.message)
  rescue StandardError => e
    if defined?(Monadic::Utils::ExtraLogger)
      Monadic::Utils::ExtraLogger.log { "[Library] /library/import failed: #{e.class}: #{e.message}" }
    end
    error_json("Library import failed: #{e.class.name} - #{e.message}")
  end
end
