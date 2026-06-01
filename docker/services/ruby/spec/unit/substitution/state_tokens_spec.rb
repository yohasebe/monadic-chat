# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/vocabulary"

# Coverage for the session-state image/notebook vocabulary tokens.
# These are NOT in DEFAULT_TOKENS — an app opts in via `vocabulary do; use
# :last_generated_image; end`. ${LAST_GENERATED_IMAGE} = the image the assistant
# produced (monadic_state "last_images" / legacy keys); ${LAST_UPLOADED_IMAGE} =
# the image the user uploaded (latest user message's "images" attachment).
RSpec.describe "Monadic::Substitution::Vocabulary image/notebook tokens" do
  let(:described) { Monadic::Substitution::Vocabulary }

  describe "BUILTINS registry" do
    it "registers :last_generated_image as ${LAST_GENERATED_IMAGE} with :expand display" do
      meta = described::BUILTINS[:last_generated_image]
      expect(meta[:token]).to eq("LAST_GENERATED_IMAGE")
      expect(meta[:display]).to eq(:expand)
      expect(meta[:description]).to be_a(String).and(satisfy { |d| !d.empty? })
    end

    it "registers :last_uploaded_image as ${LAST_UPLOADED_IMAGE} with :expand display" do
      meta = described::BUILTINS[:last_uploaded_image]
      expect(meta[:token]).to eq("LAST_UPLOADED_IMAGE")
      expect(meta[:display]).to eq(:expand)
      expect(meta[:description]).to be_a(String).and(satisfy { |d| !d.empty? })
    end

    it "registers :notebook as ${NOTEBOOK} with :expand display" do
      meta = described::BUILTINS[:notebook]
      expect(meta[:token]).to eq("NOTEBOOK")
      expect(meta[:display]).to eq(:expand)
    end

    it "keeps the opt-in image/notebook tokens OUT of DEFAULT_TOKENS" do
      %i[last_generated_image last_uploaded_image notebook].each do |t|
        expect(described::DEFAULT_TOKENS).not_to include(t)
      end
    end
  end

  describe ".tokens_for (per-app applicability)" do
    it "excludes the opt-in tokens for an app that does not declare them" do
      tokens = described.tokens_for(nil)
      expect(tokens).not_to include(:last_generated_image)
      expect(tokens).not_to include(:last_uploaded_image)
      expect(tokens).not_to include(:notebook)
      expect(tokens).to include(:shared)
    end

    it "includes the image tokens when the app opts in via `use`" do
      settings = { vocabulary: { tokens: [:last_generated_image, :last_uploaded_image], enabled: true } }
      expect(described.tokens_for(settings)).to include(:last_generated_image, :last_uploaded_image)
    end
  end

  describe ".last_generated_image (assistant output)" do
    it "reads the unified monadic_state last_images slot (basename)" do
      session = {
        parameters: { "app_name" => "ImageGeneratorOpenAI" },
        monadic_state: {
          "ImageGeneratorOpenAI" => { last_images: { data: ["sub/dir/cat_2026.png"], version: 1 } }
        }
      }
      expect(described.last_generated_image(session)).to eq("cat_2026.png")
    end

    it "falls back to the provider-specific legacy single-image key" do
      session = { parameters: { "app_name" => "ImageGeneratorGrok" }, grok_last_image: "/monadic/data/grok_img.png" }
      expect(described.last_generated_image(session)).to eq("grok_img.png")
    end

    it "returns nil when nothing has been generated" do
      expect(described.last_generated_image({ parameters: { "app_name" => "ImageGeneratorOpenAI" } })).to be_nil
    end
  end

  describe ".last_uploaded_image (user upload)" do
    it "returns the filename of the most recently user-uploaded image" do
      session = { messages: [
        { "role" => "user", "images" => [{ "title" => "old.png" }] },
        { "role" => "assistant", "text" => "ok" },
        { "role" => "user", "images" => [{ "title" => "first.png" }, { "title" => "diagram_v2.png" }] }
      ] }
      expect(described.last_uploaded_image(session)).to eq("diagram_v2.png")
    end

    it "tolerates a 'filename' key and basenames any path" do
      session = { messages: [{ "role" => "user", "images" => [{ "filename" => "uploads/photo.jpg" }] }] }
      expect(described.last_uploaded_image(session)).to eq("photo.jpg")
    end

    it "considers only user messages and returns nil when the user uploaded nothing" do
      session = { messages: [
        { "role" => "assistant", "images" => [{ "title" => "ai.png" }] },
        { "role" => "user", "text" => "hi" }
      ] }
      expect(described.last_uploaded_image(session)).to be_nil
    end
  end

  describe ".current_notebook" do
    it "reads notebook_filename from the monadic_state context slot" do
      session = {
        parameters: { "app_name" => "JupyterNotebookOpenAI" },
        monadic_state: {
          "JupyterNotebookOpenAI" => { context: { data: { "notebook_filename" => "analysis.ipynb" }, version: 2 } }
        }
      }
      expect(described.current_notebook(session)).to eq("analysis.ipynb")
    end

    it "returns nil when no notebook has been created" do
      expect(described.current_notebook({ parameters: { "app_name" => "JupyterNotebookOpenAI" } })).to be_nil
    end
  end

  describe "Registry invariants still hold with the renamed/added tokens" do
    it "passes validate_builtins! (UPPER_CASE, disjoint from Privacy <<TYPE_N>>)" do
      require "monadic/substitution/registry"
      expect { Monadic::Substitution::Registry.validate_builtins! }.not_to raise_error
    end
  end
end
