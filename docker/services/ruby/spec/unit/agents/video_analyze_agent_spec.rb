# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/image_analysis_agent'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'
require_relative '../../../lib/monadic/agents/video_analyze_agent'

RSpec.describe VideoAnalyzeAgent do
  # Define a test helper class at file scope to avoid constant redefinition warnings
  let(:test_class) do
    Class.new do
      include ImageAnalysisAgent
      include AudioTranscriptionAgent
      include VideoAnalyzeAgent

      attr_accessor :settings

      def initialize
        @settings = { "provider" => "openai", "model" => "gpt-4.1" }
      end

      def session
        @session ||= { parameters: {} }
      end

      # Mock send_command — only used for extract_frames.py (Python container)
      def send_command(command:, container:)
        if command.include?("extract_frames.py")
          <<~OUTPUT
            13 frames extracted
            Base64-encoded frames saved to ./frames_20250629_154801.json
            Audio extracted to ./audio_20250629_154802.mp3
          OUTPUT
        else
          "Unknown command"
        end
      end

      # Mock audio_transcription_agent (replaces stt_query.rb delegation)
      def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
        "Hello world, this is the audio transcript."
      end
    end
  end

  before do
    # Define SHARED_VOL and LOCAL_SHARED_VOL on MonadicApp if not already defined,
    # so the agent module can resolve paths
    stub_const("SHARED_VOL", "/monadic/data") unless defined?(SHARED_VOL)
    stub_const("LOCAL_SHARED_VOL", File.expand_path(File.join(Dir.home, "monadic", "data"))) unless defined?(LOCAL_SHARED_VOL)
  end

  let(:agent) { test_class.new }

  # Sample frames data (small base64 PNG stubs)
  let(:sample_frames) { ["iVBORw0KGgo=", "iVBORw0KGgo=", "iVBORw0KGgo="] }
  let(:sample_frames_json) { JSON.generate(sample_frames) }

  before do
    # Also stub CONFIG
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test-openai-key",
      "EXTRA_LOGGING" => nil
    })
  end

  describe '#analyze_video' do
    context 'when video processing is successful' do
      before do
        # Stub file reading for frames JSON
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_20250629_154801.json").and_return(sample_frames_json)

        # Stub Vision API call
        allow(agent).to receive(:video_vision_openai).and_return("This is a video showing a deer crossing the road.")
      end

      it 'extracts frames and returns video description with audio transcript' do
        result = agent.analyze_video(file: "test.mp4", fps: 1, query: "What is happening?")

        expect(result).to include("This is a video showing a deer crossing the road")
        expect(result).to include("Audio Transcript:")
        expect(result).to include("Hello world")
      end

      it 'handles video without query parameter' do
        result = agent.analyze_video(file: "test.mp4", fps: 1)

        expect(result).to include("This is a video showing a deer crossing the road")
      end

      it 'only calls send_command for extract_frames (no video_query or stt_query)' do
        allow(agent).to receive(:send_command).and_call_original

        agent.analyze_video(file: "test.mp4", fps: 1)

        # send_command should only be called for extract_frames.py
        expect(agent).to have_received(:send_command).with(hash_including(command: /extract_frames\.py/))
        expect(agent).not_to have_received(:send_command).with(hash_including(command: /video_query\.rb/))
        expect(agent).not_to have_received(:send_command).with(hash_including(command: /stt_query\.rb/))
      end
    end

    context 'when frame extraction fails' do
      it 'returns error message when no JSON file is found' do
        allow(agent).to receive(:send_command).and_return("Error: Failed to extract frames")

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Error: Failed to extract frames from video")
      end
    end

    context 'when file parameter is missing' do
      it 'returns error message for nil' do
        result = agent.analyze_video(file: nil)
        expect(result).to eq("Error: file is required.")
      end

      it 'returns error message for empty string' do
        result = agent.analyze_video(file: "")
        expect(result).to eq("Error: file is required.")
      end
    end

    context 'when frames JSON file is not found' do
      before do
        local_shared = File.expand_path(File.join(Dir.home, "monadic", "data"))
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with(File.join(local_shared, "frames_20250629_154801.json")).and_return(false)
      end

      it 'returns error about missing file' do
        result = agent.analyze_video(file: "test.mp4")
        expect(result).to include("ERROR: Frames JSON file not found")
      end
    end

    context 'output without audio file' do
      before do
        allow(agent).to receive(:send_command).with(hash_including(container: "python")).and_return(
          "15 frames extracted\nBase64-encoded frames saved to ./frames_only.json"
        )
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_only.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_only.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_only.json").and_return(sample_frames_json)
        allow(agent).to receive(:video_vision_openai).and_return("Video description only")
      end

      it 'returns description without audio transcript' do
        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video description only")
        expect(result).not_to include("Audio Transcript:")
      end
    end

    context 'error handling' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_20250629_154801.json").and_return(sample_frames_json)
      end

      it 'returns video analysis error when Vision API fails' do
        allow(agent).to receive(:video_vision_openai).and_return("ERROR: OpenAI Vision API error (500): Internal server error")

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video analysis failed:")
      end

      it 'includes audio error in output when audio transcription fails' do
        allow(agent).to receive(:video_vision_openai).and_return("Video description")
        allow(agent).to receive(:send_command).with(hash_including(container: "python")).and_return(
          "Base64-encoded frames saved to ./frames_20250629_154801.json\nAudio extracted to ./audio.mp3"
        )
        allow(agent).to receive(:audio_transcription_agent).and_return(
          "ERROR: Failed to transcribe audio"
        )

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video description")
        expect(result).to include("Audio transcription failed:")
      end
    end
  end

  describe '#balance_frames' do
    it 'evenly samples frames when over limit' do
      frames = (1..10).map(&:to_s)
      result = agent.send(:balance_frames, frames, 5)

      expect(result.size).to eq(5)
      expect(result.first).to eq("1")
      expect(result.last).to eq("10")
    end

    it 'handles single-frame edge case' do
      frames = ["1"]
      # balance_frames with max_frames=1 should return the single frame
      result = agent.send(:balance_frames, frames, 1)

      expect(result.size).to eq(1)
      expect(result.first).to eq("1")
    end
  end

  describe '#read_frames_json' do
    it 'strips data URL prefixes from frames' do
      frames_with_prefix = [
        "data:image/png;base64,iVBORw0KGgo=",
        "iVBORw0KGgo="
      ]
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/test/frames.json").and_return(true)
      allow(File).to receive(:read).with("/test/frames.json").and_return(JSON.generate(frames_with_prefix))

      result = agent.send(:read_frames_json, "/test/frames.json")

      expect(result).to eq(["iVBORw0KGgo=", "iVBORw0KGgo="])
    end

    it 'returns error for invalid JSON' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/test/frames.json").and_return(true)
      allow(File).to receive(:read).with("/test/frames.json").and_return("not json")

      result = agent.send(:read_frames_json, "/test/frames.json")

      expect(result).to start_with("ERROR: Failed to parse frames JSON")
    end
  end

  describe '#video_vision_query' do
    before do
      allow(File).to receive(:exist?).and_call_original
    end

    it 'uses resolve_vision_provider to determine provider' do
      allow(agent).to receive(:resolve_vision_provider).and_return("openai")
      allow(agent).to receive(:video_vision_openai).and_return("Description")

      result = agent.send(:video_vision_query, "What happens?", sample_frames)

      expect(result).to eq("Description")
      expect(agent).to have_received(:resolve_vision_provider)
    end

    it 'applies per-provider frame limits' do
      agent.settings["provider"] = "anthropic"
      stub_const("CONFIG", {
        "ANTHROPIC_API_KEY" => "test-claude-key",
        "EXTRA_LOGGING" => nil
      })

      # 30 frames should be reduced to 20 for Claude
      many_frames = (1..30).map { "iVBORw0KGgo=" }
      allow(agent).to receive(:video_vision_claude).and_return("Description")

      agent.send(:video_vision_query, "What happens?", many_frames)

      # The frames passed to video_vision_claude should be limited to 20
      expect(agent).to have_received(:video_vision_claude) do |_query, frames, _model, _key|
        expect(frames.size).to eq(20)
      end
    end
  end
end
