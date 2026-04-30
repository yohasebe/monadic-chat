# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'open3'
require 'shellwords'

# Helper for integration specs that need real Qdrant + embeddings containers.
# Provides probes so specs can confirm the services are running. In production
# mode (Electron's default compose) the qdrant + embeddings host ports are not
# exposed, so we offer ensure_dev_overlay! to bring up compose.dev.yml on
# demand for the duration of the test run.
module VectorServiceHelper
  module_function

  QDRANT_URL = ENV.fetch('QDRANT_URL', 'http://localhost:6333')
  EMBEDDINGS_URL = ENV.fetch('EMBEDDINGS_URL', 'http://localhost:8002')

  def qdrant_available?
    probe("#{QDRANT_URL}/healthz")
  end

  def embeddings_available?
    probe("#{EMBEDDINGS_URL}/v1/health")
  end

  def both_available?
    qdrant_available? && embeddings_available?
  end

  # Raises an RSpec skip exception when either container is unreachable from
  # the host. Production mode (Electron) does not expose qdrant/embeddings
  # ports, so these specs skip cleanly there. Run in dev mode
  # (compose.dev.yml overlay) to get host-side access.
  def skip_unless_both!
    return if both_available?
    missing = []
    missing << 'qdrant' unless qdrant_available?
    missing << 'embeddings' unless embeddings_available?
    msg = "Skipping: required containers not reachable from host (#{missing.join(', ')}). " \
          "Run in dev mode (rake server:debug) or expose ports via compose.dev.yml."
    raise RSpec::Core::Pending::SkipDeclaredInExample.new(msg)
  end

  # Bring up qdrant_service + embeddings_service with the dev compose overlay
  # so their host ports are reachable from the spec process. This is the
  # path used by `rake test:all[full]` where production mode containers are
  # already running but no host ports are exposed.
  #
  # The recreate is non-destructive: only port mappings change. After the
  # test run the containers continue with the dev overlay until the next
  # full app start cycles them.
  #
  # Raises RuntimeError if the overlay can't be brought up (e.g., docker
  # daemon down, compose files missing). Does NOT skip — callers can decide
  # whether to skip on their own.
  COMPOSE_PROJECT_NAME = 'monadic-chat'

  def ensure_dev_overlay!(timeout: 30)
    return if both_available?

    services_dir = find_services_dir
    raise "Could not locate docker/services/ directory containing compose.yml" unless services_dir

    main_compose = File.join(services_dir, 'compose.yml')
    qdrant_dev = File.join(services_dir, 'qdrant', 'compose.dev.yml')
    embed_dev = File.join(services_dir, 'embeddings', 'compose.dev.yml')

    [main_compose, qdrant_dev, embed_dev].each do |f|
      raise "Missing compose file: #{f}" unless File.exist?(f)
    end

    # Project name and working dir must match the original `docker compose
    # up` call (made by monadic.sh / Electron) or docker treats this as a
    # different project and refuses to recreate the existing container.
    cmd = [
      'docker', 'compose',
      '-p', COMPOSE_PROJECT_NAME,
      '-f', main_compose,
      '-f', qdrant_dev,
      '-f', embed_dev,
      'up', '-d',
      'qdrant_service', 'embeddings_service'
    ]

    out, status = Open3.capture2e(*cmd, chdir: services_dir)
    unless status.success?
      raise "Failed to bring up dev overlay: #{out.lines.last(20).join}"
    end

    deadline = Time.now + timeout
    until both_available?
      if Time.now >= deadline
        missing = []
        missing << 'qdrant' unless qdrant_available?
        missing << 'embeddings' unless embeddings_available?
        raise "Dev overlay started but services still unreachable after #{timeout}s: #{missing.join(', ')}"
      end
      sleep 0.5
    end
  end

  def probe(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
      http.get(uri.path).is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end

  # Walk up from this file to find the `docker/services/` directory. Layout:
  #   docker/services/ruby/spec/support/vector_service_helper.rb (this file)
  # so docker/services/ is 3 levels up from File.dirname(__FILE__).
  def find_services_dir
    base = File.dirname(__FILE__)
    candidate = File.expand_path('../../..', base)
    return candidate if File.basename(candidate) == 'services' &&
                        File.exist?(File.join(candidate, 'compose.yml'))
    nil
  end
end
