# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'rack'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/workspace/chat_request_scope'
require_relative '../../../lib/monadic/utils/privacy/egress_guard'
require_relative '../../../lib/monadic/utils/privacy/words'

# The chat a page's request is for, fixed from its tab before its body is
# read: an unknown tab's upload is refused, and a request of a chat that
# hides words runs as that chat's work.
RSpec.describe Monadic::Workspace::ChatRequestScope do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:guard) { Monadic::Utils::Privacy::EgressGuard }
  let(:tabs) { {} }
  let(:states) { {} }
  let(:reached) { [] }

  def chat
    { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [], parameters: {} }
  end

  def hiding_chat(word)
    session = chat
    words.start!(session).confirm!(word, 'PERSON')
    session
  end

  after { words::LOCK.synchronize { words::TABLES.clear } }

  # A body that fails the test when anything reads it.
  class UnreadBody
    def read(*) = raise('the body was read')
    def gets(*) = raise('the body was read')
    def each = raise('the body was read')
    def rewind = nil
  end

  def scope_for(app)
    described_class.new(app, paths: ['/attachments', '/document'],
                             session_lookup: ->(id) { tabs[id] }, state_lookup: ->(id) { states[id] })
  end

  let(:reading) do
    scope_for(lambda do |env|
      reached << env['PATH_INFO']
      env['rack.input'].read
      [200, {}, ['ok']]
    end)
  end

  def post(path, tab_id:, input: UnreadBody.new, to: reading, method: 'POST')
    query = tab_id ? "tab_id=#{tab_id}" : ''
    to.call('REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query, 'rack.input' => input)
  end

  it "lets through a request that names no tab (a program's, not a chat's)" do
    expect(post('/document', tab_id: nil, input: StringIO.new('file')).first).to eq(200)
    expect(reached).to eq(['/document'])
  end

  it 'refuses an upload naming a tab it does not know, before its body is read' do
    status, _headers, body = post('/document', tab_id: 'tab-gone')
    expect(status).to eq(409)
    expect(JSON.parse(body.first)).to include('reason' => 'tab_unknown')
    expect(reached).to be_empty
  end

  it 'lets through a request of an unknown tab to a path that makes no files' do
    expect(post('/other', tab_id: 'tab-gone', input: StringIO.new('x')).first).to eq(200)
    expect(reached).to eq(['/other'])
  end

  it "takes a known tab's upload, and other requests" do
    tabs['tab-n'] = chat
    expect(post('/attachments', tab_id: 'tab-n', input: StringIO.new('file')).first).to eq(200)
    expect(post('/other', tab_id: nil, input: StringIO.new('x')).first).to eq(200)
    expect(reached).to eq(['/attachments', '/other'])
  end

  it 'takes the upload of a tab that is away, known by its saved state' do
    states['tab-away'] = { chat_id: chat[:chat_id], chat_state: {} }
    expect(post('/document', tab_id: 'tab-away', input: StringIO.new('file')).first).to eq(200)
    expect(reached).to eq(['/document'])
  end

  # The request is checked, as the chat's connection is, against the chat's
  # words: the tab's live chat, or its saved state while the tab is away.
  it "checks what a request sends out against the words of the tab's chat" do
    seen = []
    worker = scope_for(lambda do |_env|
      seen << guard.words
      [200, {}, ['ok']]
    end)
    session = hiding_chat('MARKEDWORD')
    tabs['tab-live'] = session
    states['tab-away'] = { chat_id: session[:chat_id], chat_state: { words::MARK_KEY => session[words::MARK_KEY] } }
    tabs['tab-plain'] = chat
    %w[tab-live tab-away tab-plain].each do |tab|
      post('/load', tab_id: tab, input: StringIO.new('x'), to: worker)
    end
    expect(seen).to eq([['MARKEDWORD'], ['MARKEDWORD'], []])
    expect(Fiber[guard::CHAT_KEY]).to be_nil
  end

  it "refuses a word of the chat sent from the route" do
    worker = scope_for(lambda do |_env|
      guard.check!('api.example.com', 'about MARKEDWORD')
      [200, {}, ['ok']]
    end)
    tabs['tab-live'] = hiding_chat('MARKEDWORD')
    expect { post('/load', tab_id: 'tab-live', input: StringIO.new('x'), to: worker) }
      .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    expect(Fiber[guard::CHAT_KEY]).to be_nil
  end

  # The body is listed, streamed and closed after the route returned (the
  # access log is written on close): that is the chat's work as well.
  it "keeps the chat's scope while the body is listed, streamed and closed, and gives the earlier scope back" do
    seen = []
    egress = guard
    inner = Class.new do
      define_method(:each) do |&block|
        seen << [:each, egress.words]
        block.call('ok')
      end
      define_method(:call) { |_stream| seen << [:call, egress.words] }
    end.new
    body = Rack::BodyProxy.new(inner) { seen << [:close, egress.words] }
    worker = scope_for(->(_env) { [200, {}, body] })
    tabs['tab-live'] = hiding_chat('MARKEDWORD')
    earlier = guard::Scope.of(chat)
    Fiber[guard::CHAT_KEY] = earlier
    _status, _headers, returned = post('/x', tab_id: 'tab-live', input: StringIO.new(''), to: worker, method: 'GET')
    expect(Fiber[guard::CHAT_KEY]).to equal(earlier)
    returned.each { |_part| nil }
    returned.call(nil)
    returned.close
    expect(seen).to eq([[:each, ['MARKEDWORD']], [:call, ['MARKEDWORD']], [:close, ['MARKEDWORD']]])
    expect(Fiber[guard::CHAT_KEY]).to equal(earlier)
  ensure
    Fiber[guard::CHAT_KEY] = nil
  end

  it 'is in front of everything that reads a body' do
    config = File.read(File.expand_path('../../../config.ru', __dir__))
    scope_at = config.index('use Monadic::Workspace::ChatRequestScope')
    expect(scope_at).not_to be_nil
    ['use Rack::TempfileReaper', 'use Monadic::Workspace::UploadContext', 'use Monadic::Workspace::UploadLimit',
     'use Rack::Session::CappedPool'].each do |later|
      expect(config.index(later)).to be > scope_at
    end
    %w[AttachmentRoutes::PATH /pdf /document /upload_audio /fetch_webpage].each do |path|
      expect(config[scope_at, 400]).to include(path)
    end
  end
end
