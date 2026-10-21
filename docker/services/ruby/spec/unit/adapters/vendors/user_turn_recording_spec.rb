# frozen_string_literal: true

require "spec_helper"
%w[openai claude gemini grok deepseek mistral].each do |p|
  require_relative "../../../../lib/monadic/adapters/vendors/#{p}_helper"
end

# Each provider's api_request, as the WebSocket runs it: the server has
# recorded the user message under the turn's request, and the same text was
# sent earlier in the chat. The provider's fields go to this turn's message,
# no second copy is added, and the page is shown its attachments. The
# request itself fails at once; only what happens before it is checked.
RSpec.describe "Recording the user turn in each provider helper" do
  PROVIDERS_FOR_TURN = { OpenAIHelper => ["openai", "OPENAI_API_KEY"], ClaudeHelper => ["anthropic", "ANTHROPIC_API_KEY"],
                         GeminiHelper => ["gemini", "GEMINI_API_KEY"], GrokHelper => ["xai", "XAI_API_KEY"],
                         DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY"], MistralHelper => ["mistral", "MISTRAL_API_KEY"] }.freeze

  let(:refs) { [{ "attachment_id" => "a_0123456789abcdef", "role" => "input", "purpose" => "video", "display_name" => "clip.mp4" }] }

  PROVIDERS_FOR_TURN.each do |mod, (prov, key)|
    it "#{mod.name} adds its fields to this turn's message, not the earlier one with the same text" do
      model = Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first
      app = Struct.new(:settings).new({ "tools" => [], tools: [] })
      stub_const("APPS", { "SpecApp" => app })
      stub_const("CONFIG", { key => "k" })
      h = Class.new(MonadicApp) { include mod }.new
      allow(h).to receive(:sleep)
      res = double("res", status: HTTP::Response::Status.new(502), body: "<html>Bad Gateway</html>", code: 502, headers: {})
      allow(h).to receive(:post_json_with_retries).and_return(res)
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post).and_return(res)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)

      earlier = { "mid" => "s1", "request_id" => "q_earlier", "role" => "user", "text" => "Describe it", "active" => true }
      current = { "mid" => "s2", "request_id" => "q_current", "role" => "user", "text" => "Describe it", "active" => true,
                  "attachments" => refs }
      s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                          "message" => "Describe it", "temperature" => "0.5" },
            messages: [{ "role" => "system", "text" => "S", "active" => true }, earlier,
                       { "role" => "assistant", "text" => "A clip.", "active" => true }, current] }
      context = Monadic::Workspace::RequestContext.new(chat_id: "c_x", request_id: "q_current")
      out = []
      Monadic::Workspace::RequestContext.with(context) { h.api_request("user", s) { |r| out << r } }

      users = s[:messages].select { |m| m["role"] == "user" }
      expect(users.size).to eq(2)
      expect(current).to have_key("html")
      expect(earlier).not_to have_key("html")
      shown = out.find { |r| r.is_a?(Hash) && r["type"] == "user" }
      expect(shown).not_to be_nil
      expect(shown["content"]["attachments"]).to eq(refs)
      expect(s[:messages].map { |m| m["mid"] }).to include(shown["content"]["mid"])
    end
  end
end
