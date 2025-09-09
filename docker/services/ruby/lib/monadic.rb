# frozen_string_literal: false

# Optimize load path by removing duplicates
$LOAD_PATH.uniq!

require_relative "monadic/utils/document_store_registry"

# Optional startup profiling
if ENV['PROFILE_STARTUP'] == 'true'
  require_relative "monadic/utils/startup_profiler"
  at_exit { StartupProfiler.report }
end

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
    { success: false, error: e.message }.to_json
  end
end

# AI User: expose defaults per provider for UI (SSOT-based)
get "/api/ai_user_defaults" do
  content_type :json
  begin
    providers = %w[openai anthropic gemini cohere mistral deepseek grok perplexity]
    result = {}
    providers.each do |p|
      has_key = case p
        when 'openai' then !!(CONFIG['OPENAI_API_KEY'] && !CONFIG['OPENAI_API_KEY'].to_s.strip.empty?)
        when 'anthropic' then !!(CONFIG['ANTHROPIC_API_KEY'] && !CONFIG['ANTHROPIC_API_KEY'].to_s.strip.empty?)
        when 'gemini' then !!(CONFIG['GEMINI_API_KEY'] && !CONFIG['GEMINI_API_KEY'].to_s.strip.empty?)
        when 'cohere' then !!(CONFIG['COHERE_API_KEY'] && !CONFIG['COHERE_API_KEY'].to_s.strip.empty?)
        when 'mistral' then !!(CONFIG['MISTRAL_API_KEY'] && !CONFIG['MISTRAL_API_KEY'].to_s.strip.empty?)
        when 'deepseek' then !!(CONFIG['DEEPSEEK_API_KEY'] && !CONFIG['DEEPSEEK_API_KEY'].to_s.strip.empty?)
        when 'grok' then !!(CONFIG['XAI_API_KEY'] && !CONFIG['XAI_API_KEY'].to_s.strip.empty?)
        when 'perplexity' then !!(CONFIG['PERPLEXITY_API_KEY'] && !CONFIG['PERPLEXITY_API_KEY'].to_s.strip.empty?)
        else false
      end
      default_model = SystemDefaults.get_default_model(p)
      result[p] = { has_key: has_key, default_model: default_model }
    end
    { success: true, defaults: result }.to_json
  rescue => e
    status 500
    { success: false, error: e.message }.to_json
  end
end

# OpenAI Responses: PDF upload/list/clear (vector store)
post "/openai/pdf" do
  content_type :json
  action = params["action"] || "upload"
  api_key = CONFIG["OPENAI_API_KEY"]
  return { success: false, error: "OpenAI API key not configured" }.to_json unless api_key && !api_key.empty?

  begin
    case action
    when "upload"
      unless params["pdfFile"]
        return { success: false, error: "No file selected. Please choose a PDF file to upload." }.to_json
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
          return { success: false, error: "OpenAI file upload failed: #{upload_res.status}" }.to_json
        end
        upload_json = JSON.parse(upload_res.body.to_s) rescue nil
        file_id = upload_json && upload_json["id"]
        unless file_id
          puts "[OpenAI PDF] Invalid file upload response: #{upload_res.body.to_s[0..200]}"
          return { success: false, error: "OpenAI file upload response invalid" }.to_json
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
          return { success: false, error: "Vector store creation failed: #{vs_res.status}" }.to_json
        end
        vs_json = JSON.parse(vs_res.body.to_s) rescue nil
        vs_id = vs_json && vs_json["id"]
        unless vs_id
          puts "[OpenAI PDF] Invalid vector store response: #{vs_res.body.to_s[0..200]}"
          return { success: false, error: "Vector store creation response invalid" }.to_json
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
                  return { success: false, error: "Adding file to vector store failed: #{retry_add.status}" }.to_json
                end
                uploaded_new_file = true
              else
                return { success: false, error: "OpenAI file upload response invalid (retry)" }.to_json
              end
            else
              puts "[OpenAI PDF] File upload (retry) failed: status=#{upload_res.status} body=#{upload_res.body.to_s[0..200]}"
              return { success: false, error: "OpenAI file upload failed (retry): #{upload_res.status}" }.to_json
            end
          rescue StandardError => e
            return { success: false, error: "OpenAI file attach failed: #{e.message}" }.to_json
          end
        else
          puts "[OpenAI PDF] Add file to vector store failed: status=#{add_res.status} body=#{add_res.body.to_s[0..200]}"
          return { success: false, error: "Adding file to vector store failed: #{add_res.status}" }.to_json
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
      begin
        session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
      rescue StandardError
        # no-op
      end
      { success: true, filename: filename, vector_store_id: vs_id, file_id: file_id, deduplicated: (!uploaded_new_file) }.to_json

    else
      status 400
      { success: false, error: "Unsupported action" }.to_json
    end
  rescue => e
    { success: false, error: "OpenAI PDF endpoint error: #{e.class}: #{e.message}" }.to_json
  end
end

# Capabilities: return install-option driven availability for frontend gating
get "/api/capabilities" do
  content_type :json
  begin
    latex_enabled = !!(CONFIG && CONFIG['INSTALL_LATEX'])
    latex_available = false
    if latex_enabled
      # Try a quick health check via docker exec (python container); cache in memory for a short time
      @@latex_health ||= { ts: Time.at(0), ok: false }
      if (Time.now - @@latex_health[:ts]) > 120 # 2 minutes TTL
        ok = false
        begin
          # This command should succeed when LaTeX minimal set is installed
          ok = system("docker exec monadic-chat-python-container sh -lc 'pdflatex -version >/dev/null 2>&1'")
        rescue StandardError
          ok = false
        end
        @@latex_health = { ts: Time.now, ok: ok }
      end
      latex_available = @@latex_health[:ok]
    end

    providers = {
      openai: !!(CONFIG && CONFIG['OPENAI_API_KEY'] && !CONFIG['OPENAI_API_KEY'].to_s.strip.empty?),
      anthropic: !!(CONFIG && CONFIG['ANTHROPIC_API_KEY'] && !CONFIG['ANTHROPIC_API_KEY'].to_s.strip.empty?),
      tavily: !!(CONFIG && CONFIG['TAVILY_API_KEY'] && !CONFIG['TAVILY_API_KEY'].to_s.strip.empty?)
    }

    selenium_enabled = !!(CONFIG && CONFIG['SELENIUM_ENABLED'])

    resp = {
      success: true,
      latex: { enabled: latex_enabled, available: latex_available },
      providers: providers,
      selenium: { enabled: selenium_enabled }
    }
    resp.to_json
  rescue StandardError => e
    status 500
    { success: false, error: e.message }.to_json
  end
