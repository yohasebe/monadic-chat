# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/turn_records"
require_relative "../../../lib/monadic/utils/websocket"

# The work screen as each turn left it, kept for the turn's card: taken when
# the user's message is accepted and when the reply ends, shown from the
# card's message, and deleted with it.
RSpec.describe Monadic::Workbench::TurnRecords do
  around do |example|
    Dir.mktmpdir("workbench-turns-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:channel) { Monadic::Workbench::Channel }
  let(:live) { ->(t) { t == "tab-1" ? 1 : nil } }
  let(:first) { Monadic::Workspace::Ids.generate(:request) }
  let(:user) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = live
    Monadic::Workbench::ViewTokens.reset!
    Monadic::Workbench::Approvals.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def write(path, text)
    full = File.join(@data, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def board = Monadic::Workbench::Board.for(chat, store: store)
  def epoch = Monadic::Workspace::Chats.epoch(chat)

  def open_file(path, origin = user)
    board.add_file(path: path, origin: origin, epoch: epoch).first
  end

  def ids(record) = record["items"].map { |item| [item["id"], item["place"]] }

  def session_with(messages) = { chat_id: chat, _ws_generation: 1, messages: messages }

  it "keeps the desk as the user's message and the reply left it, before the layers move" do
    write("notes.txt", "one")
    mine = open_file("notes.txt")
    Monadic::Workbench::Board.begin_reply(chat, first)
    record = described_class.read(chat, first, "user", store: store)
    expect(ids(record)).to eq([[mine["id"], "current"]])
    expect(record).to include("request_id" => first, "by" => "user", "put_away" => 0)

    write("answer.txt", "two")
    theirs = open_file("answer.txt", { actor: :agent, request_id: first })
    Monadic::Workbench::Board.end_reply(first)
    reply = described_class.read(chat, first, "agent", store: store)
    # The user's item went down when the message was accepted; the reply's is in Now.
    expect(ids(reply)).to eq([[theirs["id"], "current"], [mine["id"], "latest"]])
    expect(reply["items"].first).to include("name" => "answer.txt", "version" => theirs.dig("file", "sha256"))
  end

  it "keeps the marks shown then, as they were: erasing them later changes no record" do
    require_relative "../../../lib/monadic/workbench/picture"
    File.binwrite(File.join(@data, "plan.pdf"), "%PDF-1.4 plan")
    item = open_file("plan.pdf")
    version = item.dig("file", "sha256")
    mark = { "shape" => "rect", "color" => "cyan", "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2 }
    sent = Monadic::Workbench::Picture.new(id: "p_#{SecureRandom.hex(10)}", chat_id: chat, request_id: first, item_id: item["id"],
                                           version: version, kind: "pdf", page: 1, pages: 2, mark: mark, bytes: "png",
                                           mark_id: "m_aaaaaa", mark_rev: 1, rect: { "x" => 0.3, "y" => 0.4, "w" => 0.1, "h" => 0.1 })
    Monadic::Workbench::Board.begin_reply(chat, first, marks: { pictures: [sent], erased: [] })
    Monadic::Workbench::Board.end_reply(first)
    second = Monadic::Workspace::Ids.generate(:request)
    board.accept(item_id: item["id"], action: "bring", operation_id: "op-bring-0001", epoch: epoch, sha256: version)
    Monadic::Workbench::Board.begin_reply(chat, second,
                                          marks: { pictures: [], erased: [{ "item_id" => item["id"], "version" => version,
                                                                             "targets" => [["m_aaaaaa", 1]] }] })
    kept = described_class.read(chat, first, "user", store: store)["items"].first["marks"]
    expect(kept.map { |m| [m["id"], m["rect"]["x"]] }).to eq([["m_aaaaaa", 0.3]])
    expect(described_class.read(chat, second, "user", store: store)["items"].first["marks"]).to be_nil
  end

  it "keeps a turn that placed nothing, and an empty desk for a chat without a work screen" do
    Monadic::Workbench::Board.begin_reply(chat, first)
    expect(described_class.read(chat, first, "user", store: store)).to include("items" => [], "put_away" => 0)
  end

  it "keeps the reply's turn after a restart that stopped it" do
    write("notes.txt", "one")
    open_file("notes.txt")
    Monadic::Workbench::Board.begin_reply(chat, first)
    write("half.txt", "half")
    open_file("half.txt", { actor: :agent, request_id: first })
    Monadic::Workbench::Board.reset!
    board.snapshot
    expect(described_class.read(chat, first, "agent", store: store)["items"].map { |item| item["name"] })
      .to eq(%w[half.txt notes.txt])
  end

  it "shows a card's desk: what is the same, changed or gone, with addresses for what is the same" do
    write("notes.txt", "one")
    write("plan.txt", "plan")
    notes = open_file("notes.txt")
    plan = open_file("plan.txt")
    Monadic::Workbench::Board.begin_reply(chat, first)
    Monadic::Workbench::Board.end_reply(first)
    write("notes.txt", "one, changed")
    open_file("notes.txt")
    board.accept(item_id: plan["id"], action: "remove", operation_id: "op-remove-0001", epoch: epoch,
                 sha256: plan.dig("file", "sha256"))
    messages = [{ "mid" => "m_user", "role" => "user", "text" => "hi", "request_id" => first },
                { "mid" => "m_reply", "role" => "assistant", "text" => "yes", "reply_to" => first },
                { "mid" => "m_old", "role" => "assistant", "text" => "before" }]
    view = channel.turn_view(session_with(messages), mid: "m_user", tab: "tab-1", generation: 1, live: live)
    expect(view).to include("status" => "ok", "by" => "user")
    states = view["items"].to_h { |item| [item["name"], item["now"]] }
    expect(states["notes.txt"]).to eq("changed")
    expect(view["assets"].keys).not_to include(notes["id"])
    expect(channel.turn_view(session_with(messages), mid: "m_reply", tab: "tab-1", generation: 1, live: live))
      .to include("status" => "ok", "by" => "agent")
    expect(channel.turn_view(session_with(messages), mid: "m_old", tab: "tab-1", generation: 1, live: live))
      .to include("status" => "none")
    expect(channel.turn_view(session_with(messages), mid: "m_nope", tab: "tab-1", generation: 1, live: live))
      .to include("status" => "not_found")
    expect(channel.turn_view(session_with(messages), mid: "m_user", tab: "tab-2", generation: 1, live: live)).to be_nil
  end

  it "gives addresses for an item still at the version the turn had" do
    write("notes.txt", "one")
    notes = open_file("notes.txt")
    Monadic::Workbench::Board.begin_reply(chat, first)
    messages = [{ "mid" => "m_user", "role" => "user", "text" => "hi", "request_id" => first }]
    view = channel.turn_view(session_with(messages), mid: "m_user", tab: "tab-1", generation: 1, live: live)
    expect(view["items"].first["now"]).to eq("same")
    expect(view["assets"].keys).to eq([notes["id"]])
  end

  it "is deleted with its card only: the other side's card keeps its own" do
    Monadic::Workbench::Board.begin_reply(chat, first)
    Monadic::Workbench::Board.end_reply(first)
    editor = Class.new { include WebSocketHelper }.new
    rack_session = { Monadic::Workspace::Chats::SESSION_KEY => chat }
    editor.forget_turn_record(rack_session, { "mid" => "m_reply", "role" => "assistant", "reply_to" => first })
    expect(described_class.read(chat, first, "agent", store: store)).to be_nil
    expect(described_class.read(chat, first, "user", store: store)).not_to be_nil
  end

  it "reads and writes no record outside the chat's folder" do
    expect(described_class.path_of(chat, "../../etc/passwd", "user", store: store)).to be_nil
    expect(described_class.path_of(chat, first, "someone", store: store)).to be_nil
    expect(described_class.read(chat, "nope", "user", store: store)).to be_nil
  end
end
