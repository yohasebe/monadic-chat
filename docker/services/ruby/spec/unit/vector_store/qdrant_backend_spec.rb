# frozen_string_literal: true

require 'spec_helper'
require 'monadic/vector_store'

RSpec.describe Monadic::VectorStore::QdrantBackend do
  let(:endpoint) { 'http://qdrant_service:6333' }
  let(:backend) { described_class.new(endpoint: endpoint, timeout: 5) }
  let(:http_client) { instance_double(HTTP::Client) }

  before do
    allow(HTTP).to receive(:timeout).and_return(http_client)
  end

  # Build a fake HTTP::Response that satisfies the parts QdrantBackend reads:
  # status.success?, status.code, body.to_s
  def fake_response(status: 200, body: '{}')
    status_obj = instance_double(
      HTTP::Response::Status,
      success?: status.between?(200, 299),
      code: status
    )
    instance_double(HTTP::Response, status: status_obj, body: body)
  end

  describe '#create_collection' do
    it 'PUTs the vectors config to /collections/{name}' do
      expect(http_client).to receive(:put).with(
        "#{endpoint}/collections/foo",
        json: hash_including(vectors: { 'content' => { size: 768, distance: 'Cosine' } })
      ).and_return(fake_response(body: '{"result":true,"status":"ok"}'))

      result = backend.create_collection(
        name: 'foo',
        vectors: { 'content' => { size: 768, distance: 'Cosine' } }
      )
      expect(result).to be true
    end

    it 'creates payload indexes after the collection itself' do
      call_log = []
      allow(http_client).to receive(:put) do |url, _opts|
        call_log << url
        fake_response(body: '{"result":true}')
      end

      backend.create_collection(
        name: 'foo',
        vectors: { 'content' => { size: 768, distance: 'Cosine' } },
        payload_indexes: [
          { field: 'language', schema: 'keyword' },
          { field: 'doc_id',   schema: 'integer' }
        ]
      )

      expect(call_log).to eq([
        "#{endpoint}/collections/foo",
        "#{endpoint}/collections/foo/index",
        "#{endpoint}/collections/foo/index"
      ])
    end

    it 'raises BackendError on a 4xx/5xx response' do
      allow(http_client).to receive(:put).and_return(
        fake_response(status: 400, body: 'invalid vector size')
      )

      expect {
        backend.create_collection(
          name: 'foo',
          vectors: { 'content' => { size: 0, distance: 'Cosine' } }
        )
      }.to raise_error(Monadic::VectorStore::BackendError, /400/)
    end
  end

  describe '#delete_collection' do
    it 'sends DELETE and treats 404 as success (idempotent)' do
      response = fake_response(status: 404, body: '{}')
      expect(HTTP).to receive(:timeout).with(5).and_return(http_client)
      expect(http_client).to receive(:delete).with("#{endpoint}/collections/foo")
        .and_return(response)
      expect(backend.delete_collection(name: 'foo')).to be true
    end

    it 'raises on other error codes' do
      allow(http_client).to receive(:delete).and_return(
        fake_response(status: 500, body: 'server error')
      )
      expect {
        backend.delete_collection(name: 'foo')
      }.to raise_error(Monadic::VectorStore::BackendError, /500/)
    end
  end

  describe '#collection_exists?' do
    it 'returns true on 200' do
      allow(http_client).to receive(:get).and_return(fake_response(status: 200))
      expect(backend.collection_exists?(name: 'foo')).to be true
    end

    it 'returns false on 404' do
      allow(http_client).to receive(:get).and_return(fake_response(status: 404))
      expect(backend.collection_exists?(name: 'foo')).to be false
    end

    it 'returns false on transport error' do
      allow(http_client).to receive(:get).and_raise(HTTP::Error.new('network down'))
      expect(backend.collection_exists?(name: 'foo')).to be false
    end
  end

  describe '#upsert_points' do
    it 'wraps points and waits for write commit' do
      expect(http_client).to receive(:put).with(
        "#{endpoint}/collections/foo/points?wait=true",
        json: {
          points: [
            { id: 1, vector: [0.1, 0.2], payload: { 'k' => 'v' } },
            { id: 2, vector: [0.3, 0.4] }
          ]
        }
      ).and_return(fake_response(body: '{"result":{"status":"completed"}}'))

      result = backend.upsert_points(
        collection: 'foo',
        points: [
          { id: 1, vector: [0.1, 0.2], payload: { 'k' => 'v' } },
          { id: 2, vector: [0.3, 0.4] }
        ]
      )
      expect(result).to eq('status' => 'completed')
    end
  end

  describe '#search' do
    it 'sends an unnamed vector when vector_name is nil' do
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/search",
        json: hash_including(vector: [0.1, 0.2], limit: 5)
      ).and_return(fake_response(body: '{"result":[{"id":1,"score":0.9}]}'))

      hits = backend.search(collection: 'foo', vector: [0.1, 0.2], limit: 5)
      expect(hits).to eq([{ 'id' => 1, 'score' => 0.9 }])
    end

    it 'wraps the vector in {name, vector} when a vector_name is given' do
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/search",
        json: hash_including(vector: { name: 'content', vector: [0.1, 0.2] })
      ).and_return(fake_response(body: '{"result":[]}'))

      backend.search(
        collection: 'foo',
        vector: [0.1, 0.2],
        vector_name: 'content',
        limit: 1
      )
    end

    it 'forwards a filter when one is provided' do
      filter = { must: [{ key: 'language', match: { value: 'en' } }] }
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/search",
        json: hash_including(filter: filter)
      ).and_return(fake_response(body: '{"result":[]}'))

      backend.search(collection: 'foo', vector: [0.1], filter: filter)
    end
  end

  describe '#scroll' do
    it 'returns points and the next page offset' do
      payload = '{"result":{"points":[{"id":1}],"next_page_offset":42}}'
      allow(http_client).to receive(:post).and_return(fake_response(body: payload))

      out = backend.scroll(collection: 'foo', limit: 1)
      expect(out[:points]).to eq([{ 'id' => 1 }])
      expect(out[:next]).to eq(42)
    end

    it 'reports next: nil when the server returns no further pages' do
      payload = '{"result":{"points":[],"next_page_offset":null}}'
      allow(http_client).to receive(:post).and_return(fake_response(body: payload))
      expect(backend.scroll(collection: 'foo')[:next]).to be_nil
    end
  end

  describe '#count' do
    it 'returns the integer count from the response' do
      allow(http_client).to receive(:post).and_return(
        fake_response(body: '{"result":{"count":1234}}')
      )
      expect(backend.count(collection: 'foo')).to eq(1234)
    end

    it 'forwards the filter and exact flag' do
      filter = { must: [{ key: 'doc_id', match: { value: 5 } }] }
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/count",
        json: { exact: true, filter: filter }
      ).and_return(fake_response(body: '{"result":{"count":3}}'))

      backend.count(collection: 'foo', filter: filter, exact: true)
    end
  end

  describe '#delete_points' do
    it 'requires either ids or filter' do
      expect {
        backend.delete_points(collection: 'foo')
      }.to raise_error(ArgumentError, /ids: or filter:/)
    end

    it 'sends point ids when ids: is provided' do
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/delete?wait=true",
        json: { points: [1, 2, 3] }
      ).and_return(fake_response(body: '{"result":{"status":"completed"}}'))

      backend.delete_points(collection: 'foo', ids: [1, 2, 3])
    end

    it 'sends a filter when filter: is provided' do
      filter = { must: [{ key: 'doc_id', match: { value: 5 } }] }
      expect(http_client).to receive(:post).with(
        "#{endpoint}/collections/foo/points/delete?wait=true",
        json: { filter: filter }
      ).and_return(fake_response(body: '{"result":{"status":"completed"}}'))

      backend.delete_points(collection: 'foo', filter: filter)
    end
  end

  describe '#health' do
    it 'returns true on 200' do
      allow(HTTP).to receive(:timeout).with(2).and_return(http_client)
      allow(http_client).to receive(:get).with("#{endpoint}/healthz")
        .and_return(fake_response(status: 200))
      expect(backend.health).to be true
    end

    it 'returns false on transport failure (does not raise)' do
      allow(HTTP).to receive(:timeout).with(2).and_return(http_client)
      allow(http_client).to receive(:get).and_raise(HTTP::Error.new('refused'))
      expect(backend.health).to be false
    end
  end
end
