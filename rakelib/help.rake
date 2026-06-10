# frozen_string_literal: true

# Help database namespace
namespace :help do
  # Help database build pipeline.
  #
  # The runtime app does NOT need this to run — it consumes the prebuilt
  # JSON dump baked into the Ruby image at docker/services/ruby/help_data/.
  # These tasks regenerate that dump from docs/*.md (and docs_dev/*.md when
  # internal docs are requested) using the embeddings_service container.

  HELP_BUILD_SCRIPT = File.expand_path(
    'docker/services/ruby/scripts/utilities/process_documentation.rb', __dir__
  )

  HELP_DATA_DUMP = File.expand_path(
    'docker/services/ruby/help_data/help_db.json', __dir__
  )

  # Ensure the embeddings_service container is up before invoking the script.
  # Returns true if it was newly started (so the caller knows to stop it),
  # or false if it was already running.
  def ensure_embeddings_service
    if system("docker ps --format '{{.Names}}' | grep -q '^monadic-chat-embeddings-container$'")
      return false
    end

    puts 'Starting embeddings container...'
    compose_file = File.expand_path('docker/services/compose.yml', __dir__)
    embeddings_dev = File.expand_path('docker/services/embeddings/compose.dev.yml', __dir__)
    project_dir = File.expand_path('docker/services', __dir__)
    overlays = ["-f '#{compose_file}'"]
    overlays << "-f '#{embeddings_dev}'" if File.exist?(embeddings_dev)
    system("docker compose --project-directory '#{project_dir}' #{overlays.join(' ')} -p 'monadic-chat' up -d embeddings_service")

    print 'Waiting for embeddings service '
    60.times do
      if system('curl -sf http://localhost:8002/v1/health >/dev/null 2>&1')
        puts ' ready.'
        return true
      end
      print '.'
      sleep 1
    end
    puts ' (timeout)'
    raise 'embeddings_service did not become ready in 60s'
  end

  desc 'Build help database JSON dump from docs/* (includes internal docs)'
  task :build do
    started = ensure_embeddings_service
    # The script depends on the `http` gem, which lives only in
    # docker/services/ruby/Gemfile (the project-root Gemfile is minimal).
    # with_unbundled_env clears the parent BUNDLE_GEMFILE so the inner
    # `bundle exec` resolves against docker/services/ruby/Gemfile.
    # The explicit require handles plain `rake build:mac_arm64` invocations
    # where Bundler is not autoloaded (only `bundle exec rake` autoloads it).
    require 'bundler'
    Bundler.with_unbundled_env do
      Dir.chdir(File.expand_path('docker/services/ruby', __dir__)) do
        sh "bundle exec ruby '#{HELP_BUILD_SCRIPT}' --include-internal"
      end
    end
    if started && ENV['KEEP_VECTOR_SERVICES'] != 'true'
      compose_file = File.expand_path('docker/services/compose.yml', __dir__)
      project_dir = File.expand_path('docker/services', __dir__)
      system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop embeddings_service")
    end
  end

  desc '[DEPRECATED] Use rake help:build instead'
  task :build_dev do
    warn '[help:build_dev] deprecated; redirecting to help:build.'
    Rake::Task['help:build'].invoke
  end

  desc 'Rebuild help database JSON dump from scratch'
  task :rebuild do
    File.delete(HELP_DATA_DUMP) if File.exist?(HELP_DATA_DUMP)
    Rake::Task['help:build'].invoke
  end

  desc 'Show help database dump statistics'
  task :stats do
    unless File.exist?(HELP_DATA_DUMP)
      puts 'No help DB dump found. Run rake help:build first.'
      exit 1
    end
    require 'json'
    data = JSON.parse(File.read(HELP_DATA_DUMP))
    puts "Help DB dump: #{HELP_DATA_DUMP}"
    puts "Version:           #{data['version']}"
    puts "Embedding model:   #{data['embedding_model']}"
    puts "Dimension:         #{data['embedding_dimension']}"
    puts "Exported at:       #{data['exported_at']}"
    (data['collections'] || {}).each do |name, contents|
      puts "Collection #{name}: #{(contents['points'] || []).size} points"
    end
  end

  desc 'Show the path of the help database dump'
  task :export do
    puts HELP_DATA_DUMP
    exit(File.exist?(HELP_DATA_DUMP) ? 0 : 1)
  end
end
