# frozen_string_literal: true

require 'spec_helper'
require 'http'
require 'net/http'
require 'stringio'
require 'async/websocket/client'
require_relative '../../../../lib/monadic/utils/privacy/egress_guard'
require_relative '../../../../lib/monadic/adapters/base_vendor_helper'
require_relative '../../../../lib/monadic/utils/interaction_utils'

# Every request that leaves for another service is checked where it is sent
# (the HTTP clients and the WebSocket client), so no word the user marked in
# a chat goes out, however the request was put together.
RSpec.describe Monadic::Utils::Privacy::EgressGuard do
  let(:refused) { Monadic::Utils::Privacy::Outbound::Refused }
  let(:chat) { { monadic_state: { privacy: { terms: [{ text: 'SecretName', type: 'PERSON' }] } } } }

  before do
    described_class.install!
    Thread.current[:rack_session] = chat
  end

  after do
    Thread.current[:rack_session] = nil
    Fiber[described_class::CHAT_KEY] = nil
  end

  describe 'the http gem' do
    it 'stops a request before it is made' do
      expect_any_instance_of(HTTP::Client).not_to receive(:monadic_unguarded_perform)
      expect { HTTP.post('https://api.example.invalid/v1/x', json: { 'input' => 'Speak to SecretName' }) }
        .to raise_error(refused)
    end

    it 'checks the request as sent: a persistent client, default options' do
      expect_any_instance_of(HTTP::Client).not_to receive(:monadic_unguarded_perform)
      expect { HTTP.persistent('https://api.example.invalid').post('/x', json: { 'a' => 'SecretName' }) }
        .to raise_error(refused)
      expect { HTTP::Client.new(json: { 'a' => 'SecretName' }).post('https://api.example.invalid/x') }
        .to raise_error(refused)
    end

    it 'checks every hop of a redirect' do
      hops = []
      allow_any_instance_of(HTTP::Client).to receive(:monadic_unguarded_perform) do |_client, req, _options|
        hops << req.uri.to_s
        HTTP::Response.new(status: 307, version: '1.1', request: req, body: '',
                           headers: { 'Location' => 'https://api.example.invalid/x' })
      end
      expect { HTTP.follow.post('http://localhost:9/start', json: { 'a' => 'SecretName' }) }.to raise_error(refused)
      expect(hops).to eq(['http://localhost:9/start'])
    end

    it 'checks the address and a form' do
      expect { HTTP.get('https://api.example.invalid/search', params: { q: 'SecretName' }) }.to raise_error(refused)
      expect { HTTP.post('https://api.example.invalid/x', form: { note: 'SecretName' }) }.to raise_error(refused)
    end

    it 'checks the text fields of a multipart form but not the file it uploads' do
      file = HTTP::FormData::File.new(StringIO.new('audio SecretName'), filename: 'clip.mp3')
      allow_any_instance_of(HTTP::Client).to receive(:monadic_unguarded_perform).and_return(:sent)
      expect(HTTP.post('https://api.example.invalid/x', form: { file: file, model: 'm' })).to eq(:sent)
      expect { HTTP.post('https://api.example.invalid/x', form: { file: file, prompt: 'SecretName' }) }
        .to raise_error(refused)
    end
  end

  describe 'a multipart body sent as a string (as speech-to-text sends it)' do
    def send_form(fields)
      form = HTTP::FormData.create(fields)
      HTTP.headers('Content-Type' => form.content_type).post('https://api.example.invalid/x', body: form.to_s)
    end

    let(:wav) { "RIFF\x00\x00WAVE\xFF\x00SecretName\xFF".b }

    before { allow_any_instance_of(HTTP::Client).to receive(:monadic_unguarded_perform).and_return(:sent) }

    it 'reads its text fields and file names even when the audio is bytes' do
      audio = HTTP::FormData::File.new(StringIO.new(wav), filename: 'clip.wav')
      expect { send_form(file: audio, model: 'SecretName') }.to raise_error(refused)
      named = HTTP::FormData::File.new(StringIO.new(wav), filename: 'SecretName.wav')
      expect { send_form(file: named, model: 'm') }.to raise_error(refused)
    end

    it 'does not read the audio, also when the audio happens to be valid text' do
      audio = HTTP::FormData::File.new(StringIO.new('plain SecretName text'), filename: 'clip.wav')
      expect(send_form(file: audio, model: 'm')).to eq(:sent)
      expect(send_form(file: HTTP::FormData::File.new(StringIO.new(wav), filename: 'a.wav'), model: 'm')).to eq(:sent)
    end

    def raw_multipart(parts, boundary: 'XyZ')
      body = parts.map { |head, content| "--#{boundary}\r\n#{head}\r\n\r\n#{content}\r\n" }.join + "--#{boundary}--\r\n"
      HTTP.headers('Content-Type' => %(multipart/form-data; boundary="#{boundary}"))
          .post('https://api.example.invalid/x', body: body)
    end

    it 'keeps the boundary as written (the File Inputs upload uses upper case)' do
      expect(raw_multipart([['Content-Disposition: form-data; name="purpose"', 'user_data']], boundary: '----MonadicChatAbC1'))
        .to eq(:sent)
    end

    it 'takes a file only by its filename parameter, and reads filename* decoded' do
      expect { raw_multipart([['Content-Disposition: form-data; name="filename=note"', 'SecretName']]) }
        .to raise_error(refused)
      expect(HTTP.post('https://api.example.invalid/x', form: { 'filename=note' => 'Hello' })).to eq(:sent)
      expect do
        raw_multipart([["Content-Disposition: form-data; name=\"f\"; filename*=UTF-8''%53ecretName.txt", 'bytes']])
      end.to raise_error(refused)
    end

    it 'decodes base64 and quoted-printable fields, reads nested multipart, and refuses an unknown encoding' do
      expect do
        raw_multipart([["Content-Disposition: form-data; name=\"a\"\r\nContent-Transfer-Encoding: base64", 'U2VjcmV0TmFtZQ==']])
      end.to raise_error(refused)
      expect do
        raw_multipart([["Content-Disposition: form-data; name=\"a\"\r\nContent-Transfer-Encoding: quoted-printable", '=53ecretName']])
      end.to raise_error(refused)
      inner = "--in\r\nContent-Disposition: form-data; name=\"t\"\r\n\r\nSecretName\r\n" \
              "--in\r\nContent-Disposition: attachment; filename=\"a.bin\"\r\n\r\n\xFF\x00\r\n--in--"
      expect do
        raw_multipart([["Content-Disposition: form-data; name=\"m\"\r\nContent-Type: multipart/mixed; boundary=in", inner]])
      end.to raise_error(refused)
      expect do
        raw_multipart([["Content-Disposition: form-data; name=\"a\"\r\nContent-Transfer-Encoding: x-gzip", 'zz']])
      end.to raise_error(refused)
    end

    it 'reads a quoted file name as it decodes' do
      expect { raw_multipart([['Content-Disposition: form-data; name="f"; filename="Secret\\Name.txt"', 'x']]) }
        .to raise_error(refused)
    end

    it 'does not take a line in a file that begins with the boundary for a delimiter' do
      expect(raw_multipart([['Content-Disposition: form-data; name="f"; filename="a.txt"', "Hello\r\n--XyZWorld"]]))
        .to eq(:sent)
    end

    it 'does not take a line in a file that begins with the closing delimiter for one' do
      expect(raw_multipart([['Content-Disposition: form-data; name="f"; filename="a.txt"', "Hello\r\n--XyZ--World"]]))
        .to eq(:sent)
    end

    it 'splits only at delimiter lines, not where the boundary appears inside a file' do
      expect(raw_multipart([['Content-Disposition: form-data; name="f"; filename="a.txt"', 'Hello--bWorld'],
                            ['Content-Disposition: form-data; name="model"', 'm']], boundary: 'b')).to eq(:sent)
    end

    it 'refuses a multipart body it cannot split' do
      expect do
        HTTP.headers('Content-Type' => 'multipart/form-data; boundary=zz').post('https://api.example.invalid/x', body: 'no parts')
      end.to raise_error(refused)
    end
  end

  describe 'Net::HTTP' do
    let(:http) { Net::HTTP.new('api.example.invalid', 443) }

    it 'stops a JSON body' do
      req = Net::HTTP::Post.new('/v1/x')
      req.body = JSON.generate('messages' => [{ 'content' => 'Hi SecretName' }])
      expect { http.request(req) }.to raise_error(refused)
    end

    it 'checks the path and query, as written and decoded' do
      Thread.current[:rack_session] = { monadic_state: { privacy: { terms: [{ text: 'Secret Name', type: 'PERSON' }] } } }
      %w[/search?q=Secret+Name /search?q=Secret%20Name].each do |path|
        expect { http.request(Net::HTTP::Get.new(path)) }.to raise_error(refused)
      end
    end

    it 'reads a StringIO from where it stands, leaves it there, and decodes a form in it' do
      stream = StringIO.new('SecretNameHello')
      stream.pos = 10
      expect(described_class.body_texts(stream)).to eq(['Hello'])
      expect(stream.pos).to eq(10)
      form = StringIO.new('q=%53ecretName')
      expect { described_class.check!('api.example.invalid') { described_class.body_texts(form) } }.to raise_error(refused)
    end

    it 'reads a StringIO stream, leaves a file stream, and refuses a stream it cannot read again' do
      req = Net::HTTP::Post.new('/x')
      req.body_stream = StringIO.new(JSON.generate('a' => 'SecretName'))
      expect { http.request(req) }.to raise_error(refused)

      expect { described_class.body_texts(Object.new.tap { |o| o.define_singleton_method(:read) { '' } }) }
        .to raise_error(refused)
      Tempfile.create('upload') do |f|
        expect(described_class.body_texts(f)).to eq([])
      end
    end
  end

  describe 'the WebSocket client' do
    it 'checks every text message a connection to another service sends, but not its audio' do
      handler = nil
      allow_any_instance_of(Async::WebSocket::Client).to receive(:monadic_unguarded_connect) do |_c, _a, _p, **opts|
        handler = opts[:handler]
      end
      client = Async::WebSocket::Client.allocate
      client.connect('api.example.invalid:443', '/v1/realtime')
      expect { handler.allocate.send_text(JSON.generate('item' => { 'text' => 'SecretName' })) }.to raise_error(refused)

      audio = { 'type' => 'input_audio_buffer.append', 'audio' => 'U2VjcmV0TmFtZQ==SecretName' }
      gemini = { 'realtimeInput' => { 'audio' => { 'data' => 'SecretName', 'mimeType' => 'audio/pcm' } } }
      [audio, gemini].each do |frame|
        expect { described_class.check!('api.example.invalid', *described_class.frame_texts(JSON.generate(frame))) }
          .not_to raise_error
      end
    end

    it 'checks the address it connects to' do
      client = Async::WebSocket::Client.allocate
      expect { client.connect('api.example.invalid', '/v1?prompt=SecretName') }.to raise_error(refused)
    end
  end

  describe 'which hosts are on this computer' do
    it 'knows loopback addresses and the containers Monadic Chat runs' do
      %w[localhost 127.0.0.1 127.0.0.2 ::1 [::1] ::ffff:127.0.0.1 0.0.0.0 host.docker.internal app.localhost
         privacy_service embeddings_service monadic-chat-selenium-container].each do |host|
        expect(described_class.local_host?(host)).to be(true), host
      end
    end

    it 'treats any other name or address as another service' do
      ['', '2001:db8::123', '[2001:db8::123]', 'intranet', 'printer.local', 'api.internal', '10.0.0.5',
       'api.example.invalid', 'evil_service.example.com'].each do |host|
        expect(described_class.local_host?(host)).to be(false), host
      end
    end
  end

  describe 'whose words' do
    it 'covers what a thread or fiber started from the chat sends' do
      Thread.current[:rack_session] = nil
      Fiber.new do
        described_class.for_chat(chat)
        thread = Thread.new do
          described_class.check!('api.example.invalid', { 'text' => 'SecretName' })
        rescue Monadic::Utils::Privacy::Outbound::Refused
          :refused
        end
        expect(thread.value).to eq(:refused)
        expect(Fiber.new { described_class.words }.resume).to eq(['SecretName'])
      end.resume
    end

    it 'checks work begun before a Reset for the words of the chat it began in' do
      session = chat.merge(parameters: {}, messages: [])
      Fiber.new do
        Monadic::Workspace::Chats.start_new!(session) # the chat begins: its connection's work is done for it
        gate = Queue.new
        old_work = Thread.new do
          gate.pop
          described_class.check!('api.example.invalid', { 'text' => 'SecretName' })
          :sent
        rescue Monadic::Utils::Privacy::Outbound::Refused
          :refused
        end
        Monadic::Workspace::Chats.begin_new!(session) # Reset: the marked words are dropped from the session
        gate << :go
        expect(old_work.value).to eq(:refused)
        # Work begun in the new chat is checked for the new chat's words (none).
        expect(Thread.new { described_class.words }.value).to eq([])
      end.resume
    end

    it 'still finds the words when a Reset falls between reading the chat id and the words' do
      session = chat.merge(parameters: {}, messages: [])
      Fiber.new do
        Monadic::Workspace::Chats.start_new!(session)
        reset = false
        allow(described_class).to receive(:terms_now).and_wrap_original do |original, s|
          unless reset
            reset = true
            Monadic::Workspace::Chats.clear_chat_state!(session) # the Reset clears the session here
          end
          original.call(s)
        end
        expect { described_class.check!('api.example.invalid', { 'text' => 'SecretName' }) }.to raise_error(refused)
      end.resume
    end

    it 'refuses when a Reset falls between the reads and the kept words are gone too' do
      session = chat.merge(parameters: {}, messages: [])
      Fiber.new do
        Monadic::Workspace::Chats.start_new!(session)
        old_id = session[:chat_id]
        reset = false
        allow(described_class).to receive(:terms_now).and_wrap_original do |original, s|
          unless reset
            reset = true
            Monadic::Workspace::Chats.begin_new!(session)
            described_class.instance_variable_get(:@ended_lock).synchronize do
              described_class.instance_variable_get(:@ended).delete(old_id) # pushed out by later chats
            end
          end
          original.call(s)
        end
        expect { described_class.check!('api.example.invalid', { 'text' => 'Hello' }) }.to raise_error(refused)
      end.resume
    end

    it 'drops the chat id before anything else of the chat when it ends' do
      order = []
      session = Class.new(Hash) do
        define_method(:delete) { |key| order << key.to_s; super(key) }
      end.new
      session[:monadic_state] = chat[:monadic_state]
      session[:chat_id] = 'c_x'
      Monadic::Workspace::Chats.clear_chat_state!(session)
      expect(order.first).to eq('chat_id')
      expect(order).to include('monadic_state')
    end

    it 'refuses work of a chat that ended without its words being kept' do
      Fiber.new do
        Fiber[described_class::CHAT_KEY] = described_class::Scope.new({ chat_id: 'chat_gone' }, 'chat_old')
        expect { described_class.check!('api.example.invalid', { 'text' => 'Hello' }) }.to raise_error(refused)
      end.resume
    end

    it 'checks a chat only for its own words, and a request of no chat for none' do
      other = { monadic_state: { privacy: { terms: [{ text: 'OtherName', type: 'PERSON' }] } } }
      expect { described_class.check!('api.example.invalid', { 'text' => 'OtherName' }) }.not_to raise_error
      Fiber.new do
        described_class.for_chat(other)
        expect { described_class.check!('api.example.invalid', { 'text' => 'OtherName' }) }.to raise_error(refused)
        expect { described_class.check!('api.example.invalid', { 'text' => 'SecretName' }) }.not_to raise_error
      end.resume
      Thread.current[:rack_session] = nil
      expect { described_class.check!('api.example.invalid', { 'text' => 'SecretName' }) }.not_to raise_error
    end

    it 'reads nothing of a request to this computer, or while no chat has marked words' do
      stream = Object.new.tap { |o| o.define_singleton_method(:read) { |*| raise 'read' } }
      allow_any_instance_of(HTTP::Client).to receive(:monadic_unguarded_perform).and_return(:sent)
      expect(HTTP.post('http://localhost:9/x', body: stream)).to eq(:sent)
      Thread.current[:rack_session] = nil
      expect(HTTP.post('https://api.example.invalid/x', body: stream)).to eq(:sent)
    end

    it 'leaves requests to this computer, and requests without marked words' do
      expect { described_class.check!('privacy_service', { 'text' => 'SecretName' }) }.not_to raise_error
      expect { described_class.check!('api.example.invalid', { 'text' => 'Hello' }) }.not_to raise_error
      Thread.current[:rack_session] = nil
      expect { described_class.check!('api.example.invalid', { 'text' => 'SecretName' }) }.not_to raise_error
    end
  end

  describe 'what is read in a body' do
    it 'finds a word as written in JSON, and in plain text, but not in bytes or attached data' do
      Thread.current[:rack_session] = { monadic_state: { privacy: { terms: [{ text: 'A"B', type: 'PERSON' }] } } }
      expect { described_class.check!('api.example.invalid', JSON.generate('a' => JSON.generate('A"B'))) }
        .to raise_error(refused)
      expect { described_class.check!('api.example.invalid', *described_class.body_texts('note: A"B')) }
        .to raise_error(refused)
      expect(described_class.body_texts("\xFF\xFEA\"B".b)).to eq([])
      image = { 'messages' => [{ 'role' => 'user', 'content' => [
        { 'type' => 'image', 'source' => { 'type' => 'base64', 'media_type' => 'image/png', 'data' => 'xxA"Bxx' } }
      ] }] }
      expect { described_class.check!('api.example.invalid', JSON.generate(image)) }.not_to raise_error
    end
  end

  describe 'a refusal at the last check' do
    it 'is not tried again as if the network had failed' do
      helper = Class.new do
        include(Module.new do
          include BaseVendorHelper
          define_timeouts 'GUARDTEST', open: 1, read: 1, write: 1
        end)
      end.new
      calls = 0
      allow_any_instance_of(HTTP::Client).to receive(:post).and_wrap_original do |m, *args, **kw|
        calls += 1
        m.call(*args, **kw)
      end
      expect do
        helper.post_json_with_retries(HTTP, 'https://api.example.invalid/x', { 'a' => 'SecretName' },
                                      max_retries: 3, retry_delay: 0, rescue_errors: [StandardError])
      end.to raise_error(refused)
      expect(calls).to eq(1)
    end

    it 'gives speech a withheld result, not an error' do
      utils = Class.new do
        include InteractionUtils
        def settings = Struct.new(:api_key).new(nil)
      end.new
      stub_const('CONFIG', { 'OPENAI_API_KEY' => 'test-key' })
      result = utils.tts_api_request('Hello SecretName', provider: 'openai-tts', voice: 'alloy', response_format: 'mp3')
      expect(result).to eq('type' => 'privacy_withheld')
    end
  end
end
