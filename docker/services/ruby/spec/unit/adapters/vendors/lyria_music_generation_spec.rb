# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

# Unit coverage for generate_music_with_lyria. The live Gemini call is stubbed;
# these specs pin the response parsing (audio part extraction, mime→ext, lyrics
# formatting), the file save, and the error/empty paths — the part the live
# dogfood exercised but no unit test covered.
RSpec.describe 'GeminiHelper#generate_music_with_lyria' do
  subject(:helper) do
    Class.new do
      include GeminiHelper
    end.new
  end

  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def response(code, hash)
    instance_double('Net::HTTPResponse', code: code, body: JSON.generate(hash))
  end

  def audio_body(mime:, text:, audio: 'FAKE-AUDIO-BYTES')
    {
      "candidates" => [{
        "content" => {
          "parts" => [
            { "text" => text },
            { "inlineData" => { "mimeType" => mime, "data" => Base64.strict_encode64(audio) } }
          ]
        }
      }]
    }
  end

  before do
    stub_const('CONFIG', { 'GEMINI_API_KEY' => 'test-key' })
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(tmpdir)
    # with_progress just runs the block (no websocket in unit context)
    allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress) { |*_, &blk| blk.call }
  end

  it 'parses an MP3 response, formats lyrics, and saves the file' do
    allow(Net::HTTP).to receive(:start).and_return(
      response('200', audio_body(mime: 'audio/mpeg',
                                 text: "[[A0]]\n[0.0:] First line\n[:] Second line"))
    )

    result = JSON.parse(helper.generate_music_with_lyria(prompt: 'a calm tune'))

    expect(result['success']).to be true
    expect(result['mime_type']).to eq('audio/mpeg')
    expect(result['filename']).to match(/\Alyria_music_\d+_[0-9a-f]{6}\.mp3\z/)
    # lyrics formatted: timestamp → [m:ss], continuation aligned, raw codes gone
    expect(result['lyrics']).to eq("[0:00] First line\n       Second line")
    # file actually written with the decoded audio bytes
    saved = File.join(tmpdir, result['filename'])
    expect(File.exist?(saved)).to be true
    expect(File.binread(saved)).to eq('FAKE-AUDIO-BYTES')
  end

  it 'uses a .wav extension when the response is WAV (Pro)' do
    allow(Net::HTTP).to receive(:start).and_return(
      response('200', audio_body(mime: 'audio/wav', text: '<instrumental>'))
    )
    result = JSON.parse(helper.generate_music_with_lyria(prompt: 'x', lyria_model: 'pro'))
    expect(result['filename']).to end_with('.wav')
    expect(result['lyrics']).to eq('') # instrumental → no lyrics
  end

  it 'returns success:false with the API error message on a non-200' do
    allow(Net::HTTP).to receive(:start).and_return(
      response('500', { 'error' => { 'message' => 'internal boom' } })
    )
    result = JSON.parse(helper.generate_music_with_lyria(prompt: 'x'))
    expect(result['success']).to be false
    expect(result['error']).to include('internal boom')
  end

  it 'returns success:false when no audio part is present' do
    allow(Net::HTTP).to receive(:start).and_return(
      response('200', { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'no audio here' }] } }] })
    )
    result = JSON.parse(helper.generate_music_with_lyria(prompt: 'x'))
    expect(result['success']).to be false
    expect(result['error']).to match(/No audio/i)
  end

  it 'errors cleanly when GEMINI_API_KEY is not configured' do
    stub_const('CONFIG', {})
    result = JSON.parse(helper.generate_music_with_lyria(prompt: 'x'))
    expect(result['success']).to be false
    expect(result['error']).to match(/GEMINI_API_KEY/)
  end
end
