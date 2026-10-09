require 'spec_helper'
require 'tmpdir'

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

  # The real lookup, against an env file that holds what users write.
  describe "api key lookup" do
    around do |example|
      Dir.mktmpdir("openai-image-env") do |dir|
        @env_file = File.join(dir, "env")
        example.run
      end
    end

    before { allow(Monadic::Utils::Environment).to receive(:env_path).and_return(@env_file) }

    it "returns a plain key" do
      File.write(@env_file, "OPENAI_API_KEY=sk-plain\n")
      expect(script.get_api_key).to eq("sk-plain")
    end

    it "returns the delivered value of a 1Password reference" do
      File.write(@env_file, "OPENAI_API_KEY=op://Test/OPENAI/credential\n")
      allow(Monadic::Utils::SecretReferences).to receive(:resolved).and_return({ "OPENAI_API_KEY" => "sk-delivered" })
      expect(script.get_api_key).to eq("sk-delivered")
    end

    it "exits with guidance on an unread reference instead of sending its text" do
      File.write(@env_file, "OPENAI_API_KEY=op://Test/OPENAI/credential\n")
      allow(Monadic::Utils::SecretReferences).to receive(:resolved).and_return({})
      expect { script.get_api_key }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(satisfy { |text| text.include?("OPENAI_API_KEY is not set") && !text.include?("op://") }).to_stdout
    end

    it "exits with guidance when no file holds a key" do
      expect { script.get_api_key }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(/OPENAI_API_KEY is not set/).to_stdout
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
