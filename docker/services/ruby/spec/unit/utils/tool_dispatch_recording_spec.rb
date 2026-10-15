# frozen_string_literal: true

require "spec_helper"
%w[openai claude gemini grok mistral cohere deepseek ollama].each do |p|
  require_relative "../../../lib/monadic/adapters/vendors/#{p}_helper"
end

# Each provider records the tool names of a chat request right before sending
# it, so the dispatch guard knows what was offered.
RSpec.describe "Recording the offered tools before a chat request" do
  PROVIDERS_FOR_RECORDING = { OpenAIHelper => ["openai", "OPENAI_API_KEY"], ClaudeHelper => ["anthropic", "ANTHROPIC_API_KEY"], GeminiHelper => ["gemini", "GEMINI_API_KEY"],
             GrokHelper => ["xai", "XAI_API_KEY"], MistralHelper => ["mistral", "MISTRAL_API_KEY"], CohereHelper => ["cohere", "COHERE_API_KEY"],
             DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY"], OllamaHelper => ["ollama", "OLLAMA_X"] }
  PROVIDERS_FOR_RECORDING.each do |mod, (prov, key)|
    it mod.name do
      model = Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first || "llama3"
      tools = [{ "type" => "function", "function" => { "name" => "declared_tool", "description" => "d", "parameters" => { "type" => "object", "properties" => {} } } }]
      tools = { "function_declarations" => [{ "name" => "declared_tool", "description" => "d", "parameters" => { "type" => "object", "properties" => {} } }] } if mod == GeminiHelper
      tools = [{ "name" => "declared_tool", "description" => "d", "input_schema" => { "type" => "object", "properties" => {} } }] if mod == ClaudeHelper
      app = Struct.new(:settings).new({ "tools" => tools, tools: tools })
      stub_const("APPS", { "SpecApp" => app }); stub_const("CONFIG", { key => "k" })
      h = Class.new(MonadicApp) { include mod }.new
      chain = double("http"); allow(chain).to receive(:timeout).and_return(chain); allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) { raise "STOP-POST" }
      allow(HTTP).to receive(:headers).and_return(chain); allow(HTTP).to receive(:timeout).and_return(chain)
      allow(h).to receive(:post_json_with_retries) { raise "STOP-POST" }
      if mod == OllamaHelper
        allow(OllamaHelper).to receive(:find_endpoint).and_return("http://x")
        allow(h).to receive(:list_models).and_return([model])
        allow(chain).to receive(:get) { raise "STOP-GET" }
        allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return(nil)
        allow(chain).to receive(:post) { |uri, **| raise(uri.to_s.end_with?("/chat") ? "STOP-CHAT" : "STOP-OTHER #{uri}") }
      end
      s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100", "message" => "hi", "tools" => tools.to_json, "temperature" => "0.5" },
            messages: [{ "role" => "system", "text" => "S", "active" => true }] }
      out = []
      begin; h.api_request("user", s) { |r| out << r }; rescue => e; out << "EXC #{e.message[0,80]}"; end
      expect(out.last.to_s).to include("STOP-")
      expect(Monadic::Utils::ToolDispatchGuard.offered(s, "SpecApp")).to eq(["declared_tool"])
    end
  end
end
