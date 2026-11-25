# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/whiteboard"
require_relative "../../../lib/monadic/workbench/whiteboard_layout"
require_relative "../../../lib/monadic/workbench/asset_server"
require_relative "../../../lib/monadic/workbench/look"
require "base64"

# A whiteboard drawn on an image: the image copied into the chat's
# whiteboards folder when the board is made, the sheet taking its
# proportions, kept as it is by every save and every change by the AI.
RSpec.describe Monadic::Workbench::WhiteboardBackground do
  def png(width, height, salt = "", animated: false)
    bytes = "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
            "\x00".b * 4
    bytes += [8].pack("N") + "acTL".b + "\x00".b * 12 if animated
    bytes + [0].pack("N") + "IDAT".b + "\x00".b * 4 + salt.b
  end

  # A JPEG of width × height whose EXIF says it is turned (orientation).
  def jpeg(width, height, orientation)
    tiff = "MM".b + [42, 8].pack("nN") + [1].pack("n") + [0x0112, 3, 1, orientation, 0].pack("nnNnn") + [0].pack("N")
    exif = "Exif\x00\x00".b + tiff
    "\xFF\xD8".b + "\xFF\xE1".b + [exif.bytesize + 2].pack("n") + exif +
      "\xFF\xC0".b + [17, 8, height, width, 3].pack("nCnnC") + "\x01\x11\x00\x02\x11\x01\x03\x11\x01".b + "\xFF\xD9".b
  end

  def moving_webp(width, height)
    chunk = [0x02, 0, 0, 0].pack("C4") + [width - 1].pack("V")[0, 3] + [height - 1].pack("V")[0, 3]
    "RIFF".b + [4 + 8 + chunk.bytesize].pack("V") + "WEBP".b + "VP8X".b + [chunk.bytesize].pack("V") + chunk
  end

  around do |example|
    Dir.mktmpdir("workbench-background-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:whiteboard) { Monadic::Workbench::Whiteboard }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def board = Monadic::Workbench::Board.for(chat, store: store)

  # An image file of the shared folder opened on the work screen.
  def opened(path, bytes)
    full = File.join(@data, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, bytes)
    item, = board.add_file(path: path, origin: origin, epoch: epoch)
    item
  end

  def draw_on(item, version: item.dig("file", "sha256"))
    whiteboard.create_on(chat, item_id: item["id"], version: version, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
  end

  def kept(item) = JSON.parse(File.read(File.join(@data, item.dig("file", "path"))))

  def save(item, data)
    whiteboard.save(chat, item_id: item["id"], version: item.dig("file", "sha256"), data: data, app_name: "ChatOpenAI",
                          origin: origin, epoch: epoch)
  end

  describe "the image's header" do
    let(:check) { Monadic::Workbench::ImageCheck }

    it "reads how a JPEG is turned, and 1 for one that says nothing or another kind" do
      expect(check.orientation("image/jpeg", jpeg(40, 30, 6))).to eq(6)
      expect(check.orientation("image/jpeg", jpeg(40, 30, 9))).to eq(1)
      expect(check.orientation("image/png", png(4, 3))).to eq(1)
      expect(check.check!(jpeg(40, 30, 6))).to include(content_type: "image/jpeg", width: 40, height: 30)
    end

    it "tells a moving PNG or WebP from a still one" do
      expect(check.animated?("image/png", png(4, 3, animated: true))).to be(true)
      expect(check.animated?("image/png", png(4, 3))).to be(false)
      expect(check.animated?("image/webp", moving_webp(4, 3))).to be(true)
    end
  end

  describe "the sheet" do
    def record(width, height, orientation = 1)
      { "pixel_width" => width, "pixel_height" => height, "orientation" => orientation }
    end

    it "takes the picture's proportions as it is seen, its longer side 1600" do
      expect(described_class.size_for(record(4000, 3000), 1600)).to eq([1600, 1200])
      expect(described_class.size_for(record(3000, 4000), 1600)).to eq([1200, 1600])
      expect(described_class.size_for(record(4000, 3000, 6), 1600)).to eq([1200, 1600])
      expect(described_class.size_for(record(10_000, 1), 1600)).to eq([1600, 1])
    end
  end

  describe "a whiteboard on an image" do
    it "copies the image as it is into the chat's whiteboards folder and keeps its record, not its path" do
      bytes = png(300, 400, "photo")
      photo = opened("photos/a.png", bytes)
      item = draw_on(photo)
      expect(item.dig("file", "path")).to end_with("/whiteboards/whiteboard-1.wb.json")
      sha256 = Digest::SHA256.hexdigest(bytes)
      expect(kept(item)).to eq("version" => 2, "width" => 1200, "height" => 1600,
                               "background" => { "sha256" => sha256, "content_type" => "image/png", "pixel_width" => 300,
                                                 "pixel_height" => 400, "orientation" => 1 },
                               "shapes" => [])
      copy = File.join(File.dirname(File.join(@data, item.dig("file", "path"))), "assets", "#{sha256}.png")
      expect(File.binread(copy)).to eq(bytes)
      expect(File.read(File.join(@data, item.dig("file", "path")))).not_to include("photos/a.png")
    end

    it "keeps one copy for two boards on the same picture, and the board when the image's file goes" do
      photo = opened("photos/a.png", png(300, 400))
      first = draw_on(photo)
      second = draw_on(photo)
      expect([first, second].map { |i| File.basename(i.dig("file", "path")) }).to eq(%w[whiteboard-1.wb.json whiteboard-2.wb.json])
      assets = File.join(File.dirname(File.join(@data, first.dig("file", "path"))), "assets")
      expect(Dir.children(assets).size).to eq(1)
      File.delete(File.join(@data, "photos/a.png"))
      saved = save(first, { "version" => 2, "shapes" => [{ "id" => "a", "type" => "rect", "x" => 1, "y" => 1, "w" => 9, "h" => 9 }] })
      expect(kept(saved)["background"]).to eq(kept(first)["background"])
    end

    it "takes an image made in the chat too" do
      made = board.add_image(bytes: png(64, 48, "made"), epoch: epoch, name: "cat.png", run: "j_#{SecureRandom.hex(10)}",
                             origin: { actor: :agent, request_id: Monadic::Workspace::Ids.generate(:request) },
                             app_name: "Image Generator")
      item = draw_on(made, version: made.dig("artifact", "sha256"))
      expect(kept(item)).to include("width" => 1600, "height" => 1200)
    end

    it "draws on none for another kind, a version the user did not see, or a moving image" do
      notes = File.join(@data, "notes.txt")
      File.write(notes, "a")
      text, = board.add_file(path: "notes.txt", origin: origin, epoch: epoch)
      photo = opened("photos/a.png", png(30, 40))
      moving = opened("photos/m.png", png(30, 40, animated: true))
      expect { draw_on(text) }.to raise_error(whiteboard::Refused, /only an image/)
      expect { draw_on(photo, version: "0" * 64) }.to raise_error(whiteboard::Refused)
      expect { draw_on(moving) }.to raise_error(whiteboard::Refused, /moving/)
      expect(Dir.glob(File.join(@data, "**", "*.wb.json"))).to be_empty
    end

    it "numbers boards made at once one after another" do
      photo = opened("photos/a.png", png(300, 400))
      made = Array.new(4) { Thread.new { draw_on(photo) } }.map(&:value)
      expect(made.map { |i| File.basename(i.dig("file", "path")) }.sort)
        .to eq(%w[whiteboard-1.wb.json whiteboard-2.wb.json whiteboard-3.wb.json whiteboard-4.wb.json])
    end
  end

  describe "saving and changing it" do
    let(:photo) { opened("photos/a.png", png(300, 400)) }
    let(:item) { draw_on(photo) }

    it "keeps the picture and the sheet it has, whatever the page sends for them" do
      saved = save(item, { "version" => 2, "width" => 1600, "height" => 1000,
                           "background" => { "sha256" => "f" * 64, "content_type" => "image/png", "pixel_width" => 1,
                                             "pixel_height" => 1, "orientation" => 1 },
                           "shapes" => [{ "id" => "a", "type" => "text", "x" => 1100, "y" => 1500, "text" => "here" }] })
      board_data = kept(saved)
      expect(board_data.values_at("width", "height")).to eq([1200, 1600])
      expect(board_data["background"]).to eq(kept(item)["background"])
      expect(board_data["shapes"].first).to include("x" => 1100.0, "y" => 1500.0)
    end

    it "takes points within its own sheet only" do
      expect { save(item, { "version" => 2, "shapes" => [{ "id" => "a", "type" => "text", "x" => 1700, "y" => 10, "text" => "x" }] }) }
        .to raise_error(whiteboard::Refused, /out of range/)
    end

    it "refuses a save from a page that knows only plain boards, and keeps the file" do
      before = File.binread(File.join(@data, item.dig("file", "path")))
      [{ "version" => 1, "shapes" => [] }, { "shapes" => [] }].each do |data|
        expect { save(item, data) }.to raise_error(whiteboard::Refused, /reload/)
      end
      expect(File.binread(File.join(@data, item.dig("file", "path")))).to eq(before)
    end

    it "refuses a plain board saved as one on a picture" do
      plain = whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
      expect { save(plain, { "version" => 2, "shapes" => [] }) }.to raise_error(whiteboard::Refused, /reload/)
    end

    it "refuses a board of a kind this version does not know" do
      path = File.join(@data, item.dig("file", "path"))
      File.write(path, JSON.generate(kept(item).merge("version" => 3)))
      fresh, = board.add_file(path: item.dig("file", "path"), origin: origin, epoch: epoch)
      expect { save(fresh, { "version" => 3, "shapes" => [] }) }.to raise_error(whiteboard::Refused, /does not know/)
    end

    it "gives the AI's change its sheet, and keeps the picture" do
      sheet = nil
      changed = whiteboard.edit(chat, item.dig("file", "path"), app_name: "ChatOpenAI", origin: origin, epoch: epoch) do |shapes, frame|
        sheet = frame
        shapes << whiteboard.shape_of({ "id" => "n", "type" => "text", "x" => 1100, "y" => 1500, "text" => "note" }, frame)
      end
      expect(sheet).to eq(whiteboard::Frame.new(width: 1200, height: 1600))
      expect(kept(changed)["background"]).to eq(kept(item)["background"])
      expect(kept(changed)["shapes"].size).to eq(1)
    end
  end

  describe "the picture the page gets" do
    let(:session) { { chat_id: chat, _ws_generation: 1, messages: [] } }
    let(:live) { ->(t) { t == "tab-1" ? 1 : nil } }
    let(:server) { Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, ["app"]] }, live: live) }
    let(:bytes) { png(300, 400, "photo") }

    before { Monadic::Workbench::ViewTokens.reset! }

    def addresses = Monadic::Workbench::Channel.view(session, tab: "tab-1", generation: 1, live: live)["backgrounds"]

    def fetch(url)
      status, headers, body = server.call({ "PATH_INFO" => url, "REQUEST_METHOD" => "GET",
                                            "HTTP_SEC_FETCH_SITE" => "same-origin" })
      [status, headers, body.join]
    end

    def copy_of(item)
      File.join(File.dirname(File.join(@data, item.dig("file", "path"))), "assets", "#{Digest::SHA256.hexdigest(bytes)}.png")
    end

    it "serves the copy the board names, as the image it is, at the board's own address" do
      item = draw_on(opened("photos/a.png", bytes))
      status, headers, body = fetch(addresses.fetch(item["id"]))
      expect(status).to eq(200)
      expect(headers).to include("content-type" => "image/png")
      expect(body.b).to eq(bytes)
    end

    it "serves nothing for a plain board, a copy gone, or a copy that is not the picture" do
      plain = whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
      expect(fetch(addresses.fetch(plain["id"])).first).to eq(404)
      item = draw_on(opened("photos/a.png", bytes))
      File.binwrite(copy_of(item), png(300, 400, "another"))
      expect(fetch(addresses.fetch(item["id"])).first).to eq(409)
      File.delete(copy_of(item))
      expect(fetch(addresses.fetch(item["id"])).first).to eq(410)
    end

    it "serves nothing for a board file kept elsewhere in the shared folder" do
      item = draw_on(opened("photos/a.png", bytes))
      FileUtils.mkdir_p(File.join(@data, "notes", "assets"))
      FileUtils.cp(copy_of(item), File.join(@data, "notes", "assets"))
      File.write(File.join(@data, "notes", "plan.wb.json"), JSON.generate(kept(item)))
      elsewhere, = board.add_file(path: "notes/plan.wb.json", origin: origin, epoch: epoch)
      expect(fetch(addresses.fetch(elsewhere["id"])).first).to eq(404)
    end

    it "gives no address for an item that is not a whiteboard" do
      photo = opened("photos/a.png", bytes)
      expect(addresses).not_to have_key(photo["id"])
    end
  end

  describe "a look at it" do
    let(:capture) { Monadic::Workbench::Capture }
    let(:caller_for) do
      Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                     session: { chat_id: chat, messages: [] }, tab: "tab-1", generation: 1)
    end

    around do |example|
      transport = capture.transport
      example.run
    ensure
      capture.transport = transport
      capture.reset!
    end

    before { Monadic::Workbench::Look::Ledger.reset! }

    def page(width, height)
      answer = { "range" => {}, "image" => Base64.strict_encode64(png(width, height)),
                 "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 1600, "sent_width" => width,
                             "sent_height" => height } }
      capture.transport = lambda do |_tab, _generation, _chat, json|
        request = JSON.parse(json)
        Thread.new { capture.reading(request["id"], 2) { answer } }
        true
      end
    end

    it "takes the tab's picture of the board at its sheet's proportions, and says it is drawn on a picture" do
      draw_on(opened("photos/a.png", png(300, 400)))
      page(600, 800)
      out = JSON.parse(Monadic::Workbench::Look.run(caller_for, scope: "visible").to_s)
      expect(out["image"]).to include("attached")
      expect(out["board"]).to eq("width" => 1200, "height" => 1600)
      expect(out["drawn_on_picture"]).to include("picture")
    end

    it "takes no picture of the plain sheet's proportions for it" do
      draw_on(opened("photos/a.png", png(300, 400)))
      page(800, 500)
      out = JSON.parse(Monadic::Workbench::Look.run(caller_for, scope: "visible").to_s)
      expect(out["image"]).to include("No picture")
    end
  end

  describe "laying out on its sheet" do
    let(:layout) { Monadic::Workbench::WhiteboardLayout }
    let(:tall) { Monadic::Workbench::Whiteboard::Frame.new(width: 600, height: 1600) }

    it "keeps a box grown to its text, and one moved off another, on the sheet" do
      box = { "id" => "b", "type" => "rect", "x" => 500, "y" => 10, "w" => 50, "h" => 40, "text" => "a long text " * 3 }
      layout.fit!(box, frame: tall)
      expect(box["x"] + box["w"]).to be <= 600
      # It covers the other's right edge a little: a step right would leave the sheet.
      shape = { "id" => "s", "type" => "rect", "x" => 440, "y" => 100, "w" => 150, "h" => 100 }
      other = { "id" => "o", "type" => "rect", "x" => 300, "y" => 150, "w" => 150, "h" => 100 }
      expect(layout.nudge!(shape, [other], frame: tall)).to be_a(Array)
      expect(shape["x"] + shape["w"]).to be <= 600
      expect(layout.overlaps(shape, [other])).to be_empty
    end

    it "says boxes laid out wider than the sheet do not fit" do
      boxes = Array.new(4) { |i| { "id" => "b#{i}", "type" => "rect", "text" => "step #{i}" } }
      edges = [%w[b0 b1], %w[b1 b2], %w[b2 b3]]
      expect(layout.layout!(boxes, edges, "right", [], frame: tall)).to include("larger than the board")
      expect(layout.layout!(boxes, edges, "down", [], frame: tall)).to be_nil
    end
  end
end
