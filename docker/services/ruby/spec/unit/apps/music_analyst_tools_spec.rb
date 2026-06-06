# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../apps/music_analyst/music_analyst_tools'

RSpec.describe MusicAnalystTools do
  let(:test_class) do
    Class.new do
      include MusicAnalystTools
      # Stand-in for the MonadicApp#send_command provided at runtime.
      def send_command(command:, container:)
        ''
      end
    end
  end
  let(:tool) { test_class.new }

  describe '#critique_audio' do
    it 'rejects MIDI files (critique is audio-only)' do
      expect(tool.critique_audio(file_path: "song.mid")).to match(/supports audio only/)
    end

    it 'delegates audio files to AudioAnalysisAgent with a critique prompt and resolved path' do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/monadic/data")
      expect(AudioAnalysisAgent).to receive(:analyze) do |audio_path:, prompt:, model:|
        expect(audio_path).to eq("/monadic/data/perf.mp3")
        expect(prompt).to match(/interpretive, qualitative critique/i)
        expect(model).to match(/\Agemini-/) # resolved from SSOT (default_audio_model)
        "critique text"
      end
      expect(tool.critique_audio(file_path: "perf.mp3")).to eq("critique text")
    end

    it 'weaves a requested focus into the prompt' do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/monadic/data")
      allow(AudioAnalysisAgent).to receive(:analyze) { |prompt:, **_| prompt }
      result = tool.critique_audio(file_path: "perf.mp3", focus: "intonation")
      expect(result).to match(/Additional focus requested.*intonation/m)
    end
  end

  describe '#analyze_audio_features' do
    it 'formats the nested analyzer JSON, collapsing repeated chords' do
      json = {
        "success" => true, "file_type" => "audio", "duration_seconds" => 125,
        "tempo" => { "bpm" => 92.3 },
        "key" => { "key" => "D", "mode" => "minor" },
        "time_signature" => { "beats_per_bar" => 4, "note_value" => 4 },
        "chords" => [{ "chord" => "Dm" }, { "chord" => "Dm" }, { "chord" => "Gm" }, { "chord" => "A7" }],
        "sections" => [{ "label" => "intro" }, { "label" => "verse" }],
        "description" => "A melancholic piece."
      }.to_json
      allow(tool).to receive(:send_command).and_return(json)

      result = tool.analyze_audio_features(file_path: "song.mp3")

      expect(result).to include("Duration: 2:05")
      expect(result).to include("Tempo: 92.3 BPM")
      expect(result).to include("Key: D minor")
      expect(result).to include("Time signature: 4/4")
      expect(result).to include("Dm - Gm - A7") # consecutive Dm collapsed
      expect(result).to include("Sections: intro, verse")
      expect(result).to include("A melancholic piece.")
    end

    it 'includes MIDI track names when present' do
      json = {
        "success" => true, "file_type" => "midi", "duration_seconds" => 60,
        "tempo" => { "bpm" => 120 }, "key" => { "key" => "C", "mode" => "major" },
        "time_signature" => { "beats_per_bar" => 4, "note_value" => 4 },
        "tracks" => [{ "name" => "Piano", "instrument" => "Acoustic Grand" }, { "instrument" => "Bass" }]
      }.to_json
      allow(tool).to receive(:send_command).and_return(json)

      result = tool.analyze_audio_features(file_path: "song.mid")
      expect(result).to include("Tracks: Piano, Bass")
    end

    it 'returns a tool error when the analyzer reports failure' do
      allow(tool).to receive(:send_command).and_return('{"success": false, "error": "bad file"}')
      expect(tool.analyze_audio_features(file_path: "x.mp3")).to match(/❌.*bad file/)
    end

    it 'returns a tool error when the analyzer output has no JSON' do
      allow(tool).to receive(:send_command).and_return('Traceback: boom')
      expect(tool.analyze_audio_features(file_path: "x.mp3")).to match(/❌/)
    end
  end
end
