# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/vocabulary"

# Coverage for the session-state vocabulary tokens ${LAST_IMAGE} / ${NOTEBOOK}.
# Unlike the tier-1 tokens these are NOT in DEFAULT_TOKENS — an app opts in via
# `vocabulary do; use :last_image; end` so the variable only appears where it is
# meaningful (image generators, Jupyter). Their resolvers read session state
# already populated by the image/Jupyter tools.
RSpec.describe "Monadic::Substitution::Vocabulary session-state tokens" do
  let(:described) { Monadic::Substitution::Vocabulary }

  describe "BUILTINS registry" do
    it "registers :last_image as ${LAST_IMAGE} with :expand display" do
      meta = described::BUILTINS[:last_image]
      expect(meta[:token]).to eq("LAST_IMAGE")
      expect(meta[:display]).to eq(:expand)
      expect(meta[:description]).to be_a(String).and(satisfy { |d| !d.empty? })
    end

    it "registers :notebook as ${NOTEBOOK} with :expand display" do
      meta = described::BUILTINS[:notebook]
      expect(meta[:token]).to eq("NOTEBOOK")
      expect(meta[:display]).to eq(:expand)
      expect(meta[:description]).to be_a(String).and(satisfy { |d| !d.empty? })
    end

    it "keeps the new tokens OUT of DEFAULT_TOKENS (opt-in only)" do
      expect(described::DEFAULT_TOKENS).not_to include(:last_image)
      expect(described::DEFAULT_TOKENS).not_to include(:notebook)
    end
  end

  describe ".tokens_for (per-app applicability)" do
    it "excludes :last_image/:notebook for an app that does not declare them" do
      tokens = described.tokens_for(nil)
      expect(tokens).not_to include(:last_image)
      expect(tokens).not_to include(:notebook)
      expect(tokens).to include(:shared) # default still on
    end

    it "includes :last_image when the app opts in via `use`" do
      settings = { vocabulary: { tokens: [:last_image], enabled: true } }
      expect(described.tokens_for(settings)).to include(:last_image)
    end

    it "includes :notebook when the app opts in via `use`" do
      settings = { vocabulary: { tokens: [:notebook], enabled: true } }
      expect(described.tokens_for(settings)).to include(:notebook)
    end
  end

  describe ".last_generated_image" do
    it "reads the unified monadic_state last_images slot (basename)" do
      session = {
        parameters: { "app_name" => "ImageGeneratorOpenAI" },
        monadic_state: {
          "ImageGeneratorOpenAI" => {
            last_images: { data: ["sub/dir/cat_2026.png"], version: 1 }
          }
        }
      }
      expect(described.last_generated_image(session)).to eq("cat_2026.png")
    end

    it "falls back to the provider-specific legacy single-image key" do
      session = {
        parameters: { "app_name" => "ImageGeneratorGrok" },
        grok_last_image: "/monadic/data/grok_img.png"
      }
      expect(described.last_generated_image(session)).to eq("grok_img.png")
    end

    it "returns nil when nothing has been generated" do
      session = { parameters: { "app_name" => "ImageGeneratorOpenAI" } }
      expect(described.last_generated_image(session)).to be_nil
    end
  end

  describe ".current_notebook" do
    it "reads notebook_filename from the monadic_state context slot" do
      session = {
        parameters: { "app_name" => "JupyterNotebookOpenAI" },
        monadic_state: {
          "JupyterNotebookOpenAI" => {
            context: { data: { "notebook_filename" => "analysis.ipynb" }, version: 2 }
          }
        }
      }
      expect(described.current_notebook(session)).to eq("analysis.ipynb")
    end

    it "returns nil when no notebook has been created" do
      session = { parameters: { "app_name" => "JupyterNotebookOpenAI" } }
      expect(described.current_notebook(session)).to be_nil
    end
  end

  describe "Registry invariants still hold with the new tokens" do
    it "passes validate_builtins! (UPPER_CASE, disjoint from Privacy <<TYPE_N>>)" do
      require "monadic/substitution/registry"
      expect { Monadic::Substitution::Registry.validate_builtins! }.not_to raise_error
    end
  end
end
