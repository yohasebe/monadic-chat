# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/deepseek_helper"

# DeepSeek gained vision on 2026-08-21 with deepseek-v4-flash-vision-exp. The
# model is experimental and is NOT a chat default, so images reach it only via
# the helper's swap. These specs pin the pieces that decide whether an image
# gets through at all.
RSpec.describe "DeepSeek vision support" do
  let(:helper) do
    Class.new do
      include DeepSeekHelper
      public :deepseek_supported_images, :switch_to_deepseek_vision_model,
             :append_deepseek_prompt_suffix
    end.new
  end

  describe "#deepseek_supported_images" do
    it "keeps the formats the vision model reads" do
      images = [
        { "type" => "image/png", "data" => "data:image/png;base64,AAA" },
        { "type" => "image/jpeg", "data" => "data:image/jpeg;base64,BBB" },
        { "type" => "image/webp", "data" => "data:image/webp;base64,CCC" },
        { "type" => "image/gif", "data" => "data:image/gif;base64,DDD" }
      ]
      expect(helper.deepseek_supported_images(images).size).to eq(4)
    end

    it "drops PDFs, which arrive in the same attachment array and would 400" do
      images = [
        { "type" => "application/pdf", "data" => "data:application/pdf;base64,AAA" },
        { "type" => "image/png", "data" => "data:image/png;base64,BBB" }
      ]
      kept = helper.deepseek_supported_images(images)
      expect(kept.size).to eq(1)
      expect(kept.first["type"]).to eq("image/png")
    end

    it "treats an entry with no declared type as an image" do
      images = [{ "data" => "data:image/png;base64,AAA" }]
      expect(helper.deepseek_supported_images(images)).not_to be_empty
    end

    it "ignores entries without usable data" do
      expect(helper.deepseek_supported_images([{ "type" => "image/png" }])).to be_empty
      expect(helper.deepseek_supported_images(nil)).to eq([])
      expect(helper.deepseek_supported_images("nope")).to eq([])
    end
  end

  describe "#switch_to_deepseek_vision_model" do
    it "swaps a text model for the vision model and says so" do
      body = { "model" => "deepseek-v4-flash" }
      notices = []
      helper.switch_to_deepseek_vision_model(body) { |msg| notices << msg }

      expect(body["model"]).to eq("deepseek-v4-flash-vision-exp")
      expect(notices.first["type"]).to eq("system_info")
      expect(notices.first["content"]).to include("deepseek-v4-flash-vision-exp")
    end

    it "leaves a model that can already see" do
      body = { "model" => "deepseek-v4-flash-vision-exp" }
      notices = []
      helper.switch_to_deepseek_vision_model(body) { |msg| notices << msg }

      expect(body["model"]).to eq("deepseek-v4-flash-vision-exp")
      expect(notices).to be_empty
    end

    it "leaves the model alone when the spec cannot be read" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_raise(StandardError)
      allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models).and_raise(StandardError)

      body = { "model" => "deepseek-v4-flash" }
      expect { helper.switch_to_deepseek_vision_model(body) }.not_to raise_error
      expect(body["model"]).to eq("deepseek-v4-flash")
    end
  end

  describe "SSOT" do
    it "lists the vision model for the provider without making it a chat default" do
      vision = Monadic::Utils::ModelSpec.get_provider_models("deepseek", "vision")
      chat = Monadic::Utils::ModelSpec.get_provider_models("deepseek", "chat")

      expect(vision).to eq(["deepseek-v4-flash-vision-exp"])
      expect(chat).not_to include("deepseek-v4-flash-vision-exp")
    end

    it "marks the vision model as seeing and tool-capable" do
      expect(Monadic::Utils::ModelSpec.get_model_property("deepseek-v4-flash-vision-exp", "vision_capability")).to be true
      expect(Monadic::Utils::ModelSpec.get_model_property("deepseek-v4-flash-vision-exp", "tool_capability")).to be true
    end

    it "keeps the thinking controls, which the model needs to answer at all" do
      # It reasons by default; without a way to disable that it spends the whole
      # budget on a trace and returns empty content (observed on a live probe).
      expect(Monadic::Utils::ModelSpec.get_model_property("deepseek-v4-flash-vision-exp", "reasoning_content"))
        .to include("disabled")
    end
  end

  # A latent break found while adding vision: the prompt_suffix append assumed
  # the last message's content is a String. With an image attached it is an
  # Array, and `Array += String` raises TypeError — i.e. attaching an image in
  # any app that sets prompt_suffix would have failed the request.
  describe "#append_deepseek_prompt_suffix" do
    it "appends to the text part when the message carries images" do
      message = { "role" => "user", "content" => [
        { "type" => "text", "text" => "look at this" },
        { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,AAA" } }
      ] }
      helper.append_deepseek_prompt_suffix(message, "Answer briefly.")

      expect(message["content"].first["text"]).to eq("look at this\n\nAnswer briefly.")
      # The image part survives untouched.
      expect(message["content"].last["type"]).to eq("image_url")
    end

    it "still appends to plain string content" do
      message = { "role" => "user", "content" => "hello" }
      helper.append_deepseek_prompt_suffix(message, "Answer briefly.")
      expect(message["content"]).to eq("hello\n\nAnswer briefly.")
    end

    it "adds a text part when the content is images only" do
      message = { "role" => "user", "content" => [
        { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,AAA" } }
      ] }
      helper.append_deepseek_prompt_suffix(message, "Answer briefly.")
      expect(message["content"].first).to eq({ "type" => "text", "text" => "Answer briefly." })
    end

    it "does nothing without a suffix" do
      message = { "role" => "user", "content" => "hello" }
      helper.append_deepseek_prompt_suffix(message, nil)
      expect(message["content"]).to eq("hello")
    end
  end
end
