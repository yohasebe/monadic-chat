# frozen_string_literal: true

require "spec_helper"

# The Gemini video tool runs the bundled generator and returns its JSON. The
# tool is generate_video_with_gemini; generate_video_with_veo, its name with
# Veo, still answers for conversations saved then.
RSpec.describe "Gemini video tool", :no_api do
  let(:host) { Class.new(MonadicApp) { include GeminiHelper }.new }
  let(:session) { {} }
  let(:commands) { [] }

  def stub_generator(stdout:, stderr: "")
    allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress) { |**_, &block| block.call }
    allow(host).to receive(:send_command) do |command:, container:, &block|
      commands << [command, container]
      block.call(stdout, stderr, double(success?: true))
    end
  end

  it "runs the generator with the request's settings and returns its JSON" do
    saved = { success: true, filename: "gemini_omni_a.mp4", videos: [{ filename: "gemini_omni_a.mp4" }] }
    stub_generator(stdout: "a stray line\n#{saved.to_json}\n")
    result = JSON.parse(host.generate_video_with_gemini(prompt: "a boat", aspect_ratio: "9:16", duration: 5,
                                                        negative_prompt: "people", session: session))
    expect(result).to include("success" => true, "filename" => "gemini_omni_a.mp4", "original_prompt" => "a boat")
    expect(session[:gemini_last_video_filename]).to eq("gemini_omni_a.mp4")
    command, container = commands.first
    expect(container).to eq("ruby")
    expect(Shellwords.split(command)).to eq(["video_generator_gemini.rb", "-p", "a boat", "-a", "9:16", "-d", "5",
                                             "--negative-prompt", "people"])
  end

  it "reports a generator that printed no result" do
    stub_generator(stdout: "", stderr: "boom\n")
    result = JSON.parse(host.generate_video_with_gemini(prompt: "a boat"))
    expect(result["success"]).to be false
    expect(result["message"]).to include("gave no result", "boom")
  end

  it "answers to the Veo name and says which Veo settings Omni ignores" do
    stub_generator(stdout: { success: true, filename: "gemini_omni_b.mp4" }.to_json)
    result = JSON.parse(host.generate_video_with_veo(prompt: "a boat", duration_seconds: 6, veo_model: "quality", session: session))
    expect(result["success"]).to be true
    expect(result["note"]).to include("veo_model")
    expect(Shellwords.split(commands.first[0])).to include("-d", "6")
  end

  it "treats both names as the video tool when reading results" do
    expect(GeminiHelper.gemini_video_tool?("generate_video_with_gemini")).to be true
    expect(GeminiHelper.gemini_video_tool?("generate_video_with_veo")).to be true
    expect(GeminiHelper.gemini_video_tool?("generate_image_with_gemini")).to be false
    failed = host.send(:handle_media_generation_result, "generate_video_with_gemini",
                       { success: false, message: "Gemini refused the request" }.to_json, session)
    expect(failed).to eq("Video generation failed: Gemini refused the request")
  end
end
