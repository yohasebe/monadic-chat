# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../../support/turn_settings_turn"
%w[openai claude gemini grok mistral cohere deepseek ollama].each do |name|
  require_relative "../../../../lib/monadic/adapters/vendors/#{name}_helper"
end

# The picture of the work screen a user sent with a message goes with that
# message's requests (the request that returns a tool's result too), once
# in each, and with no later message's; the chat's messages keep only its
# reference.
RSpec.describe "A picture of the work screen sent with a message" do
  include TurnSettingsTurn

  PICTURED = {
    "OpenAI" => [OpenAIHelper, "openai", "OPENAI_API_KEY", StreamContract::Responses, :sse],
    "Claude" => [ClaudeHelper, "anthropic", "ANTHROPIC_API_KEY", StreamContract::Claude, :sse],
    "Gemini" => [GeminiHelper, "gemini", "GEMINI_API_KEY", StreamContract::Gemini, :sse],
    "Grok" => [GrokHelper, "xai", "XAI_API_KEY", StreamContract::Responses, :sse],
    "Mistral" => [MistralHelper, "mistral", "MISTRAL_API_KEY", StreamContract::ChatCompletions, :sse],
    "Cohere" => [CohereHelper, "cohere", "COHERE_API_KEY", StreamContract::Cohere, :ndjson],
    "DeepSeek" => [DeepSeekHelper, "deepseek", "DEEPSEEK_API_KEY", StreamContract::ChatCompletions, :sse],
    "Ollama" => [OllamaHelper, "ollama", nil, StreamContract::Ollama, :ndjson]
  }.freeze

  let(:bytes) do
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [7, 5].pack("NN") + "\x08\x02\x00\x00\x00".b + "PICTURED-WORK-SCREEN".b
  end
  let(:encoded) { Base64.strict_encode64(bytes) }

  def model_of(provider)
    return "seeing-local-model" if provider == "ollama"

    Monadic::Utils::ModelSpec.get_provider_models(provider, "chat").find do |m|
      Monadic::Utils::ModelSpec.get_model_property(m, "vision_capability") == true
    end
  end

  def turn(name, picture:, messages: nil, picture_chat: nil, text: "What is this?")
    helper, provider, key, format, kind = PICTURED.fetch(name)
    model = model_of(provider)
    if helper == OllamaHelper
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://localhost:11434/api")
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return({ capabilities: %w[completion tools vision] })
    end
    turn_bodies(helper, format: format, kind: kind, key: key, models: [model], picture: picture ? bytes : nil,
                picture_chat: picture_chat, messages: messages,
                message: { "model" => model, "context_size" => "10", "message" => text })
  end

  def count(body, text) = JSON.generate(body).scan(text).size

  PICTURED.each_key do |name|
    it "#{name}: goes with every request of its message, once, and says what it is" do
      sent = turn(name, picture: true)
      expect(sent.size).to eq(2)
      expect(sent.map { |b| count(b, encoded) }).to eq([1, 1])
      expect(sent.map { |b| count(b, "translucent orange ellipse") }).to eq([1, 1])
    end

    it "#{name}: carries none of the item's id or version, nor any word of the message" do
      word = "Quillfeather"
      sent = turn(name, picture: true, text: "What does #{word} mean here?")
      plain = turn(name, picture: false, text: "What does #{word} mean here?")
      sent.each do |b|
        expect(count(b, TurnSettingsTurn::PICTURED_ITEM)).to eq(0)
        expect(count(b, TurnSettingsTurn::PICTURED_VERSION)).to eq(0)
      end
      expect(sent.map { |b| count(b, word) }).to eq(plain.map { |b| count(b, word) })
    end

    it "#{name}: goes with no later message, and the chat keeps only its reference" do
      turn(name, picture: true)
      earlier = @turn_messages
      expect(JSON.generate(earlier)).not_to include(encoded)
      later = turn(name, picture: false, messages: earlier)
      expect(later).not_to be_empty
      later.each { |b| expect(count(b, encoded)).to eq(0) }
    end
  end

  # Claude, Gemini and Cohere add it from the request's context: only when
  # it was taken for the session's chat.
  %w[Claude Gemini Cohere].each do |name|
    it "#{name}: goes with no request of another chat" do
      sent = turn(name, picture: true, picture_chat: Monadic::Workspace::Ids.generate(:chat))
      expect(sent).not_to be_empty
      sent.each { |b| expect(count(b, encoded)).to eq(0) }
    end
  end
end