end

get "/openai/pdf" do
  content_type :json
  action = params["action"] || "list"
  api_key = CONFIG["OPENAI_API_KEY"]
  return { success: false, error: "OpenAI API key not configured" }.to_json unless api_key && !api_key.empty?

  begin
    case action
    when "list"
      # Resolve VS from session/app ENV/registry/global ENV/fallback
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
      vs_id = env_vs_id if (vs_id.nil? || vs_id.empty?) && env_vs_id && !env_vs_id.empty?
      vs_id = reg_vs_id if (vs_id.nil? || vs_id.empty?) && reg_vs_id
      vs_id = fallback_vs if (vs_id.nil? || vs_id.empty?) && fallback_vs
      # Keep session in sync for downstream usage
      session[:openai_vector_store_id] = vs_id if vs_id
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
        { success: false, error: "Failed to fetch file list: #{res.status}" }.to_json
      end
    else
      status 400
      { success: false, error: "Unsupported action" }.to_json
    end
  rescue => e
    { success: false, error: "OpenAI PDF list error: #{e.class}: #{e.message}" }.to_json
  end
end

delete "/openai/pdf" do
  content_type :json
  action = params["action"] || "clear"
  api_key = CONFIG["OPENAI_API_KEY"]
  return { success: false, error: "OpenAI API key not configured" }.to_json unless api_key && !api_key.empty?
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
          # ENV固定: VS自体は残し、中身（ファイル）だけ削除
          files_res = HTTP.headers(headers).get("#{api_base}/vector_stores/#{vs_id}/files")
          if files_res.status.success?
            data = (JSON.parse(files_res.body.to_s) rescue {})
            (data["data"] || []).each do |f|
              fid = f["id"]
              begin
                HTTP.headers(headers).delete("#{api_base}/vector_stores/#{vs_id}/files/#{fid}")
              rescue StandardError; end
              begin
                HTTP.headers(headers).delete("#{api_base}/files/#{fid}")
              rescue StandardError; end
            end
          end
          # メタのfilesを空に
          if File.exist?(vs_meta_path)
            begin
              meta = (JSON.parse(File.read(vs_meta_path)) rescue {})
              meta["files"] = []
              File.write(vs_meta_path, JSON.pretty_generate(meta))
            rescue StandardError; end
          end
          # レジストリ上も当該アプリのfilesを空に
          begin
            Monadic::Utils::DocumentStoreRegistry.clear_cloud(app_key)
          rescue StandardError; end
        else
          # ENV固定なし: VS自体を削除し、メタもクリア
          begin
            HTTP.headers(headers).delete("#{api_base}/vector_stores/#{vs_id}")
          rescue StandardError; end
          if File.exist?(vs_meta_path)
            begin
              File.write(vs_meta_path, JSON.pretty_generate({}))
            rescue StandardError; end
          end
          # レジストリ上のVSとfilesをクリア
          begin
            Monadic::Utils::DocumentStoreRegistry.clear_cloud(app_key)
            Monadic::Utils::DocumentStoreRegistry.set_cloud_vs(app_key, nil)
          rescue StandardError; end
        end
      end
      # Bump session cache version to invalidate mode/presence caches
      begin
        session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
      rescue StandardError
        # no-op
      end
      { success: true }.to_json
    when "delete"
      file_id = params["file_id"]
      return { success: false, error: "file_id required" }.to_json unless file_id
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
      rescue
        # ignore
      end
      del_res = HTTP.headers(headers).delete("#{api_base}/files/#{file_id}")
      if del_res.status.success?
        # update fallback meta if present
        if File.exist?(vs_meta_path)
          begin
            meta = (JSON.parse(File.read(vs_meta_path)) rescue {})
            meta["files"] = (meta["files"] || []).reject { |f| f["file_id"] == file_id }
            File.write(vs_meta_path, JSON.pretty_generate(meta))
          rescue StandardError; end
        end
        begin
          Monadic::Utils::DocumentStoreRegistry.remove_cloud_file(app_key, file_id)
        rescue StandardError; end
        # Bump cache version
        begin
          session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
        rescue StandardError; end
        { success: true }.to_json
      else
        { success: false, error: "Failed to delete file: #{del_res.status}" }.to_json
      end
    else
      status 400
      { success: false, error: "Unsupported action" }.to_json
    end
  rescue => e
    { success: false, error: "OpenAI PDF clear error: #{e.class}: #{e.message}" }.to_json
  end
end

require "active_support"
require "active_support/core_ext/hash/indifferent_access"
require "base64"
require "cld"
require "digest"
require "dotenv"
require "eventmachine"
require "faye/websocket"
require "http"
require "http/form_data"
require "httparty"
require "i18n_data"
require "json"
require "commonmarker"
require "method_source"
require "net/http"
require "nokogiri"
require "open3"
require "pragmatic_segmenter"
require "rouge"
require "securerandom"
require "strscan"
require "tempfile"
require "uri"
require "cgi"
require "yaml"
require "csv"

# Make $MODELS a HashWithIndifferentAccess so it can be accessed with both strings and symbols
$MODELS = ActiveSupport::HashWithIndifferentAccess.new

