# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"

# A turn that calls tools more than once: every round of the turn goes back
# with the next request, in order.
RSpec.describe "Gemini tool rounds of a turn" do
  let(:chat) { Class.new(MonadicApp) { include GeminiHelper }.new }
  let(:model) { Monadic::Utils::ModelSpec.get_provider_models("gemini", "chat")&.first }
  let(:sent) { [] }

  def result(name, depth)
    { "functionCall" => { "name" => name, "args" => {} },
      "functionResponse" => { "name" => name, "response" => { "name" => name, "content" => "#{name} done" } },
      "call_depth" => depth }
  end

  before do
    stub_const("APPS", { "SpecApp" => double("app", settings: {}) })
    stub_const("CONFIG", { "GEMINI_API_KEY" => "k" })
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) do |_uri, json:|
      sent << JSON.parse(JSON.generate(json))
      text = { "candidates" => [{ "content" => { "role" => "model", "parts" => [{ "text" => "Done." }] }, "finishReason" => "STOP" }] }
      body = Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| blk.call("data: #{JSON.generate(text)}\n\n") } }
      double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
    end
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)
    allow(chat).to receive(:sleep)
  end

  it "sends each round's calls before their results, the earlier round first" do
    session = { parameters: { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "1000",
                              "message" => "Go", "temperature" => "0.5",
                              "tool_results" => [result("first", 1), result("second", 2)] },
                messages: [{ "role" => "system", "text" => "S", "active" => true },
                           { "role" => "user", "text" => "Go", "active" => true }] }
    chat.api_request("tool", session) { |_| }
    order = sent.first["contents"].flat_map do |c|
      c["parts"].filter_map do |p|
        if p["functionCall"] then [:call, p.dig("functionCall", "name")]
        elsif p["functionResponse"] then [:result, p.dig("functionResponse", "name")]
        end
      end
    end
    expect(order).to eq([[:call, "first"], [:result, "first"], [:call, "second"], [:result, "second"]])
  end
end
