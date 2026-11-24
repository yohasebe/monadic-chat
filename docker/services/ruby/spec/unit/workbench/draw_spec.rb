# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/draw"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/history/serializer"

# The AI draws on a whiteboard of the work screen: on the one the tab shows
# or a new one, adding shapes, changing and removing them by id, and the
# reply keeps what it added so deleting its message takes it off again.
RSpec.describe Monadic::Workbench::Draw do
  around do |example|
    Dir.mktmpdir("workbench-draw-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:user) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:session) { { parameters: { "app_name" => "ChatOpenAI" } } }
  let(:whiteboard) { Monadic::Workbench::Whiteboard }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    described_class.reset!
    Monadic::Workbench::Made.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
    allow(Monadic::Workbench::Shown).to receive(:running?).and_return(true)
    allow(Monadic::Workbench::Shown).to receive(:add)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def caller_for
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: request_id, session: session, tab: "tab-1",
                                   generation: 1)
  end

  def shapes_of(item) = JSON.parse(File.read(File.join(@data, item.dig("file", "path"))))["shapes"]

  def kept(path) = JSON.parse(File.read(File.join(@data, path)))["shapes"]

  let(:diagram) do
    JSON.generate([{ "id" => "order", "type" => "box", "x" => 100, "y" => 100, "w" => 220, "h" => 90, "text" => "Order" },
                   { "id" => "link", "type" => "arrow", "from" => "order", "to" => "ship" },
                   { "id" => "ship", "type" => "ellipse", "x" => "600", "y" => 100, "w" => 220, "h" => 90,
                     "text" => "Ship", "color" => "green" }])
  end

  it "draws on a new whiteboard when the tab shows none, the reply making it, and joins shapes by id" do
    done = described_class.run(caller_for, shapes: diagram)
    path = done[:item].dig("file", "path")
    expect(path).to end_with("/whiteboards/whiteboard-1.wb.json")
    expect(Monadic::Workbench::Made.pending(request_id)).to eq([path])
    expect(done[:added]).to eq(%w[order ship link])
    order, ship, link = shapes_of(done[:item])
    expect(order).to include("type" => "rect", "by" => "ai", "color" => "violet", "text" => "Order", "size" => 20)
    expect(ship).to include("type" => "ellipse", "x" => 600.0, "color" => "green")
    # Its ends at the middles of the two shapes (drawn at their edges).
    expect(link).to include("from" => "order", "to" => "ship", "x1" => 210.0, "y1" => 145.0, "x2" => 710.0, "y2" => 145.0)
    expect(described_class.seal(request_id)).to eq([{ "path" => path, "ids" => %w[order ship link] }])
  end

  it "draws on the whiteboard the tab shows: changes and removes by id, keeping only what it added" do
    board = whiteboard.create(chat, app_name: "ChatOpenAI", origin: user, epoch: epoch)
    board = whiteboard.save(chat, item_id: board["id"], version: board.dig("file", "sha256"), app_name: "ChatOpenAI",
                                  origin: user, epoch: epoch,
                                  data: { "shapes" => [{ "id" => "u1", "type" => "rect", "x" => 0, "y" => 0, "w" => 50, "h" => 50 },
                                                       { "id" => "u2", "type" => "line", "x1" => 0, "y1" => 0, "x2" => 9, "y2" => 9 }] })
    done = described_class.run(caller_for, shapes: [{ "id" => "u1", "x" => 300 }, { "type" => "text", "x" => 5, "y" => 5,
                                                                                    "text" => "Note" }],
                                           remove: ["u2"])
    expect(done[:item]["id"]).to eq(board["id"])
    expect(done[:changed]).to eq(["u1"])
    expect(done[:removed]).to eq(["u2"])
    expect(done[:added].size).to eq(1)
    expect(done[:added].first).to start_with("ai-")
    shapes = shapes_of(done[:item])
    expect(shapes.map { |s| s["id"] }).to eq(["u1", done[:added].first])
    expect(shapes[0]).to include("x" => 300.0, "by" => "user", "w" => 50.0)
    expect(described_class.seal(request_id).first["ids"]).to eq(done[:added])
  end

  describe "where the shapes go" do
    let(:layout) { Monadic::Workbench::WhiteboardLayout }

    it "lays out new boxes by their arrows when asked, apart and joined at their middles" do
      flow = [{ "id" => "a", "type" => "box", "text" => "Order" }, { "id" => "b", "type" => "box", "text" => "Pay" },
              { "id" => "c", "type" => "box", "text" => "Ship" },
              { "type" => "arrow", "from" => "a", "to" => "b" }, { "type" => "arrow", "from" => "b", "to" => "c" }]
      done = described_class.run(caller_for, shapes: flow, layout: "right")
      shapes = shapes_of(done[:item]).to_h { |sh| [sh["id"], sh] }
      expect(shapes["a"]["x"]).to be < shapes["b"]["x"]
      expect(shapes["b"]["x"]).to be < shapes["c"]["x"]
      %w[a b c].combination(2).each do |p, q|
        expect(layout.overlap?(layout.bounds(shapes[p]), layout.bounds(shapes[q]))).to be false
      end
      link = shapes.values.find { |sh| sh["from"] == "a" }
      expect([link["x1"], link["y1"]]).to eq([shapes["a"]["x"] + (shapes["a"]["w"] / 2), shapes["a"]["y"] + (shapes["a"]["h"] / 2)])
      expect(done[:issues]).to eq([])
      expect { described_class.run(caller_for, shapes: flow, layout: "diagonal") }.to raise_error(described_class::Refused, /layout/)
    end

    it "moves a new box off what the user drew, grows a box to its text, and tells both" do
      board = whiteboard.create(chat, app_name: "ChatOpenAI", origin: user, epoch: epoch)
      whiteboard.save(chat, item_id: board["id"], version: board.dig("file", "sha256"), app_name: "ChatOpenAI", origin: user,
                            epoch: epoch, data: { "shapes" => [{ "id" => "mine", "type" => "rect", "x" => 400, "y" => 400, "w" => 200, "h" => 100 }] })
      done = described_class.run(caller_for, shapes: [{ "id" => "n", "type" => "box", "x" => 450, "y" => 420, "w" => 60, "h" => 30,
                                                        "text" => "A rather long label" }])
      shapes = shapes_of(done[:item]).to_h { |sh| [sh["id"], sh] }
      expect(layout.overlap?(layout.bounds(shapes["n"]), layout.bounds(shapes["mine"]))).to be false
      expect(shapes["n"]["w"]).to be > 60
      expect(done[:adjusted].map { |a| a.keys.sort }).to contain_exactly(%w[grew id], %w[id moved])
      expect(shapes["mine"]).to include("x" => 400.0, "y" => 400.0)
    end

    it "tells the shapes it had no time to move, and leaves them where they were given" do
      stub_const("#{described_class}::TIDY_SECONDS", -1.0)
      board = whiteboard.create(chat, app_name: "ChatOpenAI", origin: user, epoch: epoch)
      whiteboard.save(chat, item_id: board["id"], version: board.dig("file", "sha256"), app_name: "ChatOpenAI", origin: user,
                            epoch: epoch, data: { "shapes" => [{ "id" => "mine", "type" => "rect", "x" => 400, "y" => 400, "w" => 200, "h" => 100 }] })
      done = described_class.run(caller_for, shapes: [{ "id" => "n", "type" => "box", "x" => 450, "y" => 420 }])
      expect(done[:issues]).to include("n was not moved off what it covers: no time left")
      expect(shapes_of(done[:item]).find { |sh| sh["id"] == "n" }).to include("x" => 450.0, "y" => 420.0)
    end

    it "routes a joined arrow round a box in its way, and tells a straight one that goes through it" do
      row = [{ "id" => "a", "type" => "box", "x" => 100, "y" => 100, "text" => "A" },
             { "id" => "b", "type" => "box", "x" => 500, "y" => 100, "text" => "B" },
             { "id" => "c", "type" => "box", "x" => 900, "y" => 100, "text" => "C" },
             { "id" => "ac", "type" => "arrow", "from" => "a", "to" => "c" },
             { "id" => "st", "type" => "arrow", "from" => "a", "to" => "c", "route" => "straight", "text" => "direct" }]
      out = JSON.parse(MonadicSharedTools::WorkbenchTools.draw(caller_for, shapes: JSON.generate(row), remove: nil,
                                                                           new_whiteboard: false, layout: nil))
      expect(out["issues"]).to eq(["st goes through b"])
      shapes = shapes_of(described_class.run(caller_for, shapes: [], remove: ["nothing"])[:item]).to_h { |sh| [sh["id"], sh] }
      expect(shapes["ac"]).to include("route" => "elbow")
      expect(shapes["st"]).to include("route" => "straight", "text" => "direct", "size" => 20)
    end
  end

  it "describes the tool whole, from the board to deleting a message" do
    text = Monadic::Workbench::DrawTool::DESCRIPTION
    expect(text).to start_with("Draw on a whiteboard in the work screen")
    expect(text).to include('give layout "right"')
    expect(text).to end_with("what the user drew stays.")
  end

  it "refuses what it cannot draw, and draws nothing of it" do
    expect { described_class.run(caller_for, shapes: "[{") }.to raise_error(described_class::Refused, /not valid JSON/)
    expect { described_class.run(caller_for, shapes: nil) }.to raise_error(described_class::Refused, /give shapes/)
    expect { described_class.run(nil, shapes: diagram) }.to raise_error(described_class::Refused)
    item = described_class.run(caller_for, shapes: [{ "id" => "a", "type" => "box", "x" => 1, "y" => 1, "w" => 9, "h" => 9 }])[:item]
    expect do
      described_class.run(caller_for, shapes: [{ "type" => "box", "x" => 1, "y" => 1, "w" => 9, "h" => 9 },
                                               { "type" => "arrow", "from" => "a", "to" => "nowhere" }])
    end.to raise_error(described_class::Refused, /to names no shape/)
    expect(shapes_of(item).map { |s| s["id"] }).to eq(["a"])
  end

  it "takes off what a deleted message added, and leaves what the user drew" do
    done = described_class.run(caller_for, shapes: diagram)
    path = done[:item].dig("file", "path")
    item = Monadic::Workbench::Board.existing(chat).item_at(path)
    whiteboard.save(chat, item_id: item["id"], version: item.dig("file", "sha256"), app_name: "ChatOpenAI", origin: user,
                          epoch: epoch, data: { "shapes" => kept(path) + [{ "id" => "mine", "type" => "line", "x1" => 0,
                                                                            "y1" => 0, "x2" => 9, "y2" => 9 }] })
    drawn = described_class.clean(described_class.seal(request_id))
    expect(described_class.undo(chat, drawn, app_name: "ChatOpenAI")).to eq([path])
    expect(kept(path).map { |s| s["id"] }).to eq(["mine"])
  end

  it "takes off what a message drew when the message is deleted, and keeps it in the history" do
    path = described_class.run(caller_for, shapes: diagram)[:item].dig("file", "path")
    message = { "mid" => "m1", "role" => "assistant", "text" => "Here",
                described_class::KEY => described_class.clean(described_class.seal(request_id)) }
    kept_message = Monadic::History::Serializer.message(message)
    expect(kept_message[described_class::KEY]).to eq([{ "path" => path, "ids" => %w[order ship link] }])
    editor = Class.new { include WebSocketHelper }.new
    rack_session = { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "ChatOpenAI" } }
    editor.take_off_drawn(rack_session, kept_message)
    expect(kept(path)).to eq([])
  end

  it "leaves what a deleted message drew when the user chose to keep it" do
    path = described_class.run(caller_for, shapes: diagram)[:item].dig("file", "path")
    message = { "mid" => "m1", "role" => "assistant", "text" => "Here",
                described_class::KEY => described_class.clean(described_class.seal(request_id)) }
    editor = Class.new { include WebSocketHelper }.new
    allow(editor).to receive(:send_or_broadcast)
    rack_session = { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "ChatOpenAI" },
                     messages: [message] }
    Thread.current[:rack_session] = rack_session
    editor.handle_delete_message(nil, { "mid" => "m1", "keep_drawn" => true })
    expect(rack_session[:messages]).to eq([])
    expect(kept(path).map { |s| s["id"] }).to eq(%w[order ship link])
  ensure
    Thread.current[:rack_session] = nil
  end

  it "takes off what a reply drew when it ends without a message" do
    path = described_class.run(caller_for, shapes: diagram)[:item].dig("file", "path")
    described_class.close(request_id)
    expect(kept(path)).to eq([])
    expect(described_class.seal(request_id)).to eq([])
  end

  it "keeps of a message's record only whiteboards of the chat folders with ids" do
    folder = "#{Monadic::Workspace::Folders::ROOT_DIRNAME}/c1"
    expect(described_class.clean([{ "path" => "#{folder}/whiteboards/whiteboard-1.wb.json", "ids" => ["a", "bad id", 3] },
                                  { "path" => "/etc/passwd", "ids" => ["a"] },
                                  { "path" => "#{folder}/notes.md", "ids" => ["a"] },
                                  { "path" => "#{folder}/whiteboards/whiteboard-2.wb.json", "ids" => [] },
                                  "nothing"]))
      .to eq([{ "path" => "#{folder}/whiteboards/whiteboard-1.wb.json", "ids" => ["a"] }])
    expect(described_class.clean("x")).to be_nil
  end

  it "answers the tool with what it drew, or why nothing was" do
    out = JSON.parse(MonadicSharedTools::WorkbenchTools.draw(caller_for, shapes: diagram, remove: nil, new_whiteboard: false))
    expect(out).to eq("status" => "drawn", "name" => "whiteboard-1.wb.json", "added" => %w[order ship link])
    again = JSON.parse(MonadicSharedTools::WorkbenchTools.draw(caller_for, shapes: [{ "id" => "x", "type" => "box", "x" => 1,
                                                                                         "y" => 1, "w" => 9, "h" => 9 }],
                                                                           remove: nil, new_whiteboard: "true"))
    expect(again["name"]).to eq("whiteboard-2.wb.json")
    expect(MonadicSharedTools::WorkbenchTools.draw(caller_for, shapes: "", remove: nil, new_whiteboard: false))
      .to start_with("❌ Nothing was drawn")
  end
end
