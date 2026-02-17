# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/agents/second_opinion_agent"

# Ensure WebSocketHelper is defined for progress tests
module WebSocketHelper
  def self.send_progress_fragment(fragment, session_id = nil)
    # no-op in tests
  end
end unless defined?(WebSocketHelper)

RSpec.describe SecondOpinionAgent, "#parallel_second_opinions" do
  # Create a test class that includes the module with a stubbed second_opinion_agent
  let(:test_class) do
    Class.new do
      include SecondOpinionAgent

      # Override second_opinion_agent for unit testing (no real API calls)
      def second_opinion_agent(user_query: "", agent_response: "", provider: nil, model: nil)
        target_provider, target_model = send(:determine_provider_and_model, provider, model)
        sleep(0.05) # simulate latency
        {
          comments: "Test comment from #{target_provider}",
          validity: "8/10",
          model: "#{target_provider}:#{target_model}"
        }
      end
    end
  end

  let(:agent) { test_class.new }
  let(:session) { {} }

  describe "input validation" do
    it "returns error when providers is not an array" do
      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: "claude", session: session
      )
      expect(result).to include("Error")
      expect(result).to include("at least 2")
    end

    it "returns error when providers has fewer than 2 entries" do
      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["claude"], session: session
      )
      expect(result).to include("Error")
      expect(result).to include("at least 2")
    end

    it "returns error when providers has more than 5 entries" do
      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude", "gemini", "mistral", "cohere", "grok"],
        session: session
      )
      expect(result).to include("Error")
      expect(result).to include("at most 5")
    end
  end

  describe "API key availability" do
    it "skips providers without API keys configured" do
      # Temporarily remove a key to test skipping
      original = CONFIG["MISTRAL_API_KEY"]
      CONFIG.delete("MISTRAL_API_KEY") if CONFIG.is_a?(Hash)
      ENV.delete("MISTRAL_API_KEY")

      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude", "mistral"], session: session
      )

      # Restore key
      if original
        CONFIG["MISTRAL_API_KEY"] = original if CONFIG.is_a?(Hash)
        ENV["MISTRAL_API_KEY"] = original
      end

      # Should still succeed with 2 providers (openai + claude)
      expect(result).to include("Multi-Provider Verification Results")
      expect(result).to include("Openai")
      expect(result).to include("Claude")
    end

    it "returns error when fewer than 2 providers are available" do
      # Remove all keys except one
      saved = {}
      %w[ANTHROPIC_API_KEY GEMINI_API_KEY].each do |k|
        saved[k] = CONFIG[k] if CONFIG.is_a?(Hash) && CONFIG[k]
        CONFIG.delete(k) if CONFIG.is_a?(Hash)
        ENV.delete(k)
      end

      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["claude", "gemini"], session: session
      )

      # Restore keys
      saved.each do |k, v|
        CONFIG[k] = v if CONFIG.is_a?(Hash)
        ENV[k] = v
      end

      expect(result).to include("Error")
      expect(result).to include("At least 2 providers must be available")
    end
  end

  describe "normal parallel execution" do
    it "returns results from all requested providers" do
      result = agent.parallel_second_opinions(
        user_query: "What is 2+2?",
        agent_response: "2+2 equals 4",
        providers: ["openai", "claude", "gemini"],
        session: session
      )

      expect(result).to include("Multi-Provider Verification Results")
      expect(result).to include("Openai")
      expect(result).to include("Claude")
      expect(result).to include("Gemini")
      expect(result).to include("8/10")
    end

    it "handles provider name normalization (anthropic -> claude)" do
      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["anthropic", "gpt"], session: session
      )

      expect(result).to include("Multi-Provider Verification Results")
      expect(result).to include("Claude")
      expect(result).to include("Openai")
    end
  end

  describe "partial failure handling" do
    let(:partial_failure_class) do
      Class.new do
        include SecondOpinionAgent

        def second_opinion_agent(user_query: "", agent_response: "", provider: nil, model: nil)
          target_provider, = send(:determine_provider_and_model, provider, model)
          raise "API timeout" if target_provider == "gemini"

          {
            comments: "Comment from #{target_provider}",
            validity: "7/10",
            model: "#{target_provider}:test-model"
          }
        end
      end
    end

    it "includes successful results and error for failed provider" do
      agent_with_failure = partial_failure_class.new
      result = agent_with_failure.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude", "gemini"], session: session
      )

      expect(result).to include("Multi-Provider Verification Results")
      expect(result).to include("Comment from openai")
      expect(result).to include("Comment from claude")
      expect(result).to include("Error: API timeout")
    end
  end

  describe "session call depth" do
    it "sets call_depth_per_turn to 99_999 after execution" do
      session_hash = {}
      agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude"], session: session_hash
      )

      expect(session_hash[:call_depth_per_turn]).to eq(99_999)
    end
  end

  describe "progress reporting" do
    it "sends progress updates via WebSocketHelper" do
      progress_calls = []
      allow(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _session_id|
        progress_calls << fragment
      end

      agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude"], session: session
      )

      # Should have initial progress + one per completion
      expect(progress_calls.length).to be >= 2
      expect(progress_calls.first["source"]).to eq("MultiProviderVerification")
      expect(progress_calls.first["parallel_progress"]["total"]).to eq(2)
    end

    it "includes step_progress in progress fragments" do
      progress_calls = []
      allow(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _session_id|
        progress_calls << fragment
      end

      agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude"], session: session
      )

      progress_calls.each do |fragment|
        sp = fragment["step_progress"]
        expect(sp).not_to be_nil
        expect(sp["mode"]).to eq("parallel")
        expect(sp["total"]).to eq(2)
        expect(sp["steps"]).to all(be_a(String))
      end
    end
  end

  describe "result formatting" do
    it "includes synthesis instruction at the end" do
      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude"], session: session
      )

      expect(result).to include("Do NOT call any more tools")
    end

    it "includes skipped providers note when some are skipped" do
      # Remove one key
      original = CONFIG["DEEPSEEK_API_KEY"] if CONFIG.is_a?(Hash)
      CONFIG.delete("DEEPSEEK_API_KEY") if CONFIG.is_a?(Hash)
      ENV.delete("DEEPSEEK_API_KEY")

      result = agent.parallel_second_opinions(
        user_query: "test", agent_response: "test",
        providers: ["openai", "claude", "deepseek"], session: session
      )

      # Restore
      if original
        CONFIG["DEEPSEEK_API_KEY"] = original if CONFIG.is_a?(Hash)
        ENV["DEEPSEEK_API_KEY"] = original
      end

      expect(result).to include("Skipped")
      expect(result).to include("deepseek")
    end
  end
end
