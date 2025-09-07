namespace :vector_db do
  desc "Migrate legacy metadata to app-scoped registry (safe, idempotent)"
  task :migrate_to_registry do
    require 'json'
    require_relative '../../monadic/utils/environment'
    require_relative '../../monadic/utils/document_store_registry'

    data_dir = Monadic::Utils::Environment.data_path
    legacy_meta = File.join(data_dir, 'pdf_navigator_openai.json')
    unless File.exist?(legacy_meta)
      puts '[vector_db] No legacy meta found; nothing to migrate.'
      next
    end
    begin
      meta = JSON.parse(File.read(legacy_meta))
    rescue => e
      puts "[vector_db] Failed to read legacy meta: #{e.message}"
      next
    end

    vs = meta['vector_store_id']
    files = (meta['files'] || []).dup
    app_key = 'default'

    if vs && !vs.to_s.empty?
      Monadic::Utils::DocumentStoreRegistry.set_cloud_vs(app_key, vs)
      puts "[vector_db] Migrated VS id to registry for app=#{app_key}: #{vs}"
    end

    files.each do |f|
      Monadic::Utils::DocumentStoreRegistry.add_cloud_file(
        app_key,
        file_id: f['file_id'],
        filename: f['filename'] || 'file.pdf',
        hash: f['hash']
      )
    end
    puts "[vector_db] Migrated #{files.size} file entries to registry."
    puts "[vector_db] Done."
  end
end

