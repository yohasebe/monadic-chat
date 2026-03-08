# frozen_string_literal: false

# PDF storage and document management routes
# Handles local PGVector storage and OpenAI Vector Store (cloud) operations

# API: PDF storage status (mode/local/cloud presence/VS id)
get "/api/pdf_storage_status" do
  content_type :json
  begin
    # Determine app key for registry scope
    app_key = begin
      (session[:parameters] && session[:parameters]["app_name"]) || "default"
    rescue StandardError
      "default"
    end
    # VS presence
    vs_id = begin
      Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
    rescue StandardError
      nil
    end
    if (!vs_id || vs_id.to_s.empty?) && CONFIG.key?("OPENAI_VECTOR_STORE_ID")
      env_vs = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip
      vs_id = env_vs unless env_vs.empty?
    end
    if (!vs_id || vs_id.to_s.empty?)
      vs_meta_path = File.join(Monadic::Utils::Environment.data_path, 'pdf_navigator_openai.json')
      if File.exist?(vs_meta_path)
        begin
          meta = JSON.parse(File.read(vs_meta_path))
          vs_id = meta["vector_store_id"] if meta && meta["vector_store_id"]
        rescue StandardError
          # ignore
        end
      end
    end
    cloud_present = !!vs_id
  # Local presence (fast check)
  local_present = begin
    if defined?(EMBEDDINGS_DB) && EMBEDDINGS_DB
      if EMBEDDINGS_DB.respond_to?(:any_docs?)
        EMBEDDINGS_DB.any_docs?
      else
        arr = list_pdf_titles
        arr.is_a?(Array) && !arr.empty?
      end
    else
      false
    end
  rescue StandardError
    false
  end
    # Mode resolution (no hybrid)
    session_mode = (defined?(session) ? session[:pdf_storage_mode].to_s.downcase : '')
  configured_mode = get_pdf_storage_mode
  mode = if session_mode == 'local'
    'local'
  elsif session_mode == 'cloud' && cloud_present
    'cloud'
  elsif configured_mode == 'cloud' && cloud_present
    'cloud'
  elsif configured_mode == 'local' && local_present
    'local'
  elsif cloud_present
    'cloud'
  elsif local_present
    'local'
  else
    configured_mode
  end
    { success: true, mode: mode, vector_store_id: vs_id, local_present: local_present, cloud_present: cloud_present }.to_json
  rescue StandardError => e
    status 500
    error_json(e.message)
  end
end

# API: PDF storage defaults and availability for UI
get "/api/pdf_storage_defaults" do
  content_type :json
  begin
    default_storage = get_pdf_storage_mode
    pgvector_available = begin
      defined?(EMBEDDINGS_DB) && !EMBEDDINGS_DB.nil?
    rescue StandardError
      false
    end
    { default_storage: default_storage, pgvector_available: pgvector_available }.to_json
  rescue StandardError => e
    status 500
    { default_storage: 'local', pgvector_available: false }.to_json
  end
end

