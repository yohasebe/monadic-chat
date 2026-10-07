# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/utils/http_client'
require_relative '../../../lib/monadic/utils/tool_key_requirements'
require_relative '../../../apps/music_generator/music_generator_tools'

# ElevenLabs Music in the Music Generator. The HTTP call is stubbed; these
# pin the request (endpoint, model from providerDefaults, length and
# instrumental), the saved file, the service label on every result, and the
# key gate.
RSpec.describe MusicGeneratorTools do
  subject(:tool) { Class.new { include MusicGeneratorTools }.new }

  let(:tmpdir) { Dir.mktmpdir }
  let(:client) { double('http client') }
  let(:posted) { [] }

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def response(code:, body:, mime: 'audio/mpeg')
    status = double('status', success?: (200..299).cover?(code), code: code)
    double('response', status: status, body: body, content_type: double('ctype', mime_type: mime))
  end

  before do
    stub_const('CONFIG', { 'ELEVENLABS_API_KEY' => 'test-key' })
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(tmpdir)
    allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress) { |*_, &blk| blk.call }
    allow(Monadic::Utils::HttpClient).to receive(:generation).and_return(client)
    allow(client).to receive(:headers) { |h| posted << [:headers, h]; client }
    allow(client).to receive(:post) do |url, json:|
      posted << [:post, url, json]
      response(code: 200, body: 'MP3-BYTES')
    end
  end

  def request_body
    posted.find { |e| e.first == :post }[2]
  end

  def request_url
    posted.find { |e| e.first == :post }[1]
  end

  it 'saves the audio and labels the result with the service and model' do
    result = JSON.parse(tool.generate_music_with_elevenlabs(prompt: 'a calm piano piece'))
    expect(result['success']).to be true
    expect(result['service']).to eq('ElevenLabs Music')
    expect(result['model']).to eq('music_v2_5')
    expect(result['mime_type']).to eq('audio/mpeg')
    expect(result['filename']).to match(/\Aelevenlabs_music_\d+_[0-9a-f]{6}\.mp3\z/)
    expect(File.binread(File.join(tmpdir, result['filename']))).to eq('MP3-BYTES')
  end

  it 'posts to the music endpoint with the model from providerDefaults and the key in a header' do
    tool.generate_music_with_elevenlabs(prompt: 'x')
    expect(request_url).to start_with('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128')
    expect(request_body).to eq({ prompt: 'x', model_id: 'music_v2_5' })
    expect(posted.find { |e| e.first == :headers }[1]).to include('xi-api-key' => 'test-key')
  end

  it 'sends a length in milliseconds, clamped to what the API accepts' do
    tool.generate_music_with_elevenlabs(prompt: 'x', length_seconds: 90)
    expect(request_body[:music_length_ms]).to eq(90_000)
    posted.clear
    tool.generate_music_with_elevenlabs(prompt: 'x', length_seconds: 1)
    expect(request_body[:music_length_ms]).to eq(3_000)
    posted.clear
    tool.generate_music_with_elevenlabs(prompt: 'x', length_seconds: 3600)
    expect(request_body[:music_length_ms]).to eq(600_000)
    posted.clear
    tool.generate_music_with_elevenlabs(prompt: 'x', length_seconds: 'about a minute')
    expect(request_body).not_to have_key(:music_length_ms)
  end

  it 'asks for an instrumental only when told to' do
    tool.generate_music_with_elevenlabs(prompt: 'x', instrumental: true)
    expect(request_body[:force_instrumental]).to be true
    posted.clear
    tool.generate_music_with_elevenlabs(prompt: 'x', instrumental: 'false')
    expect(request_body).not_to have_key(:force_instrumental)
  end

  it 'reports the API message on an error, still naming the service' do
    allow(client).to receive(:post).and_return(
      response(code: 422, body: { detail: { status: 'bad_prompt', message: 'The prompt names a specific artist.' } }.to_json)
    )
    result = JSON.parse(tool.generate_music_with_elevenlabs(prompt: 'x'))
    expect(result['success']).to be false
    expect(result['service']).to eq('ElevenLabs Music')
    expect(result['error']).to eq('The prompt names a specific artist.')
  end

  it 'refuses without a key and makes no request' do
    stub_const('CONFIG', {})
    result = JSON.parse(tool.generate_music_with_elevenlabs(prompt: 'x'))
    expect(result['success']).to be false
    expect(result['error']).to match(/ELEVENLABS_API_KEY/)
    expect(posted).to be_empty
  end
end

RSpec.describe Monadic::Utils::ToolKeyRequirements do
  let(:tools) do
    [{ 'name' => 'generate_music_with_lyria' }, { 'name' => 'generate_music_with_elevenlabs' },
     { 'function' => { 'name' => 'generate_music_with_elevenlabs' } }]
  end

  it 'offers the ElevenLabs tool only when its key is set' do
    expect(described_class.filter(tools, {}).map { |t| described_class.tool_name_of(t) })
      .to eq(['generate_music_with_lyria'])
    expect(described_class.filter(tools, { 'ELEVENLABS_API_KEY' => '  ' }).size).to eq(1)
    expect(described_class.filter(tools, { 'ELEVENLABS_API_KEY' => 'k' })).to eq(tools)
  end

  it 'leaves tools without a requirement alone' do
    expect(described_class.available?('anything_else', {})).to be true
  end
end

require_relative '../../../lib/monadic/adapters/vendors/gemini_helper'

# The gate where it matters: the request the Gemini helper builds.
RSpec.describe 'GeminiHelper tool assembly with a key-gated tool' do
  let(:helper) { Class.new { include GeminiHelper }.new }
  let(:declarations) { [{ 'name' => 'generate_music_with_lyria' }, { 'name' => 'generate_music_with_elevenlabs' }] }

  before do
    stub_const('APPS', { 'MusicGeneratorGemini' => double('app', settings: { tools: declarations }) })
  end

  def offered_names(config)
    stub_const('CONFIG', config)
    body = {}
    helper.send(:configure_gemini_tools, app: 'MusicGeneratorGemini', role: 'user', body: body, obj: {},
                                         session: {}, tool_capable: true, use_native_websearch: false)
    Array(body.dig('tools', 0, 'function_declarations')).map { |t| t['name'] }
  end

  it 'leaves the ElevenLabs tool out of the request without ELEVENLABS_API_KEY' do
    expect(offered_names({})).to eq(['generate_music_with_lyria'])
  end

  it 'includes it when the key is set' do
    expect(offered_names({ 'ELEVENLABS_API_KEY' => 'k' }))
      .to eq(%w[generate_music_with_lyria generate_music_with_elevenlabs])
  end
end
