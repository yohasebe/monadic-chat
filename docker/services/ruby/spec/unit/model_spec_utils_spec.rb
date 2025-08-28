require 'spec_helper'
require_relative '../../lib/monadic/utils/model_spec_utils'

RSpec.describe ModelSpecUtils do
  # Mock model_spec.js content for testing
  let(:mock_model_spec) do
    {
      "gpt-4.1-mini" => {
        "context_window" => [1, 1047576],
        "max_output_tokens" => [1, 32768],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gpt-5" => {
        "context_window" => [1, 400000],
        "max_output_tokens" => [1, 128000],
        "reasoning_effort" => [["minimal", "low", "medium", "high"], "low"],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "claude-3.5-sonnet-v4-20250805" => {
        "context_window" => [1, 1000000],
        "max_output_tokens" => [1, 32768],
        "tool_capability" => true,
        "vision_capability" => true,
        "reasoning_model" => false
      },
      "claude-3.5-thinking-20250820" => {
        "context_window" => [1, 1000000],
        "max_output_tokens" => [1, 65536],
        "tool_capability" => false,
        "vision_capability" => false,
        "reasoning_model" => true
      },
      "gemini-2.5-flash" => {
        "context_window" => [1, 1000000],
        "max_output_tokens" => [1, 8192],
        "reasoning_effort" => [["minimal", "low", "medium", "high", "maximum"], "low"],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gemini-2.0-flash" => {
        "context_window" => [1, 1000000],
        "max_output_tokens" => [1, 8192],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "deepseek-chat" => {
        "context_window" => [1, 128000],
        "max_output_tokens" => [1, 8192],
        "tool_capability" => true,
        "vision_capability" => false
      },
      "deepseek-reasoner" => {
        "context_window" => [1, 128000],
        "max_output_tokens" => [1, 8192],
        "reasoning_effort" => [["low", "medium", "high"], "medium"],
        "tool_capability" => false,
        "vision_capability" => false,
        "reasoning_model" => true
      },
      "command-a-08-2025" => {
        "context_window" => [1, 256000],
        "max_output_tokens" => [1, 32768],
        "tool_capability" => true,
        "vision_capability" => false
      },
      "command-a-reasoning-08-2025" => {
        "context_window" => [1, 256000],
        "max_output_tokens" => [1, 32768],
        "tool_capability" => false,
        "reasoning_model" => true
      }
    }
  end
  
  before do
    allow(ModelSpecUtils).to receive(:load_model_spec).and_return(mock_model_spec)
  end
  
  describe '.load_model_spec' do
    context 'when model_spec.js exists' do
      it 'loads and parses the file' do
        # Use the real method for this test
        allow(ModelSpecUtils).to receive(:load_model_spec).and_call_original
        
        spec_file = File.join(File.dirname(__FILE__), "../../public/js/monadic/model_spec.js")
        if File.exist?(spec_file)
          result = ModelSpecUtils.load_model_spec
          expect(result).to be_a(Hash)
          expect(result).not_to be_empty
        else
          skip "model_spec.js not found in test environment"
        end
      end
    end
    
    context 'when parsing fails' do
      it 'returns empty hash and logs warning' do
        allow(ModelSpecUtils).to receive(:load_model_spec).and_call_original
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("invalid javascript")
        
        result = ModelSpecUtils.load_model_spec
        expect(result).to eq({})
      end
    end
  end
  
  describe '.get_provider_models' do
    it 'returns models for a specific provider' do
      openai_models = ModelSpecUtils.get_provider_models("gpt")
      expect(openai_models.keys).to include("gpt-4.1-mini", "gpt-5")
      expect(openai_models.keys).not_to include("claude-3.5-sonnet-v4-20250805")
    end
    
    it 'returns models for Claude provider' do
      claude_models = ModelSpecUtils.get_provider_models("claude")
      expect(claude_models.keys).to include("claude-3.5-sonnet-v4-20250805", "claude-3.5-thinking-20250820")
      expect(claude_models.keys).not_to include("gpt-4.1-mini")
    end
    
    it 'returns empty hash for unknown provider' do
      unknown_models = ModelSpecUtils.get_provider_models("unknown")
      expect(unknown_models).to eq({})
    end
    
    it 'preserves order from model_spec' do
      # In our mock, gpt-4.1-mini comes before gpt-5
      openai_models = ModelSpecUtils.get_provider_models("gpt")
      expect(openai_models.keys).to eq(["gpt-4.1-mini", "gpt-5"])
    end
  end
  
  describe '.get_default_model' do
    context 'without requirements' do
      it 'returns the first model for the provider' do
        expect(ModelSpecUtils.get_default_model("gpt")).to eq("gpt-4.1-mini")
        expect(ModelSpecUtils.get_default_model("claude")).to eq("claude-3.5-sonnet-v4-20250805")
        expect(ModelSpecUtils.get_default_model("gemini")).to eq("gemini-2.5-flash")
      end
    end
    
    context 'with requirements' do
      it 'returns first model meeting all requirements' do
        # Find a Claude model with reasoning_model: true
        model = ModelSpecUtils.get_default_model("claude", { reasoning_model: true })
        expect(model).to eq("claude-3.5-thinking-20250820")
      end
      
      it 'returns first model with tool capability' do
        model = ModelSpecUtils.get_default_model("claude", { tool_capability: true })
        expect(model).to eq("claude-3.5-sonnet-v4-20250805")
      end
      
      it 'returns nil when no model meets requirements' do
        model = ModelSpecUtils.get_default_model("deepseek", { 
          tool_capability: true, 
          vision_capability: true 
        })
        expect(model).to be_nil
      end
    end
  end
  
  describe '.model_supports?' do
    it 'returns true when model has capability' do
      expect(ModelSpecUtils.model_supports?("gpt-5", "tool_capability")).to be true
      expect(ModelSpecUtils.model_supports?("gpt-5", "vision_capability")).to be true
    end
    
    it 'returns false when model lacks capability' do
      expect(ModelSpecUtils.model_supports?("deepseek-chat", "vision_capability")).to be false
      expect(ModelSpecUtils.model_supports?("claude-3.5-thinking-20250820", "tool_capability")).to be false
    end
    
    it 'returns false for unknown model' do
      expect(ModelSpecUtils.model_supports?("unknown-model", "tool_capability")).to be false
    end
    
    it 'handles both _capability suffix and plain capability names' do
      expect(ModelSpecUtils.model_supports?("gpt-5", "tool")).to be true
      expect(ModelSpecUtils.model_supports?("gpt-5", "tool_capability")).to be true
    end
  end
  
  describe '.get_model_capabilities' do
    it 'returns all capabilities for a model' do
      capabilities = ModelSpecUtils.get_model_capabilities("gpt-5")
      expect(capabilities).to include("tool", "vision")
    end
    
    it 'returns empty array for model without capabilities' do
      # Mock a model with no capability flags
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "basic-model" => {
          "context_window" => [1, 1000],
          "max_output_tokens" => [1, 100]
        }
      })
      
      capabilities = ModelSpecUtils.get_model_capabilities("basic-model")
      expect(capabilities).to eq([])
    end
    
    it 'returns empty array for unknown model' do
      capabilities = ModelSpecUtils.get_model_capabilities("unknown")
      expect(capabilities).to eq([])
    end
  end
  
  describe '.is_thinking_model?' do
    it 'detects thinking models by explicit flag' do
      expect(ModelSpecUtils.is_thinking_model?("claude-3.5-thinking-20250820")).to be true
      expect(ModelSpecUtils.is_thinking_model?("deepseek-reasoner")).to be true
      expect(ModelSpecUtils.is_thinking_model?("command-a-reasoning-08-2025")).to be true
    end
    
    it 'returns false for non-thinking models' do
      expect(ModelSpecUtils.is_thinking_model?("gpt-4.1-mini")).to be false
      expect(ModelSpecUtils.is_thinking_model?("gemini-2.5-flash")).to be false
    end
    
    it 'detects by name pattern as fallback' do
      # Test with a model not in spec but with thinking/reasoning in name
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({})
      expect(ModelSpecUtils.is_thinking_model?("some-thinking-model")).to be true
      expect(ModelSpecUtils.is_thinking_model?("reasoning-model-v2")).to be true
    end
    
    it 'handles nil input' do
      expect(ModelSpecUtils.is_thinking_model?(nil)).to be false
    end
  end
  
  describe '.get_image_generation_model' do
    it 'returns model with image_generation_capability' do
      # Add a model with image generation capability
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return(mock_model_spec.merge({
        "gemini-imagen-3.0" => {
          "image_generation_capability" => true
        }
      }))
      
      model = ModelSpecUtils.get_image_generation_model("gemini")
      expect(model).to eq("gemini-imagen-3.0")
    end
    
    it 'returns nil when no image generation model found' do
      model = ModelSpecUtils.get_image_generation_model("gpt")
      expect(model).to be_nil
    end
  end
  
  describe '.supports_vision?' do
    it 'returns true for models with vision capability' do
      expect(ModelSpecUtils.supports_vision?("gpt-5")).to be true
      expect(ModelSpecUtils.supports_vision?("gemini-2.5-flash")).to be true
    end
    
    it 'returns false for models without vision' do
      expect(ModelSpecUtils.supports_vision?("deepseek-chat")).to be false
      expect(ModelSpecUtils.supports_vision?("command-a-reasoning-08-2025")).to be false
    end
    
    it 'detects vision models by name' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "gpt-4-vision-preview" => {
          "context_window" => [1, 128000]
        }
      })
      
      expect(ModelSpecUtils.supports_vision?("gpt-4-vision-preview")).to be true
    end
  end
  
  describe '.get_vision_model' do
    it 'prefers models with vision in the name' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "gpt-4" => { "vision_capability" => true },
        "gpt-4-vision" => { "context_window" => [1, 128000] },
        "gpt-4o" => { "vision_capability" => true }
      })
      
      model = ModelSpecUtils.get_vision_model("gpt")
      expect(model).to eq("gpt-4-vision")
    end
    
    it 'falls back to any model with vision capability' do
      model = ModelSpecUtils.get_vision_model("gemini")
      expect(["gemini-2.5-flash", "gemini-2.0-flash"]).to include(model)
    end
    
    it 'returns nil when no vision model found' do
      model = ModelSpecUtils.get_vision_model("deepseek")
      expect(model).to be_nil
    end
  end
  
  describe 'edge cases and error handling' do
    it 'handles empty model spec gracefully' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({})
      
      expect(ModelSpecUtils.get_provider_models("any")).to eq({})
      expect(ModelSpecUtils.get_default_model("any")).to be_nil
      expect(ModelSpecUtils.model_supports?("any", "tool")).to be false
    end
    
    it 'handles malformed model spec entries' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "broken-model" => nil,
        "partial-model" => { "name" => "test" }
      })
      
      expect(ModelSpecUtils.model_supports?("broken-model", "tool")).to be false
      expect(ModelSpecUtils.get_model_capabilities("partial-model")).to eq([])
    end
    
    it 'handles special characters in model names' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "model-with-special.chars_v2.0" => {
          "tool_capability" => true
        }
      })
      
      expect(ModelSpecUtils.model_supports?("model-with-special.chars_v2.0", "tool")).to be true
    end
  end
  
  describe 'real-world usage patterns' do
    it 'correctly identifies GPT-5 models' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_call_original
      spec_file = File.join(File.dirname(__FILE__), "../../public/js/monadic/model_spec.js")
      
      if File.exist?(spec_file)
        gpt5_models = ModelSpecUtils.get_provider_models("gpt-5")
        expect(gpt5_models).not_to be_empty
        
        # All GPT-5 models should have tool and vision capabilities
        gpt5_models.each do |name, spec|
          expect(spec["tool_capability"]).to be true
          expect(spec["vision_capability"]).to be true
        end
      else
        skip "model_spec.js not found"
      end
    end
    
    it 'correctly identifies Gemini flash models' do
      gemini_models = ModelSpecUtils.get_provider_models("gemini")
      flash_models = gemini_models.select { |name, _| name.include?("flash") }
      
      expect(flash_models).not_to be_empty
      flash_models.each do |name, spec|
        expect(spec["tool_capability"]).to be true
      end
    end
  end
end