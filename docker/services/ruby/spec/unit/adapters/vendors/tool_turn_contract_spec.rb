# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../support/stream_contract"
%w[openai claude gemini grok mistral cohere deepseek ollama].each do |name|
  require_relative "../../../../lib/monadic/adapters/vendors/#{name}_helper"
end

# A turn whose model calls a tool: the user's message, the call, then the
# request that sends the result back. What every provider sends in it.
RSpec.describe "A turn with a tool call (every provider)" do
  SUFFIX = "Answer in the language of the question."

  # name => [helper, provider of the model spec, key, stream format, line format]
  PROVIDERS = {
    "OpenAI" => [OpenAIHelper, "openai", "OPENAI_API_KEY", StreamContract::Responses, :sse],
    "Claude" => [ClaudeHelper, "anthropic", "ANTHROPIC_API_KEY", StreamContract::Claude, :sse],
    "Gemini" => [GeminiHelper, "gemini", "GEMINI_API_KEY", StreamContract::Gemini, :sse],
    "Grok" => [GrokHelper, "xai", "XAI_API_KEY", StreamContract::Responses, :sse],
    "Mistral" => [MistralHelper, "mistral", "MISTRAL_API_KEY", StreamContract::ChatCompletions, :sse],
    "Cohere" => [CohereHelper, "cohere", "COHERE_API_KEY", StreamContract::Cohere, :ndjson],
    "DeepSeek" => [DeepSeekHelper, "deepseek", "DEEPSEEK_API_KEY", StreamContract::ChatCompletions, :sse],
    "Ollama" => [OllamaHelper, "ollama", nil, StreamContract::Ollama, :ndjson]
  }.freeze

  class TurnApp
    attr_reader :ran

    def initialize = @ran = []

    def settings
      { "prompt_suffix" => SUFFIX,
        "tools" => [{ "type" => "function",
                      "function" => { "name" => "first_tool", "description" => "t",
                                      "parameters" => { "type" => "object", "properties" => {} } } }] }
    end

    def first_tool(**)
      @ran << "first_tool"
      "done"
    end
  end

  def encode(kind, objects)
    kind == :ndjson ? objects.map { |o| "#{JSON.generate(o)}\n" }.join : objects.map { |o| "data: #{JSON.generate(o)}\n\n" }.join
  end

  # The turn, the model answering the first request with one call and the
  # second with text; the request bodies it sent.
  def turn(name, greeting: false, answers: nil, kept: {})
    helper_module, provider, key, format, kind = PROVIDERS.fetch(name)
    helper = Class.new(MonadicApp) { include helper_module }.new
    allow(helper).to receive(:sleep)
    app = TurnApp.new
    stub_const("APPS", { "SpecApp" => app })
    stub_const("CONFIG", CONFIG.merge(key => "k").compact) if key
    allow(OllamaHelper).to receive(:find_endpoint).and_return("http://localhost:11434/api")
    allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return({ capabilities: %w[completion tools] })
    # An answer is the model's stream, or an HTTP error ({ status:, body: }).
    answers = (answers || [format.calls([["first_tool", {}]]), format.text(["Done."])]).map do |a|
      a.is_a?(Hash) ? a : encode(kind, a)
    end
    bodies = []
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) do |_uri, json:|
      bodies << JSON.parse(JSON.generate(json))
      # The last answer is given again to every later request (a retry).
      answer = answers.length > 1 ? answers.shift : answers.first
      if answer.is_a?(Hash)
        next double("res", status: HTTP::Response::Status.new(answer[:status]), body: answer[:body], code: answer[:status], headers: {})
      end

      body = Object.new.tap do |o|
        o.define_singleton_method(:each) { |&blk| blk.call(answer.dup) }
        o.define_singleton_method(:to_s) { answer.dup }
      end
      double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
    end
    allow(chain).to receive(:get) do
      tags = JSON.generate({ "models" => [{ "name" => "gpt-oss:20b" }] })
      double("res", status: HTTP::Response::Status.new(200), body: tags, code: 200, headers: {})
    end
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)
    model = Monadic::Utils::ModelSpec.get_provider_models(provider, "chat")&.first || "m"
    session = { parameters: { "app_name" => "SpecApp", "model" => model, "message" => "What is the weather?",
                              "context_size" => "5", "max_tokens" => "1000", "temperature" => "0.5",
                              "prompt_suffix" => SUFFIX, "tools" => app.settings["tools"] },
                messages: [{ "role" => "system", "text" => "S", "active" => true }] }.merge(kept)
    # As a reply runs: in its chat, for its request.
    chat = Monadic::Workspace::Ids.generate(:chat)
    session[Monadic::Workspace::Chats::SESSION_KEY] = chat
    Monadic::Workspace::RequestContext.with(Monadic::Workspace::RequestContext.new(chat_id: chat)) do
      @events = []
      session[:parameters].merge!("message" => "", "initiate_from_assistant" => true) if greeting
      @reply = helper.api_request("user", session) { |e| @events << e.slice("type", "content") if e.is_a?(Hash) }
    end
    [bodies, app]
  end

  PROVIDERS.each_key do |name|
    it "#{name}: runs the call and sends its result back in a second request" do
      bodies, app = turn(name)
      expect(app.ran).to eq(["first_tool"]), "events: #{@events.inspect[0, 600]}"
      expect(bodies.size).to eq(2)
      expect(JSON.generate(bodies[1])).to include("done")
    end

    it "#{name}: sends the turn's message with its suffix in both requests" do
      bodies, = turn(name)
      expect(bodies.map { |b| JSON.generate(b).include?(SUFFIX) }).to eq([true, true])
    end

    it "#{name}: ends the reply as the error of the request that sends the result back" do
      format = PROVIDERS.fetch(name)[3]
      # Grok sends a round's results back without streaming: its error is the HTTP response's.
      failure = if name == "Grok"
                  { status: 503, body: JSON.generate({ "error" => { "message" => "the service is overloaded" } }) }
                else
                  [format.error("the service is overloaded")]
                end
      turn(name, answers: [format.calls([["first_tool", {}]]), failure])
      error = Array(@reply).find { |r| r.is_a?(Hash) && r["type"] == "error" }
      expect(error&.dig("content")).to include("the service is overloaded"), "reply: #{@reply.inspect[0, 400]}"
    end

    it "#{name}: sends the greeting, which has no user message, without the suffix" do
      bodies, = turn(name, greeting: true)
      expect(bodies.first).not_to be_nil
      expect(JSON.generate(bodies.first)).not_to include(SUFFIX)
    end
  end

  it "Mistral: shows no text kept from an earlier turn when the reply is empty" do
    turn("Mistral", answers: [StreamContract::ChatCompletions.text([""])], kept: { mistral_pre_tool_content: "Stale guess." })
    expect(@reply.inspect).not_to include("Stale guess.")
  end
end
