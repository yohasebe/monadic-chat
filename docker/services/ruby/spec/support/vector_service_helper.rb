# frozen_string_literal: true

require 'net/http'
require 'uri'

# Helper for integration specs that need real Qdrant + embeddings containers.
# Provides probes so specs can skip cleanly when the services are not running
# (e.g. in CI environments without Docker).
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

  def probe(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
      http.get(uri.path).is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end
end
