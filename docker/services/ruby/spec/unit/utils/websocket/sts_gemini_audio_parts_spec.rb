# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/websocket'

RSpec.describe 'The audio of a Gemini Live Conversation reply' do
  let(:host) { Class.new { include WebSocketHelper }.new }

  def audio_of(parts, g = {})
    host.send(:sts_gemini_audio_parts, g, parts)
  end

  it 'plays inline data of an audio type, and inline data with no type' do
    parts = [{ 'inlineData' => { 'mimeType' => 'audio/pcm;rate=24000', 'data' => 'AAAA' } },
             { 'inlineData' => { 'data' => 'BBBB' } }]
    expect(audio_of(parts)).to eq(%w[AAAA BBBB])
  end

  it 'does not play data of another type, or parts with no data' do
    parts = [{ 'inlineData' => { 'mimeType' => 'image/png', 'data' => 'UElD' } },
             { 'text' => 'words' }, { 'inlineData' => { 'mimeType' => 'audio/pcm' } }, 'junk', nil]
    expect(audio_of(parts)).to eq([])
    expect(audio_of(nil)).to eq([])
  end

  it 'counts the chunks of an odd number of bytes' do
    g = {}
    # 'AAA=' is two bytes, 'AA==' one, 'AAAA' three.
    audio_of([{ 'inlineData' => { 'data' => 'AAA=' } }, { 'inlineData' => { 'data' => 'AA==' } },
              { 'inlineData' => { 'data' => 'AAAA' } }], g)
    expect(g[:odd_audio]).to eq(2)
  end

  it 'takes the audio of a reply through the translation of its frames' do
    state = { provider: 'gemini', gemini: { item_seq: 0, resp_seq: 0 } }
    frame = { 'serverContent' => { 'modelTurn' => { 'parts' => [
      { 'inlineData' => { 'mimeType' => 'image/png', 'data' => 'UElD' } },
      { 'inlineData' => { 'mimeType' => 'audio/pcm;rate=24000', 'data' => 'AAAA' } }
    ] } } }
    deltas = host.send(:sts_translate_events, state, frame).select { |e| e['type'] == 'response.output_audio.delta' }
    expect(deltas.map { |e| e['delta'] }).to eq(['AAAA'])
  end
end
