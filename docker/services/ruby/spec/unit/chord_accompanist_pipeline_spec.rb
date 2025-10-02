require 'rspec'
require 'json'

CONFIG = Hash.new { |hash, key| hash[key] = nil } unless defined?(CONFIG)

require_relative '../../lib/monadic/app'
require_relative '../../apps/chord_accompanist/chord_accompanist_tools'

RSpec.describe ChordAccompanist::Pipeline do
  let(:app) { ChordAccompanist.new }

  it 'builds an accompaniment from fully specified requirements without external calls' do
    allow_any_instance_of(ChordAccompanist).to receive(:check_with_abcjs).and_return({ success: true })
    allow_any_instance_of(described_class).to receive(:request_json_from_model).and_raise('did not expect API call')

    requirements = {
      'tempo' => 100,
      'time_signature' => '4/4',
      'key' => 'C',
      'instrument' => 'Piano',
      'feel' => 'ballad',
      'style' => 'arpeggio',
      'length_bars' => 8,
      'sections' => [
        { 'name' => 'Verse', 'repeat' => 1, 'bars' => %w[C Am F G] },
        { 'name' => 'Chorus', 'repeat' => 1, 'bars' => %w[F G C C] }
      ]
    }

    response_json = app.run_multi_agent_pipeline(
      context: 'Create a gentle piano accompaniment',
      requirements: requirements
    )

    response = JSON.parse(response_json)

    expect(response['success']).to eq(true)
    expect(response['pattern']).to eq('arpeggio')
    expect(response['abc_code']).to include('X:1')
    expect(response['abc_code']).to include('|]')
    expect(response['requirements']['tempo']).to eq(100)
  end

  it 'falls back to deterministic defaults when upstream agents fail' do
    allow_any_instance_of(ChordAccompanist).to receive(:check_with_abcjs).and_return({ success: true })
    allow_any_instance_of(described_class).to receive(:request_json_from_model).and_return({ success: false, error: 'timeout' })

    response_json = app.run_multi_agent_pipeline(
      context: 'Soft rock groove with gentle feel'
    )

    response = JSON.parse(response_json)

    expect(response['success']).to eq(true)
    expect(response['requirements']['tempo']).to eq(120)
    expect(response['progression']['sections'].first['bars']).not_to be_empty
    expect(response['validation']['success']).to eq(true)
    expect(response['assumptions']).to include('Filled missing requirements using local defaults due to upstream failure.')
  end

  it 'parses structured notes payload without additional agent calls' do
    allow_any_instance_of(ChordAccompanist).to receive(:check_with_abcjs).and_return({ success: true })
    expect_any_instance_of(described_class).not_to receive(:request_json_from_model)

    structured_notes = <<~TEXT
      requirements: {"tempo_bpm":74,"time_signature":"4/4","key":"C","instrument":"Piano","feel":"Let It Be","length_bars":16}
      progression_hint: ["C","G","Am","F","C","G","F","C","C","G","Am","F","C","G","F","C"]
      reference_tracks: ["The Beatles - Let It Be"]
    TEXT

    response_json = app.run_multi_agent_pipeline(
      context: 'Beatles Let It Be style accompaniment',
      notes: structured_notes
    )

    response = JSON.parse(response_json)

    expect(response['success']).to eq(true)
    expect(response['requirements']['tempo']).to eq(74)
    expect(response['requirements']['length_bars']).to eq(16)
    bars = response['progression']['sections'].first['bars']
    expect(bars.length).to eq(16)
    expect(bars.first).to eq('C')
  end
end
