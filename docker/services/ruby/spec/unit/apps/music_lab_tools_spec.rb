require_relative '../../spec_helper'
require 'json'

# Load MusicLabTools and classes
app_base_dir = File.expand_path('../../../apps', __dir__)
tools_file = File.join(app_base_dir, 'music_lab', 'music_lab_tools.rb')
require tools_file if File.exist?(tools_file)

RSpec.describe 'MusicLabTools' do
  describe 'Class definitions' do
    it 'defines MusicLabOpenAI class' do
      expect(Object.const_defined?('MusicLabOpenAI')).to be true
    end

    it 'defines MusicLabClaude class' do
      expect(Object.const_defined?('MusicLabClaude')).to be true
    end

    it 'defines MusicLabGemini class' do
      expect(Object.const_defined?('MusicLabGemini')).to be true
    end

    it 'defines MusicLabGrok class' do
      expect(Object.const_defined?('MusicLabGrok')).to be true
    end

    it 'MusicLabOpenAI includes MusicLabTools' do
      expect(MusicLabOpenAI.ancestors).to include(MusicLabTools)
    end

    it 'MusicLabClaude includes MusicLabTools' do
      expect(MusicLabClaude.ancestors).to include(MusicLabTools)
    end

    it 'MusicLabGemini includes MusicLabTools' do
      expect(MusicLabGemini.ancestors).to include(MusicLabTools)
    end

    it 'MusicLabGrok includes MusicLabTools' do
      expect(MusicLabGrok.ancestors).to include(MusicLabTools)
    end
  end

  describe 'Tool method availability' do
    let(:openai_instance) { MusicLabOpenAI.new }
    let(:claude_instance) { MusicLabClaude.new }
    let(:gemini_instance) { MusicLabGemini.new }
    let(:grok_instance) { MusicLabGrok.new }

    %i[play_chord play_scale play_interval play_progression generate_backing_track].each do |method|
      it "MusicLabOpenAI responds to #{method}" do
        expect(openai_instance).to respond_to(method)
      end

      it "MusicLabClaude responds to #{method}" do
        expect(claude_instance).to respond_to(method)
      end

      it "MusicLabGemini responds to #{method}" do
        expect(gemini_instance).to respond_to(method)
      end

      it "MusicLabGrok responds to #{method}" do
        expect(grok_instance).to respond_to(method)
      end
    end
  end

  describe 'Method signatures' do
    let(:instance) { MusicLabOpenAI.new }

    it 'play_chord accepts chord_name, voicing, instrument, octave, session' do
      method = instance.method(:play_chord)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:chord_name)
      expect(param_names).to include(:voicing)
      expect(param_names).to include(:instrument)
      expect(param_names).to include(:octave)
      expect(param_names).to include(:session)
    end

    it 'play_scale accepts scale_name, root, octave, direction, instrument, session' do
      method = instance.method(:play_scale)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:scale_name)
      expect(param_names).to include(:root)
      expect(param_names).to include(:direction)
    end

    it 'play_interval accepts root, interval, octave, instrument, session' do
      method = instance.method(:play_interval)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:root)
      expect(param_names).to include(:interval)
    end

    it 'play_progression accepts chords, tempo, instrument, bars_per_chord, octave, session' do
      method = instance.method(:play_progression)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:chords)
      expect(param_names).to include(:tempo)
    end

    it 'generate_backing_track accepts chords, tempo, style, bars, instruments, octave, melody, melody_instrument, melody_style, melody_seed, session' do
      method = instance.method(:generate_backing_track)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:chords)
      expect(param_names).to include(:style)
      expect(param_names).to include(:instruments)
      expect(param_names).to include(:melody)
      expect(param_names).to include(:melody_instrument)
      expect(param_names).to include(:melody_style)
      expect(param_names).to include(:melody_seed)
    end
  end

  describe '#build_music_command' do
    let(:instance) { MusicLabOpenAI.new }

    it 'builds a correct CLI command for chord action' do
      cmd = instance.send(:build_music_command, "chord", { "chord_name" => "Cmaj7" })
      expect(cmd).to include("music_generator.py")
      expect(cmd).to include("chord")
      expect(cmd).to include("Cmaj7")
    end

    it 'builds a correct CLI command for scale action' do
      cmd = instance.send(:build_music_command, "scale", { "scale_name" => "major", "root" => "C" })
      expect(cmd).to include("music_generator.py")
      expect(cmd).to include("scale")
      expect(cmd).to include("major")
    end

    it 'properly escapes JSON parameters' do
      cmd = instance.send(:build_music_command, "chord", { "chord_name" => "F#dim7" })
      # Shellwords.escape escapes # character, so check the escaped form
      expect(cmd).to include("dim7")
      expect(cmd).to include("music_generator.py")
      expect(cmd).to include("--params")
    end

    it 'includes melody parameter in backing command when provided' do
      params = { "chords" => ["Am", "G"], "melody" => "E5:1 D5:0.5 C5:0.5", "melody_instrument" => "strings" }
      cmd = instance.send(:build_music_command, "backing", params)
      expect(cmd).to include("backing")
      expect(cmd).to include("melody")
      expect(cmd).to include("E5:1")
      expect(cmd).to include("strings")
    end

    it 'includes melody_style in backing command when provided' do
      params = { "chords" => ["Dm7", "G7", "Cmaj7"], "melody_style" => "jazz" }
      cmd = instance.send(:build_music_command, "backing", params)
      expect(cmd).to include("backing")
      expect(cmd).to include("melody_style")
      expect(cmd).to include("jazz")
    end

    it 'includes melody_seed in backing command when provided' do
      params = { "chords" => ["Am", "G"], "melody_style" => "lyrical", "melody_seed" => 42 }
      cmd = instance.send(:build_music_command, "backing", params)
      expect(cmd).to include("melody_seed")
      expect(cmd).to include("42")
    end
  end

  describe '#parse_music_result' do
    let(:instance) { MusicLabOpenAI.new }

    it 'parses valid JSON output' do
      json = '{"success": true, "abc": "X:1", "description": "Cmaj7", "notes": ["C4", "E4"]}'
      result = instance.send(:parse_music_result, json)
      expect(result["success"]).to be true
      expect(result["abc"]).to eq("X:1")
      expect(result["notes"]).to eq(["C4", "E4"])
    end

    it 'handles JSON with prefix text from send_command' do
      output = "Command has been executed with the following output: \n{\"success\": true, \"abc\": \"X:1\"}"
      result = instance.send(:parse_music_result, output)
      expect(result["success"]).to be true
    end

    it 'returns error for empty output' do
      result = instance.send(:parse_music_result, "")
      expect(result["success"]).to be false
      expect(result["error"]).to include("No output")
    end

    it 'returns error for nil output' do
      result = instance.send(:parse_music_result, nil)
      expect(result["success"]).to be false
    end

    it 'returns error for invalid JSON' do
      result = instance.send(:parse_music_result, "not json at all")
      expect(result["success"]).to be false
      expect(result["error"]).to include("Failed to parse")
    end

    it 'parses error response from Python' do
      json = '{"success": false, "error": "Unknown chord quality: xyz"}'
      result = instance.send(:parse_music_result, json)
      expect(result["success"]).to be false
      expect(result["error"]).to include("Unknown chord")
    end
  end

  describe '#run_music_action' do
    let(:instance) { MusicLabOpenAI.new }
    let(:session) { { parameters: {} } }

    it 'returns text description and stores ABC HTML in session' do
      json_output = '{"success": true, "abc": "X:1\nT:Cmaj7\nM:4/4\nL:1/8\nQ:1/4=120\nK:C clef=treble\n| [CEG]4 z4 |", "description": "Cmaj7 chord, root position, piano", "notes": ["C4", "E4", "G4"]}'
      allow(instance).to receive(:send_command).and_return(json_output)

      result = instance.send(:run_music_action, "chord", { "chord_name" => "Cmaj7" }, session)
      expect(result).to be_a(String)
      expect(result).to include("Cmaj7 chord, root position, piano")
      expect(result).to include("Notes: C4, E4, G4")
      # ABC is NOT in the text return — it's stored in session for post-response injection
      expect(result).not_to include("X:1")
      expect(session[:tool_html_fragments]).to be_a(Array)
      html = session[:tool_html_fragments].first
      expect(html).to include("abc-code")
      expect(html).to include("X:1")
    end

    it 'returns text without storing fragments when session is nil' do
      json_output = '{"success": true, "abc": "X:1\nT:C\nM:4/4\nL:1/8\nK:C\n| [CEG]4 z4 |", "description": "C chord", "notes": ["C4"]}'
      allow(instance).to receive(:send_command).and_return(json_output)

      result = instance.send(:run_music_action, "chord", { "chord_name" => "C" }, nil)
      expect(result).to be_a(String)
      expect(result).to include("C chord")
    end

    it 'returns error text on failure' do
      json_output = '{"success": false, "error": "Unknown chord quality: xyz"}'
      allow(instance).to receive(:send_command).and_return(json_output)

      result = instance.send(:run_music_action, "chord", { "chord_name" => "Cxyz" }, session)
      expect(result).to be_a(String)
      expect(result).to start_with("Error:")
      expect(result).to include("Unknown chord")
    end

    it 'returns error text on exception' do
      allow(instance).to receive(:send_command).and_raise(RuntimeError, "container not found")

      result = instance.send(:run_music_action, "chord", { "chord_name" => "C" }, session)
      expect(result).to be_a(String)
      expect(result).to start_with("Error:")
      expect(result).to include("container not found")
    end
  end

  describe '#generate_backing_track melody forwarding' do
    let(:instance) { MusicLabOpenAI.new }
    let(:session) { { parameters: {} } }

    it 'forwards melody and melody_instrument to the command' do
      allow(instance).to receive(:send_command) do |command:, container:|
        # Verify that the command includes melody params
        expect(command).to include("melody")
        expect(command).to include("E5:1")
        expect(command).to include("vibraphone")
        '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track with melody", "notes": ["C4"]}'
      end

      instance.generate_backing_track(
        chords: ["Am", "G"],
        melody: "E5:1 D5:0.5 C5:0.5 B4:2",
        melody_instrument: "vibraphone",
        session: session
      )
    end

    it 'works without melody parameter (backward compatible)' do
      json_output = '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track", "notes": ["C4"]}'
      allow(instance).to receive(:send_command).and_return(json_output)

      result = instance.generate_backing_track(chords: ["C", "G"], session: session)
      expect(result).to include("Backing track")
    end
  end

  describe '#generate_backing_track melody_style forwarding' do
    let(:instance) { MusicLabOpenAI.new }
    let(:session) { { parameters: {} } }

    it 'forwards melody_style to the command' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).to include("melody_style")
        expect(command).to include("jazz")
        '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track with algorithmic melody", "notes": ["C4"]}'
      end

      instance.generate_backing_track(
        chords: ["Dm7", "G7", "Cmaj7"],
        style: "jazz",
        melody_style: "jazz",
        session: session
      )
    end

    it 'forwards melody_seed to the command' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).to include("melody_seed")
        expect(command).to include("42")
        '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track", "notes": ["C4"]}'
      end

      instance.generate_backing_track(
        chords: ["C", "Am", "F", "G"],
        melody_style: "lyrical",
        melody_seed: 42,
        session: session
      )
    end

    it 'does not include melody_style when not provided' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).not_to include("melody_style")
        '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track", "notes": ["C4"]}'
      end

      instance.generate_backing_track(chords: ["C", "G"], session: session)
    end

    it 'explicit melody takes priority over melody_style (both passed to Python)' do
      allow(instance).to receive(:send_command) do |command:, container:|
        # Both should be in the command; Python decides priority
        expect(command).to include("melody")
        expect(command).to include("E5:1")
        '{"success": true, "abc": "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n| C2 |", "description": "Backing track", "notes": ["C4"]}'
      end

      instance.generate_backing_track(
        chords: ["C", "Am"],
        melody: "E5:1 D5:0.5 C5:0.5",
        melody_style: "jazz",
        session: session
      )
    end
  end

  describe '#analyze_audio_file' do
    let(:instance) { MusicLabOpenAI.new }

    it 'responds to analyze_audio_file' do
      expect(instance).to respond_to(:analyze_audio_file)
    end

    it 'accepts file_path and session parameters' do
      method = instance.method(:analyze_audio_file)
      param_names = method.parameters.map(&:last)
      expect(param_names).to include(:file_path)
      expect(param_names).to include(:session)
    end

    it 'prefixes bare filename with /monadic/data/' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).to include("/monadic/data/song.mp3")
        '{"success": true, "file_type": "audio", "file_name": "song.mp3", "duration_seconds": 60, "tempo": {"bpm": 120}, "key": {"key": "C", "mode": "major", "confidence": 0.8}, "time_signature": {"beats_per_bar": 4, "note_value": 4}, "chords": [], "description": "Test"}'
      end

      instance.analyze_audio_file(file_path: "song.mp3")
    end

    it 'preserves full /monadic/data/ paths' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).to include("/monadic/data/subdir/song.mp3")
        expect(command).not_to include("/monadic/data//monadic/data/")
        '{"success": true, "file_type": "audio", "file_name": "song.mp3", "duration_seconds": 60, "tempo": {"bpm": 120}, "key": {"key": "C", "mode": "major", "confidence": 0.8}, "time_signature": {"beats_per_bar": 4, "note_value": 4}, "chords": [], "description": "Test"}'
      end

      instance.analyze_audio_file(file_path: "/monadic/data/subdir/song.mp3")
    end

    it 'invokes music_analyzer.py via send_command' do
      allow(instance).to receive(:send_command) do |command:, container:|
        expect(command).to include("music_analyzer.py")
        expect(command).to include("analyze")
        expect(container).to eq("python")
        '{"success": true, "file_type": "audio", "file_name": "test.mp3", "duration_seconds": 30, "tempo": {"bpm": 100}, "key": {"key": "A", "mode": "minor", "confidence": 0.7}, "time_signature": {"beats_per_bar": 4, "note_value": 4}, "chords": [], "description": "Test"}'
      end

      result = instance.analyze_audio_file(file_path: "test.mp3")
      expect(result).to be_a(String)
      expect(result).to include("Audio Analysis")
    end

    it 'returns formatted error on failure' do
      json_output = '{"success": false, "error": "File not found: /monadic/data/missing.mp3"}'
      allow(instance).to receive(:send_command).and_return(json_output)

      result = instance.analyze_audio_file(file_path: "missing.mp3")
      expect(result).to start_with("Error:")
      expect(result).to include("File not found")
    end

    it 'handles exceptions gracefully' do
      allow(instance).to receive(:send_command).and_raise(RuntimeError, "container unavailable")

      result = instance.analyze_audio_file(file_path: "test.mp3")
      expect(result).to start_with("Error:")
      expect(result).to include("container unavailable")
    end
  end

  describe '#format_analysis_result' do
    let(:instance) { MusicLabOpenAI.new }

    let(:audio_result) do
      {
        "success" => true,
        "file_type" => "audio",
        "file_name" => "song.mp3",
        "duration_seconds" => 195,
        "tempo" => { "bpm" => 120.5 },
        "key" => { "key" => "C", "mode" => "major", "confidence" => 0.85 },
        "time_signature" => { "beats_per_bar" => 4, "note_value" => 4 },
        "chords" => [
          { "time" => 0.0, "duration" => 2.0, "chord" => "C" },
          { "time" => 2.0, "duration" => 2.0, "chord" => "Am" }
        ],
        "description" => "Audio: 3:15, 120 BPM, C major"
      }
    end

    let(:midi_result) do
      {
        "success" => true,
        "file_type" => "midi",
        "file_name" => "piece.mid",
        "duration_seconds" => 180,
        "tempo" => { "bpm" => 140.0 },
        "key" => { "key" => "G", "mode" => "major", "source" => "midi_metadata" },
        "time_signature" => { "beats_per_bar" => 3, "note_value" => 4 },
        "tracks" => [
          { "name" => "Piano", "instrument" => "Acoustic Grand Piano", "note_count" => 342, "pitch_range" => "C3-C6", "is_drum" => false },
          { "name" => "Drums", "instrument" => "Drums", "note_count" => 456, "is_drum" => true }
        ],
        "chords" => [
          { "time" => 0.0, "duration" => 2.0, "chord" => "G" }
        ],
        "description" => "MIDI: 3:00, 140 BPM, G major"
      }
    end

    it 'formats audio analysis with confidence' do
      text = instance.send(:format_analysis_result, audio_result)
      expect(text).to include("Audio Analysis: song.mp3")
      expect(text).to include("Duration: 3:15")
      expect(text).to include("Tempo: 120.5 BPM")
      expect(text).to include("Key: C major (confidence: 85%)")
      expect(text).to include("Time Signature: 4/4")
    end

    it 'formats MIDI analysis with source' do
      text = instance.send(:format_analysis_result, midi_result)
      expect(text).to include("MIDI Analysis: piece.mid")
      expect(text).to include("Duration: 3:00")
      expect(text).to include("Tempo: 140.0 BPM")
      expect(text).to include("Key: G major (source: midi_metadata)")
      expect(text).to include("Time Signature: 3/4")
    end

    it 'formats MIDI tracks including drum tracks' do
      text = instance.send(:format_analysis_result, midi_result)
      expect(text).to include("## Tracks:")
      expect(text).to include("Piano (Acoustic Grand Piano) - 342 notes")
      expect(text).to include("C3-C6")
      expect(text).to include("Drums (Drums) - 456 hits")
    end

    it 'formats chord progression as bar-aligned chart' do
      text = instance.send(:format_analysis_result, audio_result)
      expect(text).to include("Chord Progression")
      # Bar-aligned chart uses pipe-separated cells with centered chord names
      expect(text).to match(/\|.*C.*\|/)
      expect(text).to match(/\|.*Am.*\|/)
      expect(text).to include("unique chords")
    end

    it 'includes sections when present' do
      result_with_sections = audio_result.merge(
        "sections" => [
          { "label" => "verse", "start" => 0.0, "end" => 30.0 },
          { "label" => "chorus", "start" => 30.0, "end" => 60.0 }
        ]
      )
      text = instance.send(:format_analysis_result, result_with_sections)
      expect(text).to include("## Sections:")
      expect(text).to include("Verse: 0:00 - 0:30")
      expect(text).to include("Chorus: 0:30 - 1:00")
    end

    it 'handles missing optional fields gracefully' do
      minimal_result = {
        "success" => true,
        "file_type" => "audio",
        "duration_seconds" => 0,
        "description" => "Minimal"
      }
      text = instance.send(:format_analysis_result, minimal_result)
      expect(text).to include("Audio Analysis: unknown")
      expect(text).to include("Duration: 0:00")
    end

    it 'renders many chords as bar-aligned chart with bar count' do
      many_chords = (0..90).step(2).map { |t| { "time" => t.to_f, "duration" => 2.0, "chord" => "C" } }
      result = audio_result.merge("chords" => many_chords)
      text = instance.send(:format_analysis_result, result)
      expect(text).to include("bars")
      expect(text).to include("unique chords")
      expect(text).to match(/\|.*C.*\|/)
    end
  end

  describe '#quantize_chords_to_bars' do
    let(:instance) { MusicLabOpenAI.new }

    it 'quantizes chords into bar positions based on tempo' do
      chords = [
        { "time" => 0.0, "duration" => 2.0, "chord" => "C" },
        { "time" => 2.0, "duration" => 2.0, "chord" => "Am" },
        { "time" => 4.0, "duration" => 2.0, "chord" => "F" },
        { "time" => 6.0, "duration" => 2.0, "chord" => "G" }
      ]
      # 120 BPM, 4/4 → bar_duration = 2.0s
      bars = instance.send(:quantize_chords_to_bars, chords, 120, 4)
      expect(bars).to eq(["C", "Am", "F", "G"])
    end

    it 'fills empty bars with preceding chord' do
      chords = [
        { "time" => 0.0, "duration" => 4.0, "chord" => "C" },
        { "time" => 4.0, "duration" => 4.0, "chord" => "G" }
      ]
      # 120 BPM, 4/4 → bar_duration = 2.0s, total ~4s = 4 bars
      bars = instance.send(:quantize_chords_to_bars, chords, 120, 4)
      expect(bars[0]).to eq("C")
      expect(bars[1]).to eq("C")
      expect(bars[2]).to eq("G")
    end

    it 'returns empty array for empty chords' do
      bars = instance.send(:quantize_chords_to_bars, [], 120, 4)
      expect(bars).to eq([])
    end

    it 'returns empty array for zero tempo' do
      chords = [{ "time" => 0.0, "duration" => 2.0, "chord" => "C" }]
      bars = instance.send(:quantize_chords_to_bars, chords, 0, 4)
      expect(bars).to eq([])
    end

    it 'caps at 200 bars maximum' do
      # Very slow tempo with long audio → many bars
      chords = (0..1000).step(1).map { |t| { "time" => t.to_f, "duration" => 1.0, "chord" => "C" } }
      bars = instance.send(:quantize_chords_to_bars, chords, 120, 4)
      expect(bars.length).to be <= 200
    end
  end

  describe 'orchestration flag' do
    it 'MusicLabOpenAI does not set @clear_orchestration_history (multi-turn conversation)' do
      instance = MusicLabOpenAI.new
      expect(instance.instance_variable_get(:@clear_orchestration_history)).to be_nil
    end

    it 'MusicLabClaude does not set @clear_orchestration_history (multi-turn conversation)' do
      instance = MusicLabClaude.new
      expect(instance.instance_variable_get(:@clear_orchestration_history)).to be_nil
    end
  end
end
