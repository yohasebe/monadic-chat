# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/agents/audio_analysis_agent'

RSpec.describe AudioAnalysisAgent do
  # The audio is a file of a temporary shared folder; the agent reads it
  # through SharedPathGuard.
  around do |example|
    Dir.mktmpdir("audio-analysis") do |dir|
      @root = File.join(dir, "data")
      @outside = File.join(dir, "outside")
      FileUtils.mkdir_p([@root, @outside])
      File.binwrite(File.join(@root, "perf.mp3"), "RAWBYTES")
      example.run
    end
  end

  before do
    stub_const("CONFIG", { "GEMINI_API_KEY" => "test-gemini-key" })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root)
  end

  let(:audio_path) { File.join(@root, "perf.mp3") }

  describe '.analyze' do
    context 'guards' do
      it 'errors when GEMINI_API_KEY is missing' do
        stub_const("CONFIG", {})
        result = described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.6-flash")
        expect(result).to match(/GEMINI_API_KEY not configured/)
      end

      it 'errors when the file does not exist' do
        result = described_class.analyze(audio_path: File.join(@root, "missing.mp3"), prompt: "x", model: "gemini-3.6-flash")
        expect(result).to match(/Audio file not found/)
      end

      it 'sends nothing from outside the shared folder when the file is a link' do
        File.write(File.join(@outside, "env"), "OPENAI_API_KEY=secret")
        File.symlink(File.join(@outside, "env"), File.join(@root, "link.mp3"))
        expect(described_class).not_to receive(:post_and_parse)
        result = described_class.analyze(audio_path: File.join(@root, "link.mp3"), prompt: "x", model: "gemini-3.6-flash")
        expect(result).to match(/Audio file not found/)
      end
    end

    context 'building the Gemini generateContent request' do

      it 'sends audio inline_data + the prompt and returns the model text' do
        captured = {}
        allow(described_class).to receive(:post_and_parse) do |uri, body|
          captured[:uri] = uri
          captured[:body] = body
          "Great expressive performance."
        end

        result = described_class.analyze(audio_path: audio_path, prompt: "Critique it.", model: "gemini-3.6-flash")

        expect(result).to eq("Great expressive performance.")
        expect(captured[:uri]).to include("models/gemini-3.6-flash:generateContent")
        parts = captured[:body][:contents][0][:parts]
        expect(parts[0][:inline_data][:mime_type]).to eq("audio/mpeg")
        expect(parts[0][:inline_data][:data]).to eq(Base64.strict_encode64("RAWBYTES"))
        expect(parts[1][:text]).to eq("Critique it.")
      end

      # The Gemini 3 Developer Guide strongly recommends the default
      # temperature (1.0) for all Gemini 3 models and advises removing
      # explicitly set low values (risk: looping / degraded performance).
      # A 0.2 experiment degraded critique candor in dogfood (2026-06-10).
      # Pin that NO sampling config is sent so it can't quietly come back.
      it 'sends no generationConfig (Gemini 3 guidance: keep default temperature)' do
        captured = {}
        allow(described_class).to receive(:post_and_parse) do |_uri, body|
          captured[:body] = body
          "ok"
        end

        described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.6-flash")
        expect(captured[:body]).not_to have_key(:generationConfig)
      end
    end

    context 'when the file exceeds the inline size limit' do
      it 'returns a clear error instead of sending an oversized request' do
        # Simulate a file that could not be compressed below the limit.
        stub_const("#{described_class}::MAX_INLINE_BYTES", 3)

        result = described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.6-flash")
        expect(result).to match(/too large to analyze/i)
      end
    end
  end

  describe '.prepare_audio' do
    it 'passes small files through without compression' do
      allow(File).to receive(:size).with("/x/small.wav").and_return(1024)
      path, mime, cleanup = described_class.prepare_audio("/x/small.wav")
      expect(path).to eq("/x/small.wav")
      expect(mime).to eq("audio/wav")
      expect(cleanup).to be_nil
    end
  end
end
