require 'spec_helper'

# In-process, like every generator spec. Two properties make that safe:
#
#   1. The script has a `__FILE__ == $PROGRAM_NAME` guard, so loading it does
#      not run the CLI — this spec used to spawn
#      `ruby image_generator_grok.rb -p "test prompt"`, which reached the real
#      xAI API and billed for a generated image on every full unit run.
#   2. GeneratorScriptLoader evaluates it inside its own module, so its
#      top-level helpers do not overwrite another script's same-named ones.
#
# no_network_spec.rb pins both properties for this directory.
GROK_IMAGE_SCRIPT = GeneratorScriptLoader.load("image_generator_grok.rb")

RSpec.describe "image_generator_grok.rb" do
  let(:script) { GROK_IMAGE_SCRIPT }

  describe "argument parsing" do
    it "collects prompt, operation, aspect ratio, images and model" do
      options = script.parse_options(["-p", "a cat", "-o", "edit", "-a", "16:9",
                                      "-i", "one.png", "-i", "two.png",
                                      "-m", "grok-imagine-image-2.0"])
      expect(options[:prompt]).to eq("a cat")
      expect(options[:operation]).to eq("edit")
      expect(options[:aspect_ratio]).to eq("16:9")
      expect(options[:images]).to eq(["one.png", "two.png"])
      expect(options[:model]).to eq("grok-imagine-image-2.0")
    end

    it "defaults to the generate operation with no images" do
      options = script.parse_options(["-p", "a cat"])
      expect(options[:operation]).to eq("generate")
      expect(options[:images]).to be_empty
      expect(options[:model]).to be_nil
    end
  end

  describe "validation" do
    it "requires a prompt" do
      expect(script.validate_options({ operation: "generate", images: [] }))
        .to include("A prompt is required")
    end

    it "requires an image for edit" do
      expect(script.validate_options({ prompt: "x", operation: "edit", images: [] }))
        .to include("At least one image is required")
    end

    it "caps edit input at three images" do
      expect(script.validate_options({ prompt: "x", operation: "edit", images: %w[a b c d] }))
        .to include("Maximum 3 images")
    end

    it "accepts a usable set of options" do
      expect(script.validate_options({ prompt: "x", operation: "generate", images: [] })).to be_nil
    end
  end

  describe "image model resolution" do
    it "falls back to the provider default for blank or unknown names" do
      default = script.default_grok_image_model
      expect(script.resolve_grok_image_model(nil)).to eq(default)
      expect(script.resolve_grok_image_model("  ")).to eq(default)
      expect(script.resolve_grok_image_model("grok-imagine-image-nonexistent")).to eq(default)
    end

    it "keeps a model that the SSOT lists" do
      known = script.grok_image_models
      skip "no image models configured" if known.empty?

      expect(script.resolve_grok_image_model(known.last)).to eq(known.last)
    end
  end

  describe "account id scrubbing" do
    it "removes a team UUID from an API error message" do
      msg = "The model foo does not exist or your team " \
            "00000000-1111-2222-3333-444444444444 does not have access to it."
      out = script.scrub_account_ids(msg)
      expect(out).not_to include("00000000-1111-2222-3333-444444444444")
      expect(out).to include(Monadic::Utils::ErrorFormatter::REDACTION)
      # The rest of the message still explains what went wrong.
      expect(out).to include("does not have access")
    end

    it "leaves messages without identifiers untouched" do
      expect(script.scrub_account_ids("Rate limit exceeded")).to eq("Rate limit exceeded")
    end
  end
end
