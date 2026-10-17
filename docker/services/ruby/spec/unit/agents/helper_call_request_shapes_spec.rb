# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/provider_response"
require_relative "../../../lib/monadic/agents/context_extractor_agent"
require_relative "../../../lib/monadic/agents/image_analysis_agent"
require_relative "../../../lib/monadic/shared_tools/parallel_dispatch"

# The short helper calls that talk to the provider APIs directly (context
# extraction, image description, parallel sub-agents) take what a model
# accepts from the catalog, not from its name. Each of the cases below sent
# a parameter the model refuses, or read only the first reply block, and
# failed against the live API on 2026-10-17 with the default models.
RSpec.describe "Helper-call request shapes", :no_api do
  let(:rp) { Monadic::Utils::ProviderResponse }
  let(:spec) { Monadic::Utils::ModelSpec }

  describe Monadic::Utils::ProviderResponse do
    it "reads an error in any of the shapes providers use" do
      expect(rp.error_message('{"error":{"message":"bad model"}}')).to eq("bad model")
      expect(rp.error_message('{"error":"Image has 64 total pixels"}')).to eq("Image has 64 total pixels")
      expect(rp.error_message('{"message":"top_p must be 1 when using greedy sampling."}')).to include("top_p")
      expect(rp.error_message("not json")).to eq("not json")
    end

    it "collects every text block of a Claude reply, after any thinking block" do
      content = [{ "type" => "thinking", "thinking" => "" }, { "type" => "text", "text" => "Red" }]
      expect(rp.claude_text(content)).to eq("Red")
      expect(rp.claude_text([{ "type" => "thinking", "thinking" => "" }])).to be_nil
    end

    it "reads chat-completions content given as a string or as thinking and text parts" do
      expect(rp.message_text("hi")).to eq("hi")
      parts = [{ "type" => "thinking", "thinking" => [] }, { "type" => "text", "text" => "{\"a\":1}" }]
      expect(rp.message_text(parts)).to eq("{\"a\":1}")
    end

    it "keeps a short Claude request light on a model that thinks by default" do
      light = rp.claude_light_request("claude-sonnet-5-5", 1000)
      expect(light[:output_config]).to eq(effort: "low")
      expect(light[:max_tokens]).to be >= 4000
      expect(rp.claude_light_request("claude-haiku-4-5-20251001", 1000)).to eq(max_tokens: 1000)
    end
  end

  describe "ModelSpec.lowest_reasoning_effort" do
    it "is none where the model accepts it, else the lowest level, else nothing" do
      expect(spec.lowest_reasoning_effort("gpt-6-luna")).to eq("none")
      expect(spec.lowest_reasoning_effort("gpt-6.1-sol")).to eq("low")
      expect(spec.lowest_reasoning_effort("claude-haiku-5-5")).to eq("low")
      expect(spec.lowest_reasoning_effort("mistral-large-4")).to eq("none")
      expect(spec.lowest_reasoning_effort("claude-haiku-4-5-20251001")).to be_nil
    end
  end

  describe "parallel dispatch sub-calls" do
    let(:app) { Object.new.extend(MonadicSharedTools::ParallelDispatch) }
    let(:http) { double("http") }
    let(:sent) { [] }

    def stub_post(reply)
      allow(HTTP).to receive(:headers).and_return(http)
      allow(http).to receive(:timeout).and_return(http)
      allow(http).to receive(:post) do |_url, json:|
        sent << json
        double(status: 200, body: double(to_s: reply.to_json))
      end
    end

    it "sends temperature only to a model the catalog gives one, with top_p 1" do
      stub_post({ "choices" => [{ "message" => { "content" => "ok" } }] })
      app.send(:openai_compat_sub_call, "https://api.openai.com/v1/chat/completions", "k", "gpt-6.1-sol", "p", 10)
      app.send(:openai_compat_sub_call, "https://api.mistral.ai/v1/chat/completions", "k", "mistral-large-4", "p", 10)
      expect(sent[0]).not_to have_key("temperature")
      expect(sent[1]).to include("temperature" => 0.0, "top_p" => 1.0)
    end

    it "reads a Mistral reply given as thinking and text parts" do
      stub_post({ "choices" => [{ "message" => { "content" => [{ "type" => "thinking", "thinking" => [] },
                                                                { "type" => "text", "text" => "hi" }] } }] })
      expect(app.send(:openai_compat_sub_call, "https://api.mistral.ai/v1/chat/completions", "k", "mistral-large-4", "p", 10)).to eq("hi")
    end

    it "leaves temperature out for Claude models that refuse it, and reads past thinking" do
      stub_post({ "content" => [{ "type" => "thinking", "thinking" => "" }, { "type" => "text", "text" => "hi" }] })
      expect(app.send(:anthropic_sub_call, "https://api.anthropic.com/v1/messages", "k", "claude-sonnet-5-5", "p", 10)).to eq("hi")
      app.send(:anthropic_sub_call, "https://api.anthropic.com/v1/messages", "k", "claude-haiku-4-5-20251001", "p", 10)
      expect(sent[0]).not_to have_key("temperature")
      expect(sent[1]).to include("temperature" => 0.0)
    end
  end

  describe "context extraction" do
    let(:agent) { Object.new.extend(ContextExtractorAgent) }
    let(:sent) { [] }

    def stub_request(reply)
      allow(agent).to receive(:make_http_request) { |_uri, body, _headers| sent << body; reply.to_json }
    end

    it "asks a reasoning OpenAI model for its lowest effort instead of a temperature" do
      stub_request({ "choices" => [{ "message" => { "content" => "{}" } }] })
      agent.call_provider_api("openai", "gpt-6.1-sol", "s", "k")
      expect(sent.last).to include("reasoning_effort" => "low")
      expect(sent.last).not_to have_key("temperature")
    end

    it "keeps temperature away from Claude models that refuse it and thinks lightly" do
      stub_request({ "content" => [{ "type" => "thinking", "thinking" => "" }, { "type" => "text", "text" => "{\"t\":1}" }] })
      expect(agent.call_provider_api("anthropic", "claude-sonnet-5-5", "s", "k")).to eq("{\"t\":1}")
      expect(sent.last).not_to have_key("temperature")
      expect(sent.last["output_config"]).to eq(effort: "low")
    end

    it "says none to Mistral Large 4 and reads its parts" do
      stub_request({ "choices" => [{ "message" => { "content" => [{ "type" => "text", "text" => "{}" }] } }] })
      expect(agent.call_provider_api("mistral", "mistral-large-4", "s", "k")).to eq("{}")
      expect(sent.last).to include("reasoning_effort" => "none")
    end

    it "turns DeepSeek thinking off for every DeepSeek chat model" do
      stub_request({ "choices" => [{ "message" => { "content" => "{}" } }] })
      agent.call_provider_api("deepseek", "deepseek-flash", "s", "k")
      expect(sent.last["thinking"]).to eq("type" => "disabled")
    end
  end

  describe "Mistral chat requests" do
    let(:app_helper) { Class.new(MonadicApp) { include MistralHelper }.new }

    before do
      stub_const("APPS", { "SpecApp" => Struct.new(:settings).new({}) })
      stub_const("CONFIG", { "MISTRAL_API_KEY" => "test-key" })
    end

    def send_with(reply, **options)
      body = nil
      allow(app_helper).to receive(:post_json_with_retries) do |_http, _uri, b, **|
        body = b
        double(status: double(success?: true), body: reply.to_json)
      end
      result = app_helper.send_query({ "messages" => [{ "role" => "user", "content" => "hi" }] }.merge(options),
                                     model: "mistral-large-4")
      [body, result]
    end

    it "adds top_p 1 to a temperature of 0, which Large 4 requires for greedy sampling" do
      body, = send_with({ "choices" => [{ "message" => { "content" => "ok" } }] }, "temperature" => 0.0)
      expect(body).to include("temperature" => 0.0, "top_p" => 1.0, "reasoning_effort" => "none")
    end

    it "returns the text of a reply given as thinking and text parts" do
      parts = [{ "type" => "thinking", "thinking" => [] }, { "type" => "text", "text" => "answer" }]
      _, result = send_with({ "choices" => [{ "message" => { "content" => parts } }] })
      expect(result).to eq("answer")
    end
  end

  describe "image description with Claude" do
    let(:agent) { Object.new.extend(ImageAnalysisAgent) }
    let(:image) { { base64: "AAA=", mime_type: "image/png" } }

    it "keeps a model that thinks by default light and reads the text after its thinking" do
      sent = nil
      reply = { "content" => [{ "type" => "thinking", "thinking" => "" }, { "type" => "text", "text" => "Red" }] }
      allow(agent).to receive(:vision_http_post) do |_uri, _headers, body|
        sent = body
        double(status: double(success?: true), body: double(to_s: reply.to_json))
      end
      expect(agent.send(:vision_query_claude, "Color?", image, "claude-haiku-5-5", "k")).to eq("Red")
      expect(sent[:output_config]).to eq(effort: "low")
      expect(sent).not_to have_key(:temperature)
    end

    it "asks the other providers' models for their least reasoning" do
      sent = []
      ok = { "choices" => [{ "message" => { "content" => "Red" } }] }
      allow(agent).to receive(:vision_http_post) do |_uri, _headers, body|
        sent << body
        double(status: double(success?: true), body: double(to_s: ok.to_json))
      end
      stub_const("OpenAIHelper::OUTPUT_TOKEN_KEY", :max_completion_tokens) unless defined?(OpenAIHelper::OUTPUT_TOKEN_KEY)
      agent.send(:vision_query_openai, "Color?", image, "gpt-6.1-sol", "k")
      agent.send(:vision_query_deepseek, "Color?", image, "deepseek-flash", "k")
      agent.send(:vision_query_mistral, "Color?", image, "mistral-large-4", "k")
      expect(sent[0][:reasoning_effort]).to eq("low")
      expect(sent[1][:thinking]).to eq(type: "disabled")
      expect(sent[2][:reasoning_effort]).to eq("none")
    end

    it "reports an error whose body is a plain string" do
      allow(agent).to receive(:vision_http_post).and_return(
        double(status: double(success?: false, to_s: "400"), body: double(to_s: '{"error":"Image has 64 total pixels"}'))
      )
      expect(agent.send(:vision_query_grok, "Color?", image, "grok-4.7", "k")).to include("Image has 64 total pixels")
    end
  end
end
