require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../lib/monadic/utils/model_spec_loader"

RSpec.describe "ModelSpecLoader Integration", type: :integration do
  let(:default_spec_path) { File.expand_path("../../public/js/monadic/model_spec.js", __dir__) }
  
  describe "Loading real model_spec.js file" do
    it "successfully loads and parses the actual model_spec.js file" do
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      expect(result).to be_a(Hash)
      expect(result.keys).not_to be_empty
      
      # Check for some expected models
      expect(result).to have_key("gpt-4")
      expect(result).to have_key("claude-3-opus-20240229")
      
      # Verify structure of a model
      gpt4 = result["gpt-4"]
      expect(gpt4).to have_key("context_window")
      expect(gpt4).to have_key("max_output_tokens")
      expect(gpt4).to have_key("temperature")
      expect(gpt4).to have_key("tool_capability")
    end
    
    it "handles all models in the spec file without errors" do
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      result.each do |model_name, spec|
        expect(model_name).to be_a(String)
        expect(spec).to be_a(Hash)
        
        # Most models should have context_window, but some special ones might not
        if spec.key?("context_window")
          # context_window can be either a single value or a range [min, max]
          expect(spec["context_window"]).to be_an(Array)
          expect(spec["context_window"].size).to be_between(1, 2).inclusive
        end
        
        # All models should have at least some common parameters
        expect(spec.keys).not_to be_empty
        # Check that values are properly structured
        spec.each do |key, value|
          expect(key).to be_a(String)
          # Values can be various types but should not be nil
          expect(value).not_to be_nil
        end
      end
    end
  end
  
  describe "User models override in real environment" do
    around do |example|
      # Save original HOME if we're modifying it
      original_home = ENV["HOME"]
      temp_home = Dir.mktmpdir
      
      begin
        # Temporarily change HOME for testing
        ENV["HOME"] = temp_home unless IN_CONTAINER
        
        # Create the config directory structure
        config_dir = if IN_CONTAINER
                       "/monadic/config"
                     else
                       File.join(temp_home, "monadic", "config")
                     end
        
        FileUtils.mkdir_p(config_dir) unless IN_CONTAINER # Skip for container tests
        
        example.run
      ensure
        ENV["HOME"] = original_home
        FileUtils.rm_rf(temp_home) if Dir.exist?(temp_home)
      end
    end
    
    it "merges user models when file exists" do
      unless IN_CONTAINER # Skip this test in container environment
        # Create custom models file
        custom_models = {
          "test-custom-model" => {
            "context_window" => [1, 999999],
            "max_output_tokens" => [1, 50000],
            "temperature" => [[0.0, 2.0], 0.7],
            "tool_capability" => true
          },
          "gpt-4" => {
            "temperature" => [[0.0, 2.0], 0.5]
          }
        }
        
        models_path = ModelSpecLoader.user_models_path
        FileUtils.mkdir_p(File.dirname(models_path))
        File.write(models_path, JSON.generate(custom_models))
        
        # Load merged spec
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Check custom model was added
        expect(result).to have_key("test-custom-model")
        expect(result["test-custom-model"]["context_window"]).to eq([1, 999999])
        
        # Check existing model was modified
        expect(result["gpt-4"]["temperature"]).to eq([[0.0, 2.0], 0.5])
        
        # Check that other gpt-4 properties are preserved
        expect(result["gpt-4"]).to have_key("context_window")
        expect(result["gpt-4"]).to have_key("tool_capability")
      end
    end
    
    it "works without user models file" do
      # Ensure no user models file exists
      models_path = ModelSpecLoader.user_models_path
      FileUtils.rm_f(models_path) if File.exist?(models_path) && !IN_CONTAINER
      
      # Should load successfully with just defaults
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      expect(result).to be_a(Hash)
      expect(result).to have_key("gpt-4")
      expect(result).to have_key("claude-3-opus-20240229")
    end
  end
  
  describe "Error handling in production-like scenarios" do
    it "handles malformed user JSON gracefully" do
      unless IN_CONTAINER
        # Use a temporary directory instead of the real user directory
        temp_home = Dir.mktmpdir
        original_path_method = ModelSpecLoader.method(:user_models_path)
        
        # Mock the user_models_path to use temp directory
        allow(ModelSpecLoader).to receive(:user_models_path).and_return(File.join(temp_home, "monadic/config/models.json"))
        
        models_path = ModelSpecLoader.user_models_path
        FileUtils.mkdir_p(File.dirname(models_path))
        File.write(models_path, "{ invalid json: true }")
        
        # Should log error but not crash
        expect(STDERR).to receive(:puts).with(/Invalid JSON/)
        
        result = ModelSpecLoader.load_merged_spec(default_spec_path)
        
        # Should return default specs
        expect(result).to be_a(Hash)
        expect(result).to have_key("gpt-4")
        
        # Clean up
        FileUtils.rm_rf(temp_home)
      end
    end
    
    it "handles missing default spec file with appropriate error" do
      non_existent_path = "/tmp/non_existent_#{Time.now.to_i}_model_spec.js"
      
      expect {
        ModelSpecLoader.load_merged_spec(non_existent_path)
      }.to raise_error(Errno::ENOENT)
    end
  end
  
  describe "Complex model structures" do
    it "preserves complex nested structures in real models" do
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      
      # Check o3 model if it exists (has reasoning_effort)
      if result.key?("o3")
        o3_spec = result["o3"]
        
        expect(o3_spec).to have_key("reasoning_effort")
        reasoning = o3_spec["reasoning_effort"]
        expect(reasoning).to be_an(Array)
        expect(reasoning[0]).to be_an(Array).and include("low", "medium", "high")
      end
      
      # Check models with nested parameter structures
      result.each do |model_name, spec|
        if spec["temperature"].is_a?(Array) && spec["temperature"].size == 2
          expect(spec["temperature"][0]).to be_an(Array).and have_attributes(size: 2)
          expect(spec["temperature"][1]).to be_a(Numeric)
        end
      end
    end
  end
  
  describe "Performance considerations" do
    it "loads large model spec file efficiently" do
      start_time = Time.now
      result = ModelSpecLoader.load_merged_spec(default_spec_path)
      load_time = Time.now - start_time
      
      expect(load_time).to be < 1.0 # Should load in less than 1 second
      expect(result.keys.size).to be > 50 # We have many models
    end
    
    it "handles multiple loads without issues" do
      results = []
      
      5.times do
        results << ModelSpecLoader.load_merged_spec(default_spec_path)
      end
      
      # All loads should return the same data
      first_result = results.first
      results.each do |result|
        expect(result.keys.sort).to eq(first_result.keys.sort)
      end
    end
  end
end