# OpenAI Responses: PDF upload/list/clear (vector store)
post "/openai/pdf" do
  content_type :json
  action = params["action"] || "upload"
  api_key = CONFIG["OPENAI_API_KEY"]
  return error_json("OpenAI API key not configured") unless api_key && !api_key.empty?

  begin
    case action
    when "upload"
      unless params["pdfFile"]
        return error_json("No file selected. Please choose a PDF file to upload.")
      end

      file_param = params["pdfFile"]
      filename = file_param["filename"]
      tempfile = file_param["tempfile"]

      # Determine app scope (for registry)
      app_key = begin
        (session[:parameters] && session[:parameters]["app_name"]) || "default"
      rescue StandardError
        "default"
      end

      # Calculate file hash (sha256 + size)
      file_hash = begin
        sha = Digest::SHA256.file(tempfile.path).hexdigest
        size = File.size(tempfile.path)
        "#{sha}_#{size}"
      rescue StandardError
        nil
      end

      headers = { "Authorization" => "Bearer #{api_key}" }
      api_base = "https://api.openai.com/v1"

      # Deduplication: if a file with the same hash exists in registry, try reusing it
      dedup_candidate = nil
      begin
        app_entry = Monadic::Utils::DocumentStoreRegistry.get_app(app_key)
        files = app_entry.dig('cloud', 'files') || []
        dedup_candidate = files.find { |f| file_hash && f['hash'] == file_hash }
      rescue StandardError
        dedup_candidate = nil
      end

      file_id = nil
      uploaded_new_file = false
      if dedup_candidate && dedup_candidate['file_id']
        file_id = dedup_candidate['file_id']
        puts "[OpenAI PDF] Dedup candidate found for app=#{app_key} file_id=#{file_id}"
      else
        # Upload file to OpenAI Files API
        form = {
          purpose: "assistants",
          file: HTTP::FormData::File.new(tempfile.path, filename: filename, content_type: "application/pdf")
        }
        upload_res = HTTP.headers(headers).post("#{api_base}/files", form: form)
        unless upload_res.status.success?
          puts "[OpenAI PDF] File upload failed: status=#{upload_res.status} body=#{upload_res.body.to_s[0..200]}"
          return error_json("OpenAI file upload failed: #{upload_res.status}")
        end
        upload_json = JSON.parse(upload_res.body.to_s) rescue nil
        file_id = upload_json && upload_json["id"]
        unless file_id
          puts "[OpenAI PDF] Invalid file upload response: #{upload_res.body.to_s[0..200]}"
          return error_json("OpenAI file upload response invalid")
        end
        uploaded_new_file = true
        puts "[OpenAI PDF] Uploaded file: filename=#{filename} file_id=#{file_id}"
      end

      # Resolve Vector Store ID (session -> app ENV -> registry -> global ENV -> fallback meta -> create new)
      vs_meta_path = File.join(Monadic::Utils::Environment.data_path, 'pdf_navigator_openai.json')
      # app-specific ENV
      app_env_vs = begin
        key = "OPENAI_VECTOR_STORE_ID__#{app_key.upcase}"
        val = CONFIG[key]
        s = val.to_s.strip
        s.empty? ? nil : s
      rescue StandardError
        nil
      end
      # registry
      reg_vs_id = begin
        Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
      rescue StandardError
        nil
      end
      # global ENV
      env_vs_id = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip if CONFIG.key?("OPENAI_VECTOR_STORE_ID")
      vs_id = nil
      # read fallback meta
      fallback_vs = nil
      if File.exist?(vs_meta_path)
        begin
          meta = JSON.parse(File.read(vs_meta_path))
          fallback_vs = meta["vector_store_id"]
        rescue StandardError
          fallback_vs = nil
        end
      end
      vs_id = session[:openai_vector_store_id]
      vs_id = app_env_vs if (vs_id.nil? || vs_id.empty?) && app_env_vs
      # Prefer explicit ENV over registry for predictability
      vs_id = env_vs_id if (vs_id.nil? || vs_id.empty?) && env_vs_id && !env_vs_id.empty?
      vs_id = reg_vs_id if (vs_id.nil? || vs_id.empty?) && reg_vs_id
      vs_id = fallback_vs if (vs_id.nil? || vs_id.empty?) && fallback_vs

      unless vs_id
        # create a new VS for this app/system
        name = "monadic-pdf-navigator-#{Time.now.utc.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
        vs_res = HTTP.headers({ **headers, "Content-Type" => "application/json" }).post(
          "#{api_base}/vector_stores",
          body: { name: name }.to_json
        )
        unless vs_res.status.success?
          puts "[OpenAI PDF] Vector store creation failed: status=#{vs_res.status} body=#{vs_res.body.to_s[0..200]}"
          return error_json("Vector store creation failed: #{vs_res.status}")
        end
        vs_json = JSON.parse(vs_res.body.to_s) rescue nil
        vs_id = vs_json && vs_json["id"]
        unless vs_id
          puts "[OpenAI PDF] Invalid vector store response: #{vs_res.body.to_s[0..200]}"
          return error_json("Vector store creation response invalid")
        end
        puts "[OpenAI PDF] Vector store ready: vs_id=#{vs_id}"
        # persist to fallback meta if ENV is not set
        if env_vs_id.nil? || env_vs_id.empty?
          begin
            meta = { "vector_store_id" => vs_id, "files" => [] }
            File.write(vs_meta_path, JSON.pretty_generate(meta))
            puts "[OpenAI PDF] Tip: set OPENAI_VECTOR_STORE_ID=#{vs_id} in .env for reuse"
          rescue StandardError => e
            puts "[OpenAI PDF] Failed to write VS meta: #{e.message}"
          end
        end
        # Save to registry (app-scoped)
        begin
          Monadic::Utils::DocumentStoreRegistry.set_cloud_vs(app_key, vs_id)
        rescue StandardError => e
          puts "[Registry] Failed to set VS for app #{app_key}: #{e.message}"
        end
      end
      # Reflect VS into session for runtime helpers that still consult session
      session[:openai_vector_store_id] = vs_id

      # Add file to vector store
      add_res = HTTP.headers({ **headers, "Content-Type" => "application/json" }).post(
        "#{api_base}/vector_stores/#{vs_id}/files",
        body: { file_id: file_id }.to_json
      )
      unless add_res.status.success?
        # If dedup re-attach failed (stale file id), attempt full upload once
        if dedup_candidate && !uploaded_new_file
          begin
            form = {
              purpose: "assistants",
              file: HTTP::FormData::File.new(tempfile.path, filename: filename, content_type: "application/pdf")
            }
            upload_res = HTTP.headers(headers).post("#{api_base}/files", form: form)
            if upload_res.status.success?
              upj = JSON.parse(upload_res.body.to_s) rescue nil
              file_id = upj && upj["id"]
              if file_id
                retry_add = HTTP.headers({ **headers, "Content-Type" => "application/json" }).post(
                  "#{api_base}/vector_stores/#{vs_id}/files",
                  body: { file_id: file_id }.to_json
                )
                unless retry_add.status.success?
                  puts "[OpenAI PDF] Add file to vector store failed after retry: status=#{retry_add.status} body=#{retry_add.body.to_s[0..200]}"
                  return error_json("Adding file to vector store failed: #{retry_add.status}")
                end
                uploaded_new_file = true
              else
                return error_json("OpenAI file upload response invalid (retry)")
              end
            else
              puts "[OpenAI PDF] File upload (retry) failed: status=#{upload_res.status} body=#{upload_res.body.to_s[0..200]}"
              return error_json("OpenAI file upload failed (retry): #{upload_res.status}")
            end
          rescue StandardError => e
            return error_json("OpenAI file attach failed: #{e.message}")
          end
        else
          puts "[OpenAI PDF] Add file to vector store failed: status=#{add_res.status} body=#{add_res.body.to_s[0..200]}"
          return error_json("Adding file to vector store failed: #{add_res.status}")
        end
      end
      puts "[OpenAI PDF] Linked file to vector store: vs_id=#{vs_id} file_id=#{file_id}"
      # Update registry with file record
      begin
        # Only append a new file record if we actually uploaded a new file or if no record exists
        app_entry = Monadic::Utils::DocumentStoreRegistry.get_app(app_key)
        known = (app_entry.dig('cloud', 'files') || []).any? { |f| f['file_id'] == file_id }
        if uploaded_new_file || !known
          Monadic::Utils::DocumentStoreRegistry.add_cloud_file(app_key, file_id: file_id, filename: filename, hash: file_hash)
        end
      rescue StandardError => e
        puts "[Registry] Failed to update registry: #{e.message}"
      end
      # Mark session storage mode as cloud for downstream routing
      begin
        session[:pdf_storage_mode] = 'cloud'
      rescue StandardError
        # no-op
      end
      # Update fallback meta file with this file entry
      if (env_vs_id.nil? || env_vs_id.empty?)
        begin
          meta = File.exist?(vs_meta_path) ? (JSON.parse(File.read(vs_meta_path)) rescue {}) : {}
          meta["vector_store_id"] = vs_id
          meta["files"] ||= []
          meta["files"] << { "file_id" => file_id, "filename" => filename, "created_at" => Time.now.utc.iso8601 }
          File.write(vs_meta_path, JSON.pretty_generate(meta))
        rescue StandardError => e
          puts "[OpenAI PDF] Failed to update VS meta: #{e.message}"
        end
      end

      # Invalidate caches for mode/presence
      bump_pdf_cache_version
      { success: true, filename: filename, vector_store_id: vs_id, file_id: file_id, deduplicated: (!uploaded_new_file) }.to_json

    else
      status 400
      error_json("Unsupported action")
    end
  rescue => e
    error_json("OpenAI PDF endpoint error: #{e.class}: #{e.message}")
  end
