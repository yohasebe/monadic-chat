require "spec_helper"
require_relative "../../../lib/monadic/agents/second_opinion_agent"

RSpec.describe SecondOpinionAgent do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include SecondOpinionAgent
    end
  end
  
  let(:agent) { test_class.new }
  
  describe "#determine_provider_and_model" do
    context "provider name normalization" do
      it "normalizes claude/anthropic to claude" do
        expect(agent.send(:determine_provider_and_model, "claude", nil)[0]).to eq("claude")
        expect(agent.send(:determine_provider_and_model, "anthropic", nil)[0]).to eq("claude")
        expect(agent.send(:determine_provider_and_model, "Claude", nil)[0]).to eq("claude")
        expect(agent.send(:determine_provider_and_model, "ANTHROPIC", nil)[0]).to eq("claude")
      end
      
      it "normalizes xai/grok to grok" do
        expect(agent.send(:determine_provider_and_model, "xai", nil)[0]).to eq("grok")
        expect(agent.send(:determine_provider_and_model, "grok", nil)[0]).to eq("grok")
        expect(agent.send(:determine_provider_and_model, "XAI", nil)[0]).to eq("grok")
        expect(agent.send(:determine_provider_and_model, "Grok", nil)[0]).to eq("grok")
      end
      
      it "normalizes google/gemini to gemini" do
        expect(agent.send(:determine_provider_and_model, "google", nil)[0]).to eq("gemini")
        expect(agent.send(:determine_provider_and_model, "gemini", nil)[0]).to eq("gemini")
        expect(agent.send(:determine_provider_and_model, "Google", nil)[0]).to eq("gemini")
        expect(agent.send(:determine_provider_and_model, "GEMINI", nil)[0]).to eq("gemini")
      end
      
      it "normalizes gpt/openai to openai" do
        expect(agent.send(:determine_provider_and_model, "gpt", nil)[0]).to eq("openai")
        expect(agent.send(:determine_provider_and_model, "openai", nil)[0]).to eq("openai")
        expect(agent.send(:determine_provider_and_model, "GPT", nil)[0]).to eq("openai")
        expect(agent.send(:determine_provider_and_model, "OpenAI", nil)[0]).to eq("openai")
      end
    end
    
    context "model defaults" do
      it "uses correct default models for each provider" do
        expect(agent.send(:determine_provider_and_model, "claude", nil)[1]).to eq("claude-sonnet-4-20250514")
        expect(agent.send(:determine_provider_and_model, "openai", nil)[1]).to eq("gpt-5")
        expect(agent.send(:determine_provider_and_model, "gemini", nil)[1]).to eq("gemini-2.5-flash")
        expect(agent.send(:determine_provider_and_model, "grok", nil)[1]).to eq("grok-4-0709")
        expect(agent.send(:determine_provider_and_model, "mistral", nil)[1]).to eq("mistral-large-latest")
        expect(agent.send(:determine_provider_and_model, "cohere", nil)[1]).to eq("command-a-03-2025")
        expect(agent.send(:determine_provider_and_model, "perplexity", nil)[1]).to eq("sonar")
        expect(agent.send(:determine_provider_and_model, "deepseek", nil)[1]).to eq("deepseek-chat")
      end
    end
    
    context "with explicit model" do
      it "uses the provided model when specified" do
        expect(agent.send(:determine_provider_and_model, "claude", "claude-3-opus-20240229")).to eq(["claude", "claude-3-opus-20240229"])
        expect(agent.send(:determine_provider_and_model, "openai", "gpt-5")).to eq(["openai", "gpt-5"])
      end
      
      it "handles empty model strings by using defaults" do
        expect(agent.send(:determine_provider_and_model, "claude", "")[1]).to eq("claude-sonnet-4-20250514")
        expect(agent.send(:determine_provider_and_model, "openai", " ")[1]).to eq("gpt-5")
      end
    end
    
    context "incomplete Claude model names" do
      it "detects and fixes incomplete Claude model names" do
        # This simulates the case where the model name is cut off
        result = agent.send(:determine_provider_and_model, "claude", "claude-3-5-sonnet-2024-10")
        expect(result[1]).to eq("claude-sonnet-4-20250514")
      end
    end
  end
  
  describe "Provider-specific reasoning model detection" do
    context "Gemini models" do
      before do
        require_relative "../../../apps/second_opinion/second_opinion_gemini"
      end
      
      it "identifies thinking models as reasoning-based" do
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-2-5-thinking-exp-01-21")).to be true
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-2.5-thinking-exp")).to be true
      end
      
      it "identifies Gemini 2.5 models as reasoning-based" do
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-2.5-flash")).to be true
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-2.5-pro")).to be true
      end
      
      it "does not identify older models as reasoning-based" do
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-1.5-pro")).to be false
        expect(SecondOpinionGemini.is_reasoning_model?("gemini-1.0-pro")).to be false
      end
    end
    
    context "Mistral models" do
      before do
        require_relative "../../../apps/second_opinion/second_opinion_mistral"
      end
      
      it "identifies magistral models as reasoning-based" do
        expect(SecondOpinionMistral.is_reasoning_model?("magistral-2025")).to be true
        expect(SecondOpinionMistral.is_reasoning_model?("magistral")).to be true
      end
      
      it "does not identify regular models as reasoning-based" do
        expect(SecondOpinionMistral.is_reasoning_model?("mistral-large-latest")).to be false
        expect(SecondOpinionMistral.is_reasoning_model?("mistral-small")).to be false
      end
    end
    
    context "OpenAI models" do
      before do
        require_relative "../../../apps/second_opinion/second_opinion_openai"
      end
      
      it "does not identify any models as reasoning-based (o1/o3 don't use reasoning_effort)" do
        expect(SecondOpinionOpenAI.is_reasoning_model?("o1-preview")).to be false
        expect(SecondOpinionOpenAI.is_reasoning_model?("o1-mini")).to be false
        expect(SecondOpinionOpenAI.is_reasoning_model?("o3-mini")).to be false
        expect(SecondOpinionOpenAI.is_reasoning_model?("gpt-4.1")).to be false
        expect(SecondOpinionOpenAI.is_reasoning_model?("gpt-5")).to be false
      end
    end
    
    context "Other providers" do
      before do
        require_relative "../../../apps/second_opinion/second_opinion_claude"
        require_relative "../../../apps/second_opinion/second_opinion_cohere"
        require_relative "../../../apps/second_opinion/second_opinion_perplexity"
      end
      
      it "returns false for providers without reasoning models" do
        expect(SecondOpinionClaude.is_reasoning_model?("claude-3-5-sonnet-20241022")).to be false
        expect(SecondOpinionCohere.is_reasoning_model?("command-r")).to be false
        expect(SecondOpinionPerplexity.is_reasoning_model?("sonar")).to be false
      end
    end
    
    context "edge cases" do
      before do
        require_relative "../../../apps/second_opinion/second_opinion_gemini"
        require_relative "../../../apps/second_opinion/second_opinion_mistral"
        require_relative "../../../apps/second_opinion/second_opinion_openai"
      end
      
      it "handles nil values" do
        expect(SecondOpinionGemini.is_reasoning_model?(nil)).to be false
        expect(SecondOpinionMistral.is_reasoning_model?(nil)).to be false
        expect(SecondOpinionOpenAI.is_reasoning_model?(nil)).to be false
      end
    end
  end
  
  describe "#second_opinion_agent (real API tests)" do
    context "with actual API calls" do
      it "gets a second opinion from OpenAI" do
        result = agent.second_opinion_agent(
          user_query: "What is 2 + 2?",
          agent_response: "2 + 2 equals 4",
          provider: "openai",
          model: "gpt-4.1-mini"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("gpt-4.1-mini")
      end
      
      it "gets a second opinion from Claude" do
        result = agent.second_opinion_agent(
          user_query: "What is the capital of France?",
          agent_response: "The capital of France is Paris",
          provider: "claude",
          model: "claude-3-5-haiku-20241022"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("claude-3-5-haiku")
      end
    
      it "gets a second opinion from Gemini" do
        # Use the actual Gemini class to get proper reasoning configuration
        require_relative "../../../apps/second_opinion/second_opinion_gemini"
        gemini_agent = SecondOpinionGemini.new
        
        result = gemini_agent.second_opinion_agent(
          user_query: "What is 5 x 5?",
          agent_response: "5 x 5 equals 25",
          provider: "gemini",
          model: "gemini-2.5-flash"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("gemini-2.5-flash")
      end
      
      it "handles provider name variations" do
        # Test anthropic -> claude normalization
        result = agent.second_opinion_agent(
          user_query: "Simple math",
          agent_response: "1 + 1 = 2",
          provider: "anthropic",  # Should normalize to claude
          model: "claude-3-5-haiku-20241022"
        )
        
        expect(result[:model]).to include("claude")
        expect(result[:comments]).not_to be_empty
        
        # Test xai -> grok normalization
        result = agent.second_opinion_agent(
          user_query: "What is water?",
          agent_response: "Water is H2O",
          provider: "xai",  # Should normalize to grok
          model: "grok-4-0709"
        )
        
        expect(result[:model]).to include("grok")
        expect(result[:comments]).not_to be_empty
      end
      
      it "gets a second opinion from Mistral" do
        result = agent.second_opinion_agent(
          user_query: "What is the speed of light?",
          agent_response: "The speed of light is approximately 299,792,458 meters per second",
          provider: "mistral",
          model: "mistral-small-latest"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("mistral")
      end
      
      it "gets a second opinion from DeepSeek" do
        result = agent.second_opinion_agent(
          user_query: "What is Python?",
          agent_response: "Python is a high-level programming language",
          provider: "deepseek",
          model: "deepseek-chat"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("deepseek")
      end
      
      it "gets a second opinion from Cohere" do
        result = agent.second_opinion_agent(
          user_query: "What is AI?",
          agent_response: "AI stands for Artificial Intelligence",
          provider: "cohere",
          model: "command-r7b-12-2024"
        )
        
        expect(result[:comments]).not_to be_empty
        expect(result[:validity]).to match(/\d+\/10/)
        expect(result[:model]).to include("cohere")
      end
    end
  end
  
  describe "#get_provider_helper" do
    it "returns a helper that responds to send_query" do
      # Each helper should respond to send_query method
      expect(agent.send(:get_provider_helper, "openai")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "claude")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "gemini")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "mistral")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "cohere")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "perplexity")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "grok")).to respond_to(:send_query)
      expect(agent.send(:get_provider_helper, "deepseek")).to respond_to(:send_query)
    end
    
    it "raises an error for unknown providers" do
      expect { agent.send(:get_provider_helper, "unknown") }.to raise_error("Unknown provider: unknown")
    end
  end
end