# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"

# A round of Gemini's tool calls: each call is run once and answered by one
# result after it, in Gemini's format.
RSpec.describe "A round of Gemini's tool calls" do
  let(:app_class) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = []
      def settings = {}

      def note(text:, session:)
        @calls << [:note, text, session[:mark]]
        { success: true, saved: text }
      end

      def picture
        { success: true, _image: "model_view_1.png", gallery_html: "<p>g</p>" }
      end

      def broken
        raise ArgumentError, "it broke"
      end

      def tavily_search(query:, n: 3)
        @calls << [:tavily_search, query, n]
        "found"
      end
    end
  end
  let(:app) { app_class.new }
  let(:session) { { parameters: { "app_name" => "Probe" }, messages: [], mark: "m" } }
  let(:events) { [] }
  let(:helper) do
    Class.new { include GeminiHelper }.new.tap do |h|
      allow(h).to receive(:api_request).and_return([{ "choices" => [{ "message" => { "content" => "asked again" } }] }])
    end
  end

  before do
    stub_const("APPS", { "Probe" => app })
    allow(Monadic::Utils::ToolDispatchGuard).to receive(:refusal).and_return(nil)
  end

  def round(*calls)
    helper.process_functions("Probe", session, calls, [], 1) { |event| events << event }
    session[:parameters]["tool_results"]
  end

  def content_of(result)
    result.dig("functionResponse", "response", "content")
  end

  it "runs the tool with the session from the server and answers the call with its arguments as the model sent them" do
    call = { "name" => "note", "args" => { "text" => "hello", "session" => "from the model" }, "_thoughtSignature" => "sig" }

    results = round(call)

    expect(app.calls).to eq([[:note, "hello", "m"]])
    expect(results.size).to eq(1)
    expect(JSON.parse(content_of(results.first))).to eq("success" => true, "saved" => "hello")
    expect(results.first["functionCall"]).to eq("name" => "note", "args" => { "text" => "hello", "session" => "from the model" })
    expect(results.first["thoughtSignature"]).to eq("sig")
    expect(call["args"]).to eq("text" => "hello", "session" => "from the model")
  end

  it "reads arguments wrapped in options, and tavily_search by the names its method takes" do
    round({ "name" => "note", "args" => { "options" => { "text" => "inside" } } },
          { "name" => "tavily_search", "args" => { "q" => "ruby", "max_results" => 5 } })

    expect(app.calls).to eq([[:note, "inside", "m"], [:tavily_search, "ruby", 5]])
  end

  it "answers a call whose tool raised with the error, said in the chat as well, and goes on to the next call" do
    results = round({ "name" => "broken", "args" => {} }, { "name" => "note", "args" => { "text" => "after" } })

    expect(results.size).to eq(2)
    expect(content_of(results.first)).to include("it broke")
    expect(events).to include(a_hash_including("type" => "fragment", "content" => a_string_including("text-danger", "it broke")))
    expect(app.calls).to eq([[:note, "after", "m"]])
  end

  it "keeps a result's images for the next request and its HTML for the chat, once" do
    results = round({ "name" => "picture", "args" => {} })

    expect(JSON.parse(content_of(results.first))).to eq("success" => true, "gallery_html" => "<p>g</p>")
    expect(session[:pending_tool_images]).to eq(["model_view_1.png"])
    expect(session[:tool_html_fragments]).to eq(["<p>g</p>"])
  end

  it "does not run a tool the request did not offer" do
    allow(Monadic::Utils::ToolDispatchGuard).to receive(:refusal).and_return("❌ not offered")

    results = round({ "name" => "note", "args" => { "text" => "x" } })

    expect(app.calls).to be_empty
    expect(content_of(results.first)).to eq("❌ not offered")
  end
end