require_relative "monadic/version"

# Load environment utilities early
require_relative "monadic/utils/environment"

# Backward compatibility - DEPRECATED
# All tests have been migrated. This can be removed after verifying no external dependencies.
IN_CONTAINER = Monadic::Utils::Environment.in_container?

require_relative "monadic/utils/setup"
require_relative "monadic/utils/flask_app_client"
require_relative "monadic/utils/help_embeddings_loader"

require_relative "monadic/utils/string_utils"
helpers StringUtils

require_relative "monadic/utils/interaction_utils"
helpers InteractionUtils

require_relative "monadic/utils/websocket"
helpers WebSocketHelper

require_relative "monadic/utils/pdf_text_extractor"
require_relative "monadic/utils/text_embeddings"
require_relative "monadic/utils/debug_helper"
require_relative "monadic/utils/json_repair"
require_relative "monadic/utils/error_pattern_detector"
require_relative "monadic/utils/model_spec_loader"
require_relative "monadic/utils/language_config"

require_relative "monadic/app"
require_relative "monadic/dsl"
require_relative "monadic/adapters/vendors/tavily_helper"

envpath = File.expand_path Paths::ENV_PATH
Dotenv.load(envpath)

# Include TavilyHelper for tavily_fetch method
include TavilyHelper

# Connect to the database
begin
  EMBEDDINGS_DB = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
rescue TextEmbeddings::DatabaseError => e
  puts "[WARNING] Failed to initialize help embeddings database: #{e.message}"
  EMBEDDINGS_DB = nil
end

DEFAULT_PROMPT_SUFFIX = <<~PROMPT
When creating a numbered list in Markdown that contains code blocks or other content within list items, please follow these formatting rules:

1. Each list item's content (including code blocks, paragraphs, or nested lists) should be indented with 4 spaces from the list marker position
2. Code blocks within list items should be indented with 4 spaces plus the standard code block syntax
3. Ensure there is a blank line before and after code blocks, tables, headings, paragraphs, lists, and other elements (including those within list items)
4. The indentation must be maintained for all content belonging to the same list item

Example format:

1. First item

    ```python
    # This code block is indented with 4 spaces
    print("Hello")
    ```

    Continuation text for first item (also indented with 4 spaces)

2. Second item

    - Nested list (indented with 4 spaces)
    - Another nested item

Please format all numbered lists following these rules to ensure proper rendering.
PROMPT

# Check if Ollama container is available (for development mode)
def check_ollama_available
  # If ENV already set (e.g., in Docker), use that
  return ENV["OLLAMA_AVAILABLE"] == "true" if ENV["OLLAMA_AVAILABLE"]
  
  # Otherwise, check if Docker is available and Ollama container exists
  begin
    # Check if docker command exists
    docker_available = system("which docker > /dev/null 2>&1")
    return false unless docker_available
    
    # Check if Ollama container exists
    ollama_exists = `docker ps -a --format "{{.Names}}" 2>/dev/null`.include?("monadic-chat-ollama-container")
    return ollama_exists
  rescue => e
    # If any error occurs, assume Ollama is not available
    return false
  end
end

# Initialize CONFIG with default values
CONFIG = {
  "DISTRIBUTED_MODE" => "off",  # Default to off/standalone mode
  "EXTRA_LOGGING" => ENV["EXTRA_LOGGING"] == "true" || false,  # Check ENV first, then default to false
  "JUPYTER_PORT" => "8889",     # Default Jupyter port
  "OLLAMA_AVAILABLE" => check_ollama_available  # Check if Ollama container is available
}

