# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/adapters/base_vendor_helper"
require_relative "../../../lib/monadic/utils/function_call_error_handler"
require_relative "../../../lib/monadic/utils/interaction_utils"

RSpec.describe ToolRun do
  let(:app_class) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = []
      def settings = {}

      def plain(text: "x")
        @calls << [:plain, text]
        "said #{text}"
      end

      def with_session(text:, session:)
        @calls << [:with_session, text]
        { success: true, kept: session[:mark] }
      end

      def pictured
        { success: true, _image: "model_view_1.png", gallery_html: "<p>g</p>", note: "n" }
      end

      def broken
        raise ArgumentError, "it broke"
      end
    end
  end
  let(:app) { app_class.new }
  let(:session) { { parameters: { "app_name" => "Probe" }, mark: "m" } }
  let(:helper) do
    Class.new do
      include BaseVendorHelper
      include InteractionUtils
      include FunctionCallErrorHandler
    end.new
  end
  let(:error_text) { ->(e) { "ERROR: #{e.message}" } }

  before do
    stub_const("APPS", { "Probe" => app })
    allow(Monadic::Utils::ToolDispatchGuard).to receive(:refusal).and_return(nil)
  end

  def run(name, arguments = {}, **options)
    helper.run_tool_call("Probe", session, name, arguments, call_id: "c1", error_text: error_text, **options)
  end

  it "runs the tool with the arguments the model gave and returns what it returned" do
    result = run("plain", { text: "hello" })

    expect(app.calls).to eq([[:plain, "hello"]])
    expect(result).to have_attributes(name: "plain", value: "said hello", images: nil, stop: false)
  end

  it "runs a tool without arguments" do
    expect(run("plain").value).to eq("said x")
  end

  it "gives the session to a tool that takes one, whatever the model wrote there, and leaves the given arguments as they were" do
    arguments = { text: "t", session: "from the model" }

    result = run("with_session", arguments)

    expect(result.value).to eq(success: true, kept: "m")
    expect(arguments).to eq(text: "t", session: "from the model")
  end

  it "does not run a tool the request did not offer" do
    allow(Monadic::Utils::ToolDispatchGuard).to receive(:refusal).and_return("❌ not offered")

    expect(run("plain").value).to eq("❌ not offered")
    expect(app.calls).to be_empty
  end

  it "does not run a tool the provider refuses" do
    result = run("plain", {}, refuse: -> { "❌ off" })

    expect(result.value).to eq("❌ off")
    expect(app.calls).to be_empty
  end

  it "runs the tool when the provider's own check has nothing against it" do
    expect(run("plain", {}, refuse: -> {}).value).to eq("said x")
  end

  it "answers request_tool without calling a method of the app" do
    allow(Monadic::Utils::ProgressiveToolManager).to receive(:handle_request_tool).and_return("unlocked")

    expect(run("request_tool", { name: "plain" }).value).to eq("unlocked")
    expect(Monadic::Utils::ProgressiveToolManager).to have_received(:handle_request_tool)
      .with(hash_including(app_name: "Probe", argument_hash: { name: "plain" }))
  end

  it "makes an exception the tool's result, by the provider's wording" do
    expect(run("broken").value).to eq("ERROR: it broke")
  end

  it "sets apart the images for the model and the HTML for the chat" do
    result = run("pictured")

    expect(result.images).to eq(["model_view_1.png"])
    expect(result.without_private_keys).to eq(success: true, gallery_html: "<p>g</p>", note: "n")
    expect(session[:tool_html_fragments]).to eq(["<p>g</p>"])
  end

  it "takes the reply's speech from the tool, with what the tool returned, and keeps the tool's result when that fails" do
    allow(Monadic::Utils::TtsTextExtractor).to receive(:extract_tts_text).and_raise("no speech")

    expect(run("plain").value).to eq("said x")
    expect(Monadic::Utils::TtsTextExtractor).to have_received(:extract_tts_text)
      .with(hash_including(function_name: "plain", function_return: "said x"))
  end

  it "marks the reply ended when the tool an app names for the reply's text succeeded" do
    allow(app).to receive(:settings).and_return({ tts_target: [:tool_param, "with_session", "text"] })

    run("with_session", { text: "the reply" })
    expect(session[:tts_text]).to eq("the reply")
    expect(session[:tts_reply_ended]).to be(true)
  end

  it "does not mark the reply ended when that tool failed, or for any other tool" do
    allow(app).to receive(:settings).and_return({ tts_target: [:tool_param, "broken", "text"] })

    run("broken", { text: "the reply" })
    run("plain", { text: "other" })
    expect(session[:tts_reply_ended]).to be_nil
  end

  it "says to stop once the same error has come back too often" do
    allow(helper).to receive(:handle_function_error).and_return(false, true)

    expect(run("broken").stop).to be(false)
    expect(run("broken").stop).to be(true)
  end
end
