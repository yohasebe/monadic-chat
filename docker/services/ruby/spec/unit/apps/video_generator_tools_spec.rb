# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../apps/video_generator/video_generator_tools"

RSpec.describe "VideoGeneratorTools" do
  describe "VideoGeneratorOpenAI" do
    it "is defined as a class" do
      expect(defined?(VideoGeneratorOpenAI)).to eq("constant")
    end

    it "includes required modules" do
      expect(VideoGeneratorOpenAI.included_modules).to include(MonadicHelper)
    end

    it "responds to generate_video_with_sora method" do
      app = VideoGeneratorOpenAI.new
      expect(app).to respond_to(:generate_video_with_sora)
    end
  end

  describe "VideoGeneratorGemini" do
    it "is defined as a class" do
      expect(defined?(VideoGeneratorGemini)).to eq("constant")
    end

    it "includes required modules" do
      expect(VideoGeneratorGemini.included_modules).to include(GeminiHelper)
    end

    it "responds to generate_video_with_veo method" do
      app = VideoGeneratorGemini.new
      expect(app).to respond_to(:generate_video_with_veo)
    end
  end

  describe "VideoGeneratorGrok" do
    it "is defined as a class" do
      expect(defined?(VideoGeneratorGrok)).to eq("constant")
    end

    it "includes required modules" do
      expect(VideoGeneratorGrok.included_modules).to include(GrokHelper)
    end

    it "responds to generate_video_with_grok_imagine method" do
      app = VideoGeneratorGrok.new
      expect(app).to respond_to(:generate_video_with_grok_imagine)
    end

    describe "parameter validation" do
      let(:app) { VideoGeneratorGrok.new }

      it "rejects empty prompt" do
        expect {
          app.send(:validate_grok_video_params, prompt: "", duration: nil, aspect_ratio: nil, resolution: nil)
        }.to raise_error(ArgumentError, /Prompt cannot be empty/)
      end

      it "rejects invalid duration" do
        expect {
          app.send(:validate_grok_video_params, prompt: "test", duration: 20, aspect_ratio: nil, resolution: nil)
        }.to raise_error(ArgumentError, /Invalid duration/)
      end

      it "rejects invalid aspect_ratio" do
        expect {
          app.send(:validate_grok_video_params, prompt: "test", duration: nil, aspect_ratio: "3:2", resolution: nil)
        }.to raise_error(ArgumentError, /Invalid aspect_ratio/)
      end

      it "rejects invalid resolution" do
        expect {
          app.send(:validate_grok_video_params, prompt: "test", duration: nil, aspect_ratio: nil, resolution: "1080p")
        }.to raise_error(ArgumentError, /Invalid resolution/)
      end

      it "accepts valid parameters" do
        expect(
          app.send(:validate_grok_video_params, prompt: "a cat", duration: 10, aspect_ratio: "16:9", resolution: "720p")
        ).to eq(true)
      end
    end
  end

  describe "VideoGeneratorOpenAI parameter validation" do
    let(:app) { VideoGeneratorOpenAI.new }

    it "rejects empty prompt" do
      expect {
        app.send(:validate_sora_params, prompt: "", model: "sora-2", size: "1280x720", seconds: "8")
      }.to raise_error(ArgumentError, /Prompt cannot be empty/)
    end

    it "rejects invalid model" do
      expect {
        app.send(:validate_sora_params, prompt: "test", model: "invalid-model", size: "1280x720", seconds: "8")
      }.to raise_error(ArgumentError, /Invalid model/)
    end

    it "rejects invalid size" do
      expect {
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "640x480", seconds: "8")
      }.to raise_error(ArgumentError, /Invalid size/)
    end

    it "rejects invalid duration" do
      expect {
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1280x720", seconds: "30")
      }.to raise_error(ArgumentError, /Invalid duration/)
    end

    it "accepts 1080p resolution" do
      expect(
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1920x1080", seconds: "8")
      ).to eq(true)
    end

    it "accepts portrait 1080p resolution" do
      expect(
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1080x1920", seconds: "8")
      ).to eq(true)
    end

    it "accepts 16-second duration" do
      expect(
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1280x720", seconds: "16")
      ).to eq(true)
    end

    it "accepts 20-second duration" do
      expect(
        app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1280x720", seconds: "20")
      ).to eq(true)
    end

    it "accepts all standard sizes" do
      %w[1280x720 720x1280 1792x1024 1024x1792 1920x1080 1080x1920].each do |size|
        expect(
          app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: size, seconds: "8")
        ).to eq(true)
      end
    end

    it "accepts all standard durations" do
      %w[4 8 12 16 20].each do |seconds|
        expect(
          app.send(:validate_sora_params, prompt: "test", model: "sora-2", size: "1280x720", seconds: seconds)
        ).to eq(true)
      end
    end
  end

  describe "Dynamic timeout calculation" do
    it "calculates timeout based on video duration" do
      # Base 600s + 30s per video second
      expect(VideoGeneratorOpenAI.compute_max_wait("4")).to eq(720)
      expect(VideoGeneratorOpenAI.compute_max_wait("8")).to eq(840)
      expect(VideoGeneratorOpenAI.compute_max_wait("12")).to eq(960)
      expect(VideoGeneratorOpenAI.compute_max_wait("16")).to eq(1080)
      expect(VideoGeneratorOpenAI.compute_max_wait("20")).to eq(1200)
    end

    it "falls back to base timeout for invalid duration" do
      expect(VideoGeneratorOpenAI.compute_max_wait(nil)).to eq(600)
      expect(VideoGeneratorOpenAI.compute_max_wait("")).to eq(600)
    end
  end

  describe "Session state integration" do
    # These tests verify the session state behavior but require actual API calls
    # Run with RUN_API=true for full integration testing

    it "VideoGeneratorOpenAI session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:openai_last_video_id] and session[:openai_last_video_filename]
      # are properly set after video generation
    end

    it "VideoGeneratorGemini session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:gemini_last_video_filename] is properly set after video generation
    end
  end
end
