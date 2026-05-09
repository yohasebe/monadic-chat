# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/extractor/client'

RSpec.describe Monadic::Extractor::Client do
  let(:client) { described_class.new(endpoint: 'http://test.invalid:8000') }

  describe '#health' do
    it 'returns false when the host is unreachable' do
      # No HTTP stub: the request to http://test.invalid:8000 will fail
      # (Errno::ECONNREFUSED / SocketError). The client must swallow it.
      expect(client.health).to be false
    end
  end

  describe '#info' do
    it 'returns nil when the host is unreachable' do
      expect(client.info).to be_nil
    end
  end

  describe '#extract' do
    it 'raises ServiceUnavailableError when the host is unreachable' do
      expect { client.extract(path: '/monadic/data/foo.pdf') }
        .to raise_error(described_class::ServiceUnavailableError)
    end
  end

  describe 'endpoint resolution' do
    it 'inherits the dev/in-container split from Endpoint' do
      url = Monadic::Extractor::Endpoint.base_url
      # In the unit-test environment we are NOT inside a container,
      # so resolution should fall through to localhost.
      expect(url).to start_with('http://')
      expect(url).to include('localhost').or include('extractor_service')
    end
  end
end
