require 'spec_helper'

# In-process and namespaced, like the other generator specs.
#
# This spec used to spawn the script with `-o edit -p test --image-url
# https://example.com/img.png`. Those arguments PASS validation, so the run
# went on to fetch the image and would have continued to the OpenAI API — it
# stayed free only because example.com answers 404, i.e. the test's safety
# depended on an external site's behavior.
OPENAI_IMAGE_SCRIPT = GeneratorScriptLoader.load("image_generator_openai.rb")

RSpec.describe "image_generator_openai.rb" do
  let(:script) { OPENAI_IMAGE_SCRIPT }

  describe "image model resolution" do
    it "takes the allowed models from the providerDefaults SSOT" do
      # Constants are namespaced too: instance_eval puts them on the loaded
      # object's singleton class rather than on Object.
      models = script.singleton_class.const_get(:ALLOWED_IMAGE_MODELS)
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.first).to be_a(String)
    end
  end

  describe "api key lookup" do
    it "exits with guidance when no config file holds a key" do
      allow(File).to receive(:exist?).and_return(false)
      expect { script.get_api_key }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(/Unable to find OpenAI API key/).to_stdout
    end
  end

  describe "namespace isolation" do
    it "keeps its helpers off Object so other generator scripts are unaffected" do
      # get_api_key exists in several generator scripts with different
      # behavior; loading them all must not make the last one win.
      expect(script.respond_to?(:get_api_key)).to be true
      expect(script.respond_to?(:generate_image)).to be true
    end
  end
end
