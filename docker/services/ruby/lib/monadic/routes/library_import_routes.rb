# frozen_string_literal: false

# Knowledge Base file-import routes.
#
# POST /library/import — receives a Markdown / Code / PDF / Office file
# upload and queues it for ingestion into the Library as a single
# conversation. The Browse modal's "Import file" button posts here.
# Plays the same role for KB ingestion that LIBRARY_SAVE plays for the
# current chat session, but with file content instead of in-memory
# messages.
#
# GET /library/import/status/:id — returns the current state of a
# previously queued import (queued / extracting / embedding_storing /
# done / error). The frontend polls this endpoint to render progress.
#
# Concurrency model (beta.16, asynchronous):
#   1. POST validates size, writes the upload to disk, registers an
#      ImportTracker entry, spawns a worker Thread, and returns 202
#      Accepted with `{ import_id, status_url }` — no heavy work yet.
#   2. The worker thread runs extraction (pdfplumber or extractor
#      service) → embedding → Qdrant insert, updating the tracker as
#      each stage advances. Failure paths set stage="error" with the
#      message; success path sets stage="done" with conversation_id
#      and per-segment counts.
#   3. The frontend polls GET /library/import/status/:id with
#      exponential backoff until stage is `done` or `error`.
#
# Why async: the heavy path (image-only PDF → docling + RapidOCR →
# embedding) can occupy a Falcon worker for several minutes. Synchronous
# handling queued every other request behind a single import. Splitting
# into 202 + worker keeps the request-handler thread free for the rest
# of the application while imports run in the background.
#
# Defenses still in place:
#   - LIBRARY_IMPORT_MAX_BYTES caps a single upload (default 100 MiB)
#   - Size check is fail-CLOSED: an upload whose size cannot be
#     determined is rejected (closes a DoS bypass via Rack edge cases)
#   - extractor_service remains opt-in (Settings → Install Options);
#     without it the lighter pdfplumber path runs

require 'fileutils'
require 'securerandom'
require 'tempfile'
require 'monadic/library'

# Cap each upload at 100 MiB. Larger files would queue extractor work
# for an extended time and risk filling the imports/ directory. Override
# with LIBRARY_IMPORT_MAX_BYTES if a power user needs to bypass the limit.
LIBRARY_IMPORT_MAX_BYTES = (ENV.fetch('LIBRARY_IMPORT_MAX_BYTES', (100 * 1024 * 1024).to_s)).to_i

post "/library/import" do
  content_type :json

  return error_json("No file selected. Please choose a file to upload.") unless params["libraryFile"]

  file = params["libraryFile"]
  filename = File.basename(file["filename"].to_s)
  return error_json("Missing filename") if filename.empty?

  # Reject oversized uploads up front so we never write them to disk or
  # spawn the python extractor on something we will not finish.
  #
  # Fail-CLOSED on a missing size: if `file["tempfile"].size` raises, we
  # cannot honour the cap, so we refuse the upload rather than waving it
  # through. The previous behaviour (treat unknown size as unlimited)
  # was a DoS escape hatch via Rack edge cases (StringIO substitutes,
  # version drift in tempfile semantics).
  upload_size = begin
    file["tempfile"].size
  rescue StandardError
    nil
  end
  if upload_size.nil?
    return error_json("Could not determine upload size; rejected for safety. Re-upload via a multipart form so the server can verify the byte count.")
  end
  if upload_size > LIBRARY_IMPORT_MAX_BYTES
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

  import_id = Monadic::Library::ImportTracker.create
  Monadic::Library::ImportTracker.update(
    import_id,
    filename: filename,
    scope_app: scope_app,
    upload_bytes: upload_size
  )

  # Worker thread. We deliberately use Thread.new (not Async::Task)
  # because the inner pipeline is synchronous I/O against http extractor
  # / embeddings / Qdrant — fiber scheduling buys nothing here, and
  # Thread releases the request handler immediately.
  Thread.new do
    Thread.current.report_on_exception = false
    begin
      Monadic::Library::ImportTracker.update(import_id, stage: 'extracting')
      conversation = Monadic::Library::FileImporter.build_conversation(
        path: dest_path, filename: filename, options: options
      )

      Monadic::Library::ImportTracker.update(import_id, stage: 'embedding_storing')
      store = Monadic::Library::Store.new
      result = Monadic::Library::Manager.import_conversation(
        store: store, conversation: conversation, scope_app: scope_app
      )

      Monadic::Library::ImportTracker.update(
        import_id,
        stage: 'done',
        finished_at: Time.now,
        conversation_id: result[:conversation_id],
        counts: result[:counts].each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      )
    rescue Monadic::Library::FileImporter::UnsupportedFormatError => e
      Monadic::Library::ImportTracker.update(
        import_id, stage: 'error', finished_at: Time.now, error: e.message
      )
    rescue Monadic::Library::FileImporter::ExtractionError => e
      Monadic::Library::ImportTracker.update(
        import_id, stage: 'error', finished_at: Time.now,
        error: "Extraction failed: #{e.message}"
      )
    rescue ArgumentError => e
      Monadic::Library::ImportTracker.update(
        import_id, stage: 'error', finished_at: Time.now, error: e.message
      )
    rescue StandardError => e
      if defined?(Monadic::Utils::ExtraLogger)
        Monadic::Utils::ExtraLogger.log do
          "[Library] Async /library/import failed: #{e.class}: #{e.message}"
        end
      end
      Monadic::Library::ImportTracker.update(
        import_id, stage: 'error', finished_at: Time.now,
        error: "Library import failed: #{e.class.name} - #{e.message}"
      )
    end
  end

  status 202
  {
    success: true,
    import_id: import_id,
    status_url: "/library/import/status/#{import_id}",
    filename: filename,
    scope_app: scope_app
  }.to_json
end

get "/library/import/status/:id" do
  content_type :json
  entry = Monadic::Library::ImportTracker.get(params[:id])
  unless entry
    # Either an unknown id, or the entry has been TTL-purged after
    # completion. The frontend treats 404 the same way as a hard error
    # (it cannot distinguish "never existed" from "completed and
    # expired"), but in practice a 404 only appears for forgotten polls
    # since active polls run continuously until terminal state.
    status 404
    return error_json("Import not found or already expired")
  end

  payload = {
    success: true,
    import_id: params[:id],
    stage: entry[:stage],
    filename: entry[:filename],
    scope_app: entry[:scope_app]
  }
  payload[:conversation_id] = entry[:conversation_id] if entry[:conversation_id]
  payload[:counts] = entry[:counts] if entry[:counts]
  payload[:error] = entry[:error] if entry[:error]
  payload.to_json
end
