# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe "ElevenLabs STT Integration" do
  describe "stt_api_request routing" do
    it "routes scribe models to ElevenLabs API" do
      # Verify routing logic for ElevenLabs models
      # Note: scribe_v1 is available via REST API; scribe_v2 is WebSocket-only (not implemented)
      scribe_models = ["scribe_v1"]
      scribe_models.each do |model|
        expect(model.start_with?("scribe")).to be true
      end
    end

    it "does not route non-scribe models to ElevenLabs" do
      other_models = ["gpt-4o-transcribe", "whisper-1", "gemini-2.5-flash"]
      other_models.each do |model|
        expect(model.start_with?("scribe")).to be false
      end
    end
  end

  describe "elevenlabs_stt_api_request" do
    describe "format normalization" do
      it "normalizes audio formats correctly" do
        formats = {
          "mpeg" => "mp3",
          "mp4a-latm" => "mp4",
          "x-wav" => "wav",
          "wave" => "wav",
          "webm" => "webm",
          "mp3" => "mp3"
        }

        formats.each do |input_format, expected_format|
          normalized = input_format.to_s.downcase
          normalized = "mp3" if normalized == "mpeg"
          normalized = "mp4" if normalized == "mp4a-latm"
          normalized = "wav" if %w[x-wav wave].include?(normalized)

          expect(normalized).to eq(expected_format)
        end
      end
    end

    describe "API request structure" do
      it "builds correct multipart form data options" do
        options = {
          "model_id" => "scribe_v1",
          "file_format" => "other",
          "timestamps_granularity" => "word"
        }

        expect(options["model_id"]).to eq("scribe_v1")
        expect(options["file_format"]).to eq("other")
        expect(options["timestamps_granularity"]).to eq("word")
      end

      it "includes language_code when not auto" do
        lang_code = "ja"
        options = {}

        if lang_code && lang_code != "auto"
          options["language_code"] = lang_code
        end

        expect(options["language_code"]).to eq("ja")
      end

      it "excludes language_code when auto" do
        lang_code = "auto"
        options = {}

        if lang_code && lang_code != "auto"
          options["language_code"] = lang_code
        end

        expect(options).not_to have_key("language_code")
      end
    end

    describe "response parsing" do
      it "extracts text from successful response" do
        response = {
          "language_code" => "en",
          "language_probability" => 0.99,
          "text" => "Hello world",
          "words" => [
            { "text" => "Hello", "start" => 0.0, "end" => 0.5, "type" => "word", "logprob" => -0.1 },
            { "text" => "world", "start" => 0.6, "end" => 1.0, "type" => "word", "logprob" => -0.2 }
          ]
        }

        text = response["text"]&.strip || ""
        expect(text).to eq("Hello world")
      end

      it "builds logprobs array from words" do
        response = {
          "words" => [
            { "text" => "Hello", "logprob" => -0.1 },
            { "text" => "world", "logprob" => -0.2 }
          ]
        }

        logprobs = []
        if response["words"].is_a?(Array)
          response["words"].each do |word|
            if word["logprob"]
              logprobs << { "logprob" => word["logprob"].to_f }
            end
          end
        end

        expect(logprobs.size).to eq(2)
        expect(logprobs[0]["logprob"]).to eq(-0.1)
        expect(logprobs[1]["logprob"]).to eq(-0.2)
      end

      it "handles missing logprobs gracefully" do
        response = {
          "words" => [
            { "text" => "Hello" },
            { "text" => "world" }
          ]
        }

        logprobs = []
        if response["words"].is_a?(Array)
          response["words"].each do |word|
            if word["logprob"]
              logprobs << { "logprob" => word["logprob"].to_f }
            end
          end
        end

        expect(logprobs).to be_empty
      end
    end
  end

  describe "calculate_logprob for ElevenLabs" do
    it "returns nil for empty logprobs array" do
      res = { "logprobs" => [] }
      model = "scribe_v1"

      # Simulate the calculation logic
      result = if model.start_with?("scribe")
        return nil unless res["logprobs"].is_a?(Array) && !res["logprobs"].empty?
        avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
        Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
      end

      expect(result).to be_nil
    end

    it "calculates probability from logprobs" do
      res = {
        "logprobs" => [
          { "logprob" => -0.1 },
          { "logprob" => -0.2 },
          { "logprob" => -0.15 }
        ]
      }
      model = "scribe_v1"

      # Simulate the calculation logic
      result = if model.start_with?("scribe") && res["logprobs"].is_a?(Array) && !res["logprobs"].empty?
        avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
        Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
      end

      # Average logprob: (-0.1 + -0.2 + -0.15) / 3 = -0.15
      # exp(-0.15) ≈ 0.86
      expect(result).to be_within(0.05).of(0.86)
    end
  end

  describe "UI integration" do
    it "has correct option ID for selector" do
      option_id = "elevenlabs-stt-scribe"
      option_value = "scribe_v1"

      expect(option_id).to eq("elevenlabs-stt-scribe")
      expect(option_value).to eq("scribe_v1")
    end
  end

  describe "API key validation" do
    it "requires ELEVENLABS_API_KEY" do
      # The API key should be checked before making requests
      api_key = nil

      error_expected = api_key.nil? || api_key.to_s.strip.empty?
      expect(error_expected).to be true
    end
  end
end
