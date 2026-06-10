# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../../../lib/monadic/agents/audio_analysis_agent'

RSpec.describe AudioAnalysisAgent do
  before { stub_const("CONFIG", { "GEMINI_API_KEY" => "test-gemini-key" }) }

  let(:audio_path) { "/test/perf.mp3" }

  describe '.analyze' do
    context 'guards' do
      it 'errors when GEMINI_API_KEY is missing' do
        stub_const("CONFIG", {})
        result = described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.5-flash")
        expect(result).to match(/GEMINI_API_KEY not configured/)
      end

      it 'errors when the file does not exist' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(audio_path).and_return(false)
        result = described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.5-flash")
        expect(result).to match(/Audio file not found/)
      end
    end

    context 'building the Gemini generateContent request' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(audio_path).and_return(true)
        allow(File).to receive(:size).with(audio_path).and_return(1024) # small -> no compression
        allow(File).to receive(:binread).with(audio_path).and_return("RAWBYTES")
      end

      it 'sends audio inline_data + the prompt and returns the model text' do
        captured = {}
        allow(described_class).to receive(:post_and_parse) do |uri, body|
          captured[:uri] = uri
          captured[:body] = body
          "Great expressive performance."
        end

        result = described_class.analyze(audio_path: audio_path, prompt: "Critique it.", model: "gemini-3.5-flash")

        expect(result).to eq("Great expressive performance.")
        expect(captured[:uri]).to include("models/gemini-3.5-flash:generateContent")
        parts = captured[:body][:contents][0][:parts]
        expect(parts[0][:inline_data][:mime_type]).to eq("audio/mpeg")
        expect(parts[0][:inline_data][:data]).to eq(Base64.strict_encode64("RAWBYTES"))
        expect(parts[1][:text]).to eq("Critique it.")
      end

      # Critique is an analysis task. Without an explicit generationConfig the
      # API default temperature (1.0) applies, and that variance showed up in
      # dogfood as intermittent instrument fabrication (1 in 3 runs). Pin the
      # low-temperature setting so it can't silently fall back to the default.
      it 'sends a low temperature for analysis-grade sampling' do
        captured = {}
        allow(described_class).to receive(:post_and_parse) do |_uri, body|
          captured[:body] = body
          "ok"
        end

        described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.5-flash")
        expect(captured[:body][:generationConfig]).to eq({ temperature: 0.2 })
      end
    end

    context 'when the file exceeds the inline size limit' do
      it 'returns a clear error instead of sending an oversized request' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(audio_path).and_return(true)
        # Simulate a file that could not be compressed below the limit.
        allow(described_class).to receive(:prepare_audio).with(audio_path).and_return([audio_path, "audio/mpeg", nil])
        allow(File).to receive(:size).with(audio_path).and_return(described_class::MAX_INLINE_BYTES + 1)

        result = described_class.analyze(audio_path: audio_path, prompt: "x", model: "gemini-3.5-flash")
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
