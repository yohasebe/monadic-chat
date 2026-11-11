# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'tmpdir'
require 'stringio'
require_relative '../../support/provider_matrix_helper'
require_relative '../../../lib/monadic/utils/tts_utils'
require_relative '../../../lib/monadic/utils/stt_utils'
require_relative '../../../lib/monadic/agents/audio_analysis_agent'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'
require_relative '../../../lib/monadic/agents/image_analysis_agent'
require_relative '../../../lib/monadic/agents/video_analyze_agent'
require_relative '../../../lib/monadic/utils/gemini_omni_video'
require_relative '../../../lib/monadic/agents/context_extractor_agent'
require_relative '../../../lib/monadic/shared_tools/parallel_dispatch'
require_relative '../../../lib/monadic/utils/websocket'
require_relative '../../../lib/monadic/utils/websocket/sts_stream_handler'

RSpec.describe 'Gemini request transport invariants' do
  let(:key) { 'AIza_NOT_A_REAL_KEY_HEADER_TEST_ONLY_0000' }
  let(:requests) { [] }
  let(:client) { double('HTTP transport') }
  let(:body) do
    { candidates: [{ content: { parts: [{ text: 'ok', inlineData: {
      data: Base64.strict_encode64([0, 1].pack('s<*')), mimeType: 'audio/L16;rate=24000'
    } }] } }], models: [{ name: 'models/gemini-test', displayName: 'Test' }], done: true }.to_json
  end
  let(:response) { double('HTTP response', body: body, status: double(success?: true, code: 200, :>= => false), headers: {}) }
  let(:helper) { Class.new { include GeminiHelper }.new }
  let(:tts) { Class.new { include InteractionUtils }.new }

  def record_request(url, headers, body = nil)
    body = JSON.parse(body) if body.is_a?(String)
    body = JSON.parse(JSON.generate(body)) if body.is_a?(Hash)
    requests << [url.to_s, headers.transform_keys { |name| name.to_s.downcase }, body]
  end

  def expect_no_storage
    generated = requests.select { |url, _headers, _body| URI.parse(url).path.match?(/:(?:generateContent|streamGenerateContent)\z/) }
    generated.each do |url, _headers, body|
      expect(body).to include('store' => false), "#{url} must disable request storage"
      expect(body.fetch('generationConfig', {})).not_to have_key('store')
    end
  end

  def expect_header_auth
    expect(requests).not_to be_empty
    requests.each do |url, headers|
      expect(url).not_to include(key)
      expect(URI.decode_www_form(URI.parse(url).query.to_s).map(&:first)).not_to include('key', 'api_key')
      expect(headers['x-goog-api-key']).to eq(key)
    end
    expect_no_storage
  end

  before do
    stub_const('CONFIG', { 'GEMINI_API_KEY' => key })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
    @headers = {}
    [HTTP, client].each do |receiver|
      allow(receiver).to receive(:headers) { |headers| @headers = headers; client }
      allow(receiver).to receive(:timeout).and_return(client)
    end
    allow(client).to receive(:follow).and_return(client)
    [:post, :get].each do |verb|
      allow(client).to receive(verb) do |url, **options|
        record_request(url, @headers, options[:json] || options[:body])
        response
      end
    end
    # Never let a forgotten Net::HTTP stub make a real request.
    allow(Net::HTTP).to receive(:start).and_raise('Unstubbed transport')
    allow(Net::HTTP).to receive(:new).and_raise('Unstubbed transport')
  end

  it 'authenticates non-streaming chat in headers' do
    helper.send_query({ 'messages' => [{ 'role' => 'user', 'content' => 'Hello' }] }, model: 'gemini-test')
    expect_header_auth
  end

  it 'authenticates streaming chat at the transport boundary' do
    allow(helper).to receive(:process_json_data).and_return([])
    helper.send(:execute_gemini_api_call, headers: { 'Content-Type' => 'application/json' },
                body: { 'contents' => [] }, obj: { 'model' => 'gemini-test' }, api_key: key,
                is_thinking_model: false, has_pdf_part: false, app: 'Test', session: {}, call_depth: 0)
    expect_header_auth
  end

  it 'authenticates grounded search in headers' do
    GeminiHelper.internal_web_search(query: 'Hello', model: 'gemini-test')
    expect_header_auth
  end

  [:normal, :sentence, :cli].each do |route|
    it "authenticates #{route} TTS in headers" do
      options = { provider: 'gemini-flash-lite', voice: 'kore', response_format: 'wav', speed: 1.0, language: 'auto' }
      %w[OPEN_TIMEOUT READ_TIMEOUT WRITE_TIMEOUT].each { |name| stub_const("InteractionUtils::#{name}", 1) }
      if route == :normal
        tts.tts_api_request('Hello', **options)
      elsif route == :sentence
        allow(Thread).to receive(:new).and_yield
        allow(tts).to receive(:Async).and_yield
        tts.tts_api_request_async('Hello', **options) { |_result| }
      else
        path = File.expand_path('../../../scripts/cli_tools/tts_query.rb', __dir__)
        script = Object.new
        script.instance_eval(File.read(path).split('# Usage:', 2).first, path)
        allow(File).to receive(:read).and_call_original
        ['/monadic/config/env', File.join(Dir.home, 'monadic/config/env')].each do |config|
          allow(File).to receive(:read).with(config).and_return("GEMINI_API_KEY=#{key}\n")
        end
        script.tts_api_request('Hello', **options)
      end
      expect_header_auth
    end
  end

  it 'keeps the TTS request URL credential-free in debug and error output' do
    messages = []
    allow(Monadic::Utils::ExtraLogger).to receive(:log) { |&block| messages << block.call }
    allow(response.status).to receive(:success?).and_return(false)
    allow(response).to receive(:body).and_return({ error: { message: 'fake rejection' } }.to_json)
    %w[OPEN_TIMEOUT READ_TIMEOUT WRITE_TIMEOUT].each { |name| stub_const("InteractionUtils::#{name}", 1) }
    output = StringIO.new
    previous = $stdout
    begin
      $stdout = output
      tts.tts_api_request('Hello', provider: 'gemini-flash-lite', voice: 'kore', response_format: 'wav')
    ensure
      $stdout = previous
    end
    expect_header_auth
    expect(messages.join).not_to include(key)
    expect(output.string).not_to include(key)
    expect(messages.join).to include('Sending HTTP POST')
    expect(messages.join).to include('API error')
    # The request body holds the user's text; it is not printed.
    expect(output.string).not_to include('Hello')
    expect(messages.join).not_to include('Hello')
  end

  it 'authenticates STT in headers' do
    %w[OPEN_TIMEOUT READ_TIMEOUT WRITE_TIMEOUT].each { |name| stub_const("InteractionUtils::#{name}", 1) }
    tts.gemini_stt_api_request('fake audio', 'wav', 'en', 'gemini-test')
    expect_header_auth
  end

  it 'authenticates audio analysis in headers' do
    # The audio is read from the shared folder; a temp folder stands in for it.
    Dir.mktmpdir do |dir|
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(dir)
      path = File.join(dir, 'header-test.mp3')
      File.binwrite(path, 'fake audio')
      AudioAnalysisAgent.analyze(audio_path: path, prompt: 'Hello', model: 'gemini-test')
    end
    expect_header_auth
  end

  it 'authenticates audio transcription in headers' do
    allow(Monadic::Utils::SharedPathGuard).to receive(:read_bytes!).with('/fake/header-test.mp3', limit: anything).and_return('fake audio')
    host = Class.new { include AudioTranscriptionAgent }.new
    host.send(:transcribe_gemini, '/fake/header-test.mp3', 'gemini-test', key, 'en')
    expect_header_auth
  end

  it 'authenticates image analysis in headers' do
    host = Class.new { include ImageAnalysisAgent }.new
    host.send(:vision_query_gemini, 'Hello', { mime_type: 'image/png', base64: 'ZmFrZQ==' }, 'gemini-test', key)
    expect_header_auth
  end

  it 'authenticates video analysis in headers' do
    host = Class.new { include VideoAnalyzeAgent }.new
    host.send(:video_vision_gemini, 'Hello', ['ZmFrZQ=='], 'gemini-test', key)
    expect_header_auth
  end

  [:gemini_sub_call, :gemini_websearch_sub_call].each do |method|
    it "authenticates #{method} in headers" do
      host = Class.new { include MonadicSharedTools::ParallelDispatch }.new
      host.send(method, 'https://generativelanguage.googleapis.com/v1beta', key, 'gemini-test', 'Hello', 1)
      expect_header_auth
    end
  end

  [:instance, :class].each do |route|
    it "authenticates #{route} model listing in headers" do
      previous = $MODELS
      begin
        $MODELS = {}
        (route == :instance ? helper : GeminiHelper).list_models
        expect_header_auth
      ensure
        $MODELS = previous
      end
    end
  end

  it 'authenticates the Live handshake in headers without changing its endpoint' do
    host = Class.new { include WebSocketHelper }.new
    allow(Async::WebSocket::Client).to receive(:connect) do |endpoint, headers:|
      record_request(endpoint.url, headers)
      # Deliberately do not start the audio reader/writer tasks.
    end
    host.send(:sts_connect_and_run, { provider: 'gemini', model: 'gemini-live-test' }, 'test-session', key)
    expect_header_auth
    expect(requests.first.first).to eq(WebSocketHelper::STS_PROVIDER_PROFILES['gemini'][:url])
  end

  context 'Net::HTTP paths' do
    let(:net) { double('Net HTTP transport').as_null_object }
    # What the generators save goes to a temp folder standing in for the
    # shared folder.
    before do
      @shared = Dir.mktmpdir
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@shared)
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@shared)
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(anything, 'wb').and_yield(StringIO.new)
      allow(Net::HTTP).to receive(:start).and_yield(net)
      allow(Net::HTTP).to receive(:new).and_return(net)
      allow(net).to receive(:request) do |request|
        record_request(request.uri || "https://generativelanguage.googleapis.com#{request.path}", request.to_hash.transform_values(&:first), request.body)
        result = Net::HTTPOK.new('1.1', '200', 'OK')
        result.instance_variable_set(:@read, true)
        result.body = body
        result
      end
      allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress).and_yield
    end
    after { FileUtils.rm_rf(@shared) }

    it 'authenticates context extraction in headers' do
      host = Class.new { include ContextExtractorAgent }.new
      host.send(:call_gemini_api, 'gemini-test', 'Hello', key)
      expect_header_auth
    end

    it 'authenticates native image generation in headers' do
      helper.generate_image_with_gemini_native(prompt: 'Hello', model: 'gemini-3.1-flash-image')
      expect_header_auth
    end

    it 'authenticates the legacy image generation entry point in headers' do
      helper.generate_image_with_gemini(prompt: 'Hello')
      expect_header_auth
    end

    it 'disables storage in the provider matrix image request' do
      saved_key = ENV['GEMINI_API_KEY']
      ENV['GEMINI_API_KEY'] = key
      host = ProviderMatrixHelper::ProviderClient.new('gemini')
      allow(host).to receive(:throttle!)
      allow(host).to receive(:log_request)
      host.image_generate_api('Hello')
      expect(requests.size).to eq(1)
      expect_no_storage
    ensure
      saved_key ? ENV['GEMINI_API_KEY'] = saved_key : ENV.delete('GEMINI_API_KEY')
    end

    it 'authenticates Imagen in headers' do
      helper.generate_image_with_imagen_direct(prompt: 'Hello', model: 'imagen-test')
      expect_header_auth
    end

    it 'authenticates music generation in headers' do
      helper.generate_music_with_lyria(prompt: 'Hello')
      expect_header_auth
      expect(Dir.children(@shared)).to all(start_with('lyria_music_'))
    end
  end

  # Video generation is Gemini Omni over the Interactions API
  # (Monadic::Utils::GeminiOmniVideo, used by video_generator_gemini.rb).
  let(:omni) { Monadic::Utils::GeminiOmniVideo.new(api_key: key, model: 'gemini-omni-1.1-flash', save_dir: Dir.tmpdir) }

  it 'authenticates video generation in headers' do
    omni.generate(prompt: 'Hello')
    expect_header_auth
  end

  it 'authenticates video download in headers' do
    omni.send(:download, 'https://generativelanguage.googleapis.com/v1beta/files/fake:download?alt=media')
    expect_header_auth
  end

  it 'does not send download credentials to external storage URLs or redirect targets' do
    omni.send(:download, 'https://storage.example.invalid/fake.mp4')
    expect(requests).to be_empty

    redirect = double('redirect', body: '', headers: { 'Location' => 'https://storage.example.invalid/signed.mp4' },
                                  status: double(success?: false, code: 302))
    replies = [response, redirect, response]
    allow(client).to receive(:get) { |url, **_| record_request(url, @headers); replies.shift }
    omni.send(:download, 'https://generativelanguage.googleapis.com/v1beta/files/fake:download?alt=media')
    urls = requests.map(&:first)
    expect(urls.last).to eq('https://storage.example.invalid/signed.mp4')
    expect(requests.last[1]).not_to have_key('x-goog-api-key')
    requests[0..-2].each { |_url, headers| expect(headers['x-goog-api-key']).to eq(key) }
  end

end
