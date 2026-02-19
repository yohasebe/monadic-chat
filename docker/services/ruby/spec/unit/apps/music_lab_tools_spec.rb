require_relative '../../spec_helper'
require 'json'

# Load MusicAdvisorTools and classes
app_base_dir = File.expand_path('../../../apps', __dir__)
tools_file = File.join(app_base_dir, 'music_advisor', 'music_advisor_tools.rb')
require tools_file if File.exist?(tools_file)

RSpec.describe 'MusicAdvisorTools' do
  describe 'Class definitions' do
    it 'defines MusicAdvisorOpenAI class' do
      expect(Object.const_defined?('MusicAdvisorOpenAI')).to be true
    end

    it 'defines MusicAdvisorClaude class' do
      expect(Object.const_defined?('MusicAdvisorClaude')).to be true
    end

    it 'MusicAdvisorOpenAI includes MusicAdvisorTools' do
      expect(MusicAdvisorOpenAI.ancestors).to include(MusicAdvisorTools)
    end

    it 'MusicAdvisorClaude includes MusicAdvisorTools' do
      expect(MusicAdvisorClaude.ancestors).to include(MusicAdvisorTools)
    end
  end

  describe 'Tool method availability' do
    let(:openai_instance) { MusicAdvisorOpenAI.new }
    let(:claude_instance) { MusicAdvisorClaude.new }

    %i[play_chord play_scale play_interval play_progression generate_backing_track].each do |method|
      it "MusicAdvisorOpenAI responds to #{method}" do
        expect(openai_instance).to respond_to(method)
      end

      it "MusicAdvisorClaude responds to #{method}" do
        expect(claude_instance).to respond_to(method)
      end
    end
  end

  describe 'Method signatures' do
    let(:instance) { MusicAdvisorOpenAI.new }

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
    let(:instance) { MusicAdvisorOpenAI.new }

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
    let(:instance) { MusicAdvisorOpenAI.new }

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
    let(:instance) { MusicAdvisorOpenAI.new }
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
    let(:instance) { MusicAdvisorOpenAI.new }
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
    let(:instance) { MusicAdvisorOpenAI.new }
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

  describe 'orchestration flag' do
    it 'MusicAdvisorOpenAI does not set @clear_orchestration_history (multi-turn conversation)' do
      instance = MusicAdvisorOpenAI.new
      expect(instance.instance_variable_get(:@clear_orchestration_history)).to be_nil
    end

    it 'MusicAdvisorClaude does not set @clear_orchestration_history (multi-turn conversation)' do
      instance = MusicAdvisorClaude.new
      expect(instance.instance_variable_get(:@clear_orchestration_history)).to be_nil
    end
  end
end
