# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"

RSpec.describe "Monadic::SharedTools::MonadicSessionState" do
  let(:test_class) do
    Class.new do
      include Monadic::SharedTools::MonadicSessionState
    end
  end
  let(:instance) { test_class.new }

  describe "#monadic_load_state" do
    it "returns data from session monadic_state" do
      session = {
        monadic_state: {
          "TestApp" => {
            "my_key" => { data: [1, 2, 3], version: 2, updated_at: "2026-01-01T00:00:00Z" }
          }
        },
        parameters: { "app_name" => "TestApp" }
      }

      result = JSON.parse(instance.monadic_load_state(key: "my_key", session: session))
      expect(result["success"]).to be true
      expect(result["data"]).to eq([1, 2, 3])
      expect(result["version"]).to eq(2)
    end

    it "returns default when key is missing" do
      session = { monadic_state: {}, parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_load_state(key: "missing", default: "fallback", session: session))
      expect(result["data"]).to eq("fallback")
    end

    it "raises error for empty key" do
      session = { parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_load_state(key: "", session: session))
      expect(result["success"]).to be false
    end
  end

  describe "#monadic_save_state" do
    it "saves data to session monadic_state" do
      session = { parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_save_state(key: "images", payload: ["img.png"], session: session))
      expect(result["success"]).to be true
      expect(result["version"]).to eq(1)
      expect(session[:monadic_state]["TestApp"]["images"][:data]).to eq(["img.png"])
    end

    it "increments version on subsequent saves" do
      session = { parameters: { "app_name" => "TestApp" } }
      instance.monadic_save_state(key: "k", payload: "v1", session: session)
      result = JSON.parse(instance.monadic_save_state(key: "k", payload: "v2", session: session))
      expect(result["version"]).to eq(2)
    end

    it "raises error when session is nil" do
      result = JSON.parse(instance.monadic_save_state(key: "k", payload: "v", session: nil))
      expect(result["success"]).to be false
    end
  end

  describe "#fetch_last_images_from_session" do
    # Use send to access private method
    def fetch(session, app_key, legacy_prefix: nil)
      instance.send(:fetch_last_images_from_session, session, app_key, legacy_prefix: legacy_prefix)
    end

    context "monadic_state lookup" do
      it "returns images from monadic_state with symbol keys" do
        session = {
          monadic_state: {
            "MyApp" => {
              last_images: { data: ["a.png", "b.png"], version: 1 }
            }
          }
        }
        expect(fetch(session, "MyApp")).to eq(["a.png", "b.png"])
      end

      it "returns images from monadic_state with string keys" do
        session = {
          "monadic_state" => {
            "MyApp" => {
              "last_images" => { "data" => ["c.png"], "version" => 1 }
            }
          }
        }
        expect(fetch(session, "MyApp")).to eq(["c.png"])
      end

      it "returns nil for empty data array" do
        session = {
          monadic_state: {
            "MyApp" => {
              last_images: { data: [], version: 1 }
            }
          }
        }
        expect(fetch(session, "MyApp")).to be_nil
      end
    end

    context "legacy_prefix fallback" do
      it "falls back to {prefix}_last_image_generation with symbol key" do
        session = {
          monadic_state: {},
          openai_last_image_generation: { images: ["legacy.png"] }
        }
        expect(fetch(session, "ImageGeneratorOpenAI", legacy_prefix: "openai")).to eq(["legacy.png"])
      end

      it "falls back to {prefix}_last_image_generation with string key" do
        session = {
          monadic_state: {},
          "grok_last_image_generation" => { "images" => ["grok_legacy.png"] }
        }
        expect(fetch(session, "ImageGeneratorGrok", legacy_prefix: "grok")).to eq(["grok_legacy.png"])
      end

      it "falls back to single {prefix}_last_image" do
        session = {
          monadic_state: {},
          gemini3_last_image: "single.png"
        }
        expect(fetch(session, "ImageGeneratorGemini3Preview", legacy_prefix: "gemini3")).to eq(["single.png"])
      end

      it "returns nil without legacy_prefix when monadic_state is empty" do
        session = {
          monadic_state: {},
          openai_last_image: "should_not_find.png"
        }
        expect(fetch(session, "ImageGeneratorOpenAI")).to be_nil
      end

      it "returns nil when no data exists anywhere" do
        session = { monadic_state: {} }
        expect(fetch(session, "MyApp", legacy_prefix: "openai")).to be_nil
      end
    end

    context "priority order" do
      it "prefers monadic_state over legacy keys" do
        session = {
          monadic_state: {
            "MyApp" => {
              last_images: { data: ["new.png"], version: 2 }
            }
          },
          openai_last_image_generation: { images: ["old.png"] },
          openai_last_image: "oldest.png"
        }
        expect(fetch(session, "MyApp", legacy_prefix: "openai")).to eq(["new.png"])
      end

      it "prefers {prefix}_last_image_generation over {prefix}_last_image" do
        session = {
          monadic_state: {},
          grok_last_image_generation: { images: ["gen.png"] },
          grok_last_image: "single.png"
        }
        expect(fetch(session, "MyApp", legacy_prefix: "grok")).to eq(["gen.png"])
      end
    end
  end
end
