# frozen_string_literal: true

require 'spec_helper'
require 'monadic/embeddings'

RSpec.describe Monadic::Embeddings::Client do
  let(:endpoint) { 'http://embeddings_service:8000' }
  let(:client) { described_class.new(endpoint: endpoint, timeout: 5, batch_size: 3) }
  let(:http_client) { instance_double(HTTP::Client) }

  before do
    allow(HTTP).to receive(:timeout).and_return(http_client)
    # The retry path uses sleep; stub it so the suite stays fast.
    allow(client).to receive(:sleep)
  end

  def fake_response(status: 200, body: '{}')
    status_obj = instance_double(
      HTTP::Response::Status,
      success?: status.between?(200, 299),
      code: status
    )
    instance_double(HTTP::Response, status: status_obj, body: body)
  end

  describe '#embed' do
    it 'POSTs to /v1/embed with the task and texts' do
      expect(http_client).to receive(:post).with(
        "#{endpoint}/v1/embed",
        json: { texts: %w[a b c], task: 'passage' }
      ).and_return(fake_response(body: '{"vectors":[[0.1],[0.2],[0.3]],"model":"e5","dimension":1}'))

      vectors = client.embed(texts: %w[a b c], task: :passage)
      expect(vectors).to eq([[0.1], [0.2], [0.3]])
    end

    it 'splits oversized inputs into batch_size-sized chunks' do
      # batch_size = 3, send 5 texts → expect two POST calls (3 + 2).
      first_resp = fake_response(body: '{"vectors":[[1],[2],[3]]}')
      second_resp = fake_response(body: '{"vectors":[[4],[5]]}')
      expect(http_client).to receive(:post).twice.and_return(first_resp, second_resp)

      vectors = client.embed(texts: %w[a b c d e], task: :passage)
      expect(vectors).to eq([[1], [2], [3], [4], [5]])
    end

    it 'sends the :query task verbatim' do
      expect(http_client).to receive(:post).with(
        anything,
        json: hash_including(task: 'query')
      ).and_return(fake_response(body: '{"vectors":[[0.5]]}'))

      client.embed(texts: ['what is monad?'], task: :query)
    end

    it 'rejects an empty list locally without an HTTP call' do
      expect(http_client).not_to receive(:post)
      expect {
        client.embed(texts: [], task: :passage)
      }.to raise_error(Monadic::Embeddings::ClientError, /cannot be empty/)
    end

    it 'rejects unknown task symbols' do
      expect {
        client.embed(texts: ['a'], task: :unknown)
      }.to raise_error(Monadic::Embeddings::ClientError, /unknown task/)
    end

    it 'fails loudly when the server returns the wrong number of vectors' do
      allow(http_client).to receive(:post).and_return(
        fake_response(body: '{"vectors":[[1]]}')   # only 1 returned for 2 inputs
      )
      expect {
        client.embed(texts: %w[a b], task: :passage)
      }.to raise_error(Monadic::Embeddings::ClientError, /returned 1 vectors for batch of 2/)
    end

    it 'raises ClientError on persistent server errors' do
      allow(http_client).to receive(:post).and_return(
        fake_response(status: 500, body: 'boom')
      )
      expect {
        client.embed(texts: ['a'], task: :passage)
      }.to raise_error(Monadic::Embeddings::ClientError, /500/)
    end

    it 'retries on transient 503 then succeeds' do
      attempts = 0
      allow(http_client).to receive(:post) do
        attempts += 1
        if attempts < 2
          fake_response(status: 503, body: 'overloaded')
        else
          fake_response(body: '{"vectors":[[0.42]]}')
        end
      end

      vectors = client.embed(texts: ['a'], task: :passage)
      expect(vectors).to eq([[0.42]])
      expect(attempts).to eq(2)
    end

    it 'does not retry on a 4xx client error' do
      attempts = 0
      allow(http_client).to receive(:post) do
        attempts += 1
        fake_response(status: 400, body: 'bad input')
      end

      expect {
        client.embed(texts: ['a'], task: :passage)
      }.to raise_error(Monadic::Embeddings::ClientError, /400/)
      expect(attempts).to eq(1)
    end
  end

  describe '#embed_query / #embed_passages' do
    it 'embed_query returns a single vector and uses the query task' do
      expect(http_client).to receive(:post).with(
        anything,
        json: hash_including(task: 'query', texts: ['hello'])
      ).and_return(fake_response(body: '{"vectors":[[0.1,0.2]]}'))

      expect(client.embed_query('hello')).to eq([0.1, 0.2])
    end

    it 'embed_passages forwards all texts under the passage task' do
      expect(http_client).to receive(:post).with(
        anything,
        json: hash_including(task: 'passage', texts: %w[a b])
      ).and_return(fake_response(body: '{"vectors":[[0.1],[0.2]]}'))

      expect(client.embed_passages(%w[a b])).to eq([[0.1], [0.2]])
    end
  end

  describe '#health' do
    it 'returns true on 200' do
      allow(HTTP).to receive(:timeout).with(2).and_return(http_client)
      allow(http_client).to receive(:get).with("#{endpoint}/v1/health")
        .and_return(fake_response(status: 200))
      expect(client.health).to be true
    end

    it 'returns false on transport error (does not raise)' do
      allow(HTTP).to receive(:timeout).with(2).and_return(http_client)
      allow(http_client).to receive(:get).and_raise(HTTP::Error.new('refused'))
      expect(client.health).to be false
    end
  end

  describe '#info' do
    it 'parses and returns the server info JSON' do
      info_json = '{"model":"intfloat/multilingual-e5-base","dimension":768,"max_seq_length":512}'
      allow(http_client).to receive(:get).and_return(fake_response(body: info_json))

      info = client.info
      expect(info['model']).to eq('intfloat/multilingual-e5-base')
      expect(info['dimension']).to eq(768)
    end
  end
end