end

get "/openai/pdf" do
  content_type :json
  action = params["action"] || "list"
  api_key = CONFIG["OPENAI_API_KEY"]
  return error_json("OpenAI API key not configured") unless api_key && !api_key.empty?

  begin
    case action
    when "list"
      app_key = resolve_openai_app_key
      vs_id = resolve_vector_store_id(app_key)
      return { success: true, files: [], vector_store_id: nil }.to_json unless vs_id
      headers = { "Authorization" => "Bearer #{api_key}" }
      api_base = "https://api.openai.com/v1"
      res = HTTP.headers(headers).get("#{api_base}/vector_stores/#{vs_id}/files")
      if res.status.success?
        base = JSON.parse(res.body.to_s) rescue { "data" => [] }
        raw = base["data"] || []
        # Enrich with filename via /v1/files/{id}
        files = raw.map do |f|
          fid = f["id"]
          fname = nil
          begin
            details = HTTP.headers(headers).get("#{api_base}/files/#{fid}")
            if details.status.success?
              dj = JSON.parse(details.body.to_s) rescue nil
              fname = dj && dj["filename"]
            end
          rescue StandardError
            fname = nil
          end
          { id: fid, filename: fname, status: f["status"] }
        end
        { success: true, files: files, vector_store_id: vs_id }.to_json
      else
        error_json("Failed to fetch file list: #{res.status}")
      end
    else
      status 400
      error_json("Unsupported action")
    end
  rescue => e
    error_json("OpenAI PDF list error: #{e.class}: #{e.message}")
  end
