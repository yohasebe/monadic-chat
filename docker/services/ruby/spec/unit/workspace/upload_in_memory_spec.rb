# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'rack/mock_request'
require 'tempfile'
require_relative '../../../lib/monadic/workspace/upload_in_memory'

# A conversation to import is parsed by Rack in memory: no temporary file is
# made of it, and the reaper that removes temporary files still works.
RSpec.describe Monadic::Workspace::UploadInMemory do
  let(:read) { [] }
  let(:made) { [] }

  # Every temporary file made while a request is parsed.
  before do
    allow(Tempfile).to(receive(:new).and_wrap_original { |m, *args| m.call(*args).tap { |f| made << f } })
  end

  let(:app) do
    route = lambda do |env|
      file = Rack::Request.new(env).params['file']
      read << file[:tempfile].read
      [200, {}, ['ok']]
    end
    Rack::Builder.new.tap do |b|
      b.use Rack::TempfileReaper
      b.use described_class, paths: ['/load']
      b.run route
    end
  end

  def post(path)
    body = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chat.json\"\r\n" \
           "Content-Type: application/json\r\n\r\n{\"messages\":[]}\r\n--B--\r\n"
    Rack::MockRequest.new(app).post(path, input: body, 'CONTENT_TYPE' => 'multipart/form-data; boundary=B')
  end

  it 'reads the file of an import without a temporary file' do
    expect(post('/load').status).to eq(200)
    expect(read).to eq(['{"messages":[]}'])
    expect(made).to be_empty
  end

  it 'leaves other uploads to temporary files' do
    expect(post('/document').status).to eq(200)
    expect(made.size).to eq(1)
  end
end
