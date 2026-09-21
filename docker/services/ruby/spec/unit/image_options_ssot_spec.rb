# frozen_string_literal: true

require "spec_helper"

# Image generation vocabularies (sizes, qualities, formats, model lists) used to
# be written out three times: in the MDSL tool enum the model chooses from, in
# the generator script's validation, and in the tool layer. Two copies of one
# rule always drift, and the copy that drifts lies quietly — the OpenAI tool
# offered the DALL-E sizes 256x256 / 512x512 and the qualities "standard" / "hd"
# for months after DALL-E was removed (2026-05-12). A live probe on 2026-08-21
# had the API answer 400 to all four, i.e. whenever the model picked one of
# them, generation simply failed.
#
# The fix is not to check the copies against each other but to remove them: the
# MDSL enums are now expressions reading imageGenerationOptions. This spec keeps
# it that way.
RSpec.describe "image generation options come from the SSOT" do
  mdsl_dir = File.expand_path("../../apps/image_generator", __dir__)
  MDSL_FILES = Dir[File.join(mdsl_dir, "*.mdsl")].freeze

  # `operation` is the app's own vocabulary (generate / edit), not something a
  # provider can change under us, so it stays a literal.
  APP_OWNED_ENUMS = ["generate", "edit"].freeze

  it "has no provider vocabulary written out as a literal enum" do
    offenders = MDSL_FILES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line =~ /enum:\s*\[/
        values = line[/enum:\s*\[([^\]]*)\]/, 1].to_s.scan(/"([^"]*)"/).flatten
        next if values.sort == APP_OWNED_ENUMS.sort

        "#{File.basename(path)}:#{i + 1}: #{line.strip[0, 120]}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      A tool enum lists provider values directly. It will keep offering them
      after the provider stops accepting them, and the model has no way to know:

        #{offenders.join("\n  ")}

      Read them instead, e.g.
        enum: Monadic::Utils::ModelSpec.image_options("openai", "size")
        enum: Monadic::Utils::ModelSpec.get_provider_models("xai", "image")
    MSG
  end

  describe "the vocabularies themselves" do
    it "offers OpenAI only sizes the API still accepts" do
      sizes = Monadic::Utils::ModelSpec.image_options("openai", "size")
      expect(sizes).not_to be_empty
      # Verified 400 on a live probe: below the minimum pixel budget.
      expect(sizes).not_to include("256x256", "512x512")
      expect(sizes).to include("1024x1024", "2048x2048")
    end

    # Quality is the one parameter whose accepted values differ per model, and
    # the difference is not cosmetic: asking gpt-image-2 for `xhigh` answers
    # "The model 'gpt-image-2' does not support quality 'xhigh'" (live probe,
    # 2026-09-21), while the 2.5 models generate. A single provider-wide list
    # cannot describe both without either hiding values or offering rejected
    # ones.
    describe "quality, which differs per model" do
      it "gives gpt-image-2 the four it accepts" do
        # "standard" and "hd" are DALL-E 3 values and answer 400.
        expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: "gpt-image-2"))
          .to match_array(%w[auto low medium high])
      end

      it "gives the 2.5 models the two extra ones" do
        %w[gpt-image-2.5-flare gpt-image-2.5-sunburst].each do |model|
          expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: model))
            .to match_array(%w[auto low medium high xhigh max]), model
        end
      end

      it "resolves the default model when none is named" do
        default = Monadic::Utils::ModelSpec.get_provider_default("openai", "image")
        expect(Monadic::Utils::ModelSpec.image_options("openai", "quality"))
          .to eq(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: default))
      end

      it "offers the tool every value some model accepts" do
        # The MDSL enum is fixed when the app loads while the model is chosen
        # per call, so neither the default's list nor any one model's list
        # describes what may legitimately be asked for.
        expect(Monadic::Utils::ModelSpec.image_tool_options("openai", "quality"))
          .to match_array(%w[auto low medium high xhigh max])
      end

      it "answers nothing for an unknown model even if the provider defines the parameter" do
        # The refusal must come from the model not being listed, not from the
        # provider-level key happening to be absent. Simulate someone
        # reintroducing a provider-wide quality list.
        opts = Monadic::Utils::ModelSpec.send(:load_image_generation_options)
        original = opts["openai"].dup
        begin
          opts["openai"] = original.merge("quality" => %w[auto low])
          expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: "gpt-image-9"))
            .to eq([])
          # Positive control: a known model still resolves through that path.
          expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: "gpt-image-2"))
            .to match_array(%w[auto low medium high])
        ensure
          opts["openai"] = original
        end
      end

      it "answers nothing for a model it does not know" do
        # Falling back to the default model's vocabulary here is how a typo or
        # a new model reaches a billed request with a value the API rejects.
        expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: "gpt-image-9"))
          .to eq([])
        expect(Monadic::Utils::ModelSpec.image_option_supported?("openai", "quality", "auto", model: "gpt-image-9"))
          .to be(false)
      end

      it "decides a model-and-value pair without calling the API" do
        expect(Monadic::Utils::ModelSpec.image_option_supported?("openai", "quality", "xhigh", model: "gpt-image-2"))
          .to be(false)
        expect(Monadic::Utils::ModelSpec.image_option_supported?("openai", "quality", "xhigh", model: "gpt-image-2.5-flare"))
          .to be(true)
      end
    end

    it "keeps parameters that do not vary by model at the provider level" do
      # size is the same for every OpenAI image model, so a per-model entry
      # that omits it must still resolve.
      per_model = Monadic::Utils::ModelSpec.image_options("openai", "size", model: "gpt-image-2.5-flare")
      expect(per_model).to eq(Monadic::Utils::ModelSpec.image_options("openai", "size"))
      expect(per_model).not_to be_empty
    end

    it "leaves providers without per-model tables alone" do
      expect(Monadic::Utils::ModelSpec.image_options("xai", "aspect_ratio")).not_to be_empty
      expect(Monadic::Utils::ModelSpec.image_options("gemini", "model")).not_to be_empty
    end

    it "defines a quality vocabulary for every model it offers" do
      # A model in providerDefaults that the table does not describe resolves
      # to [], which the generator treats as "cannot validate" and refuses.
      Monadic::Utils::ModelSpec.provider_default_models("openai", "image").each do |model|
        expect(Monadic::Utils::ModelSpec.image_options("openai", "quality", model: model))
          .not_to be_empty, "#{model} has no quality vocabulary"
      end
    end

    it "returns an empty list for anything unknown instead of raising" do
      expect(Monadic::Utils::ModelSpec.image_options("nope", "size")).to eq([])
      expect(Monadic::Utils::ModelSpec.image_options("openai", "nope")).to eq([])
    end
  end

  describe "resolution at app load" do
    before(:all) { TestAppLoader.load_all_apps }

    def enums_for(app_name)
      tools = APPS[app_name]&.settings&.[]("tools")
      return {} unless tools

      declarations =
        if tools.is_a?(Hash)
          tools.values.flatten          # Gemini's function_declarations shape
        else
          tools.map { |t| t[:function] || t["function"] || t }
        end

      declarations.each_with_object({}) do |decl, acc|
        params = decl[:parameters] || decl["parameters"] || {}
        props = params[:properties] || params["properties"] || {}
        props.each do |name, schema|
          values = schema[:enum] || schema["enum"]
          acc[name.to_s] = values if values
        end
      end
    end

    it "resolves the OpenAI enums to the SSOT values, not the retired ones" do
      enums = enums_for("ImageGeneratorOpenAI")
      expect(enums["size"]).to eq(Monadic::Utils::ModelSpec.image_options("openai", "size"))
      # The tool enum is the union across offered models, not the default
      # model's list: the model picks both the image model and the quality in
      # one call, so an enum limited to the default would hide xhigh and max.
      # The pair is checked against each other before the request goes out.
      expect(enums["quality"]).to eq(Monadic::Utils::ModelSpec.image_tool_options("openai", "quality"))
      expect(enums["model"]).to eq(Monadic::Utils::ModelSpec.get_provider_models("openai", "image"))
      expect(enums["size"]).not_to include("256x256")
      expect(enums["quality"]).not_to include("hd", "standard")
    end

    it "resolves the Grok enums to the SSOT values" do
      enums = enums_for("ImageGeneratorGrok")
      expect(enums["aspect_ratio"]).to eq(Monadic::Utils::ModelSpec.image_options("xai", "aspect_ratio"))
      expect(enums["image_model"]).to eq(Monadic::Utils::ModelSpec.get_provider_models("xai", "image"))
    end

    it "resolves the Gemini model enum to the SSOT values" do
      enums = enums_for("ImageGeneratorGemini")
      expect(enums["model"]).to eq(Monadic::Utils::ModelSpec.image_options("gemini", "model"))
    end
  end
end