begin
  # Only process environment variables from the .env file, not dictionary data
  File.read(Paths::ENV_PATH).split("\n").each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")
    
    # Check for valid line format (key=value)
    if !line.include?("=")
      # Skip non-environment variable lines without warning since they might be TTS dictionary entries
      # that should be in a separate file
      next
    end
    
    key, value = line.split("=", 2) # Split only on first '=' to handle values containing '='
    next if key.nil? || key.empty?
    
    # Trim any whitespace and quotes from values
    value = value.strip.gsub(/^['"]|['"]$/, '') if value
    
    # Skip empty API keys
    if key.end_with?("_API_KEY") && (value.nil? || value.empty?)
      next
    end
    
    converted_value = case value
                      when "true"
                        true
                      when "false"
                        false
                      when /^\d+$/ # integer
                        value.to_i
                      when /^\d+\.\d+$/ # float
                        value.to_f
                      when nil
                        # Handle nil value
                        puts "Warning: Empty value for key '#{key}'"
                        next # Skip empty values instead of storing them as empty strings
                      else
                        value
                      end
    CONFIG[key] = converted_value
  end
  
  # Override with environment variables if they exist
  # This allows rake server:debug to force EXTRA_LOGGING=true
  if ENV["EXTRA_LOGGING"]
    CONFIG["EXTRA_LOGGING"] = ENV["EXTRA_LOGGING"] == "true"
  end
rescue Errno::ENOENT
  puts "Environment file not found at #{Paths::ENV_PATH}"
  CONFIG["ERROR"] = "Environment file not found. Default configuration will be used."
rescue Errno::EACCES
  puts "Permission denied when trying to read environment file at #{Paths::ENV_PATH}"
  CONFIG["ERROR"] = "Permission denied when trying to read environment file. Default configuration will be used."
rescue JSON::ParserError => e
  puts "JSON parsing error in environment file: #{e.message}"
  CONFIG["ERROR"] = "Configuration file contains invalid JSON: #{e.message}"
rescue StandardError => e
  puts "Error loading environment file: #{e.message}\n#{e.backtrace.join("\n")}"
  CONFIG["ERROR"] = "Error loading configuration: #{e.message}"
end

def handle_error(message)
  session[:error] = message
  redirect "/"
end

# List PDF titles in the database with error handling
def list_pdf_titles
  begin
    EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
  rescue StandardError => e
    puts "Error listing PDF titles: #{e.message}"
    []
  end
end

# Determine configured PDF storage mode (ENV), with backward compatibility
def get_pdf_storage_mode
  return @pdf_storage_mode_cache if instance_variable_defined?(:@pdf_storage_mode_cache)
  begin
    mode = (CONFIG["PDF_STORAGE_MODE"] || CONFIG["PDF_DEFAULT_STORAGE"] || 'local').to_s.downcase
    @pdf_storage_mode_cache = %w[local cloud].include?(mode) ? mode : 'local'
  rescue StandardError
    @pdf_storage_mode_cache = 'local'
  end
end

# Load app files
def load_app_files
  apps_to_load = {}
  base_app_dir = File.join(__dir__, "..", "apps")
  user_plugins_dir = Monadic::Utils::Environment.user_plugins_path

  # Initialize global error tracking variable
  $MONADIC_LOADING_ERRORS = []

  Dir["#{File.join(base_app_dir, "**") + File::SEPARATOR}*.{rb,mdsl}"].sort.each do |file|
    basename = File.basename(file)
    next if basename.start_with?("_") # ignore files that start with an underscore
    next if file.include?("/test/") # ignore test directories
    
    # If the basename already exists as a key, create a unique key by adding a suffix
    if apps_to_load.key?(basename)
      unique_basename = "#{basename}_#{SecureRandom.hex(4)}"
      apps_to_load[unique_basename] = file
    else
      apps_to_load[basename] = file
    end
  end

  if Dir.exist?(user_plugins_dir)
    Dir["#{File.join(user_plugins_dir, "**", "apps", "**") + File::SEPARATOR}*.{rb,mdsl}"].sort.each do |file|
      basename = File.basename(file)
      next if basename.start_with?("_") # ignore files that start with an underscore
      next if file.include?("/test/") # ignore test directories
      
      # If the basename already exists as a key, create a unique key by adding a suffix
      if apps_to_load.key?(basename)
        unique_basename = "#{basename}_#{SecureRandom.hex(4)}"
        apps_to_load[unique_basename] = file
      else
        apps_to_load[basename] = file
      end
    end
  end

  # sort apps_to_load so that rb files come before mdsl files
  apps_to_load = apps_to_load.sort_by { |k, _v| k.end_with?(".rb") ? 0 : 1 }.to_h

  apps_to_load.each_value do |file|
    MonadicDSL::Loader.load(file)
  end
  
  # Report loading errors if any occurred
  if $MONADIC_LOADING_ERRORS && !$MONADIC_LOADING_ERRORS.empty?
    error_count = $MONADIC_LOADING_ERRORS.size
    puts "\n\033[31m⚠️  #{error_count} app#{error_count > 1 ? 's' : ''} failed to load:\033[0m"
    
    $MONADIC_LOADING_ERRORS.each_with_index do |error, idx|
      puts "  #{idx + 1}. \033[33m#{error[:app]}\033[0m (#{File.basename(error[:file])})"
      puts "     Error: #{error[:error]}"
    end
    puts "\n"
  end
end

# Load the TTS dictionary
def load_tts_dict(tts_dict_data = nil)
  tts_dict = {}
  
  # 1. Check for TTS_DICT.csv in the config directory first (for Docker container)
  config_dict_path = File.join(Monadic::Utils::Environment.config_path, "TTS_DICT.csv")
  
  if File.exist?(config_dict_path)
    begin
      file_data = File.read(config_dict_path)
      tts_dict = StringUtils.process_tts_dictionary(file_data)
      puts "TTS Dictionary loaded with #{tts_dict.size} entries from config directory" if CONFIG["EXTRA_LOGGING"]
      CONFIG["TTS_DICT"] = tts_dict
      return
    rescue => e
      puts "Error reading TTS dictionary from config: #{e.message}" if CONFIG["EXTRA_LOGGING"]
    end
  end
  
  # 2. For development mode with 'rake debug': If TTS_DICT_PATH exists, read directly from that path
  if ENV['TTS_DICT_PATH'] && File.exist?(ENV['TTS_DICT_PATH'])
    begin
      file_data = File.read(ENV['TTS_DICT_PATH'])
      tts_dict = StringUtils.process_tts_dictionary(file_data)
      puts "TTS Dictionary loaded with #{tts_dict.size} entries from TTS_DICT_PATH (development mode)" if CONFIG["EXTRA_LOGGING"]
    rescue => e
      puts "Error reading TTS dictionary from TTS_DICT_PATH: #{e.message}" if CONFIG["EXTRA_LOGGING"]
    end
  # 3. Legacy support: Try using TTS_DICT_DATA if it exists
  elsif tts_dict_data || CONFIG["TTS_DICT_DATA"]
    data_to_process = tts_dict_data || CONFIG["TTS_DICT_DATA"]
    tts_dict = StringUtils.process_tts_dictionary(data_to_process)
    puts "TTS Dictionary loaded with #{tts_dict.size} entries from TTS_DICT_DATA (legacy mode)" if CONFIG["EXTRA_LOGGING"]
  else
    puts "No TTS Dictionary data available" if CONFIG["EXTRA_LOGGING"]
  end
  
  CONFIG["TTS_DICT"] = tts_dict || {}
end

# Initialize apps
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")
  
  # If in debug mode, log we're processing apps
  if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
    puts "Initializing apps in normal mode"
    puts "Debug: environment has DISTRIBUTED_MODE=#{ENV["DISTRIBUTED_MODE"]}"
  end
  
  klass.subclasses.each do |a|
    app = a.new
    class_settings = a.instance_variable_get(:@settings)
    
    # Debug: Log reasoning_effort for OpenAI apps
    if a.name.include?("OpenAI") && CONFIG["EXTRA_LOGGING"]
      puts "#{a.name} class settings: reasoning_effort = #{class_settings[:reasoning_effort].inspect}"
    end
    
    app.settings = ActiveSupport::HashWithIndifferentAccess.new(class_settings)
    
    # Debug: Log instance settings after assignment
    if a.name.include?("OpenAI") && CONFIG["EXTRA_LOGGING"]
      puts "#{a.name} instance settings: reasoning_effort = #{app.settings[:reasoning_effort].inspect}"
    end

    # Evaluate the disabled expression if it's a string containing Ruby code
    if app.settings["disabled"].is_a?(String) && app.settings["disabled"].match?(/defined\?|CONFIG/)
      begin
        app.settings["disabled"] = eval(app.settings["disabled"])
      rescue => e
        # If evaluation fails, assume the app is disabled
        app.settings["disabled"] = true
        puts "Warning: Failed to evaluate disabled condition for #{a.name}: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      end
    end

    # Evaluate the models expression if it's a string containing Ruby code
    if app.settings["models"].is_a?(String) && app.settings["models"].match?(/defined\?|list_models/)
      begin
        app.settings["models"] = eval(app.settings["models"])
      rescue => e
        # If evaluation fails, use empty array
        app.settings["models"] = []
        puts "Warning: Failed to evaluate models for #{a.name}: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      end
    end

    # Evaluate the model expression if it's a string containing Ruby code
    if app.settings["model"].is_a?(String) && app.settings["model"].match?(/ENV\[|defined\?|\|\|/)
      begin
        app.settings["model"] = eval(app.settings["model"])
      rescue => e
        # If evaluation fails, use a default model
        app.settings["model"] = "gpt-4.1"
        puts "Warning: Failed to evaluate model for #{a.name}: #{e.message}" if CONFIG["EXTRA_LOGGING"]
      end
    end

    vendor = app.settings["group"]
    models = app.settings["models"]
    if vendor && models
      MonadicApp.register_models(vendor, models)
    end

    app.settings["description"] = app.settings["description"] ? app.settings["description"].dup : ""
    if !app.settings["initial_prompt"]
      app.settings["initial_prompt"] = "You are an AI assistant but the initial prompt is missing. Tell the user they should provide a prompt."
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The initial prompt is missing.</p>"
    end
    if !app.settings["description"] || app.settings["description"].empty?
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The description is missing.</p>"
    end
    if !app.settings["icon"]
      app.settings["icon"] = "<i class='fa-solid fa-circle-question'></i>"
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The icon is missing.</p>"
    end
    if !app.settings["app_name"]
      # Use class name as app_name if not specified (for both rb and mdsl formats)
      app.settings["app_name"] = app.class.name || "UserApp_#{SecureRandom.hex(4)}"
    end
    
    # Set display_name if not specified by converting app_name to readable format
    if !app.settings["display_name"]
      app_name = app.settings["app_name"].to_s
      # Convert camelCase to space-separated words (e.g., 'CodeInterpreterGemini' -> 'Code Interpreter Gemini')
      app.settings["display_name"] = app_name.gsub(/([A-Z])/) { " #{$1}" }.lstrip
    end

    # Don't skip disabled apps - they need to be sent to frontend
    # The frontend will handle the disabled state appropriately
    
    # Register the app regardless of disabled state
    MonadicApp.register_app_settings(app.settings["app_name"], app)
    
    app_name = app.settings["app_name"]

    system_prompt_suffix = DEFAULT_PROMPT_SUFFIX.dup
    prompt_suffix = ""
    response_suffix = ""

    if app.settings["sourcecode"]
      system_prompt_suffix << <<~SYSPSUFFIX

      It is important to avoid nesting Markdown code blocks. When embedding the content of a Markdown  file within your response, use the following format. This will ensure that the content is displayed correctly in the browser. 

      EXAMPLE_START_HERE
      <div class="language-markdown highlighter-rouge”><pre class=“highlight”><code>
      Markdown content here
      </code></pre></div>
      EXAMPLE_END_HERE

      Use backticks to enclose code blocks that are not in Markdown. Make sure to insert a blank line before the opening backticks and after the closing backticks.

      When using Markdown code blocks, always insert a blank line between the code block and the element preceding it.
      SYSPSUFFIX
    end

    if app.settings["tools"]
      # the blank line at the beginning is important!
      system_prompt_suffix << <<~SYSPSUFFIX

        You should NEVER invent or use functions not defined or not listed HERE. If you need to call multiple functions, you will call them one at a time.
      SYSPSUFFIX
    end

    if app.settings["image_generation"]
      # the blank line at the beginning is important!
      response_suffix << <<~RSUFFIX

        <script>
          document.querySelectorAll('.generated_image img').forEach((img) => {
            img.addEventListener('click', (e) => {
              window.open(e.target.src, '_blank');
            });
          });
          document.querySelectorAll('.generated_image img').forEach((img) => {
            img.style.cursor = 'pointer';
          });
        </script>
      RSUFFIX
    end

    if app.settings["pdf_vector_storage"]
      # Ensure common local PDF tools are available for apps that opted in
      begin
        app.settings["tools"] ||= []
        existing = app.settings["tools"].map { |t| (t.respond_to?(:[]) ? (t["function"] && t["function"]["name"]) : nil) }.compact

        defn = lambda do |name, desc, params|
          {
            "type" => "function",
            "function" => {
              "name" => name,
              "description" => desc,
              "parameters" => {
                "type" => "object",
                "properties" => params.transform_values { |spec| { "type" => spec } },
                "required" => params.keys
              }
            }
          }
        end

        common_tools = []
        common_tools << defn.call("find_closest_text", "Find the closest text snippets in local PDF database", { "text" => "string", "top_n" => "integer" })
        common_tools << defn.call("get_text_snippet", "Retrieve one text snippet from a document by position", { "doc_id" => "integer", "position" => "integer" })
        common_tools << defn.call("list_titles", "List all document titles in local PDF database", {})
        common_tools << defn.call("find_closest_doc", "Find the closest documents in local PDF database", { "text" => "string", "top_n" => "integer" })
        common_tools << defn.call("get_text_snippets", "Retrieve all snippets of a document", { "doc_id" => "integer" })

        common_tools.each do |tool|
          name = tool.dig("function", "name")
          next if existing.include?(name)
          app.settings["tools"] << tool
        end
      rescue StandardError
        # non-fatal
      end
      # Add document search policy hint (no hybrid mode)
      begin
        configured_mode = get_pdf_storage_mode
        storage_desc = (configured_mode == 'cloud') ? 'Cloud File Search (OpenAI Vector Store)' : 'Local PDF Database (functions)'
        system_prompt_suffix << <<~SYSPSUFFIX

          DOCUMENT SEARCH POLICY:
          - Your document source is: #{storage_desc}.
          - Use it when the user asks to reference their PDFs or knowledge base.
          - If no relevant results are found, explain the limitation briefly.

          When citing results, include a compact metadata footer after an `---` divider with:
          Doc Title, Snippet tokens, and Snippet position.
        SYSPSUFFIX
      rescue StandardError
        # Non-fatal if mode cannot be determined here
      end
    end

    if app.settings["mermaid"]
      # the blank line at the beginning is important!
      prompt_suffix << <<~PSUFFIX

        Make sure to follow the format requirement specified in the initial prompt when using Mermaid diagrams. Do not make an inference about the diagram syntax from the previous messages.

        Note that you should not include parentheses in the Mermaid code. For instance, the following code does not render correctly: `A --> B[Prepare Filling (e.g., Ganache or Buttercream)]`
      PSUFFIX
    end

    # the blank line at the beginning is important!
    prompt_suffix = <<~PSUFFIX

      Return your response in the same language as the prompt. If you need to switch to another language, please inform the user.
    PSUFFIX

    if !system_prompt_suffix.empty? || !prompt_suffix.empty? || !response_suffix.empty?
      system_prompt_suffix = "\n\n" + system_prompt_suffix.strip unless system_prompt_suffix.empty?
      prompt_suffix = "\n\n" + prompt_suffix.strip unless prompt_suffix.empty?
      response_suffix = "\n\n" + response_suffix.strip unless response_suffix.empty?

      new_settings = app.settings.dup
      new_settings.merge!(
        {
          "initial_prompt" => "#{new_settings["initial_prompt"]}#{system_prompt_suffix}".strip,
          "prompt_suffix" => "#{new_settings["prompt_suffix"]}#{prompt_suffix}".strip,
          "response_suffix" => "#{new_settings["response_suffix"]}#{response_suffix}".strip
        }
      )
      app.settings = new_settings
    end

    apps[app_name] = app
  end

  # Load TTS dictionary from provided data, not from a path
  load_tts_dict

  # Filter out Jupyter apps if we're in server mode unless explicitly allowed
  distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] || "off"
  allow_jupyter_in_server = CONFIG["ALLOW_JUPYTER_IN_SERVER_MODE"] == true || CONFIG["ALLOW_JUPYTER_IN_SERVER_MODE"] == "true"
  
  if distributed_mode == "server" && !allow_jupyter_in_server
    # Create a new hash without the Jupyter apps
    filtered_apps = {}
    apps.each do |app_name, app|
      settings = app.settings
      if settings["jupyter"] == true || 
         settings["jupyter"] == "true" || 
         settings["jupyter_access"] == true || 
         settings["jupyter_access"] == "true" ||
         app_name.to_s.downcase.include?("jupyter") ||
         settings["display_name"].to_s.downcase.include?("jupyter")
        puts "Filtering out Jupyter app in server mode: #{app_name}" if CONFIG["EXTRA_LOGGING"]
      else
        filtered_apps[app_name] = app
      end
    end
    apps = filtered_apps
    puts "SERVER MODE: Filtered out Jupyter apps for security reasons (set ALLOW_JUPYTER_IN_SERVER_MODE=true in config to enable)"
  elsif distributed_mode == "server" && allow_jupyter_in_server
    puts "SERVER MODE: Jupyter apps enabled via ALLOW_JUPYTER_IN_SERVER_MODE configuration"
  end

  # Group apps by provider and sort alphabetically within each group
  grouped_apps = apps.group_by { |_, app| app.settings["group"] }
  # Sort each group alphabetically by app name
  grouped_apps.each do |group, apps_in_group|
    grouped_apps[group] = apps_in_group.sort_by { |k, _| k }.to_h
  end
  # Flatten the structure back into a single hash
  grouped_apps.values.reduce({}) { |result, group_apps| result.merge(group_apps) }
end

# Load app files and initialize apps
load_app_files
APPS = init_apps

# Start MCP server if enabled (skip in test environment)
if (CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true") && !defined?(RSpec)
  puts "MCP Server configuration detected, attempting to start..."
  
  # Ensure EventMachine is available before starting MCP server
  begin
    require 'eventmachine'
    require 'thin'
  rescue LoadError => e
    puts "Failed to load required dependencies for MCP server: #{e.message}"
    puts "Make sure EventMachine and Thin are installed"
  else
    begin
      require_relative "monadic/mcp/server"
      
      # Start MCP server in a separate thread after a short delay
      Thread.new do
        sleep 2  # Give main app time to initialize
        begin
          Monadic::MCP::Server.start!
          puts "MCP Server start command issued"
        rescue => e
          puts "Failed to start MCP server: #{e.message}"
          puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
        end
      end
    rescue LoadError => e
      puts "Failed to load MCP server: #{e.message}"
      puts "Current directory: #{Dir.pwd}"
      puts "Looking for: #{File.expand_path("monadic/mcp/server", __dir__)}"
    rescue => e
      puts "Unexpected error with MCP server: #{e.message}"
      puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
    end
  end
else
  puts "MCP Server disabled (MCP_SERVER_ENABLED = #{CONFIG["MCP_SERVER_ENABLED"].inspect})"
end

# Configure the Sinatra application
configure do
  use Rack::Session::Pool
  set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
  set :public_folder, "public"
  set :views, "views"
  set :api_key, CONFIG["OPENAI_API_KEY"]
  set :elevenlabs_api_key, CONFIG["ELEVENLABS_API_KEY"]
  enable :cross_origin
  
  # Add MIME type for WebAssembly files
  mime_type :wasm, 'application/wasm'
end

# API endpoint to check environment settings
get "/api/environment" do
  content_type :json
  {
    has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty?
  }.to_json
end

# API endpoint for dynamically loading model specifications
# Merges default model_spec.js with user's custom models.json
get "/api/models" do
  content_type :json
  
  begin
    default_spec_path = File.join(settings.public_folder, "js/monadic/model_spec.js")
    merged_spec = ModelSpecLoader.load_merged_spec(default_spec_path)
    JSON.generate(merged_spec)
  rescue => e
    STDERR.puts "[Model Spec Error] #{e.message}"
    STDERR.puts e.backtrace if CONFIG["EXTRA_LOGGING"]
    status 500
    JSON.generate({ error: "Failed to load model specifications" })
  end
end

# Accept requests from the client
get "/" do
  @timestamp = Time.now.to_i
  session[:parameters] ||= {}
  session[:messages] ||= []
  session[:version] = Monadic::VERSION
  session[:docker] = Monadic::Utils::Environment.in_container?
  
  # Get UI language from environment variable (set by Electron app)
  @ui_language = ENV['UI_LANGUAGE'] || 'en'

  if Faye::WebSocket.websocket?(env)
    websocket_handler(env)
  else
    erb :index
  end
end

def fetch_file(file_name)
  # Prevent path traversal attacks by sanitizing the filename
  safe_name = File.basename(file_name)
  
  datadir = Monadic::Utils::Environment.data_path
  file_path = File.join(datadir, safe_name)
  
  begin
    # Resolve real paths to handle symlinks
    real_path = File.realpath(file_path) if File.exist?(file_path)
    real_datadir = File.realpath(datadir)
    
    # Ensure proper directory separator
    real_datadir_with_sep = real_datadir.end_with?(File::SEPARATOR) ? 
                           real_datadir : 
                           real_datadir + File::SEPARATOR
    
    if real_path && real_path.start_with?(real_datadir_with_sep) && File.exist?(file_path)
      send_file file_path
    else
      status 404
      "Sorry, the file you are looking for is unavailable."
    end
  rescue StandardError => e
    puts "File fetch error: #{e.message}" if ENV["DEBUG"]
    status 404
    "Sorry, the file you are looking for is unavailable."
  end
end

# Convert a string to a integer
def string_to_int(str)
  hash = Digest::SHA256.hexdigest(str)
  int_value = hash[0..7].to_i(16) % 2_147_483_648 # 0 to 2,147,483,647
  int_value -= 2_147_483_648 if int_value > 1_073_741_823
  int_value
end

get "/monadic/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/:filename" do |filename|
  redirect to("/data/#{filename}")
end

# Accept requests from the client to provide language codes and country names
get "/lctags" do
  languages = I18nData.languages
  countries = I18nData.countries
  content_type :json
  return { "languages" => languages, "countries" => countries }.to_json
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

# Upload a Session JSON file to load past messages
post "/load" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json
    
    if params[:file]
      begin
        file = params[:file][:tempfile]
        content = file.read
        json_data = JSON.parse(content)
        
        # Validate required fields
        unless json_data["parameters"] && json_data["messages"]
          return { success: false, error: "Invalid format: missing parameters or messages" }.to_json
        end
        
        # Set session data
        session[:status] = "loaded"
        session[:parameters] = json_data["parameters"]

        # Check if the first message is a system message
        if json_data["messages"].first && json_data["messages"].first["role"] == "system"
          session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
        end

        # Process messages
        app_name = json_data["parameters"]["app_name"]
        session[:messages] = json_data["messages"].uniq.map do |msg|
          # Skip invalid messages
          next unless msg["role"] && msg["text"]
          
          text = msg["text"]
          
          # Handle HTML conversion based on role and settings
          # Check if mathjax is enabled for this app
          mathjax_enabled = json_data["parameters"]["mathjax"].to_s == "true"
          
          if json_data["parameters"]["monadic"].to_s == "true" && msg["role"] == "assistant" && APPS[app_name]
            begin
              html = APPS[app_name].monadic_html(text)
            rescue => e
              # Log monadic HTML error and fallback to standard markdown
              logger.warn "Monadic HTML rendering error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
              html = markdown_to_html(text, mathjax: mathjax_enabled)
            end
          elsif msg["role"] == "assistant"
            html = markdown_to_html(text, mathjax: mathjax_enabled)
          else
            html = text
          end
          
          # Create message object with required fields
          mid = msg["mid"] || SecureRandom.hex(4)
          message_obj = { 
            "role" => msg["role"], 
            "text" => text, 
            "html" => html, 
            "lang" => detect_language(text), 
            "mid" => mid, 
            "active" => true 
          }
          
          # Add optional fields if present
          message_obj["thinking"] = msg["thinking"] if msg["thinking"]
          message_obj["images"] = msg["images"] if msg["images"]
          message_obj
        end.compact # Remove nil values from invalid messages
        
        { success: true }.to_json
      rescue JSON::ParserError => e
        { success: false, error: "Invalid JSON format" }.to_json
      rescue => e
        { success: false, error: "Import error: #{e.message}" }.to_json
      end
    else
      { success: false, error: "No file selected" }.to_json
    end
  else
    # For regular form submissions, maintain original behavior
    if params[:file]
      begin
        file = params[:file][:tempfile]
        content = file.read
        json_data = JSON.parse(content)
        session[:status] = "loaded"
        session[:parameters] = json_data["parameters"]

        # Check if the first message is a system message
        if json_data["messages"].first && json_data["messages"].first["role"] == "system"
          session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
        end

        session[:messages] = json_data["messages"].uniq.map do |msg|
          if json_data["parameters"]["monadic"].to_s == "true" && msg["role"] == "assistant"
            text = msg["text"]
            html = APPS[json_data["parameters"]["app_name"]].monadic_html(msg["text"])
          else
            text = msg["text"]
            html = text
          end
          message_obj = { "role" => msg["role"], "text" => text, "html" => html, "lang" => detect_language(text), "mid" => msg["mid"], "active" => true }
          message_obj["thinking"] = msg["thinking"] if msg["thinking"]
          message_obj["images"] = msg["images"] if msg["images"]
          message_obj
        end
      rescue JSON::ParserError
        handle_error("Error: Invalid JSON file. Please upload a valid JSON file.")
      end
    else
      handle_error("Error: No file selected. Please choose a JSON file to upload.")
    end
    redirect "/"
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
        
        # Check if we got any meaningful content
        if markdown.to_s.strip.empty?
          return { success: false, error: "No content could be extracted from the document" }.to_json
        end

        doc_text = "Filename: " + utf8_filename + "\n---\n" + markdown
        result = if doc_label.to_s != ""
                  "\n---\n" + doc_label + "\n---\n" + doc_text
                else
                  "\n---\n" + doc_text
                end
        
        { success: true, content: result }.to_json
      rescue => e
        { success: false, error: "Error processing document: #{e.message}" }.to_json
      end
    else
      { success: false, error: "No file selected. Please choose a document file to convert." }.to_json
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

        user_data_dir = Monadic::Utils::Environment.data_path

        tavily_api_key = CONFIG["TAVILY_API_KEY"]
        puts "[DEBUG fetch_webpage] Tavily API key present: #{!tavily_api_key.nil?}"
        
        if tavily_api_key
          puts "[DEBUG fetch_webpage] Using Tavily to fetch: #{url}"
          puts "[DEBUG fetch_webpage] Methods available: #{self.methods.grep(/tavily/).inspect}"
          puts "[DEBUG fetch_webpage] TavilyHelper included? #{self.class.included_modules.include?(TavilyHelper)}"
          begin
            markdown = tavily_fetch(url: url)
            puts "[DEBUG fetch_webpage] Tavily returned: #{markdown.inspect}"
          rescue => e
            puts "[DEBUG fetch_webpage] Error calling tavily_fetch: #{e.class} - #{e.message}"
            puts e.backtrace.first(5).join("\n")
            markdown = "Error: #{e.message}"
          end
        else
          puts "[DEBUG fetch_webpage] Using Selenium to fetch: #{url}"
          markdown = MonadicApp.fetch_webpage(url)
        end
        
        # Check if we got any meaningful content
        if markdown.to_s.strip.empty?
          return { success: false, error: "No content could be extracted from the webpage" }.to_json
        end

        webpage_text = "URL: " + url_decoded + "\n---\n" + markdown
        result = if label.to_s != ""
                  "---\n" + label + "\n---\n" + webpage_text
                else
                  "---\n" + webpage_text
                end
        
        { success: true, content: result }.to_json
      rescue => e
        { success: false, error: "Error fetching webpage: #{e.message}" }.to_json
      end
    else
      { success: false, error: "No URL provided" }.to_json
    end
  else
    # For regular form submissions, maintain original behavior
    if params["pageURL"]
      url = params["pageURL"]
      url_decoded = CGI.unescape(url)
      label = params["urlLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

      user_data_dir = Monadic::Utils::Environment.data_path

      tavily_api_key = CONFIG["TAVILY_API_KEY"]
      if tavily_api_key
        markdown = tavily_fetch(url: url)
      else
        markdown = MonadicApp.fetch_webpage(url)
      end

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

# Upload a PDF file
post "/pdf" do
  # For AJAX requests, respond with JSON
  if request.xhr?
    content_type :json
    
    if params["pdfFile"]
      begin
        # Check if EMBEDDINGS_DB is available
        unless EMBEDDINGS_DB
          return { success: false, error: "Database connection not available" }.to_json
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
          return { success: false, error: "No text could be extracted from the PDF file" }.to_json
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
          return { success: false, error: "API key not configured" }.to_json
        end
        
        EMBEDDINGS_DB.store_embeddings(doc_data, items_data, api_key: api_key)
        # Mark session storage mode as local for downstream routing
        begin
          session[:pdf_storage_mode] = 'local'
        rescue StandardError
          # no-op
        end
        # Invalidate caches for mode/presence
        begin
          session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
        rescue StandardError
          # no-op
        end
        return { success: true, filename: params["pdfFile"]["filename"] }.to_json
      rescue TextEmbeddings::DatabaseError => e
        return { success: false, error: "Database error: #{e.message}" }.to_json
      rescue PG::Error => e
        return { success: false, error: "PostgreSQL error: #{e.message}" }.to_json
      rescue => e
        return { success: false, error: "Error processing PDF: #{e.class.name} - #{e.message}" }.to_json
      end
    else
      return { success: false, error: "No file selected. Please choose a PDF file to upload." }.to_json
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
      begin
        session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
      rescue StandardError
      end
      return params["pdfFile"]["filename"]
    else
      session[:error] = "Error: No file selected. Please choose a PDF file to upload."
    end
  end
end

# Create endpoints for each app in the APPS hash
APPS.each do |k, v|
  # convert `k` from a capitalized multi word title to snake_case
  # e.g., `Monadic App` to `monadic_app`
  endpoint = k.to_s.gsub(/\s+/, "_").downcase

  get "/#{endpoint}" do
    session[:messages] = []
    parameters = v.settings.dup
    
    
    session[:parameters] = parameters
    redirect "/"
  end
end

# Capture the INT signal (e.g., when pressing Ctrl+C)
Signal.trap("INT") do
  puts "\nTerminating the application . . ."
  EMBEDDINGS_DB.close_connection
  exit
end
