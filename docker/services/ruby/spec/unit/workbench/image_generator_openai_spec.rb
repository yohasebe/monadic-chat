# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "shellwords"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../apps/image_generator/image_generator_tools"
require_relative "../../../lib/monadic/utils/tts_text_extractor"

RSpec.describe "the OpenAI image tool on the workbench" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  let(:root) { Dir.mktmpdir }
  let(:shared) { File.join(root, "data").tap { |d| Dir.mkdir(d) } }
  let(:store) { Monadic::Workbench::Store.new(File.join(root, "state", "workbench").tap { |d| FileUtils.mkdir_p(File.dirname(d)) }) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { chat_id: chat, _ws_generation: 1, parameters: { "app_name" => "ImageGeneratorOpenAI" },
      messages: [{ "mid" => "m-user", "role" => "user", "text" => "a cat" }] }
  end
  let(:request) { Monadic::Workspace::RequestContext.new(chat_id: chat) }
  let(:app) { ImageGeneratorOpenAI.new }
  let(:commands) { [] }
  let(:seen_inputs) { [] }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::Offer.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(File.join(root, "state"))
  end

  after do
    Monadic::Workspace::Ledger.clear_unsettled!
    FileUtils.rm_rf(root)
  end

  def item_of(offered)
    Monadic::Workbench::Board.for(chat, store: store).item(offered.item_id)
  end

  # A generator that reads the inputs the server gave it and writes what it
  # is given into the out folder named in its command, as the script does.
  def fake_generator(bytes: png(64, 48), name: "generate_gpt-image-2_1_0.png")
    allow(app).to receive(:send_command) do |command:, **|
      commands << Shellwords.split(command)
      commands.last.each_cons(2) do |flag, value|
        seen_inputs << Monadic::Workbench::JobOutput.read_input(value) if flag == "--job-input"
      end
      out_dir = commands.last[commands.last.index("--out-dir") + 1]
      Monadic::Workbench::JobOutput.write!(out_dir, name, bytes) if bytes
      '{"success": true}'
    end
  end

  # The reply's chat and request, as a connection's reply runs under them.
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
      args = { operation: "generate", model: "gpt-image-2", prompt: "a cat", session: session }.merge(extra)
      Monadic::Workbench::Caller.inject!(args, app.method(:generate_image_with_openai), session)
      app.generate_image_with_openai(**args)
    end
  end

  describe "the caller" do
    it "is given by the server from the reply's chat and request, never from the arguments" do
      args = { workbench: "from the model" }
      in_reply { Monadic::Workbench::Caller.inject!(args, app.method(:generate_image_with_openai), session) }
      expect(args[:workbench]).to have_attributes(chat_id: chat, request_id: request.request_id, session: session)
      other = { workbench: "from the model" }
      Monadic::Workbench::Caller.inject!(other, method(:puts), session)
      expect(other).not_to have_key(:workbench)
    end

    it "is nil outside a reply, for a session in another chat, or under another chat's request" do
      expect(Monadic::Workbench::Caller.current(session)).to be_nil
      in_reply { expect(Monadic::Workbench::Caller.current({ chat_id: "c_other" })).to be_nil }
      other_request = Monadic::Workspace::RequestContext.new(chat_id: Monadic::Workspace::Ids.generate(:chat))
      in_reply do
        Monadic::Workspace::RequestContext.with(other_request) do
          expect(Monadic::Workbench::Caller.current(session)).to be_nil
        end
      end
    end
  end

  describe "a generation" do
    it "places one image in the chat's folder, puts it on the workbench, and ends the reply" do
      fake_generator
      result = generate
      expect(result).to be_a(Monadic::Workbench::Offered)
      expect(result.for?(session)).to be(false) # outside the reply
      in_reply { expect(result.for?(session)).to be(true) }
      expect(commands.last.each_cons(2).to_a).to include(["-n", "1"])
      item = item_of(result)
      expect(item.dig("artifact", "name")).to end_with("_generate_gpt-image-2_1_0.png")
      expect(item.dig("origin", "request_id")).to eq(request.request_id)
      expect(result.path).to eq(item.dig("artifact", "path"))
      expect(result.path).to start_with("conversations/").and include("_image-generator-open-ai_")
      expect(File.binread(File.join(shared, result.path))).to eq(png(64, 48))
      expect(Dir.children(shared)).to eq(["conversations"])
      expect(Dir.children(File.join(store.chat_dir(chat), "jobs"))).to be_empty
      expect(result.to_s).to include(Monadic::Workbench::Offered::STATUS, result.path)
    end

    it "refuses without the reply's chat, and in a Private chat, before running anything" do
      fake_generator
      expect(app.generate_image_with_openai(operation: "generate", model: "gpt-image-2", prompt: "a cat",
                                            session: session)).to start_with("❌")
      session[:_history_policy] = Monadic::History::Policy::PRIVATE
      expect(generate).to start_with("❌")
      expect(commands).to be_empty
      expect(Dir.exist?(store.chat_dir(chat))).to be(false)
    end

    it "gives the generator's error back when it made nothing, and refuses what is not an image" do
      fake_generator(bytes: nil)
      expect(generate).to eq('{"success": true}')
      fake_generator(bytes: "<svg/>", name: "x.png")
      expect(generate).to start_with("❌")
      expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items]).to be_empty
    end
  end

  describe "an edit" do
    def edit(text: "make it brighter", images: nil, mask: nil)
      session[:messages] << { "mid" => "m-u#{session[:messages].size}", "role" => "user", "text" => text }
      generate(operation: "edit", prompt: text, **(images ? { images: images } : {}), **(mask ? { mask: mask } : {}))
    end

    def job_inputs(command)
      command.each_cons(2).select { |flag, _| flag == "--job-input" }.map(&:last)
    end

    it "starts from the image that came last on the workbench, read from the shared folder and given through the run's input folder" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      first = generate
      fake_generator(bytes: png(64, 48, "second"), name: "second.png")
      second = edit
      inputs = job_inputs(commands.last)
      expect(inputs.size).to eq(1)
      expect(inputs.first).to include("/jobs/j_").and end_with("/in/input.png")
      expect(seen_inputs.last).to eq(png(64, 48, "first"))
      expect(item_of(second).dig("artifact", "derived_from")).to eq(item_of(first).dig("artifact", "id"))
      expect(Dir.children(shared)).to eq(["conversations"])
    end

    it "stops when the image that came last changed in the shared folder, and edits no other image" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "second"), name: "second.png")
      second = generate
      File.binwrite(File.join(shared, second.path), png(64, 48, "changed"))
      count = commands.size
      expect(edit).to start_with("❌").and include("changed")
      expect(commands.size).to eq(count)
    end

    it "takes an image of a chat folder the user named by its path" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      first = generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      edit(text: "make #{first.path} brighter", images: [first.path])
      expect(commands.last.each_cons(2).to_a).to include(["-i", first.path])
      expect(job_inputs(commands.last)).to be_empty
      expect(edit(text: "make conversations/none/artifacts/x.png brighter", images: ["conversations/none/artifacts/x.png"]))
        .to start_with("❌")
    end

    it "never takes the input for what the generator made" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: nil)
      expect(edit).to eq('{"success": true}')
      expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items].size).to eq(1)
    end

    it "uses a file of the shared folder only when the user named it, not when only the model did" do
      File.binwrite(File.join(shared, "old.png"), png(8, 8))
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      edit(text: "brighter, please", images: ["old.png"])
      expect(job_inputs(commands.last).size).to eq(1)
      expect(commands.last.each_cons(2).to_a).not_to include(["-i", "old.png"])
      edit(text: "make old.png brighter", images: ["old.png"])
      expect(commands.last.each_cons(2).to_a).to include(["-i", "old.png"])
      expect(job_inputs(commands.last)).to be_empty
    end

    it "stops when an image the user named is not found, rather than edit another" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      commands.clear
      expect(edit(text: "make gone.png brighter", images: ["gone.png"])).to start_with("❌ The image you named was not found: gone.png")
      File.binwrite(File.join(shared, "here.png"), png(8, 8))
      expect(edit(text: "join here.png and gone.png", images: ["here.png", "gone.png"])).to include("gone.png")
      expect(commands).to be_empty
    end

    it "takes only a whole file name the user wrote, not one inside a longer name" do
      File.binwrite(File.join(shared, "cat.png"), png(8, 8))
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      edit(text: "make bobcat.png brighter", images: ["cat.png"])
      expect(commands.last.each_cons(2).to_a).not_to include(["-i", "cat.png"])
      expect(job_inputs(commands.last).size).to eq(1)
      edit(text: "make ~/monadic/data/cat.png brighter", images: ["cat.png"])
      expect(commands.last.each_cons(2).to_a).to include(["-i", "cat.png"])
    end

    it "edits the image a mask drawn in the mask editor is for, with that mask, whatever the model passed" do
      File.binwrite(File.join(shared, "photo.png"), png(8, 8))
      File.binwrite(File.join(shared, "mask__photo.png"), png(8, 8, "mask"))
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      session[:messages] << { "mid" => "m-mask", "role" => "user", "text" => "change the sky",
                              "images" => [{ "name" => "mask__photo.png" }] }
      generate(operation: "edit", prompt: "change the sky", images: ["first.png"])
      pairs = commands.last.each_cons(2).to_a
      expect(pairs).to include(["-i", "photo.png"])
      expect(pairs.find { |flag, _| flag == "--mask" }&.last).to end_with("mask__photo.png")
      expect(job_inputs(commands.last)).to be_empty
    end

    it "keeps a mask drawn in the mask editor with the image uploaded beside it, the model passing no mask" do
      fake_generator
      data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}"
      uploads = [{ "title" => "photo.png", "data" => data, "type" => "image/png" },
                 { "title" => "mask__photo.png", "data" => data, "type" => "image/png", "is_mask" => true,
                   "mask_for" => "photo.png" }]
      session[:parameters]["images"] = uploads
      session[:messages] << { "mid" => "m-mask", "role" => "user", "text" => "change the sky", "images" => uploads }
      generate(operation: "edit", prompt: "change the sky")
      pairs = commands.last.each_cons(2).to_a
      expect(pairs).to include(["-i", "photo.png"])
      expect(pairs.find { |flag, _| flag == "--mask" }&.last).to end_with("mask__photo.png")
    end

    it "stops when an uploaded image cannot be read, rather than edit fewer or another, and leaves out documents" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      fake_generator(bytes: png(64, 48, "x"), name: "x.png")
      commands.clear
      data = "data:image/png;base64,#{Base64.strict_encode64(png(8, 8))}"
      session[:parameters]["images"] = [{ "title" => "photo.png", "data" => data, "type" => "image/png" },
                                        { "title" => "missing.png", "type" => "image/png" }]
      expect(edit(text: "join them")).to start_with("❌ The image you uploaded could not be read: missing.png")
      session[:parameters]["images"] = [{ "title" => "missing.png", "type" => "image/png" }]
      expect(edit(text: "use this")).to start_with("❌ The image you uploaded could not be read: missing.png")
      expect(commands).to be_empty
      session[:parameters]["images"] = [{ "title" => "notes.pdf", "data" => "data:application/pdf;base64,AAAA",
                                          "type" => "application/pdf" }]
      edit(text: "brighter")
      expect(job_inputs(commands.last).size).to eq(1)
    end

    it "refuses a mask for the image in the work screen rather than edit without it" do
      fake_generator(bytes: png(64, 48, "first"), name: "first.png")
      generate
      commands.clear
      expect(edit(text: "change the sky", mask: "mask__photo.png")).to start_with("❌ A mask applies to an uploaded or named image")
      expect(commands).to be_empty
    end

    it "says there is nothing to edit when the workbench is empty and nothing was uploaded or named" do
      fake_generator
      expect(edit).to start_with("❌ No image to edit")
      expect(commands).to be_empty
    end
  end

  describe "the reply" do
    let(:host) do
      Class.new(MonadicApp) { include OpenAIHelper }.new.tap do |h|
        allow(h).to receive(:api_request).and_return(:asked_the_model_again)
      end
    end

    before do
      stub_const("APPS", { "ImageGeneratorOpenAI" => app })
      stub_const("CONFIG", {})
      Monadic::Utils::ToolDispatchGuard.record!(session, "ImageGeneratorOpenAI",
                                                [{ "name" => "generate_image_with_openai" }, { "name" => "declared" }])
      fake_generator
    end

    def call(id, name, args)
      { "id" => id, "function" => { "name" => name, "arguments" => args.to_json } }
    end

    it "ends with the image on the workbench: the other calls are not run, and the model is not asked again" do
      sent = []
      context = []
      reply = in_reply do
        host.send(:process_functions, "ImageGeneratorOpenAI", session,
                  [call("c1", "generate_image_with_openai", { operation: "generate", model: "gpt-image-2", prompt: "a cat" }),
                   call("c2", "declared", {})], context, 0) { |event| sent << event }
      end
      expect(reply.dig(0, "choices", 0, "message", "content")).to include("generate_gpt-image-2_1_0.png")
      expect(host).not_to have_received(:api_request)
      expect(context.map { |c| c[:tool_call_id] }).to eq(%w[c1 c2])
      expect(context.last[:content]).to eq(Monadic::Workbench::Offered.not_executed)
      expect(sent.map { |e| e["type"] }).to eq(%w[tool_executing fragment message])
      expect(sent.last).to include("content" => "DONE")
    end

    it "gives a result to every call the model made, a duplicate too" do
      context = []
      args = { operation: "generate", model: "gpt-image-2", prompt: "a cat" }
      in_reply do
        host.send(:process_functions, "ImageGeneratorOpenAI", session,
                  [call("c1", "declared", {}), call("c2", "generate_image_with_openai", args),
                   call("c3", "generate_image_with_openai", args), call("c4", "declared", { x: 1 })], context, 0)
      end
      expect(context.map { |c| c[:tool_call_id] }).to contain_exactly("c1", "c2", "c3", "c4")
      expect(context.select { |c| c[:content] == Monadic::Workbench::Offered.not_executed }.map { |c| c[:tool_call_id] })
        .to contain_exactly("c3", "c4")
      expect(commands.size).to eq(1)
    end

    it "goes on as before when the result is not this reply's" do
      other = Monadic::Workbench::Offered.new(chat_id: chat, request_id: "another", item_id: "i_x", path: "x.png")
      allow(app).to receive(:generate_image_with_openai).and_return(other)
      reply = in_reply do
        host.send(:process_functions, "ImageGeneratorOpenAI", session,
                  [call("c1", "generate_image_with_openai", { operation: "generate", model: "gpt-image-2", prompt: "a" })],
                  [], 0)
      end
      expect(reply).to eq(:asked_the_model_again)
    end
  end

  describe "the reply's message" do
    it "is the one that names the image, and records what the reply made, which becomes the last generated image" do
      session[:monadic_state] = { "ImageGeneratorOpenAI" => { "last_images" => { data: ["older.png"] } } }
      fake_generator
      offered = generate
      session[:messages] << { "mid" => "m-1", "role" => "assistant", "text" => "done" }
      expect(Monadic::Workbench::Channel.reply_recorded(session, "m-1", "another request", [offered.item_id])).to be(false)
      # A message of the same reply that does not name the image (text written before the tool ran).
      expect(Monadic::Workbench::Channel.reply_recorded(session, "m-0", request.request_id, nil)).to be(false)
      expect(Monadic::Workbench::Channel.reply_recorded(session, "m-0", request.request_id, ["i_other"])).to be(false)
      expect(Monadic::Workbench::Channel.reply_recorded(session, "m-1", request.request_id, [offered.item_id])).to be(true)
      ended = Monadic::Workbench::Offer.end_reply(offered)
      message = ended.dig(0, "choices", 0, "message")
      made = Monadic::Workbench::Record.clean(message[Monadic::Workbench::Offer::ARTIFACTS_KEY])
      expect(made).to eq([offered.entry])
      expect(made.first).to include("id" => item_of(offered).dig("artifact", "id"), "path" => offered.path)
      expect(message["content"]).to include(offered.path)
      session[:messages].last["artifacts"] = made
      # ${LAST_GENERATED_IMAGE} names the image made last, from the record.
      expect(Monadic::Substitution::Vocabulary.last_generated_image(session)).to eq(offered.path)
    end

    it "leaves an image of the chat the tab left without a message" do
      fake_generator
      offered = generate
      session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
      expect(Monadic::Workbench::Channel.reply_recorded(session, "m-1", request.request_id, [offered.item_id])).to be(false)
      expect(Monadic::Workbench::Board.for(chat, store: store).item(offered.item_id)["mid"]).to be_nil
    end

    it "keeps the image of a reply that ends without its message, and takes nothing more from that reply" do
      fake_generator
      offered = generate
      Monadic::Workbench::Offer.close(request.request_id)
      expect(Monadic::Workbench::Board.for(chat, store: store).item(offered.item_id)).not_to be_nil
      expect(Monadic::Workbench::Offer.in_flight?(request.request_id)).to be(false)
      # The stopped reply's tool, still finishing, adds nothing.
      fake_generator(name: "late.png")
      expect(generate).to start_with("❌")
      expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items].map { |i| i[:name] })
        .not_to include("late.png")
    end
  end

  describe "the job folder" do
    let(:job) { Monadic::Workbench::JobOutput.make(chat, store: store) }
    let(:writer) { Monadic::Workbench::JobOutput }

    it "takes what a generator makes as a new plain file in the run's out folder, and nothing else" do
      out = writer.out_dir(job)
      writer.write!(out, "a.png", "x", root: store.root)
      expect { writer.write!(out, "a.png", "y", root: store.root) }.to raise_error(Errno::EEXIST)
      expect { writer.write!(out, "../a.png", "y", root: store.root) }.to raise_error(writer::Refused)
      expect { writer.write!(job, "a.png", "y", root: store.root) }.to raise_error(writer::Refused)
      expect { writer.write!(File.join(job, "in"), "a.png", "y", root: store.root) }.to raise_error(writer::Refused)
      expect { writer.write!(shared, "a.png", "y", root: store.root) }.to raise_error(writer::Refused)
      File.chmod(0o755, out)
      expect { writer.write!(out, "b.png", "y", root: store.root) }.to raise_error(writer::Refused)
      expect(writer.files(job)).to eq(["a.png"])
    end

    it "keeps what the server gives a run apart from what the run makes, and lets it read only that" do
      path = writer.put_input!(job, "input.png", "bytes", root: store.root)
      expect(writer.files(job)).to be_empty
      expect(writer.read_input(path, root: store.root)).to eq("bytes")
      File.binwrite(File.join(shared, "x.png"), "other")
      expect { writer.read_input(File.join(shared, "x.png"), root: store.root) }.to raise_error(writer::Refused)
      expect { writer.read_input(File.join(job, "in", "..", "out", "y.png"), root: store.root) }.to raise_error(writer::Refused)
      File.symlink(File.join(shared, "x.png"), File.join(job, "in", "link.png"))
      expect { writer.read_input(File.join(job, "in", "link.png"), root: store.root) }.to raise_error(writer::Refused)
    end

    it "refuses a folder reached through a link, at its name or on the way" do
      linked = File.join(store.chat_dir(chat), "jobs", "j_#{'0' * 20}")
      File.symlink(job, linked)
      expect { writer.write!(writer.out_dir(linked), "a.png", "x", root: store.root) }.to raise_error(writer::Refused)
      other_chat = Monadic::Workspace::Ids.generate(:chat)
      File.symlink(store.chat_dir(chat), File.join(store.root, other_chat))
      through = File.join(store.root, other_chat, "jobs", File.basename(job), "out")
      expect { writer.write!(through, "a.png", "x", root: store.root) }.to raise_error(writer::Refused)
      expect(writer.files(job)).to be_empty
    end
  end
end
