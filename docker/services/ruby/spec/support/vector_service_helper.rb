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

  def skip_unless_both!
    unless both_available?
      missing = []
      missing << 'qdrant' unless qdrant_available?
      missing << 'embeddings' unless embeddings_available?
      skip "Skipping: required containers not running (#{missing.join(', ')}). Start them with: docker compose -f docker/services/compose.yml up -d qdrant_service embeddings_service"
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
end
