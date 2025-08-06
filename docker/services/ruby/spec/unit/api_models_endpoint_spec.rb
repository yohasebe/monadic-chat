require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require "ostruct"
require_relative "../../lib/monadic/utils/model_spec_loader"

# Mock Sinatra app for testing
class MockApp
  def self.settings
    OpenStruct.new(public_folder: File.expand_path("../../public", __dir__))
  end
end

RSpec.describe "API /api/models endpoint" do
  let(:test_models_dir) { Dir.mktmpdir }
  let(:test_models_path) { File.join(test_models_dir, "models.json") }
  let(:default_spec_path) { File.join(MockApp.settings.public_folder, "js/monadic/model_spec.js") }
  
  let(:custom_models) do
    {
      "test-gpt-5" => {
        "context_window" => [1, 500000],
        "max_output_tokens" => [1, 100000],
        "temperature" => [[0.0, 2.0], 0.8],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gpt-4" => {
        "temperature" => [[0.0, 2.0], 0.5],
        "custom_override" => true
      }
    }
  end

  before do
    # Mock the user models path
    allow(ModelSpecLoader).to receive(:user_models_path).and_return(test_models_path)
    
    # Suppress logging during tests
    allow(STDERR).to receive(:puts)
  end

  after do
    FileUtils.rm_rf(test_models_dir) if Dir.exist?(test_models_dir)
  end

  describe "ModelSpecLoader with real model_spec.js" do
    context "without custom models.json" do
      it "loads default model specifications" do
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        expect(result).to be_a(Hash)
        expect(result.keys).to include("gpt-4", "claude-3-opus-20240229")
        expect(result["gpt-4"]).to have_key("context_window")
        expect(result["gpt-4"]).to have_key("max_output_tokens")
      end
    end

    context "with custom models.json" do
      before do
        File.write(test_models_path, JSON.generate(custom_models))
      end

      it "merges custom models with defaults" do
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Custom model should be added
        expect(result).to have_key("test-gpt-5")
        expect(result["test-gpt-5"]["context_window"]).to eq([1, 500000])
        expect(result["test-gpt-5"]["vision_capability"]).to eq(true)
        
        # Existing model should be modified
        expect(result["gpt-4"]["temperature"]).to eq([[0.0, 2.0], 0.5])
        expect(result["gpt-4"]["custom_override"]).to eq(true)
        
        # Other properties should be preserved
        expect(result["gpt-4"]).to have_key("context_window")
        expect(result["gpt-4"]).to have_key("tool_capability")
        
        # Other models should remain unchanged
        expect(result).to have_key("claude-3-opus-20240229")
      end

      it "handles deep merge correctly" do
        # Create a custom model that partially overrides a complex model
        partial_override = {
          "o3" => {
            "temperature" => [[0.0, 2.0], 0.3],
            "reasoning_effort" => [["low", "medium", "high", "ultra"], "high"]
          }
        }
        
        File.write(test_models_path, JSON.generate(partial_override))
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Check that only specified fields were overridden
        expect(result["o3"]["temperature"]).to eq([[0.0, 2.0], 0.3])
        expect(result["o3"]["reasoning_effort"]).to eq([["low", "medium", "high", "ultra"], "high"])
        
        # Other fields should remain unchanged
        expect(result["o3"]).to have_key("context_window")
        expect(result["o3"]).to have_key("max_output_tokens")
        expect(result["o3"]).to have_key("tool_capability")
      end
    end

    context "with invalid JSON" do
      before do
        File.write(test_models_path, "{ invalid: json }")
      end

      it "falls back to default specifications" do
        expect(STDERR).to receive(:puts).with(/Invalid JSON/)
        
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Should have default models
        expect(result).to have_key("gpt-4")
        expect(result).to have_key("claude-3-opus-20240229")
        
        # Should not have custom models
        expect(result).not_to have_key("test-gpt-5")
      end
    end

    context "with missing default spec file" do
      it "raises an error" do
        non_existent_path = "/tmp/non_existent_model_spec.js"
        
        expect {
          ModelSpecLoader.load_merged_spec(non_existent_path)
        }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "Model validation" do
    let(:complex_models) do
      {
        "ultra-advanced-model" => {
          "context_window" => [1, 2000000],
          "max_output_tokens" => [[1, 100000], 50000],
          "temperature" => [[0.0, 2.0], 0.7],
          "top_p" => [[0.0, 1.0], 0.95],
          "presence_penalty" => [[-2.0, 2.0], 0.5],
          "frequency_penalty" => [[-2.0, 2.0], 0.3],
          "tool_capability" => true,
          "vision_capability" => true,
          "reasoning_effort" => [["none", "low", "medium", "high", "ultra"], "high"],
          "custom_nested" => {
            "feature_a" => true,
            "feature_b" => {
              "setting1" => 100,
              "setting2" => "enabled"
            }
          }
        }
      }
    end

    before do
      File.write(test_models_path, JSON.generate(complex_models))
    end

    it "preserves all data types correctly" do
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      model = result["ultra-advanced-model"]
      
      # Numeric arrays
      expect(model["context_window"]).to eq([1, 2000000])
      
      # Nested arrays with defaults
      expect(model["max_output_tokens"]).to eq([[1, 100000], 50000])
      expect(model["temperature"]).to eq([[0.0, 2.0], 0.7])
      
      # Booleans
      expect(model["tool_capability"]).to eq(true)
      expect(model["vision_capability"]).to eq(true)
      
      # String arrays with default
      expect(model["reasoning_effort"]).to eq([["none", "low", "medium", "high", "ultra"], "high"])
      
      # Nested objects
      expect(model["custom_nested"]).to be_a(Hash)
      expect(model["custom_nested"]["feature_a"]).to eq(true)
      expect(model["custom_nested"]["feature_b"]["setting1"]).to eq(100)
      expect(model["custom_nested"]["feature_b"]["setting2"]).to eq("enabled")
    end
  end

  describe "Logging behavior" do
    before do
      File.write(test_models_path, JSON.generate(custom_models))
    end

    context "with EXTRA_LOGGING enabled" do
      before do
        allow(CONFIG).to receive(:[]).with("EXTRA_LOGGING").and_return(true)
      end

      it "logs detailed information about loaded models" do
        expect(STDERR).to receive(:puts).with(/Loaded user models from/)
        expect(STDERR).to receive(:puts).with(/Merged 2 custom model definitions/)
        
        ModelSpecLoader.load_merged_spec(default_spec_path)
      end
    end

    context "without EXTRA_LOGGING" do
      before do
        allow(CONFIG).to receive(:[]).with("EXTRA_LOGGING").and_return(false)
      end

      it "does not log model loading information" do
        expect(STDERR).not_to receive(:puts).with(/Loaded user models/)
        expect(STDERR).not_to receive(:puts).with(/Merged/)
        
        ModelSpecLoader.load_merged_spec(default_spec_path)
      end
    end
  end

  describe "Edge cases" do
    it "handles empty custom models file" do
      File.write(test_models_path, "{}")
      
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      # Should return default models unchanged
      expect(result).to have_key("gpt-4")
      expect(result).to have_key("claude-3-opus-20240229")
    end

    it "handles models with special characters in names" do
      special_models = {
        "model-with-dash" => { "context_window" => [1, 1000] },
        "model_with_underscore" => { "context_window" => [1, 2000] },
        "model.with.dots" => { "context_window" => [1, 3000] }
      }
      
      File.write(test_models_path, JSON.generate(special_models))
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      expect(result).to have_key("model-with-dash")
      expect(result).to have_key("model_with_underscore")
      expect(result).to have_key("model.with.dots")
    end

    it "handles very large custom models file" do
      # Create a large models file with many entries
      large_models = {}
      100.times do |i|
        large_models["test-model-#{i}"] = {
          "context_window" => [1, 1000 * i],
          "max_output_tokens" => [1, 100 * i],
          "temperature" => [[0.0, 2.0], 0.5 + (i * 0.01)]
        }
      end
      
      File.write(test_models_path, JSON.generate(large_models))
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      # Should have all custom models plus defaults
      expect(result.keys.size).to be > 100
      expect(result).to have_key("test-model-0")
      expect(result).to have_key("test-model-99")
      expect(result).to have_key("gpt-4")
    end
  end
end