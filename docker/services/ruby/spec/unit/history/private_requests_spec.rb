# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'securerandom'
require 'base64'
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
    let(:reached) { [] }
    let(:guard) do
      downstream = lambda do |env|
        reached << env['PATH_INFO']
        env['rack.input'].read
        [200, {}, ['ok']]
      end
      Monadic::History::PrivateRequestGuard.new(downstream, paths: ['/attachments', '/document'],
                                                            session_lookup: ->(id) { tabs[id] },
                                                            state_lookup: ->(_id) { nil })
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
