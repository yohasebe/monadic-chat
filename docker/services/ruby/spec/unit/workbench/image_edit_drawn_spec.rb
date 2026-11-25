# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "base64"
require "shellwords"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/image_tool"
require_relative "../../../apps/image_generator/image_generator_tools"

# An edit of an image with a drawing on it as the reference: the original
# first, then the board as drawn, said so before the user's words; an item
# of the work screen named by its id comes before anything else.
RSpec.describe "Editing an image with what was drawn on it" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00".b * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("image-edit-drawn-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      transport = capture.transport
      example.run
    ensure
      capture.transport = transport
      capture.reset!
    end
  end

  let(:capture) { Monadic::Workbench::Capture }
  let(:tool) { Monadic::Workbench::ImageTool }
  let(:whiteboard) { Monadic::Workbench::Whiteboard }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:session) { { chat_id: chat, messages: [{ "role" => "user", "text" => "make it so" }], parameters: { "app_name" => "ChatOpenAI" } } }
  let(:workbench) do
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                   session: session, tab: "tab-1", generation: 1)
  end
  let(:photo_bytes) { png(300, 400, "photo") }
  let(:drawn_bytes) { png(600, 800, "drawn") }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
    capture.transport = lambda do |_tab, _generation, _chat, json|
      request = JSON.parse(json)
      answer = { "range" => {}, "image" => Base64.strict_encode64(drawn_bytes),
                 "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 1600, "sent_width" => 600, "sent_height" => 800 } }
      Thread.new { capture.reading(request["id"], 2) { answer } }
      true
    end
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def board = Monadic::Workbench::Board.for(chat, store: store)

  def photo
    FileUtils.mkdir_p(File.join(@data, "photos"))
    File.binwrite(File.join(@data, "photos/a.png"), photo_bytes)
    item, = board.add_file(path: "photos/a.png", origin: origin, epoch: epoch)
    item
  end

  def board_on(image)
    whiteboard.create_on(chat, item_id: image["id"], version: image.dig("file", "sha256"), app_name: "ChatOpenAI",
                               origin: origin, epoch: epoch)
  end

  describe "which images an edit takes" do
    it "takes the picture and the board as drawn when the tab shows a whiteboard drawn on an image" do
      board_on(photo)
      source = tool.edit_source(session: session, workbench: workbench, images: nil)
      expect(source.drawn?).to be(true)
      expect(source.inputs.map(&:role)).to eq(%w[original reference])
      expect(source.inputs.map(&:bytes)).to eq([photo_bytes, drawn_bytes])
      expect(tool.edit_prompt(source, "make the roof red")).to eq("#{tool::DRAWN_NOTE}make the roof red")
      expect(tool.edit_prompt(Monadic::Workbench::ImageTool::Source.new(images: ["a.png"]), "x")).to eq("x")
    end

    it "takes an image named by its id though the tab shows another item" do
      image = photo
      board_on(image)
      source = tool.edit_source(session: session, workbench: workbench, images: nil, item: image["id"])
      expect(source.drawn?).to be(false)
      expect(source.board_input[:bytes]).to eq(photo_bytes)
    end

    it "edits nothing for an item not on the work screen, an item named with images, a text, or a plain board" do
      image = photo
      File.write(File.join(@data, "notes.txt"), "a")
      text, = board.add_file(path: "notes.txt", origin: origin, epoch: epoch)
      expect { tool.edit_source(session: session, workbench: workbench, images: nil, item: "i_#{'0' * 20}") }
        .to raise_error(tool::NoSource, /not on the work screen/)
      expect { tool.edit_source(session: session, workbench: workbench, images: ["a.png"], item: image["id"]) }
        .to raise_error(tool::NoSource, /not both/)
      expect { tool.edit_source(session: session, workbench: workbench, images: nil, item: text["id"]) }
        .to raise_error(tool::NoSource, /not an image/)
      whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
      expect { tool.edit_source(session: session, workbench: workbench, images: nil) }
        .to raise_error(tool::NoSource, /no picture/)
    end

    it "puts the original first and the reference second in the job's inputs" do
      board_on(photo)
      source = tool.edit_source(session: session, workbench: workbench, images: nil)
      seen = nil
      tool.run_job(workbench, drawn: source.inputs) do |_out, inputs|
        seen = inputs.map { |path| [File.basename(path), Monadic::Workbench::JobOutput.read_input(path)] }
        "nothing made"
      end
      expect(seen).to eq([["input-1-original.png", photo_bytes], ["input-2-reference.png", drawn_bytes]])
    end
  end

  describe "what each provider is sent" do
    let(:inputs) do
      [Monadic::Workbench::BoardEdit::Input.new(role: "original", bytes: photo_bytes, content_type: "image/png"),
       Monadic::Workbench::BoardEdit::Input.new(role: "reference", bytes: drawn_bytes, content_type: "image/png")]
    end
    let(:plain) { whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch) }

    before { allow(Monadic::Workbench::BoardEdit).to receive(:inputs).and_return(inputs) }

    # The arguments of the script the app runs, and the bytes of its job
    # inputs in the order given.
    def sent_to_script(app)
      sent = nil
      allow(app).to receive(:send_command) do |**args|
        words = Shellwords.split(args[:command])
        paths = words.each_cons(2).select { |flag, _| flag == "--job-input" }.map(&:last)
        sent = { words: words, inputs: paths.map { |path| File.binread(path) } }
        '{"success":true,"images":[]}'
      end
      yield
      sent
    end

    it "OpenAI: the original then the reference, the shape left to follow the original, what each is said first" do
      app = ImageGeneratorOpenAI.new
      sent = sent_to_script(app) do
        app.generate_image_with_openai(operation: "edit", model: "gpt-image-2", prompt: "make the roof red", item: plain["id"],
                                       session: session, workbench: workbench)
      end
      expect(sent[:inputs]).to eq([photo_bytes, drawn_bytes])
      expect(sent[:words][sent[:words].index("-s") + 1]).to eq("auto")
      expect(sent[:words][sent[:words].index("-p") + 1]).to eq("#{tool::DRAWN_NOTE}make the roof red")
    end

    it "Grok: the original then the reference, what each is said first" do
      app = ImageGeneratorGrok.new
      sent = sent_to_script(app) do
        app.generate_image_with_grok(operation: "edit", prompt: "make the roof red", item: plain["id"], session: session,
                                     workbench: workbench)
      end
      expect(sent[:inputs]).to eq([photo_bytes, drawn_bytes])
      expect(sent[:words].join(" ")).to include(tool::DRAWN_NOTE.strip)
    end

    it "Gemini: the original then the reference, what each is said first" do
      app = ImageGeneratorGemini.new
      given = nil
      allow(app).to receive(:generate_image_with_gemini_native) do |**args|
        given = args
        '{"success":false,"message":"stopped"}'
      end
      app.generate_image_with_gemini(operation: "edit", prompt: "make the roof red", item: plain["id"], session: session,
                                     workbench: workbench)
      expect(given[:images].map { |i| Base64.strict_decode64(i["data"].split(",").last) }).to eq([photo_bytes, drawn_bytes])
      expect(given[:prompt]).to eq("#{tool::DRAWN_NOTE}make the roof red")
    end

    it "takes an item only to edit" do
      app = ImageGeneratorGemini.new
      expect(app.generate_image_with_gemini(operation: "generate", prompt: "x", item: plain["id"], session: session,
                                            workbench: workbench)).to start_with("❌")
    end
  end
end
