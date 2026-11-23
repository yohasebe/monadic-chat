# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'tempfile'
require_relative '../../../lib/monadic/routes/attachment_routes'

# A file for the work screen is no larger than the work screen reads: a larger
# one is turned away before it is saved in the chat's folder.
RSpec.describe 'POST /attachments for the work screen' do
  include Rack::Test::Methods

  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:web_app) do
    chat = chat_id
    Class.new(Sinatra::Base) do
      set :environment, :test
      use(Class.new do
        define_method(:initialize) { |app| @app = app }
        define_method(:call) do |env|
          env[Monadic::Workspace::UploadContext::CHAT_KEY] = chat
          @app.call(env)
        end
      end)
      register Monadic::Routes::AttachmentRoutes
    end
  end
  let(:app) { web_app }
  let(:file) { Tempfile.new(['notes', '.md']).tap { |f| f.write("# Notes\n") && f.flush } }

  after { file.close! }

  def send_file(purpose)
    post '/attachments', 'purpose' => purpose, 'file' => Rack::Test::UploadedFile.new(file.path, 'text/markdown')
  end

  it 'turns away a file larger than the work screen reads, before saving it' do
    stub_const('Monadic::Workbench::FileItem::LIMIT', 4)
    expect(Monadic::Workspace::Attachments).not_to receive(:accept!)
    send_file('workbench')
    expect(last_response.status).to eq(413)
    expect(JSON.parse(last_response.body)).to include('reason' => 'too_large')
  end

  it 'takes a file the work screen reads, as an attachment of the chat' do
    expect(Monadic::Workspace::Attachments).to receive(:accept!)
      .with(hash_including(chat_id: chat_id, purpose: 'workbench'))
      .and_return({ attachment_id: 'a_1', original_name: 'notes.md', size: 8, purpose: 'workbench', status: 'ready' })
    send_file('workbench')
    expect(last_response.status).to eq(201)
  end

  it 'leaves the other purposes to their own limit' do
    stub_const('Monadic::Workbench::FileItem::LIMIT', 4)
    expect(Monadic::Workspace::Attachments).to receive(:accept!)
      .and_return({ attachment_id: 'a_1', original_name: 'notes.md', size: 8, purpose: 'document', status: 'ready' })
    send_file('document')
    expect(last_response.status).to eq(201)
  end
end
