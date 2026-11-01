# frozen_string_literal: true

require "spec_helper"
%w[openai claude gemini grok deepseek mistral].each do |p|
  require_relative "../../../../lib/monadic/adapters/vendors/#{p}_helper"
end

# Ends a spec whose helper would otherwise retry for ever. Not a
# StandardError, which the helpers rescue as one more failed attempt (and
# retry): run against a helper without the retry limit, a plain raise here
# kept one spec looping for 20 hours.
class RunawayRetry < Exception; end # rubocop:disable Lint/InheritException

# A request that keeps failing on the network is tried MAX_RETRIES more times
# and then reported as an error, instead of being retried for ever.
RSpec.describe "Retrying a chat request that keeps failing" do
  PROVIDERS_FOR_RETRY = { OpenAIHelper => ["openai", "OPENAI_API_KEY"], ClaudeHelper => ["anthropic", "ANTHROPIC_API_KEY"],
                          GeminiHelper => ["gemini", "GEMINI_API_KEY"], GrokHelper => ["xai", "XAI_API_KEY"],
                          DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY"], MistralHelper => ["mistral", "MISTRAL_API_KEY"] }.freeze

  PROVIDERS_FOR_RETRY.each do |mod, (prov, key)|
    it "#{mod.name} stops after MAX_RETRIES and reports the error" do
      model = Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first
      app = Struct.new(:settings).new({ "tools" => [], tools: [] })
      stub_const("APPS", { "SpecApp" => app })
      stub_const("CONFIG", { key => "k" })
      h = Class.new(MonadicApp) { include mod }.new
      allow(h).to receive(:sleep)
      attempts = 0
      fail_request = lambda do |*|
        attempts += 1
        raise RunawayRetry, "runaway retry" if attempts > 50

        raise HTTP::ConnectionError, "offline"
      end
      # Some helpers send through post_json_with_retries, others through
      # the HTTP chain directly; both fail the same way.
      allow(h).to receive(:post_json_with_retries, &fail_request)
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post, &fail_request)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
      s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                          "message" => "hi", "temperature" => "0.5" },
            messages: [{ "role" => "system", "text" => "S", "active" => true }] }
      out = []
      result = h.api_request("user", s) { |r| out << r }

      expect(attempts).to eq(mod::MAX_RETRIES + 1)
      expect(Array(result).last).to include("type" => "error")
      expect(out.map { |r| r.is_a?(Hash) ? r["type"] : nil }).to include("error")
      expect(out.to_s).not_to include("runaway retry")
    end
  end

  # A proxy or gateway can answer with an HTML page instead of JSON.
  { OpenAIHelper => ["openai", "OPENAI_API_KEY"], GeminiHelper => ["gemini", "GEMINI_API_KEY"],
    DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY"] }.each do |mod, (prov, key)|
    it "#{mod.name} reports the HTTP status of an error page that is not JSON" do
      model = Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first
      app = Struct.new(:settings).new({ "tools" => [], tools: [] })
      stub_const("APPS", { "SpecApp" => app })
      stub_const("CONFIG", { key => "k" })
      h = Class.new(MonadicApp) { include mod }.new
      allow(h).to receive(:sleep)
      res = double("res", status: HTTP::Response::Status.new(502), body: "<html><body>Bad Gateway</body></html>",
                          code: 502, headers: {})
      allow(h).to receive(:post_json_with_retries).and_return(res)
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post).and_return(res)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
      s = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                          "message" => "hi", "temperature" => "0.5" },
            messages: [{ "role" => "system", "text" => "S", "active" => true }] }
      result = h.api_request("user", s) { |_| }
      error = Array(result).last
      expect(error["type"]).to eq("error")
      expect(error["content"].to_s).to include("502")
      expect(error["content"].to_s).not_to match(/unexpected token|ParserError/i)
    end
  end

  EXECUTE_CALLS = { OpenAIHelper => :execute_openai_api_call, ClaudeHelper => :execute_claude_api_call,
                    GeminiHelper => :execute_gemini_api_call, GrokHelper => :execute_grok_api_call,
                    DeepSeekHelper => :execute_deepseek_api_call }.freeze

  EXECUTE_CALLS.each do |mod, call|
    prov, key = PROVIDERS_FOR_RETRY.fetch(mod)

    def build_helper(mod, prov, key)
      app = Struct.new(:settings).new({ "tools" => [], tools: [] })
      stub_const("APPS", { "SpecApp" => app })
      stub_const("CONFIG", { key => "k" })
      h = Class.new(MonadicApp) { include mod }.new
      allow(h).to receive(:sleep)
      session = { parameters: { "app_name" => "SpecApp", "model" => Monadic::Utils::ModelSpec.get_provider_models(prov, "chat")&.first,
                                "context_size" => "5", "max_tokens" => "100", "message" => "hi", "temperature" => "0.5" },
                  messages: [{ "role" => "system", "text" => "S", "active" => true }] }
      [h, session]
    end

    it "#{mod.name} does not send the request again once part of the reply has been shown" do
      h, session = build_helper(mod, prov, key)
      attempts = 0
      allow(h).to receive(call) do |*_args, **_kw, &blk|
        attempts += 1
        raise RunawayRetry, "runaway retry" if attempts > 50

        blk&.call({ "type" => "wait", "content" => "THINKING" })
        blk&.call({ "type" => "fragment", "content" => "Hel" })
        raise HTTP::ConnectionError, "dropped"
      end
      result = h.api_request("user", session) { |_| }
      expect(attempts).to eq(1)
      expect(Array(result).last["type"]).to eq("error")
    end

    it "#{mod.name} retries after a wait notice only, sending the request body as it was built" do
      h, session = build_helper(mod, prov, key)
      bodies = []
      allow(h).to receive(call) do |*args, **kw, &blk|
        body = kw[:body] || args[1]
        raise RunawayRetry, "runaway retry" if bodies.size > 50

        bodies << Marshal.load(Marshal.dump(body))
        body["__added_by_the_call"] = true
        blk&.call({ "type" => "wait", "content" => "THINKING" })
        raise HTTP::ConnectionError, "offline"
      end
      h.api_request("user", session) { |_| }
      expect(bodies.size).to eq(mod::MAX_RETRIES + 1)
      expect(bodies.none? { |b| b.key?("__added_by_the_call") }).to be true
    end
  end

  it "ClaudeHelper retries the fallback model after an unavailable-model notice, without asking for the unavailable model again" do
    model = "claude-fable-5-1"
    fallback = Monadic::Utils::ModelSpec.get_model_property(model, "unavailable_fallback")
    expect(fallback).to be_a(String)
    app = Struct.new(:settings).new({ "tools" => [], tools: [] })
    stub_const("APPS", { "SpecApp" => app })
    stub_const("CONFIG", { "ANTHROPIC_API_KEY" => "k" })
    h = Class.new(MonadicApp) { include ClaudeHelper }.new
    allow(h).to receive(:sleep)
    models = []
    not_found = double("res", status: HTTP::Response::Status.new(404),
                              body: JSON.generate("error" => { "type" => "not_found_error", "message" => "unavailable" }))
    allow(h).to receive(:post_json_with_retries) do |_http, _uri, body, **|
      models << body["model"]
      raise RunawayRetry, "runaway" if models.size > 50
      next not_found if body["model"] == model

      raise HTTP::ConnectionError, "offline"
    end
    session = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                              "message" => "hi" },
                messages: [{ "role" => "system", "text" => "S", "active" => true }] }
    sent = []
    result = h.api_request("user", session) { |r| sent << r }

    expect(models.first).to eq(model)
    expect(models.drop(1)).to eq([fallback] * (ClaudeHelper::MAX_RETRIES + 1))
    expect(sent.map { |r| r["type"] }).to include("system_info")
    expect(Array(result).last["type"]).to eq("error")
  end
end
