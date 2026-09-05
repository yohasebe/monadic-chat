require "spec_helper"
require_relative "../../lib/monadic/utils/model_spec"

RSpec.describe Monadic::Utils::ModelSpec do
  describe "normalization and accessors" do
    it "normalizes reasoning_model to is_reasoning_model (Cohere)" do
      model = "command-a-reasoning-08-2025"
      # Cohere spec uses reasoning_model; normalization should expose is_reasoning_model
      is_reasoning = Monadic::Utils::ModelSpec.get_model_property(model, "is_reasoning_model")
      # Either the spec already provides it, or the normalizer mapped it
      expect([true, false]).to include(is_reasoning)
      # And accessor reflects the canonical property presence
      # If reasoning_effort is present for the model, it is a reasoning-capable model
      opts = Monadic::Utils::ModelSpec.get_model_property(model, "reasoning_effort")
      expect(opts).not_to be_nil
    end

    it "marks Cohere models as not supporting PDFs" do
      model = "command-a-reasoning-08-2025"
      expect(Monadic::Utils::ModelSpec.supports_pdf?(model)).to be false
      # vision_capability may be absent; accessor defaults to true when undefined
      # this test only asserts PDF behavior for Cohere non-vision model
    end

    it "exposes streaming/tool capability with safe defaults" do
      model = "grok-4.20-0309-non-reasoning"
      # tools default to true when unspecified
      expect(Monadic::Utils::ModelSpec.tool_capability?(model)).to be true
      # streaming defaults to true when unspecified
      expect(Monadic::Utils::ModelSpec.supports_streaming?(model)).to be true
      # vision=true per spec; pdf=false per spec tweak
      expect(Monadic::Utils::ModelSpec.vision_capability?(model)).to be true
      expect(Monadic::Utils::ModelSpec.supports_pdf?(model)).to be false
    end

    it "supports Responses API detection via api_type" do
      # GPT-5 models are marked as Responses API in the spec
      model = "gpt-5"
      expect(Monadic::Utils::ModelSpec.responses_api?(model)).to be true
    end

    # The catalog carries two spellings: OpenAI, Cohere and Mistral entries
    # declare `supports_structured_output`, Anthropic and xAI the bare
    # `structured_output` the accessor reads. Before normalization the accessor
    # answered false for the whole first group, and did so silently — an absent
    # property looks the same as a declared false.
    describe "structured output alias" do
      it "resolves the supports_ spelling" do
        %w[gpt-6-astra gpt-5.6-sol command-a-plus-05-2026 mistral-medium-3-5].each do |model|
          expect(Monadic::Utils::ModelSpec.supports_structured_outputs?(model)).to be(true),
            "#{model} declares supports_structured_output but the accessor says false"
        end
      end

      it "still resolves the bare spelling" do
        %w[claude-opus-5 grok-4.6].each do |model|
          expect(Monadic::Utils::ModelSpec.supports_structured_outputs?(model)).to be true
        end
      end

      it "leaves every declaring model resolvable" do
        missed = Monadic::Utils::ModelSpec.load_spec.select do |model, props|
          props.is_a?(Hash) && props["supports_structured_output"] == true &&
            !Monadic::Utils::ModelSpec.supports_structured_outputs?(model)
        end

        expect(missed.keys).to be_empty
      end

      it "does not invent support for models that declare neither" do
        # load_spec returns the normalized copy, so asking it which models
        # "declare" a key would be asking after the very step under test — a
        # normalization that fills the key in for everyone would empty this
        # collection and pass on nothing. Read the catalog source instead.
        source = File.read(
          File.expand_path("../../public/js/monadic/model_spec.js", __dir__)
        )

        undeclared = Monadic::Utils::ModelSpec.load_spec.keys.reject do |model|
          entry = source[/^  "#{Regexp.escape(model)}":\s*\{.*?^  \},/m]
          entry && entry.include?("structured_output")
        end

        expect(undeclared).not_to be_empty,
          "no model lacks the declaration, so this example checks nothing"

        invented = undeclared.select do |model|
          Monadic::Utils::ModelSpec.supports_structured_outputs?(model)
        end

        expect(invented).to be_empty,
          "#{invented.inspect} report structured output support without declaring it"
      end
    end

    it "detects adaptive thinking support for Opus 4.6" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-opus-4-8")).to be true
    end

    it "detects adaptive thinking support for Opus 4.7" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-opus-4-7")).to be true
    end

    it "detects adaptive thinking support for Sonnet 4.6" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-sonnet-4-6")).to be true
    end

    # Fable 5 is the top tier (above Opus); it shares the Opus 4.7/4.8 contract,
    # so the claude_helper's flag-driven thinking/sampling path applies with no
    # code change. Pin the flags that drive that path.
    it "detects the Fable 5 thinking/sampling contract" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-fable-5")).to be true
      expect(Monadic::Utils::ModelSpec.rejects_sampling_params?("claude-fable-5")).to be true
      expect(Monadic::Utils::ModelSpec.thinking_display_default_omitted?("claude-fable-5")).to be true
    end

    # Fable 5.1 keeps the Fable 5 contract and adds two restrictions the
    # helper must honor: forced tool_choice is a 400, and replayed thinking
    # blocks are bound to their prefix. Fable 5 has neither.
    it "detects the Fable 5.1 contract and its two additions" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-fable-5-1")).to be true
      expect(Monadic::Utils::ModelSpec.rejects_sampling_params?("claude-fable-5-1")).to be true
      expect(Monadic::Utils::ModelSpec.thinking_display_default_omitted?("claude-fable-5-1")).to be true
      expect(Monadic::Utils::ModelSpec.rejects_forced_tool_choice?("claude-fable-5-1")).to be true
      expect(Monadic::Utils::ModelSpec.thinking_block_binding?("claude-fable-5-1")).to be true

      expect(Monadic::Utils::ModelSpec.rejects_forced_tool_choice?("claude-fable-5")).to be false
      expect(Monadic::Utils::ModelSpec.thinking_block_binding?("claude-fable-5")).to be false
    end

    it "returns false for adaptive thinking on older Claude models" do
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-haiku-4-5-20251001")).to be false
      expect(Monadic::Utils::ModelSpec.supports_adaptive_thinking?("claude-sonnet-4-5-20250929")).to be false
    end
  end
end

