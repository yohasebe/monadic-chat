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

  # The interpretive lens (Gemini) once fabricated instrumentation — naming
  # instruments that were not in the recording (e.g. a rhythm guitar in a
  # lead+bass+drums solo). These pin the dedicated, instrumentation-specific
  # guardrails so the general "don't invent" line can't quietly regress back
  # to being the only defense.
  describe '#build_critique_prompt (instrumentation guardrails)' do
    let(:prompt) { tool.send(:build_critique_prompt, nil) }

    it 'calls out instrumentation as a high-risk area for confident mistakes' do
      expect(prompt).to match(/Instrumentation/i)
      expect(prompt).to match(/clearly and directly hear/i)
    end

    it 'forbids inferring instruments from genre/style/convention' do
      expect(prompt).to match(/do not infer instruments from the genre/i)
      expect(prompt).to match(/convention is not evidence/i)
    end

    it 'tells the model to describe the sound instead of naming an uncertain instrument' do
      expect(prompt).to match(/describe the sound/i)
      expect(prompt).to match(/register, timbre, and role/i)
    end

    it 'biases toward under-counting rather than inventing parts' do
      expect(prompt).to match(/under-counting/i)
      expect(prompt).to match(/than inventing one/i)
    end

    # Dogfood (2026-06-10): the critique attributed a "wah / envelope filter"
    # to a lead tone that used only heavy distortion — fluid legato runs can
    # resemble a filter sweep. Effects attribution is as error-prone as
    # instrument naming, so pin the dedicated caution.
    it 'forbids asserting effects/signal processing that may be playing technique' do
      expect(prompt).to match(/effects and signal processing/i)
      expect(prompt).to match(/do not assert their use/i)
      expect(prompt).to match(/closely resemble a filter sweep/i)
    end
  end

  # Calibration follow-up: keep the critique inside what 16 kHz mono can defend.
  # The trigger was a confident genre verdict ("funk-rock and blues-rock") on an
  # 80s hard-rock solo — not a bandwidth issue but over-confident interpretation.
  describe '#build_critique_prompt (genre/bandwidth calibration)' do
    let(:prompt) { tool.send(:build_critique_prompt, nil) }

    it 'forbids production / sound-quality judgements (out of 16 kHz mono range)' do
      expect(prompt).to match(/production judgement/i)
      expect(prompt).to match(/16 ?kHz mono/i)
    end

    it 'requires genre to be hedged, not asserted as a fact' do
      expect(prompt).to match(/Genre\/style is an INFERENCE/i)
      expect(prompt).to match(/never state one genre as a fact/i)
    end

    it 'separates what is heard from what is inferred' do
      expect(prompt).to match(/Keep what you HEAR separate from what you INFER/i)
    end

    it 'still preserves vivid description of the playing (no flattening)' do
      expect(prompt).to match(/do not flatten the prose/i)
    end

    # Candor countermeasures live in the PROMPT, not in sampling: the Gemini 3
    # guide mandates default temperature 1.0, and a 0.2 experiment produced
    # praise bias (dropped a real timing-rush observation) before being reverted.
    it 'requires both strengths and concrete weaknesses (praise-only is incomplete)' do
      expect(prompt).to match(/critique that only praises is incomplete/i)
      expect(prompt).to match(/BOTH notable strengths AND concrete weaknesses/i)
    end

    it 'requires plainly naming instability like timing rush or pitch drift' do
      expect(prompt).to match(/timing that rushes or drags/i)
      expect(prompt).to match(/never soften a real observation into a compliment/i)
    end
  end

  # Orchestrator (MDSL) side: the conversational Gemini that synthesizes the
  # final answer is the second place overreach can creep in, so its system
  # prompt must relay the critique faithfully and keep the lenses separated.
  describe 'orchestrator system prompt (music_analyst_gemini.mdsl)' do
    let(:mdsl) do
      path = File.expand_path('../../../apps/music_analyst/music_analyst_gemini.mdsl', __dir__)
      File.read(path)
    end

    it 'tells the orchestrator to relay the critique without adding overreach' do
      expect(mdsl).to match(/Relay the critique faithfully/i)
      expect(mdsl).to match(/do NOT introduce new interpretations/i)
    end

    it 'requires interpretive claims to be attributed, not stated as measured fact' do
      expect(mdsl).to match(/Attribute interpretive claims/i)
    end

    it 'keeps the objective section free of interpretation' do
      expect(mdsl).to match(/Keep the sections clean/i)
      expect(mdsl).to match(/ONLY numbers from `analyze_audio_features`/i)
    end

    # The orchestrator never hears the audio (only critique_audio's Gemini
    # call does), so follow-up questions about how the recording sounds must
    # re-invoke the tool instead of eliciting fresh "listening" impressions.
    it 'requires re-calling critique_audio for new listening questions' do
      expect(mdsl).to match(/You cannot hear the audio yourself/i)
      expect(mdsl).to match(/call `critique_audio` again/i)
    end
  end

  describe '#analyze_audio_features' do
    # The audio path is gated on the optional Audio Analysis package; treat it
    # as installed for the formatting/parsing tests below.
    before { stub_const("CONFIG", { "PYOPT_LIBROSA" => "true" }) }

    it 'points the user to Install Options when the Audio Analysis package is off (audio file)' do
      stub_const("CONFIG", { "PYOPT_LIBROSA" => "false" })
      expect(tool).not_to receive(:send_command)
      result = tool.analyze_audio_features(file_path: "song.mp3")
      expect(result).to match(/❌.*Audio Analysis package/)
      expect(result).to match(/Install Options/)
    end

    it 'still analyzes MIDI when the audio package is off (MIDI uses pretty_midi)' do
      stub_const("CONFIG", { "PYOPT_LIBROSA" => "false" })
      allow(tool).to receive(:send_command).and_return('{"success": false, "error": "pretty_midi is not installed."}')
      # Gate does not short-circuit MIDI; the script self-reports instead.
      expect(tool.analyze_audio_features(file_path: "song.mid")).to match(/pretty_midi/)
    end

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

    it 'drops spurious brief No-Chord blips but keeps longer N.C. spans (and survives nil duration)' do
      json = {
        "success" => true, "file_type" => "audio", "duration_seconds" => 12,
        "tempo" => { "bpm" => 120 }, "key" => { "key" => "C", "mode" => "major" },
        "time_signature" => { "beats_per_bar" => 4, "note_value" => 4 },
        "chords" => [
          { "chord" => "N.C.", "duration" => 0.3 }, # brief blip → dropped
          { "chord" => "C", "duration" => 2.0 },
          { "chord" => "N.C." },                    # nil duration → treated as brief, dropped (no crash)
          { "chord" => "C", "duration" => 1.5 },    # adjacent to prior C after drop → collapses
          { "chord" => "N.C.", "duration" => 3.0 }  # long N.C. → kept
        ]
      }.to_json
      allow(tool).to receive(:send_command).and_return(json)

      result = tool.analyze_audio_features(file_path: "solo.mp3")
      expect(result).to include("Chords: C - N.C.")
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