end

delete "/openai/pdf" do
  content_type :json
  action = params["action"] || "clear"
  api_key = CONFIG["OPENAI_API_KEY"]
  return error_json("OpenAI API key not configured") unless api_key && !api_key.empty?
  begin
    case action
    when "clear"
      headers = { "Authorization" => "Bearer #{api_key}" }
      api_base = "https://api.openai.com/v1"
      vs_meta_path = File.join(Monadic::Utils::Environment.data_path, 'pdf_navigator_openai.json')
      app_key = begin
        (session[:parameters] && session[:parameters]["app_name"]) || "default"
      rescue StandardError
        "default"
      end
      app_env_vs = begin
        key = "OPENAI_VECTOR_STORE_ID__#{app_key.upcase}"
        val = CONFIG[key]
        s = val.to_s.strip
        s.empty? ? nil : s
      rescue StandardError
        nil
      end
      reg_vs_id = begin
        Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
      rescue StandardError
        nil
      end
      env_vs_id = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip if CONFIG.key?("OPENAI_VECTOR_STORE_ID")
      fallback_vs = nil
      if File.exist?(vs_meta_path)
        begin
          meta = JSON.parse(File.read(vs_meta_path))
          fallback_vs = meta["vector_store_id"]
        rescue StandardError
          fallback_vs = nil
        end
      end
      vs_id = session[:openai_vector_store_id]
      vs_id = app_env_vs if (vs_id.nil? || vs_id.empty?) && app_env_vs
      vs_id = env_vs_id if (vs_id.nil? || vs_id.empty?) && env_vs_id && !env_vs_id.empty?
      vs_id = reg_vs_id if (vs_id.nil? || vs_id.empty?) && reg_vs_id
      vs_id = fallback_vs if (vs_id.nil? || vs_id.empty?) && fallback_vs

      if vs_id
        if env_vs_id && !env_vs_id.empty?
          # ENV fixed: Keep VS itself, delete only the contents (files)
          files_res = HTTP.headers(headers).get("#{api_base}/vector_stores/#{vs_id}/files")
          if files_res.status.success?
            data = (JSON.parse(files_res.body.to_s) rescue {})
            (data["data"] || []).each do |f|
              fid = f["id"]
              begin
                HTTP.headers(headers).delete("#{api_base}/vector_stores/#{vs_id}/files/#{fid}")
              rescue StandardError => e
                Monadic::Utils::ExtraLogger.log { "[Cleanup] VS file delete failed: #{e.message}" }
              end
              begin
                HTTP.headers(headers).delete("#{api_base}/files/#{fid}")
              rescue StandardError => e
                Monadic::Utils::ExtraLogger.log { "[Cleanup] File delete failed: #{e.message}" }
              end
            end
          end
          # Clear files in metadata
          if File.exist?(vs_meta_path)
            begin
              meta = (JSON.parse(File.read(vs_meta_path)) rescue {})
              meta["files"] = []
              File.write(vs_meta_path, JSON.pretty_generate(meta))
            rescue StandardError => e
              Monadic::Utils::ExtraLogger.log { "[Cleanup] Metadata clear failed: #{e.message}" }
            end
          end
          # Also clear files for this app in registry
          begin
            Monadic::Utils::DocumentStoreRegistry.clear_cloud(app_key)
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[Cleanup] Registry clear failed: #{e.message}" }
          end
        else
          # No ENV fixed: Delete VS itself and clear metadata
          begin
            HTTP.headers(headers).delete("#{api_base}/vector_stores/#{vs_id}")
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[Cleanup] VS delete failed: #{e.message}" }
          end
          if File.exist?(vs_meta_path)
            begin
              File.write(vs_meta_path, JSON.pretty_generate({}))
            rescue StandardError => e
              Monadic::Utils::ExtraLogger.log { "[Cleanup] Metadata write failed: #{e.message}" }
            end
          end
          # Clear VS and files in registry
          begin
            Monadic::Utils::DocumentStoreRegistry.clear_cloud(app_key)
            Monadic::Utils::DocumentStoreRegistry.set_cloud_vs(app_key, nil)
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[Cleanup] Registry clear failed: #{e.message}" }
          end
        end
      end
      # Bump session cache version to invalidate mode/presence caches
      bump_pdf_cache_version
      { success: true }.to_json
    when "delete"
      file_id = params["file_id"]
      return error_json("file_id required") unless file_id
      headers = { "Authorization" => "Bearer #{api_key}" }
      api_base = "https://api.openai.com/v1"
      # Best-effort: remove from vector store (if present), then delete file
      app_key = begin
        (session[:parameters] && session[:parameters]["app_name"]) || "default"
      rescue StandardError
        "default"
      end
      app_env_vs = begin
        key = "OPENAI_VECTOR_STORE_ID__#{app_key.upcase}"
        val = CONFIG[key]
        s = val.to_s.strip
        s.empty? ? nil : s
      rescue StandardError
        nil
      end
      reg_vs_id = begin
        Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
      rescue StandardError
        nil
      end
      env_vs_id = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip if CONFIG.key?("OPENAI_VECTOR_STORE_ID")
      vs_meta_path = File.join(Monadic::Utils::Environment.data_path, 'pdf_navigator_openai.json')
      fallback_vs = nil
      if File.exist?(vs_meta_path)
        begin
          meta = JSON.parse(File.read(vs_meta_path))
          fallback_vs = meta["vector_store_id"]
        rescue StandardError
          fallback_vs = nil
        end
      end
      vs_id = session[:openai_vector_store_id]
      vs_id = app_env_vs if (vs_id.nil? || vs_id.empty?) && app_env_vs
      vs_id = reg_vs_id if (vs_id.nil? || vs_id.empty?) && reg_vs_id
      vs_id = env_vs_id if (vs_id.nil? || vs_id.empty?) && env_vs_id && !env_vs_id.empty?
      vs_id = fallback_vs if (vs_id.nil? || vs_id.empty?) && fallback_vs
      begin
        if vs_id
          HTTP.headers(headers).delete("#{api_base}/vector_stores/#{vs_id}/files/#{file_id}")
        end
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[Cleanup] VS file unlink failed: #{e.message}" }
      end
      del_res = HTTP.headers(headers).delete("#{api_base}/files/#{file_id}")
      if del_res.status.success?
        # update fallback meta if present
        if File.exist?(vs_meta_path)
          begin
            meta = (JSON.parse(File.read(vs_meta_path)) rescue {})
            meta["files"] = (meta["files"] || []).reject { |f| f["file_id"] == file_id }
            File.write(vs_meta_path, JSON.pretty_generate(meta))
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[Cleanup] Metadata update failed: #{e.message}" }
          end
        end
        begin
          Monadic::Utils::DocumentStoreRegistry.remove_cloud_file(app_key, file_id)
        rescue StandardError => e
          Monadic::Utils::ExtraLogger.log { "[Cleanup] Registry file remove failed: #{e.message}" }
        end
        # Bump cache version
        bump_pdf_cache_version
        { success: true }.to_json
      else
        error_json("Failed to delete file: #{del_res.status}")
      end
    else
      status 400
      error_json("Unsupported action")
    end
  rescue => e
    error_json("OpenAI PDF clear error: #{e.class}: #{e.message}")
  end
