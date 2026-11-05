# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../apps/image_generator/image_generator_tools"
require_relative "../../../lib/monadic/utils/tts_text_extractor"

RSpec.describe "the Gemini image tool on the workbench" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  def decoded(input)
    Base64.decode64(input["data"].split(",").last)
  end

  let(:root) { Dir.mktmpdir }
  let(:shared) { File.join(root, "data").tap { |d| Dir.mkdir(d) } }
  let(:store) { Monadic::Workbench::Store.new(File.join(root, "state", "workbench").tap { |d| FileUtils.mkdir_p(File.dirname(d)) }) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { chat_id: chat, _ws_generation: 1, parameters: { "app_name" => "ImageGeneratorGemini" },
      messages: [{ "mid" => "m-user", "role" => "user", "text" => "a cat" }] }
  end
  let(:request) { Monadic::Workspace::RequestContext.new(chat_id: chat) }
  let(:app) { ImageGeneratorGemini.new }
  let(:runs) { [] }
  let(:model) { Monadic::Utils::ModelSpec.image_options("gemini", "model").first }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::Offer.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
  end

  after { FileUtils.rm_rf(root) }

  # The provider call: records what it was given and writes what it is
  # given into the run's out folder, as the helper does.
  def fake_native(bytes: png(64, 48), name: "gemini3_image_1.png")
    allow(app).to receive(:generate_image_with_gemini_native) do |**args|
      runs << args
      next '{"success": false, "error": "blocked"}' unless bytes

      Monadic::Workbench::JobOutput.write!(args[:out_dir], name, bytes)
      { success: true, filename: name }.to_json
    end
  end

  def in_reply
    key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY
    saved = Fiber[key]
    Fiber[key] = Monadic::Utils::Privacy::EgressGuard::Scope.of(session)
    Monadic::Workspace::RequestContext.with(request) { yield }
  ensure
    Fiber[key] = saved
  end

  def generate(**extra)
    in_reply do
      args = { operation: "generate", prompt: "a cat", model: model, session: session }.merge(extra)
      Monadic::Workbench::Caller.inject!(args, app.method(:generate_image_with_gemini), session)
      app.generate_image_with_gemini(**args)
    end
  end

  def edit(text: "make it brighter", **extra)
    session[:messages] << { "mid" => "m-u#{session[:messages].size}", "role" => "user", "text" => text }
    generate(operation: "edit", prompt: text, **extra)
  end

  it "puts one image on the workbench, sending no image for a new one and writing nothing in the shared folder" do
    session[:messages] << { "role" => "user", "text" => "old", "images" => [{ "title" => "old.png",
                                                                             "data" => "data:image/png;base64,AAAA" }] }
    fake_native
    result = generate
    expect(result).to be_a(Monadic::Workbench::Offered)
    expect(runs.last[:images]).to eq([])
    expect(runs.last).not_to have_key(:session)
    expect(Dir.children(shared)).to be_empty
    expect(Dir.children(File.join(store.chat_dir(chat), "jobs"))).to be_empty
  end

  it "refuses without the reply's chat, in a Private chat, or with a model that is not an image model" do
    fake_native
    expect(app.generate_image_with_gemini(prompt: "a cat", model: model, session: session)).to start_with("❌")
    expect(generate(model: "gemini")).to start_with("❌ Unknown image model")
    session[:_history_policy] = Monadic::History::Policy::PRIVATE
    expect(generate).to start_with("❌")
    expect(runs).to be_empty
  end

  it "edits the image that came last on the workbench, the bytes taken when the edit started" do
    fake_native(bytes: png(64, 48, "first"), name: "first.png")
    first = generate
    fake_native(bytes: png(64, 48, "second"), name: "second.png")
    second = edit
    expect(runs.last[:images].map { |i| decoded(i) }).to eq([png(64, 48, "first")])
    item = Monadic::Workbench::Board.for(chat, store: store).item(second.item_id)
    expect(item.dig("candidate", "derived_from", "id")).to eq(first.item_id)
  end

  it "edits the images the user named or uploaded, every one, and not an older upload" do
    File.binwrite(File.join(shared, "a.png"), png(8, 8, "a"))
    File.binwrite(File.join(shared, "b.png"), png(8, 8, "b"))
    fake_native
    edit(text: "join a.png and b.png", images: ["a.png", "b.png"])
    expect(runs.last[:images].map { |i| decoded(i) }).to eq([png(8, 8, "a"), png(8, 8, "b")])
    data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8, "up"))}"
    session[:parameters]["images"] = [{ "title" => "up.png", "data" => data }]
    edit(text: "use this")
    expect(runs.last[:images].map { |i| decoded(i) }).to eq([png(8, 8, "up")])
  end

  it "gives the generator's error back when it made nothing, and refuses a mask" do
    fake_native(bytes: nil)
    expect(generate).to include("blocked")
    File.binwrite(File.join(shared, "photo.png"), png(8, 8))
    File.binwrite(File.join(shared, "mask__photo.png"), png(8, 8, "mask"))
    session[:messages] << { "role" => "user", "text" => "sky", "images" => [{ "name" => "mask__photo.png" }] }
    runs.clear
    expect(generate(operation: "edit", prompt: "sky")).to start_with("❌ Gemini image editing does not take a mask")
    expect(runs).to be_empty
  end

  it "refuses a mask drawn beside an uploaded image rather than edit without it" do
    fake_native
    data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}"
    session[:parameters]["images"] = [{ "title" => "photo.png", "data" => data, "type" => "image/png" },
                                      { "title" => "mask__photo.png", "data" => data, "type" => "image/png", "is_mask" => true }]
    expect(edit(text: "change the sky")).to start_with("❌ Gemini image editing does not take a mask")
    expect(runs).to be_empty
  end

  describe "the provider call for a workbench run" do
    let(:host) { Class.new(MonadicApp) { include GeminiHelper }.new }
    let(:sent) { [] }

    before do
      stub_const("CONFIG", { "GEMINI_API_KEY" => "test-key" })
      body = { "candidates" => [{ "content" => { "parts" => [
        { "inlineData" => { "mimeType" => "image/png", "data" => Base64.strict_encode64(png(16, 16)) } }
      ] } }] }.to_json
      allow(Net::HTTP).to receive(:start) do |*_, **_, &block|
        http = double("http")
        allow(http).to receive(:request) { |req| sent << JSON.parse(req.body); double(code: "200", body: body) }
        block.call(http)
      end
    end

    it "sends only the images it is given and writes the image in the run's out folder, leaving the session alone" do
      job = Monadic::Workbench::JobOutput.make(chat)
      messages = [{ "role" => "user", "text" => "x",
                    "images" => [{ "data" => "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}" }] }]
      out = host.generate_image_with_gemini_native(prompt: "a cat", model: model, images: nil,
                                                   session: { messages: messages, gemini3_last_image: "x.png" },
                                                   out_dir: Monadic::Workbench::JobOutput.out_dir(job))
      expect(JSON.parse(out)["success"]).to be(true)
      expect(sent.last.dig("contents", 0, "parts").size).to eq(1)
      expect(messages.size).to eq(1)
      expect(Monadic::Workbench::JobOutput.files(job).size).to eq(1)
      expect(Dir.children(shared)).to be_empty
    end
  end

  describe "the reply" do
    let(:host) do
      Class.new(MonadicApp) { include GeminiHelper }.new.tap do |h|
        allow(h).to receive(:api_request).and_return(:asked_the_model_again)
      end
    end

    before do
      stub_const("APPS", { "ImageGeneratorGemini" => app })
      stub_const("CONFIG", {})
      Monadic::Utils::ToolDispatchGuard.record!(session, "ImageGeneratorGemini",
                                                [{ "name" => "generate_image_with_gemini" }, { "name" => "declared" }])
      fake_native
    end

    def call(name, args, signature)
      { "name" => name, "args" => args, "_thoughtSignature" => signature }
    end

    it "ends with the image on the workbench, each call answered after its own call and signature" do
      sent = []
      args = { "operation" => "generate", "prompt" => "a cat", "model" => model }
      reply = in_reply do
        host.process_functions("ImageGeneratorGemini", session,
                               [call("generate_image_with_gemini", args, "sig-1"),
                                call("generate_image_with_gemini", args, "sig-2"), call("declared", {}, "sig-3")],
                               [], 0) { |event| sent << event }
      end
      expect(Monadic::Workbench::Offer.ended_reply?(reply)).to be(true)
      expect(host).not_to have_received(:api_request)
      expect(runs.size).to eq(1)
      results = session[:parameters]["tool_results"]
      expect(results.map { |r| r["thoughtSignature"] }).to eq(%w[sig-1 sig-2 sig-3])
      expect(results.map { |r| r.dig("functionCall", "args") }).to eq([args, args, {}])
      expect(results.drop(1).map { |r| r.dig("functionResponse", "response", "content") })
        .to all(eq(Monadic::Workbench::Offered.not_executed))
      expect(sent.last).to include("content" => "DONE")
    end

    it "is kept whole from the model's stream to the reply, text before the call or not" do
      args = { "operation" => "generate", "prompt" => "a cat", "model" => model }
      ["", "Here it comes."].each do |before|
        parts = []
        parts << { "text" => before } unless before.empty?
        parts << { "functionCall" => { "name" => "generate_image_with_gemini", "args" => args }, "thoughtSignature" => "s" }
        chunk = "[#{JSON.pretty_generate({ "candidates" => [{ "content" => { "parts" => parts, "role" => "model" } }] })}\n"
        session[:call_depth_per_turn] = 0
        reply = in_reply do
          host.process_json_data(app: "ImageGeneratorGemini", session: session, query: {}, res: [chunk], call_depth: 0) { |_| }
        end
        expect(reply.dig(0, "choices", 0, "message", Monadic::Workbench::Offer::ITEMS_KEY).size).to eq(1)
      end
      expect(runs.size).to eq(2)
    end

    it "does not run the other calls, or answer the one that ran again, when sending the end of the reply fails" do
      args = { "operation" => "generate", "prompt" => "a cat", "model" => model }
      failed = false
      expect do
        in_reply do
          host.process_functions("ImageGeneratorGemini", session,
                                 [call("generate_image_with_gemini", args, "sig-1"),
                                  call("generate_image_with_gemini", args, "sig-2")], [], 0) do |event|
            next unless event["type"] == "fragment" && !failed

            failed = true
            raise IOError, "socket closed"
          end
        end
      end.to raise_error(IOError)
      expect(runs.size).to eq(1)
      results = session[:parameters]["tool_results"]
      expect(results.map { |r| r["thoughtSignature"] }).to eq(%w[sig-1 sig-2])
      expect(results.last.dig("functionResponse", "response", "content")).to eq(Monadic::Workbench::Offered.not_executed)
    end

    it "answers a call that raised after that call and its signature" do
      allow(app).to receive(:generate_image_with_gemini).and_raise(RuntimeError, "boom")
      in_reply do
        host.process_functions("ImageGeneratorGemini", session,
                               [call("generate_image_with_gemini", { "prompt" => "a" }, "sig-e")], [], 0) { |_| }
      end
      result = session[:parameters]["tool_results"].last
      expect(result).to include("thoughtSignature" => "sig-e")
      expect(result.dig("functionCall", "args")).to eq("prompt" => "a")
      expect(result.dig("functionResponse", "response", "content")).to include("boom")
    end

    it "goes on as before when the result is not this reply's" do
      other = Monadic::Workbench::Offered.new(chat_id: chat, request_id: "another", item_id: "i_x", name: "x.png")
      allow(app).to receive(:generate_image_with_gemini).and_return(other)
      reply = in_reply do
        host.process_functions("ImageGeneratorGemini", session,
                               [call("generate_image_with_gemini", { "prompt" => "a" }, "s")], [], 0)
      end
      expect(Monadic::Workbench::Offer.ended_reply?(reply)).to be(false)
    end
  end
end
