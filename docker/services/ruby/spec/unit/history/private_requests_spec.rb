# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'securerandom'
require 'base64'
require 'rack'
require_relative '../../../lib/monadic/history'
require_relative '../../../lib/monadic/history/private_request_guard'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/privacy/egress_guard'
require_relative '../../../lib/monadic/shared_tools/file_operations'
require_relative '../../../lib/monadic/utils/websocket/audio_handler'

# A Private chat makes no files: the requests that would make them are
# refused before their body is read, the tool that writes files refuses,
# and voice input is taken only where the audio stays in memory.
RSpec.describe 'What would make files of a Private chat' do
  let(:policy) { Monadic::History::Policy }

  # Each example starts with no chat's scope in this fiber (another spec run
  # before may have left one), and the one there before is put back.
  around do |example|
    key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY
    before = Fiber[key]
    Fiber[key] = nil
    example.run
  ensure
    Fiber[key] = before
  end

  def chat(private: false)
    session = { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [], parameters: {} }
    policy.mark_private!(session) if private
    session
  end

  # A body that fails the test when anything reads it.
  class UnreadBody
    def read(*) = raise('the body was read')
    def gets(*) = raise('the body was read')
    def each = raise('the body was read')
    def rewind = nil
  end

  describe 'the requests' do
    let(:tabs) { {} }
    let(:states) { {} }
    let(:reached) { [] }
    let(:guard) do
      downstream = lambda do |env|
        reached << env['PATH_INFO']
        env['rack.input'].read
        [200, {}, ['ok']]
      end
      Monadic::History::PrivateRequestGuard.new(downstream, paths: ['/attachments', '/document'],
                                                            session_lookup: ->(id) { tabs[id] },
                                                            state_lookup: ->(id) { states[id] })
    end

    def post(path, tab_id:, input: UnreadBody.new)
      query = tab_id ? "tab_id=#{tab_id}" : ''
      guard.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => path, 'QUERY_STRING' => query, 'rack.input' => input)
    end

    it "refuses a Private chat's upload before its body is read" do
      tabs['tab-p'] = chat(private: true)
      status, _headers, body = post('/attachments', tab_id: 'tab-p')
      expect(status).to eq(403)
      expect(JSON.parse(body.first)).to include('reason' => 'private_chat')
      expect(reached).to be_empty
    end

    it "lets through a request that names no tab (a program's, not a chat's)" do
      expect(post('/document', tab_id: nil, input: StringIO.new('file')).first).to eq(200)
      expect(reached).to eq(['/document'])
    end

    it 'refuses a request naming a tab it does not know, before its body is read' do
      status, _headers, body = post('/document', tab_id: 'tab-gone')
      expect(status).to eq(409)
      expect(JSON.parse(body.first)).to include('reason' => 'tab_unknown')
      expect(reached).to be_empty
    end

    # The tab is away (no connection), and its saved state says Private.
    it 'refuses the upload of a Private chat whose tab is away' do
      states['tab-away'] = { chat_id: chat[:chat_id], chat_state: { policy::SESSION_KEY => policy::PRIVATE } }
      expect(post('/document', tab_id: 'tab-away').first).to eq(403)
      states['tab-normal-away'] = { chat_id: chat[:chat_id], chat_state: {} }
      expect(post('/document', tab_id: 'tab-normal-away', input: StringIO.new('file')).first).to eq(200)
      expect(reached).to eq(['/document'])
    end

    # An import from the tab of a Private chat is not logged either: what
    # runs for it is the Private chat's work.
    it "runs another request from a Private chat's tab as that chat's work" do
      seen = []
      worker = Monadic::History::PrivateRequestGuard.new(
        lambda do |_env|
          seen << policy.current_work_private?
          [200, {}, ['ok']]
        end,
        paths: ['/document'], session_lookup: ->(id) { tabs[id] }, state_lookup: ->(_id) { nil }
      )
      tabs['tab-p'] = chat(private: true)
      tabs['tab-n'] = chat
      %w[tab-p tab-n].each do |tab|
        worker.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/load', 'QUERY_STRING' => "tab_id=#{tab}",
                    'rack.input' => StringIO.new('x'))
      end
      expect(seen).to eq([true, false])
      expect(Fiber[Monadic::Utils::Privacy::EgressGuard::CHAT_KEY]).to be_nil
    end

    # The request is checked, as the chat's connection is, against the words
    # marked in the chat: the tab's live chat, or its saved state while the
    # tab is away.
    it "checks what such a request sends out against the words marked in the tab's chat" do
      guard = Monadic::Utils::Privacy::EgressGuard
      words = []
      worker = Monadic::History::PrivateRequestGuard.new(
        lambda do |_env|
          words << guard.words
          [200, {}, ['ok']]
        end,
        paths: ['/document'], session_lookup: ->(id) { tabs[id] }, state_lookup: ->(id) { states[id] }
      )
      marked = { privacy: { terms: [{ text: 'MARKEDWORD' }] } }
      tabs['tab-p'] = chat(private: true).merge(monadic_state: marked)
      states['tab-away'] = { chat_id: chat[:chat_id], chat_state: { policy::SESSION_KEY => policy::PRIVATE, monadic_state: marked } }
      %w[tab-p tab-away].each do |tab|
        worker.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/load', 'QUERY_STRING' => "tab_id=#{tab}",
                    'rack.input' => StringIO.new('x'))
      end
      expect(words).to eq([['MARKEDWORD'], ['MARKEDWORD']])
    end

    # The body is listed and closed after the route returned, and the access
    # log is written on close: both are the Private chat's work as well.
    it "keeps a Private chat's request its work while the body is listed and closed" do
      seen = []
      body = Rack::BodyProxy.new(Class.new do
        define_method(:each) do |&block|
          seen << [:each, Monadic::History::Policy.current_work_private?]
          block.call('ok')
        end
      end.new) { seen << [:log, Monadic::History::Policy.current_work_private?] }
      worker = Monadic::History::PrivateRequestGuard.new(->(_env) { [200, {}, body] }, paths: ['/document'],
                                                                                     session_lookup: ->(id) { tabs[id] },
                                                                                     state_lookup: ->(_id) { nil })
      tabs['tab-p'] = chat(private: true)
      _status, _headers, returned = worker.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/x', 'QUERY_STRING' => 'tab_id=tab-p',
                                                'rack.input' => StringIO.new(''))
      expect(policy.current_work_private?).to be(false)
      returned.each { |_part| nil }
      returned.close
      expect(seen).to eq([[:each, true], [:log, true]])
      expect(Fiber[Monadic::Utils::Privacy::EgressGuard::CHAT_KEY]).to be_nil
    end

    it "takes a normal chat's upload, and other requests" do
      tabs['tab-n'] = chat
      expect(post('/attachments', tab_id: 'tab-n', input: StringIO.new('file')).first).to eq(200)
      expect(post('/other', tab_id: nil, input: StringIO.new('x')).first).to eq(200)
      expect(reached).to eq(['/attachments', '/other'])
    end

    it 'is in front of everything that reads a body' do
      config = File.read(File.expand_path('../../../config.ru', __dir__))
      guard_at = config.index('use Monadic::History::PrivateRequestGuard')
      expect(guard_at).not_to be_nil
      ['use Rack::TempfileReaper', 'use Monadic::Workspace::UploadContext', 'use Monadic::Workspace::UploadLimit',
       'use Rack::Session::CappedPool'].each do |later|
        expect(config.index(later)).to be > guard_at
      end
      %w[AttachmentRoutes::PATH /pdf /document /upload_audio /fetch_webpage].each do |path|
        expect(config[guard_at, 400]).to include(path)
      end
    end
  end

  describe 'voice input' do
    let(:host) do
      Class.new do
        include WebSocketHelper
        attr_accessor :current
        def session = current
        def errors = (@errors ||= [])
        def send_error(content, *) = errors << content
        def transcribed = (@transcribed ||= [])
        def process_transcription(_connection, _blob, _format, _lang, model, _id) = transcribed << model
      end.new
    end

    def speak(model)
      host.send(:handle_audio_message, nil, { 'content' => Base64.strict_encode64('audio'), 'stt_model' => model })
    end

    it 'is taken in a Private chat only where the audio stays in memory' do
      allow(host).to receive(:stt_provider_for) { |model| model.start_with?('gemini') ? 'gemini' : 'openai' }
      host.current = chat(private: true)
      speak('gpt-transcribe')
      expect(host.errors).to eq(['voice_input_private'])
      expect(host.transcribed).to be_empty
      speak('gemini-flash')
      expect(host.transcribed).to eq(['gemini-flash'])

      host.current = chat
      speak('gpt-transcribe')
      expect(host.transcribed).to eq(%w[gemini-flash gpt-transcribe])
    end
  end

  describe 'the tool that writes files' do
    let(:tool) { Class.new { include MonadicSharedTools::FileOperations }.new }

    def working_for(session)
      Fiber.new(storage: {}) do
        Monadic::Utils::Privacy::EgressGuard.for_chat(session)
        yield
      end.resume
    end

    it 'writes nothing for a Private chat' do
      result = working_for(chat(private: true)) { tool.write_file_to_shared_folder(filepath: 'note.md', content: 'x') }
      expect(result).to include(success: false)
      expect(result[:error]).to include('Private')
    end

    it 'is not refused as Private for a normal chat' do
      allow(tool).to receive(:validate_file_path).and_return(nil)
      result = working_for(chat) { tool.write_file_to_shared_folder(filepath: 'note.md', content: 'x') }
      expect(result[:error].to_s).not_to include('Private')
    end
  end
end
