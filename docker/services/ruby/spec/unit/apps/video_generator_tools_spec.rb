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
