# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "shellwords"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../apps/image_generator/image_generator_tools"
require_relative "../../../lib/monadic/utils/tts_text_extractor"

RSpec.describe "the Grok image tool on the workbench" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  let(:root) { Dir.mktmpdir }
  let(:shared) { File.join(root, "data").tap { |d| Dir.mkdir(d) } }
  let(:store) { Monadic::Workbench::Store.new(File.join(root, "state", "workbench").tap { |d| FileUtils.mkdir_p(File.dirname(d)) }) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { chat_id: chat, _ws_generation: 1, parameters: { "app_name" => "ImageGeneratorGrok" },
      messages: [{ "mid" => "m-user", "role" => "user", "text" => "a cat" }] }
  end
  let(:request) { Monadic::Workspace::RequestContext.new(chat_id: chat) }
  let(:app) { ImageGeneratorGrok.new }
  let(:commands) { [] }
  let(:seen_inputs) { [] }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::Offer.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
  end

  after { FileUtils.rm_rf(root) }

  # A generator that reads the inputs the server gave it and writes what it
  # is given into the out folder named in its command, as the script does.
  def fake_generator(bytes: png(64, 48), name: "grok_image_1.png")
    allow(app).to receive(:send_command) do |command:, **, &block|
      commands << Shellwords.split(command)
      commands.last.each_cons(2) do |flag, value|
        seen_inputs << Monadic::Workbench::JobOutput.read_input(value) if flag == "--job-input"
      end
      out_dir = commands.last[commands.last.index("--out-dir") + 1]
      Monadic::Workbench::JobOutput.write!(out_dir, name, bytes) if bytes
      said = bytes ? '{"success": true}' : '{"success": false, "error": "refused"}'
      block ? block.call(said, "", nil) : said
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
      args = { operation: "generate", prompt: "a cat", session: session }.merge(extra)
      Monadic::Workbench::Caller.inject!(args, app.method(:generate_image_with_grok), session)
      app.generate_image_with_grok(**args)
    end
  end

  def edit(text: "make it brighter", **extra)
    session[:messages] << { "mid" => "m-u#{session[:messages].size}", "role" => "user", "text" => text }
    generate(operation: "edit", prompt: text, **extra)
  end

  def job_inputs(command)
    command.each_cons(2).select { |flag, _| flag == "--job-input" }.map(&:last)
  end

  it "puts one image on the workbench, writing nothing in the shared folder" do
    fake_generator
    result = generate
    expect(result).to be_a(Monadic::Workbench::Offered)
    expect(commands.last).to include("--out-dir")
    expect(Dir.children(shared)).to be_empty
    expect(Dir.children(File.join(store.chat_dir(chat), "jobs"))).to be_empty
  end

  it "says in the reply when the generator used another model than the one asked for" do
    allow(app).to receive(:send_command) do |command:, **, &block|
      args = Shellwords.split(command)
      Monadic::Workbench::JobOutput.write!(args[args.index("--out-dir") + 1], "grok_image_1.png", png(64, 48))
      block.call(JSON.generate(success: true, fallback_from: "big", message: "Requested model big was unavailable."), "", nil)
    end
    result = generate
    expect(Monadic::Workbench::Offer.reply_text(result)).to start_with("Requested model big was unavailable.")
    expect(JSON.parse(result.to_s)["notice"]).to eq("Requested model big was unavailable.")
    fake_generator
    expect(JSON.parse(generate.to_s)).not_to have_key("notice")
    expect(Monadic::Workbench::ImageTool.notice_in('{"fallback_from": "big", "message": {"x": 1}}')).to be_nil
    expect(Monadic::Workbench::ImageTool.notice_in(JSON.generate(fallback_from: "big", message: "a" * 1000)).size)
      .to eq(Monadic::Workbench::ImageTool::NOTICE_LIMIT)
  end

  it "refuses without the reply's chat, and in a Private chat, before running anything" do
    fake_generator
    expect(app.generate_image_with_grok(prompt: "a cat", session: session)).to start_with("❌")
    session[:_history_policy] = Monadic::History::Policy::PRIVATE
    expect(generate).to start_with("❌")
    expect(commands).to be_empty
  end

  it "edits the image that came last on the workbench, given through the run's input folder" do
    fake_generator(bytes: png(64, 48, "first"), name: "first.png")
    first = generate
    fake_generator(bytes: png(64, 48, "second"), name: "second.png")
    second = edit
    expect(job_inputs(commands.last).size).to eq(1)
    expect(seen_inputs.last).to eq(png(64, 48, "first"))
    item = Monadic::Workbench::Board.for(chat, store: store).item(second.item_id)
    expect(item.dig("candidate", "derived_from", "id")).to eq(first.item_id)
    expect(Dir.children(shared)).to be_empty
  end

  it "gives the generator's error back when it made nothing" do
    fake_generator(bytes: png(64, 48, "first"), name: "first.png")
    generate
    fake_generator(bytes: nil)
    expect(edit).to include("refused")
    expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items].size).to eq(1)
  end

  it "edits every image the user uploaded, not only the first" do
    fake_generator
    data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}"
    session[:parameters]["images"] = [{ "title" => "a.png", "data" => data }, { "title" => "b.png", "data" => data }]
    edit(text: "join them")
    pairs = commands.last.each_cons(2).select { |flag, _| flag == "-i" }.map(&:last)
    expect(pairs.map { |p| File.basename(p) }).to eq(%w[a.png b.png])
  end

  it "refuses a mask drawn in the mask editor, which xAI cannot take, rather than ignore it" do
    File.binwrite(File.join(shared, "photo.png"), png(8, 8))
    File.binwrite(File.join(shared, "mask__photo.png"), png(8, 8, "mask"))
    fake_generator
    session[:messages] << { "mid" => "m-mask", "role" => "user", "text" => "change the sky",
                            "images" => [{ "name" => "mask__photo.png" }] }
    expect(generate(operation: "edit", prompt: "change the sky")).to start_with("❌ xAI image editing does not take a mask")
    expect(commands).to be_empty
  end

  it "refuses a mask drawn beside an uploaded image rather than edit without it" do
    fake_generator
    data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}"
    session[:parameters]["images"] = [{ "title" => "photo.png", "data" => data, "type" => "image/png" },
                                      { "title" => "mask__photo.png", "data" => data, "type" => "image/png", "is_mask" => true }]
    expect(edit(text: "change the sky")).to start_with("❌ xAI image editing does not take a mask")
    expect(commands).to be_empty
  end

  it "refuses more than five images rather than drop some" do
    fake_generator
    names = (1..6).map { |i| "p#{i}.png" }
    names.each { |n| File.binwrite(File.join(shared, n), png(8, 8)) }
    expect(edit(text: "join #{names.join(' ')}", images: names)).to start_with("❌ Maximum 5 images")
    expect(commands).to be_empty
  end

  describe "the reply" do
    let(:host) do
      Class.new(MonadicApp) { include GrokHelper }.new.tap do |h|
        allow(h).to receive(:api_request).and_return(:asked_the_model_again)
      end
    end

    before do
      stub_const("APPS", { "ImageGeneratorGrok" => app })
      stub_const("CONFIG", {})
      Monadic::Utils::ToolDispatchGuard.record!(session, "ImageGeneratorGrok",
                                                [{ "name" => "generate_image_with_grok" }, { "name" => "declared" }])
      fake_generator
    end

    def call(id, name, args)
      { "id" => id, "function" => { "name" => name, "arguments" => args.to_json } }
    end

    it "ends with the image on the workbench: the other calls are not run, and the model is not asked again" do
      sent = []
      reply = in_reply do
        host.send(:process_functions, "ImageGeneratorGrok", session,
                  [call("c1", "generate_image_with_grok", { prompt: "a cat" }), call("c2", "declared", {})],
                  [], 0) { |event| sent << event }
      end
      expect(reply.dig(0, "choices", 0, "message", "content")).to include("grok_image_1.png")
      expect(reply.dig(0, "choices", 0, "message", Monadic::Workbench::Offer::ITEMS_KEY).size).to eq(1)
      expect(host).not_to have_received(:api_request)
      returns = session[:parameters]["function_returns"]
      expect(returns.map { |r| r["call_id"] }).to eq(%w[c1 c2])
      expect(returns.last["content"]).to eq(Monadic::Workbench::Offered.not_executed)
      expect(sent.last).to include("content" => "DONE")
    end

    it "gives a result to every call, a duplicate too, and runs the generator once" do
      args = { prompt: "a cat" }
      in_reply do
        host.send(:process_functions, "ImageGeneratorGrok", session,
                  [call("c1", "declared", {}), call("c2", "generate_image_with_grok", args),
                   call("c3", "generate_image_with_grok", args)], [], 0)
      end
      returns = session[:parameters]["function_returns"]
      expect(returns.map { |r| r["call_id"] }).to contain_exactly("c1", "c2", "c3")
      expect(returns.find { |r| r["call_id"] == "c3" }["content"]).to eq(Monadic::Workbench::Offered.not_executed)
      expect(commands.size).to eq(1)
    end

    it "does not end this reply with an image that is not this reply's" do
      other = Monadic::Workbench::Offered.new(chat_id: chat, request_id: "another", item_id: "i_x", name: "x.png")
      allow(app).to receive(:generate_image_with_grok).and_return(other)
      reply = in_reply do
        host.send(:process_functions, "ImageGeneratorGrok", session,
                  [call("c1", "generate_image_with_grok", { prompt: "a" })], [], 0)
      end
      expect(reply.dig(0, "choices", 0, "message")).not_to have_key(Monadic::Workbench::Offer::ITEMS_KEY)
      expect(reply.dig(0, "choices", 0, "message", "content")).not_to include("x.png")
    end
  end
end
