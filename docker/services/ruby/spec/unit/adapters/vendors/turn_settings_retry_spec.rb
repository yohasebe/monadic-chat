# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/turn_settings_turn"
%w[openai claude gemini grok mistral cohere deepseek ollama].each do |name|
  require_relative "../../../../lib/monadic/adapters/vendors/#{name}_helper"
end

# A request sent again within a turn is sent with the settings of the turn's
# message, whatever the chat's kept parameters have become since the first
# attempt.
RSpec.describe "A request sent again within a turn" do
  include TurnSettingsTurn

  # name => [helper, provider of the model spec, key, stream format, line format]
  RETRYING = {
    "OpenAI" => [OpenAIHelper, "openai", "OPENAI_API_KEY", StreamContract::Responses, :sse],
    "Claude" => [ClaudeHelper, "anthropic", "ANTHROPIC_API_KEY", StreamContract::Claude, :sse],
    "Gemini" => [GeminiHelper, "gemini", "GEMINI_API_KEY", StreamContract::Gemini, :sse],
    "Grok" => [GrokHelper, "xai", "XAI_API_KEY", StreamContract::Responses, :sse],
    "Mistral" => [MistralHelper, "mistral", "MISTRAL_API_KEY", StreamContract::ChatCompletions, :sse],
    "Cohere" => [CohereHelper, "cohere", "COHERE_API_KEY", StreamContract::Cohere, :ndjson],
    "DeepSeek" => [DeepSeekHelper, "deepseek", "DEEPSEEK_API_KEY", StreamContract::ChatCompletions, :sse],
    "Ollama" => [OllamaHelper, "ollama", nil, StreamContract::Ollama, :ndjson]
  }.freeze

  # The models of a provider: the one the message names, and another the
  # chat is changed to meanwhile.
  def models_of(provider)
    return %w[first-local-model second-local-model] if provider == "ollama"

    Monadic::Utils::ModelSpec.get_provider_models(provider, "chat").first(2)
  end

  def run(name, **options)
    helper, provider, key, format, kind = RETRYING.fetch(name)
    model, other = models_of(provider)
    if helper == OllamaHelper
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://localhost:11434/api")
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return({ capabilities: %w[completion tools thinking] })
    end
    allow(SecureRandom).to receive(:hex).and_return("abcd1234")
    bodies = turn_bodies(helper, format: format, kind: kind, key: key, models: [model, other],
                         message: { "model" => model, "context_size" => "5", "temperature" => "0.2",
                                    "max_tokens" => "300", "show_thinking" => false, "websearch" => false },
                         change: { "model" => other, "temperature" => "1.4", "max_tokens" => "9000",
                                   "show_thinking" => true, "websearch" => true, "reasoning_effort" => "high",
                                   "presence_penalty" => "1.5" },
                         **options)
    [bodies, @turn_uris.dup, @turn_failed.dup]
  end

  RETRYING.each_key do |name|
    it "#{name}: is the same request after a failed connection, the chat's settings changed meanwhile" do
      undisturbed, uris, = run(name, change: {})
      again, uris_again, failed = run(name, failing: 1)
      expect(failed.size).to eq(1)
      expect(again.size).to eq(undisturbed.size)
      expect(again).to eq(undisturbed)
      expect(uris_again).to eq(uris)
      expect(failed.first).to eq(undisturbed.first)
    end
  end

  # DeepSeek asks again, from the start, for a reply that wrote its tool
  # calls as text it cannot read.
  it "DeepSeek: asks again for an unreadable reply with the same settings" do
    unreadable = StreamContract::ChatCompletions.text(["<｜DSML｜invoke name=\"a\">" * 5])
    answer = StreamContract::ChatCompletions.text(["Done."])
    undisturbed, = run("DeepSeek", change: {}, answers: [answer])
    asked_again, = run("DeepSeek", answers: [unreadable, answer], failing: 1)
    expect(asked_again.size).to eq(2)
    expect(asked_again).to all(eq(undisturbed.first))
  end
end