end

# Upload a PDF file (local PGVector storage)
post "/pdf" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json

    if params["pdfFile"]
      begin
        # Check if EMBEDDINGS_DB is available
        unless EMBEDDINGS_DB
          return error_json("Database connection not available")
        end
        pdf_file_handler = params["pdfFile"]["tempfile"]
        temp_file = Tempfile.new("temp_pdf")
        temp_file.binmode
        temp_file.write(pdf_file_handler.read)
        temp_file.rewind

        # Close the original file handler
        pdf_file_handler.close

        pdf = PDF2Text.new(path: temp_file.path, max_tokens: 800, separator: "\n", overwrap_lines: 2)
        pdf.extract

        # Close and delete the temporary file
        temp_file.close
        temp_file.unlink

        doc_data = { items: 0, metadata: {} }
        items_data = []

        # Check if text was extracted successfully
        if pdf.split_text.empty?
          return error_json("No text could be extracted from the PDF file")
        end

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

        api_key = settings.api_key
        if api_key.nil? || api_key.empty?
          return error_json("API key not configured")
        end

        EMBEDDINGS_DB.store_embeddings(doc_data, items_data, api_key: api_key)
        # Mark session storage mode as local for downstream routing
        begin
          session[:pdf_storage_mode] = 'local'
        rescue StandardError
          # no-op
        end
        # Invalidate caches for mode/presence
        bump_pdf_cache_version
        return { success: true, filename: params["pdfFile"]["filename"] }.to_json
      rescue TextEmbeddings::DatabaseError => e
        return error_json("Database error: #{e.message}")
      rescue PG::Error => e
        return error_json("PostgreSQL error: #{e.message}")
      rescue => e
        return error_json("Error processing PDF: #{e.class.name} - #{e.message}")
      end
    else
      return error_json("No file selected. Please choose a PDF file to upload.")
    end
  else
    # For regular form submissions, maintain original behavior
    if params["pdfFile"]
      pdf_file_handler = params["pdfFile"]["tempfile"]
      temp_file = Tempfile.new("temp_pdf")
      temp_file.binmode
      temp_file.write(pdf_file_handler.read)
      temp_file.rewind

      # Close the original file handler
      pdf_file_handler.close

      pdf = PDF2Text.new(path: temp_file.path, max_tokens: 800, separator: "\n", overwrap_lines: 2)
      pdf.extract

      # Close and delete the temporary file
      temp_file.close
      temp_file.unlink

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
      EMBEDDINGS_DB.store_embeddings(doc_data, items_data, api_key: settings.api_key)
      bump_pdf_cache_version
      return params["pdfFile"]["filename"]
    else
      session[:error] = "Error: No file selected. Please choose a PDF file to upload."
    end
  end
end
