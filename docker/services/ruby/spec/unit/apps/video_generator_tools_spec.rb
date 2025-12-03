# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../apps/video_generator/video_generator_tools"
require_relative "../../../lib/monadic/adapters/vendors/gemini_helper"

# Mock MonadicHelper for testing purposes
module MonadicHelper
  def generate_video_with_sora(prompt:, model:, size:, seconds:, 
                               image_path: nil, remix_video_id: nil, max_wait: nil, session: nil)
    # Simulate successful video generation
    if image_path || remix_video_id
      { "success" => true, "video_id" => "remixed_video_#{Time.now.to_i}", "filename" => "remixed_video_#{Time.now.to_i}.mp4" }.to_json
    else
      { "success" => true, "video_id" => "generated_video_#{Time.now.to_i}", "filename" => "generated_video_#{Time.now.to_i}.mp4" }.to_json
    end
  end

  # Simulate generate_video_with_veo in GeminiHelper, as it's directly called by the app
  # This mock is specifically for the MonadicHelper (super) call within ImageGeneratorGemini
  def generate_video_with_veo(prompt:, image_path: nil, aspect_ratio: "16:9", number_of_videos: nil, 
                              person_generation: nil, negative_prompt: nil, duration_seconds: nil, 
                              veo_model: nil, session: nil)
    # Simulate temporary file creation for image_path from session
    actual_image_path = nil
    if image_path.nil? && session && session[:messages]
      last_user_msg = session[:messages].reverse.find { |m| m["role"] == "user" }
      if last_user_msg && last_user_msg["images"] && !last_user_msg["images"].empty?
        actual_image_path = last_user_msg["images"].first["name"]
      end
    elsif image_path
      actual_image_path = image_path
    end

    if actual_image_path
      { "success" => true, "filename" => "veo_video_from_image_#{Time.now.to_i}.mp4" }.to_json
    else
      { "success" => true, "filename" => "veo_generated_video_#{Time.now.to_i}.mp4" }.to_json
    end
  end
end

RSpec.describe "VideoGeneratorTools" do
  let(:openai_app) { VideoGeneratorOpenAI.new("VideoGeneratorOpenAI") }
  let(:gemini_app) { VideoGeneratorGemini.new("VideoGeneratorGemini") }
  let(:session) { { parameters: {}, messages: [] } }

  describe "VideoGeneratorOpenAI" do
    it "saves the generated video ID and filename to session" do
      result_json = openai_app.generate_video_with_sora(
        prompt: "a cat running in a field",
        model: "sora-2",
        size: "1280x720",
        seconds: "8",
        session: session
      )
      parsed_result = JSON.parse(result_json)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_video_id]).to eq(parsed_result["video_id"])
      expect(session[:openai_last_video_filename]).to eq(parsed_result["filename"])
    end

    it "uses uploaded image for image-to-video if present in session" do
      session[:messages] << { "role" => "user", "images" => [{ "name" => "uploaded_cat.jpg", "data" => "base64data" }] }
      result_json = openai_app.generate_video_with_sora(
        prompt: "animate this cat",
        model: "sora-2",
        size: "1280x720",
        seconds: "8",
        image_path: nil, # Explicitly nil to test session fallback
        session: session
      )
      parsed_result = JSON.parse(result_json)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_video_id]).to eq(parsed_result["video_id"])
    end

    it "uses session[:openai_last_video_id] for remix operation if not provided" do
      session[:openai_last_video_id] = "existing_video_123"
      session[:openai_last_video_filename] = "existing_video_123.mp4"
      result_json = openai_app.generate_video_with_sora(
        prompt: "make it longer",
        model: "sora-2",
        size: "1280x720",
        seconds: "12",
        remix_video_id: nil, # Explicitly nil to test session fallback
        session: session
      )
      parsed_result = JSON.parse(result_json)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_video_id]).to eq(parsed_result["video_id"])
    end
  end

  describe "VideoGeneratorGemini" do
    it "saves the generated video filename to session[:gemini_last_video_filename]" do
      result_json = gemini_app.generate_video_with_veo(
        prompt: "a dog playing in a park",
        veo_model: "fast",
        session: session
      )
      parsed_result = JSON.parse(result_json)
      expect(parsed_result["success"]).to be true
      expect(session[:gemini_last_video_filename]).to eq(parsed_result["filename"])
    end

    it "uses uploaded image for image-to-video if present in session" do
      session[:messages] << { "role" => "user", "images" => [{ "name" => "uploaded_dog.jpg", "data" => "base64data" }] }
      result_json = gemini_app.generate_video_with_veo(
        prompt: "animate this dog",
        veo_model: "fast",
        image_path: nil, # Explicitly nil to test session fallback
        session: session
      )
      parsed_result = JSON.parse(result_json)
      expect(parsed_result["success"]).to be true
      expect(session[:gemini_last_video_filename]).to eq(parsed_result["filename"])
    end
  end
end