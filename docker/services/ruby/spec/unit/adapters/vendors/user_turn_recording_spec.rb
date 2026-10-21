# frozen_string_literal: true

require "spec_helper"
%w[openai claude gemini grok deepseek mistral cohere ollama].each do |p|
  require_relative "../../../../lib/monadic/adapters/vendors/#{p}_helper"
end

# Each provider's api_request, as the WebSocket runs it: the server has
# recorded the user message under the turn's request. The provider's fields
# go to this turn's message, no second copy is added, the page is shown its
# attachments, and the request tells the model about them while the session
# keeps the text as typed. The request itself fails at once; only what
# happens before it is checked.
RSpec.describe "Recording the user turn in each provider helper" do
  PROVIDERS_FOR_TURN = { OpenAIHelper => ["openai", "OPENAI_API_KEY"], ClaudeHelper => ["anthropic", "ANTHROPIC_API_KEY"],
                         GeminiHelper => ["gemini", "GEMINI_API_KEY"], GrokHelper => ["xai", "XAI_API_KEY"],
                         DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY"], MistralHelper => ["mistral", "MISTRAL_API_KEY"],
                         CohereHelper => ["cohere", "COHERE_API_KEY"], OllamaHelper => ["ollama", nil] }.freeze

  let(:refs) { [{ "attachment_id" => "a_0123456789abcdef", "role" => "input", "purpose" => "video", "display_name" => "clip.mp4" }] }
  let(:line) { "Attached video: clip.mp4 (attachment_id: a_0123456789abcdef)" }

  # Runs api_request for `text` with `messages` in the session; returns what
  # the page was shown, what was sent to the provider, and the session.
  def run_turn(mod, prov, key, text, messages)
    model = Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first || "spec-model"
    app = Struct.new(:settings).new({ "tools" => [], tools: [] })
    stub_const("APPS", { "SpecApp" => app })
    stub_const("CONFIG", key ? { key => "k" } : {})
    allow(OllamaHelper).to receive(:find_endpoint).and_return("http://ollama.invalid/api")
    h = Class.new(MonadicApp) { include mod }.new
    allow(h).to receive(:sleep)
    allow(h).to receive(:list_models).and_return([]) if mod == OllamaHelper
    res = double("res", status: HTTP::Response::Status.new(502), body: "<html>Bad Gateway</html>", code: 502, headers: {})
    sent = []
    allow(h).to receive(:post_json_with_retries) { |*args, **kw| sent << [args, kw].to_json; res }
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) { |*args, **kw| sent << [args, kw].to_json; res }
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)

    s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                        "message" => text, "temperature" => "0.5" },
          messages: messages }
    context = Monadic::Workspace::RequestContext.new(chat_id: "c_x", request_id: "q_current")
    out = []
    Monadic::Workspace::RequestContext.with(context) { h.api_request("user", s) { |r| out << r } }
    [out.find { |r| r.is_a?(Hash) && r["type"] == "user" }, sent.join, s]
  end

  PROVIDERS_FOR_TURN.each do |mod, (prov, key)|
    it "#{mod.name} adds its fields to this turn's message, not the earlier one with the same text" do
      earlier = { "mid" => "s1", "request_id" => "q_earlier", "role" => "user", "text" => "Describe it", "active" => true }
      current = { "mid" => "s2", "request_id" => "q_current", "role" => "user", "text" => "Describe it", "active" => true,
                  "attachments" => refs }
      messages = [{ "role" => "system", "text" => "S", "active" => true }, earlier,
                  { "role" => "assistant", "text" => "A clip.", "active" => true }, current]

      shown, sent, s = run_turn(mod, prov, key, "Describe it", messages)

      expect(s[:messages].count { |m| m["role"] == "user" }).to eq(2)
      expect(current).to have_key("html")
      expect(earlier).not_to have_key("html")
      expect(shown).not_to be_nil
      expect(shown["content"]["attachments"]).to eq(refs)
      expect(s[:messages].map { |m| m["mid"] }).to include(shown["content"]["mid"])
      expect(sent).to include(line)
      expect(current["text"]).to eq("Describe it")
    end

    it "#{mod.name} takes a message of attached files only" do
      current = { "mid" => "s2", "request_id" => "q_current", "role" => "user", "text" => "", "active" => true,
                  "attachments" => refs }
      messages = [{ "role" => "system", "text" => "S", "active" => true }, current]

      shown, sent, s = run_turn(mod, prov, key, "", messages)

      expect(s[:messages].count { |m| m["role"] == "user" }).to eq(1)
      expect(shown).not_to be_nil
      expect(shown["content"]["attachments"]).to eq(refs)
      expect(sent).to include(line)
      expect(current["text"]).to eq("")
    end
  end
end
