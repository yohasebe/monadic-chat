# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "base64"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/whiteboard"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/retention"

# A whiteboard: a file of the chat's folder holding the shapes drawn on it,
# taken only in the form clean makes, saved as the page sends it, and looked
# at as the tab draws it.
RSpec.describe Monadic::Workbench::Whiteboard do
  around do |example|
    Dir.mktmpdir("workbench-whiteboard-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

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

  let(:shapes) do
    [{ "id" => "a1", "type" => "pen", "color" => "blue", "stroke" => 6, "points" => [[10, 20], [30.25, 40]] },
     { "id" => "a2", "type" => "arrow", "x1" => 0, "y1" => 0, "x2" => 100, "y2" => 50 },
     { "id" => "a3", "type" => "rect", "x" => 5, "y" => 5, "w" => 200, "h" => 100, "fill" => true, "color" => "red" },
     { "id" => "a4", "type" => "text", "x" => 50, "y" => 60, "text" => "Plan A\nthen B", "size" => 32 }]
  end

  def create = described_class.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)

  def save(item, data, version: item.dig("file", "sha256"))
    described_class.save(chat, item_id: item["id"], version: version, data: data, app_name: "ChatOpenAI", origin: origin,
                               epoch: epoch)
  end

  def kept(item) = JSON.parse(File.read(File.join(@data, item.dig("file", "path"))))

  # The user's turn and the reply after it end: the next turn may place a
  # whiteboard again.
  def next_turn!
    request = Monadic::Workspace::Ids.generate(:request)
    Monadic::Workbench::Board.for(chat).begin_reply(request)
    Monadic::Workbench::Board.for(chat).end_reply(request)
  end

  it "makes a new, empty whiteboard in the chat's folder and puts it on the work screen, numbered" do
    first = create
    next_turn!
    second = create
    expect(first.dig("file", "path")).to end_with("/whiteboards/whiteboard-1.wb.json")
    expect(second.dig("file", "path")).to end_with("/whiteboards/whiteboard-2.wb.json")
    expect(kept(first)).to eq("version" => 1, "width" => 1600, "height" => 1000, "shapes" => [])
    expect(Monadic::Workspace::SharedFolderPreview.render_for(first.dig("file", "path"))).to eq("whiteboard")
  end

  it "keeps a board that left Now as it was, also when brought back, and says so in the view" do
    item = create
    board = Monadic::Workbench::Board.for(chat)
    expect(board.snapshot[:items].first[:frozen]).to be_nil
    board.accept(item_id: item["id"], action: "stash", operation_id: "op-stash-0001", epoch: epoch, sha256: item.dig("file", "sha256"))
    board.accept(item_id: item["id"], action: "bring", operation_id: "op-bring-0001", epoch: epoch, sha256: item.dig("file", "sha256"))
    expect(board.item(item["id"])).to include("place" => "current", "frozen" => true)
    expect(board.snapshot[:items].first).to include(frozen: true)
    expect { save(item, { "shapes" => shapes }) }.to raise_error(described_class::Refused, /left Now/)
  end

  it "places one whiteboard in a turn, and another in the next" do
    create
    expect { create }.to raise_error(described_class::Refused, /placed in this turn already/)
    expect(Dir.glob(File.join(@data, "**", "*.wb.json")).size).to eq(1)
    next_turn!
    expect(create.dig("file", "path")).to end_with("whiteboard-2.wb.json")
  end

  it "saves the board as the page sends it, in the form it is kept, and the item takes the new version" do
    item = create
    saved = save(item, { "shapes" => shapes, "extra" => "dropped" })
    expect(saved["id"]).to eq(item["id"])
    expect(saved.dig("file", "sha256")).not_to eq(item.dig("file", "sha256"))
    board = kept(saved)
    expect(board.keys).to eq(%w[version width height shapes])
    expect(board["shapes"].map { |s| s["type"] }).to eq(%w[pen arrow rect text])
    expect(board["shapes"][0]).to eq("id" => "a1", "type" => "pen", "by" => "user", "color" => "blue",
                                     "points" => [[10.0, 20.0], [30.3, 40.0]], "stroke" => 6, "fill" => "none")
    expect(board["shapes"][2]).to include("fill" => "light", "color" => "red")
    expect(board["shapes"][3]).to include("text" => "Plan A\nthen B", "size" => 32)
  end

  it "records what a save changed of the shapes (added, changed, removed), and nothing for a save that changed none" do
    item = create
    first = save(item, { "shapes" => shapes })
    board = Monadic::Workbench::Board.for(chat, store: store)
    events = -> { board.observe(tab: "tab-1", generation: 1)[:events].select { |e| e["kind"] == "edited" } }
    expect(events.call.last).to include("added" => shapes.size, "changed" => 0, "removed" => 0, "by" => "user")
    moved = shapes.map(&:dup)
    moved[2] = moved[2].merge("x" => moved[2]["x"] + 10)
    second = save(first, { "shapes" => moved[0..-2] })
    expect(events.call.last).to include("added" => 0, "changed" => 1, "removed" => 1)
    count = events.call.size
    save(second, { "shapes" => moved[0..-2] })
    expect(events.call.size).to eq(count)
  end

  it "keeps one lock for each chat, so chats do not wait for each other" do
    other = Monadic::Workspace::Ids.generate(:chat)
    expect(described_class.lock_for(chat)).to equal(described_class.lock_for(chat))
    expect(described_class.lock_for(chat)).not_to equal(described_class.lock_for(other))
    # A chat discarded lets its lock go.
    first = described_class.lock_for(chat)
    Monadic::Workbench::Retention.discard(chat, store: store)
    expect(described_class::LOCKS).not_to have_key(chat)
    expect(described_class.lock_for(chat)).not_to equal(first)
  end

  it "refuses a save over a version that is not the item's now" do
    item = create
    save(item, { "shapes" => shapes })
    expect { save(item, { "shapes" => [] }) }.to raise_error(described_class::Refused, "changed")
  end

  it "saves only a whiteboard of the chat's folder" do
    File.write(File.join(@data, "notes.wb.json"), '{"shapes":[]}')
    other, = Monadic::Workbench::Board.for(chat).add_file(path: "notes.wb.json", origin: origin, epoch: epoch, wait: 0)
    expect { save(other, { "shapes" => [] }) }.to raise_error(described_class::Refused, /not a whiteboard/)
  end

  it "takes only known shapes, colors and sizes, numbers in range, within the limits" do
    clean = ->(list) { described_class.clean({ "shapes" => list }) }
    expect(clean.call([shapes[0].merge("color" => "chartreuse", "stroke" => "4")])["shapes"][0]).to include("color" => "black", "stroke" => 6)
    expect(clean.call([shapes[0].merge("color" => "peach", "stroke" => 20, "fill" => "solid")])["shapes"][0])
      .to include("color" => "peach", "stroke" => 24, "fill" => "solid")
    expect(clean.call([shapes[2].merge("fill" => "dotted")])["shapes"][0]).to include("fill" => "none")
    expect(clean.call([shapes[3].merge("size" => 65)])["shapes"][0]).to include("size" => 72)
    marker = clean.call([shapes[0].merge("type" => "marker", "fill" => "solid")])["shapes"][0]
    expect(marker).to include("type" => "marker", "stroke" => 6)
    expect(marker).not_to have_key("fill")
    expect(clean.call([shapes[3].merge("text" => "a\u0007b\nc")])["shapes"][0]["text"]).to eq("ab\nc")
    [[{ "id" => "x", "type" => "script" }],
     [shapes[0].merge("id" => "bad id!")],
     [shapes[0], shapes[0]],
     [shapes[1].merge("x2" => 99_999)],
     [shapes[1].merge("x2" => "100")],
     [shapes[2].merge("w" => -1)],
     [shapes[3].merge("text" => " ")],
     [shapes[3].merge("text" => "x" * 1001)],
     [shapes[0].merge("points" => [[1, 2, 3]])],
     [shapes[0].merge("points" => [])]].each do |list|
      expect { clean.call(list) }.to raise_error(described_class::Refused)
    end
    expect { described_class.clean({ "shapes" => "none" }) }.to raise_error(described_class::Refused)
    many = Array.new(described_class::SHAPES_LIMIT + 1) { |i| shapes[1].merge("id" => "s#{i}") }
    expect { clean.call(many) }.to raise_error(described_class::Refused, /too many shapes/)
  end

  describe "a look at it" do
    let(:capture) { Monadic::Workbench::Capture }
    let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
    let(:session) { { chat_id: chat, messages: [] } }

    around do |example|
      transport = capture.transport
      example.run
    ensure
      capture.transport = transport
      capture.reset!
    end

    before { Monadic::Workbench::Look::Ledger.reset! }

    def png(width, height)
      "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
    end

    def page(answer)
      capture.transport = lambda do |_tab, _generation, _chat, json|
        request = JSON.parse(json)
        Thread.new { capture.reading(request["id"], 2) { answer } }
        true
      end
    end

    def caller_for
      Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: request_id, session: session, tab: "tab-1",
                                     generation: 1)
    end

    it "gives the board as the tab draws it, with its shapes by type and its texts from the file" do
      save(create, { "shapes" => shapes })
      page({ "range" => {}, "image" => Base64.strict_encode64(png(800, 500)),
             "crop" => { "x" => 0, "y" => 0, "width" => 1600, "height" => 1000, "sent_width" => 800, "sent_height" => 500 } })
      out = JSON.parse(Monadic::Workbench::Look.run(caller_for, scope: "visible").to_s)
      expect(out["item"]).to include("kind" => "whiteboard")
      expect(out["image"]).to include("attached")
      expect(out["shapes"]).to eq("pen" => 1, "arrow" => 1, "rect" => 1, "text" => 1)
      expect(out["texts"]).to eq(["Plan A\nthen B"])
    end

    it "gives its texts when the tab gives no picture, or one of another shape" do
      save(create, { "shapes" => shapes })
      page({ "range" => {}, "image" => Base64.strict_encode64(png(500, 500)),
             "crop" => { "x" => 0, "y" => 0, "width" => 1600, "height" => 1000, "sent_width" => 500, "sent_height" => 500 } })
      out = JSON.parse(Monadic::Workbench::Look.run(caller_for, scope: "visible").to_s)
      expect(out["image"]).to include("No picture")
      expect(out["texts"]).to eq(["Plan A\nthen B"])
    end
  end
end
