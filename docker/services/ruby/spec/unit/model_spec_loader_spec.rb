require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../lib/monadic/utils/model_spec_loader"

RSpec.describe ModelSpecLoader do
  let(:test_default_spec) do
    {
      "gpt-4" => {
        "context_window" => [1, 8192],
        "max_output_tokens" => [1, 4096],
        "temperature" => [[0.0, 2.0], 1.0],
        "tool_capability" => true,
        "vision_capability" => false
      },
      "claude-3-opus" => {
        "context_window" => [1, 200000],
        "max_output_tokens" => [1, 4096],
        "temperature" => [[0.0, 1.0], 1.0]
      }
    }
  end

  let(:test_user_spec) do
    {
      "gpt-4" => {
        "temperature" => [[0.0, 2.0], 0.7],
        "max_output_tokens" => [1, 8192]
      },
      "gpt-5-preview" => {
        "context_window" => [1, 2000000],
        "max_output_tokens" => [1, 200000],
        "temperature" => [[0.0, 2.0], 1.0],
        "tool_capability" => true,
        "vision_capability" => true
      }
    }
  end

  describe "#deep_merge" do
    it "merges nested hashes correctly" do
      hash1 = { "a" => { "b" => 1, "c" => 2 }, "d" => 3 }
      hash2 = { "a" => { "b" => 10, "e" => 4 }, "f" => 5 }
      
      result = ModelSpecLoader.deep_merge(hash1, hash2)
      
      expect(result).to eq({
        "a" => { "b" => 10, "c" => 2, "e" => 4 },
        "d" => 3,
        "f" => 5
      })
    end

    it "overwrites non-hash values" do
      hash1 = { "a" => [1, 2], "b" => "old" }
      hash2 = { "a" => [3, 4], "b" => "new" }
      
      result = ModelSpecLoader.deep_merge(hash1, hash2)
      
      expect(result).to eq({ "a" => [3, 4], "b" => "new" })
    end
  end

  describe "#user_models_path" do
    context "in development environment" do
      before do
        stub_const("IN_CONTAINER", false)
      end

      it "returns expanded home path" do
        path = ModelSpecLoader.user_models_path
        expect(path).to include(ENV["HOME"])
        expect(path).to end_with("/monadic/config/models.json")
      end
    end

    context "in Docker container" do
      before do
        stub_const("IN_CONTAINER", true)
      end

      it "returns container path" do
        path = ModelSpecLoader.user_models_path
        expect(path).to eq("/monadic/config/models.json")
      end
    end
  end

  describe "#load_merged_spec" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:default_spec_path) { File.join(temp_dir, "model_spec.js") }
    let(:user_models_path) { File.join(temp_dir, "models.json") }

    before do
      # Create default spec file in the same format as the real one
      js_content = "const modelSpec = #{JSON.pretty_generate(test_default_spec)};"
      File.write(default_spec_path, js_content)
      
      # Mock user_models_path
      allow(ModelSpecLoader).to receive(:user_models_path).and_return(user_models_path)
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context "when user models file doesn't exist" do
      it "returns default spec" do
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        expect(result).to eq(test_default_spec)
      end
    end

    context "when user models file exists" do
      before do
        File.write(user_models_path, JSON.generate(test_user_spec))
      end

      it "merges user spec with default spec" do
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Check that gpt-4 was modified
        expect(result["gpt-4"]["temperature"]).to eq([[0.0, 2.0], 0.7])
        expect(result["gpt-4"]["max_output_tokens"]).to eq([1, 8192])
        expect(result["gpt-4"]["context_window"]).to eq([1, 8192]) # unchanged
        expect(result["gpt-4"]["tool_capability"]).to eq(true) # unchanged
        
        # Check that new model was added
        expect(result["gpt-5-preview"]).to eq(test_user_spec["gpt-5-preview"])
        
        # Check that claude-3-opus remains unchanged
        expect(result["claude-3-opus"]).to eq(test_default_spec["claude-3-opus"])
      end
    end

    context "when user models file has invalid JSON" do
      before do
        File.write(user_models_path, "{ invalid json }")
      end

      it "returns default spec and logs error" do
        # Allow debug messages
        allow(STDERR).to receive(:puts).with(/Model Spec Debug/)
        # Expect the error message
        expect(STDERR).to receive(:puts).with(/Invalid JSON/)
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        expect(result).to eq(test_default_spec)
      end
    end
  end
end