require 'spec_helper'
require_relative '../../lib/monadic/utils/model_spec_utils'

RSpec.describe "ModelSpecUtils Extended Features" do
  let(:mock_model_spec) do
    {
      "gpt-3.5-turbo" => {
        "context_window" => [1, 16384],
        "max_output_tokens" => [1, 4096],
        "tool_capability" => true
      },
      "gpt-4" => {
        "context_window" => [1, 128000],
        "max_output_tokens" => [1, 4096],
        "tool_capability" => true,
        "vision_capability" => false
      },
      "gpt-4.1-mini" => {
        "context_window" => [1, 1047576],
        "max_output_tokens" => [1, 32768],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gpt-5" => {
        "context_window" => [1, 400000],
        "max_output_tokens" => [1, 128000],
        "tool_capability" => true,
        "vision_capability" => true,
        "reasoning_capability" => true
      },
      "claude-3-haiku" => {
        "context_window" => [1, 200000],
        "max_output_tokens" => [1, 4096],
        "tool_capability" => true
      },
      "claude-3.5-sonnet-20241022" => {
        "context_window" => [1, 200000],
        "max_output_tokens" => [1, 8192],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gemini-1.5-pro" => {
        "context_window" => [1, 2000000],
        "max_output_tokens" => [1, 8192],
        "tool_capability" => true,
        "vision_capability" => true
      },
      "gemini-2.0-flash" => {
        "context_window" => [1, 1000000],
        "max_output_tokens" => [1, 8192],
        "tool_capability" => true,
        "vision_capability" => true
      }
    }
  end
  
  before do
    allow(ModelSpecUtils).to receive(:load_model_spec).and_return(mock_model_spec)
  end
  
  describe '.find_model_by_capabilities' do
    it 'returns model with all required capabilities' do
      model = ModelSpecUtils.find_model_by_capabilities(
        "gpt",
        [:tool, :vision]
      )
      expect(["gpt-4.1-mini", "gpt-5"]).to include(model)
    end
    
    it 'returns nil when no model matches requirements' do
      model = ModelSpecUtils.find_model_by_capabilities(
        "gpt",
        [:tool, :vision, :nonexistent]
      )
      expect(model).to be_nil
    end
    
    it 'prefers models with more optional capabilities' do
      model = ModelSpecUtils.find_model_by_capabilities(
        "gpt",
        [:tool],  # required
        [:vision, :reasoning]  # optional
      )
      # GPT-5 has both vision and reasoning
      expect(model).to eq("gpt-5")
    end
    
    it 'works with _capability suffix in requirements' do
      model = ModelSpecUtils.find_model_by_capabilities(
        "gpt",
        [:tool_capability, :vision_capability]
      )
      expect(["gpt-4.1-mini", "gpt-5"]).to include(model)
    end
    
    it 'returns first eligible when no optional caps specified' do
      model = ModelSpecUtils.find_model_by_capabilities(
        "claude",
        [:tool]
      )
      expect(model).to eq("claude-3-haiku")  # First model with tool capability
    end
  end
  
  describe '.compare_model_versions' do
    it 'correctly compares version numbers' do
      expect(ModelSpecUtils.compare_model_versions("gpt-3.5-turbo", "gpt-4")).to eq(-1)
      expect(ModelSpecUtils.compare_model_versions("gpt-4", "gpt-3.5-turbo")).to eq(1)
      expect(ModelSpecUtils.compare_model_versions("gpt-4", "gpt-4")).to eq(0)
    end
    
    it 'handles models with decimal versions' do
      expect(ModelSpecUtils.compare_model_versions("gpt-4.1-mini", "gpt-4")).to eq(1)
      expect(ModelSpecUtils.compare_model_versions("claude-3.5-sonnet", "claude-3-haiku")).to eq(1)
    end
    
    it 'handles nil values' do
      expect(ModelSpecUtils.compare_model_versions(nil, "gpt-4")).to eq(-1)
      expect(ModelSpecUtils.compare_model_versions("gpt-4", nil)).to eq(1)
      expect(ModelSpecUtils.compare_model_versions(nil, nil)).to eq(0)
    end
    
    it 'handles models without version numbers' do
      expect(ModelSpecUtils.compare_model_versions("mistral-large", "mistral-small")).to eq(0)
    end
  end
  
  describe '.extract_version' do
    it 'extracts decimal versions' do
      expect(ModelSpecUtils.extract_version("gpt-4.1-mini")).to eq([4, 1])
      expect(ModelSpecUtils.extract_version("claude-3.5-sonnet")).to eq([3, 5])
    end
    
    it 'extracts simple versions' do
      expect(ModelSpecUtils.extract_version("gpt-5")).to eq([5, 0])
      expect(ModelSpecUtils.extract_version("claude-3-haiku")).to eq([3, 0])
    end
    
    it 'returns [0, 0] for models without versions' do
      expect(ModelSpecUtils.extract_version("mistral-large")).to eq([0, 0])
      expect(ModelSpecUtils.extract_version("deepseek-chat")).to eq([0, 0])
    end
  end
  
  describe '.get_latest_version' do
    it 'returns the latest version for a provider' do
      latest = ModelSpecUtils.get_latest_version("gpt")
      expect(latest).to eq("gpt-5")
    end
    
    it 'handles providers with decimal versions' do
      latest = ModelSpecUtils.get_latest_version("claude")
      expect(latest).to eq("claude-3.5-sonnet-20241022")
    end
    
    it 'returns nil for unknown provider' do
      expect(ModelSpecUtils.get_latest_version("unknown")).to be_nil
    end
    
    it 'handles single model correctly' do
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({
        "single-model-1.0" => { "tool_capability" => true }
      })
      
      latest = ModelSpecUtils.get_latest_version("single")
      expect(latest).to eq("single-model-1.0")
    end
  end
  
  describe '.get_provider_strategy' do
    it 'returns correct strategy for each provider' do
      expect(ModelSpecUtils.get_provider_strategy("openai")).to eq(:latest)
      expect(ModelSpecUtils.get_provider_strategy("gpt")).to eq(:latest)
      expect(ModelSpecUtils.get_provider_strategy("claude")).to eq(:first)
      expect(ModelSpecUtils.get_provider_strategy("anthropic")).to eq(:first)
      expect(ModelSpecUtils.get_provider_strategy("gemini")).to eq(:first)
      expect(ModelSpecUtils.get_provider_strategy("deepseek")).to eq(:first)
      expect(ModelSpecUtils.get_provider_strategy("cohere")).to eq(:most_capable)
      expect(ModelSpecUtils.get_provider_strategy("grok")).to eq(:latest)
      expect(ModelSpecUtils.get_provider_strategy("xai")).to eq(:latest)
      expect(ModelSpecUtils.get_provider_strategy("mistral")).to eq(:first)
      expect(ModelSpecUtils.get_provider_strategy("perplexity")).to eq(:first)
    end
    
    it 'returns :first for unknown providers' do
      expect(ModelSpecUtils.get_provider_strategy("unknown")).to eq(:first)
    end
    
    it 'is case-insensitive' do
      expect(ModelSpecUtils.get_provider_strategy("OPENAI")).to eq(:latest)
      expect(ModelSpecUtils.get_provider_strategy("Claude")).to eq(:first)
    end
  end
  
  describe '.get_model_by_strategy' do
    context 'with :latest strategy' do
      it 'returns the latest version' do
        model = ModelSpecUtils.get_model_by_strategy("gpt", :latest)
        expect(model).to eq("gpt-5")
      end
    end
    
    context 'with :first strategy' do
      it 'returns the first model' do
        model = ModelSpecUtils.get_model_by_strategy("gpt", :first)
        expect(model).to eq("gpt-3.5-turbo")
      end
    end
    
    context 'with :most_capable strategy' do
      it 'returns model with most capabilities' do
        model = ModelSpecUtils.get_model_by_strategy("gpt", :most_capable)
        # GPT-5 has 3 capabilities (tool, vision, reasoning)
        expect(model).to eq("gpt-5")
      end
    end
    
    context 'with nil strategy' do
      it 'uses provider default strategy' do
        # OpenAI defaults to :latest
        model = ModelSpecUtils.get_model_by_strategy("gpt", nil)
        expect(model).to eq("gpt-5")
        
        # Claude defaults to :first
        model = ModelSpecUtils.get_model_by_strategy("claude", nil)
        expect(model).to eq("claude-3-haiku")
      end
    end
    
    it 'returns nil for unknown provider' do
      expect(ModelSpecUtils.get_model_by_strategy("unknown", :latest)).to be_nil
    end
  end
  
  describe 'PROVIDER_DEFAULTS constant' do
    it 'contains all major providers' do
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("openai")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("claude")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("gemini")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("deepseek")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("cohere")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("grok")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("mistral")
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to have_key("perplexity")
    end
    
    it 'each provider has required keys' do
      ModelSpecUtils::PROVIDER_DEFAULTS.each do |provider, config|
        expect(config).to have_key(:strategy)
        expect(config).to have_key(:fallback_chain)
        expect(config).to have_key(:special_cases)
        
        expect(config[:fallback_chain]).to be_an(Array)
        expect(config[:special_cases]).to be_a(Hash)
      end
    end
    
    it 'is frozen to prevent accidental modification' do
      expect(ModelSpecUtils::PROVIDER_DEFAULTS).to be_frozen
    end
  end
  
  describe 'integration scenarios' do
    it 'selects appropriate model for Code Interpreter' do
      # Code Interpreter needs tool capability
      model = ModelSpecUtils.find_model_by_capabilities(
        "gpt",
        [:tool],
        [:vision]  # Nice to have for analyzing output
      )
      expect(["gpt-4.1-mini", "gpt-5"]).to include(model)
      expect(ModelSpecUtils.model_supports?(model, "tool")).to be true
    end
    
    it 'selects appropriate model for Jupyter Notebook' do
      # Jupyter needs tool capability
      model = ModelSpecUtils.find_model_by_capabilities(
        "gemini",
        [:tool]
      )
      expect(["gemini-1.5-pro", "gemini-2.0-flash"]).to include(model)
    end
    
    it 'selects appropriate model for image tasks' do
      # Image tasks need vision capability
      model = ModelSpecUtils.find_model_by_capabilities(
        "claude",
        [:vision]
      )
      expect(model).to eq("claude-3.5-sonnet-20241022")
    end
    
    it 'handles provider migration gracefully' do
      # Simulate provider with no models
      allow(ModelSpecUtils).to receive(:load_model_spec).and_return({})
      
      model = ModelSpecUtils.get_model_by_strategy("openai", :latest)
      expect(model).to be_nil
      
      # Fallback chain would be used in actual implementation
      fallback = ModelSpecUtils::PROVIDER_DEFAULTS["openai"][:fallback_chain]
      expect(fallback).not_to be_empty
    end
  end
end