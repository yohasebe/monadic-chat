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

    it "offers OpenAI only the qualities gpt-image-2 defines" do
      quality = Monadic::Utils::ModelSpec.image_options("openai", "quality")
      # "standard" and "hd" are DALL-E 3 values and answer 400.
      expect(quality).to match_array(%w[auto low medium high])
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
      expect(enums["quality"]).to eq(Monadic::Utils::ModelSpec.image_options("openai", "quality"))
      expect(enums["size"]).not_to include("256x256")
      expect(enums["quality"]).not_to include("hd")
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
