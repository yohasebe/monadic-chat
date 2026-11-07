# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "base64"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workbench/show"
require_relative "../../../lib/monadic/history/serializer"

# "Show to the assistant": what the page fixed at a press is taken as a look
# takes it, held for the message being written, and taken by the message
# all at once.
RSpec.describe "showing the assistant what the work screen shows" do
  let(:shown) { Monadic::Workbench::Shown }
  let(:show) { Monadic::Workbench::Show }
  let(:capture) { Monadic::Workbench::Capture }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, messages: [], parameters: {}, _ws_generation: 1 } }
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:told) { Queue.new }
  let(:deliver) { ->(message) { told << message } }
  # What the page fixed at each press (op → its answer), and how long the
  # page takes to answer.
  let(:fixed) { {} }
  let(:answer_after) { 0 }
  let(:asked) { [] }

  around do |example|
    transport = capture.transport
    Dir.mktmpdir("workbench-show-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  ensure
    capture.transport = transport
    capture.reset!
  end

  before do
    shown.reset!
    show.reset!
    capture.reset!
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { live_tabs[t] }
    Monadic::Workbench::Look::Ledger.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    capture.transport = lambda do |_tab, _generation, _chat, json|
      request = JSON.parse(json)
      asked << request
      answer = fixed[request["op"]]
      delay = answer_after
      Thread.new { sleep delay; capture.reading(request["id"], 2) { answer } } if answer
      true
    end
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  # A JPEG's header (what the relay's frames are).
  def jpeg(width, height)
    "\xFF\xD8\xFF\xC0\x00\x11\x08".b + [height, width].pack("nn") + "\x03\x01\x22\x00\x02\x11\x01\x03\x11\x01\xFF\xD9".b
  end

  def epoch
    Monadic::Workspace::Chats.epoch(chat)
  end

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def open_file(name, bytes)
    File.binwrite(File.join(@data, name), bytes)
    board.add_file(path: name, origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 }, epoch: epoch).first
  end

  def op = SecureRandom.hex(8)

  def press(item, op_id: op, serial: board.selection(tab: "tab-1", generation: 1).last)
    version = item["browser"] ? "browser:#{item.dig('browser', 'instance')}" : (item["artifact"] || item["file"])["sha256"]
    result = show.press(session: session, tab: "tab-1", generation: 1, op_id: op_id, item_id: item["id"], version: version,
                        serial: serial, deliver: deliver)
    [op_id, result]
  end

  def answer_for(op_id)
    message = told.pop(timeout: 5)
    expect(message["op_id"]).to eq(op_id)
    message
  end

  describe "a press" do
    it "holds an image as the user showed it, and tells the page" do
      item = open_file("a.png", png(4, 3))
      op_id, accepted = press(item)
      expect(accepted).to be(true)
      message = answer_for(op_id)
      expect(message).to include("type" => "workbench_shown", "status" => "ready")
      expect(message["expires_in"]).to be_between(shown::TTL - 5, shown::TTL)
      expect(message["snapshot_id"]).to match(shown::SNAPSHOT_ID)
      expect(message["record"]).to include("kind" => "image", "name" => "a.png", "image" => true)
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("ready")
    end

    context "when the page answers a moment later" do
      let(:answer_after) { 0.6 }

      it "takes what it fixed at the press though the tab selected something else meanwhile" do
        item = open_file("n.txt", "one\ntwo\n")
        other = open_file("b.png", png(2, 2))
        board.select(tab: "tab-1", generation: 1, item_id: item["id"])
        op_id = op
        fixed[op_id] = { "range" => { "first_line" => 1, "last_line" => 2 } }
        press(item, op_id: op_id)
        board.select(tab: "tab-1", generation: 1, item_id: other["id"])
        expect(answer_for(op_id)["status"]).to eq("ready")
      end
    end

    it "takes the lines the page fixed at the press, asking it for that press, whatever the tab selects later" do
      item = open_file("n.txt", (1..20).map { |n| "line #{n}" }.join("\n") + "\n")
      other = open_file("b.png", png(2, 2))
      op_id = op
      fixed[op_id] = { "range" => { "first_line" => 5, "last_line" => 6 }, "note" => nil }
      serial = board.selection(tab: "tab-1", generation: 1).last
      board.select(tab: "tab-1", generation: 1, item_id: item["id"])
      serial = board.selection(tab: "tab-1", generation: 1).last
      _, accepted = press(item, op_id: op_id, serial: serial)
      expect(accepted).to be(true)
      board.select(tab: "tab-1", generation: 1, item_id: other["id"])
      message = answer_for(op_id)
      expect(message["status"]).to eq("ready")
      expect(asked.last).to include("op" => op_id, "item_id" => item["id"], "wants" => ["range"])
      expect(message["record"]["lines"]).to eq({ "first" => 2, "last" => 9 })
    end

    it "is refused at once for another selection than the page's, and in a Private chat" do
      item = open_file("a.png", png(2, 2))
      expect(press(item, serial: -1).last).to eq("selection_changed")
      session[Monadic::History::Policy::SESSION_KEY] = Monadic::History::Policy::PRIVATE
      expect(press(item).last).to eq("private")
    end

    it "is not brought back by a late completion once the user took it back" do
      item = open_file("n.txt", "one\n")
      op_id = op
      _, accepted = press(item, op_id: op_id)
      expect(accepted).to be(true)
      show.remove(tab: "tab-1", generation: 1, op_id: op_id)
      fixed[op_id] = { "range" => { "first_line" => 1, "last_line" => 1 } }
      message = answer_for(op_id)
      expect(message["status"]).to eq("refused")
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("removed")
      expect(press(item, op_id: op_id).last).to eq("unknown")
    end

    it "takes the browser's frame the work screen showed at the press" do
      item = board.add_browser(instance: "inst-1", origin: { actor: :agent, source: :browser, tab: "tab-1", generation: 1 },
                               epoch: epoch)
      op_id = op
      fixed[op_id] = { "relay" => Base64.strict_encode64(jpeg(1280, 720)), "relay_browser" => "inst-1" }
      press(item, op_id: op_id)
      message = answer_for(op_id)
      expect(message["record"]).to include("kind" => "browser", "image" => true, "source" => "workbench_relay")
      record = Monadic::Workbench::Look::Record.clean([{ "id" => "look_#{'c' * 16}", "kind" => "browser",
                                                         "state" => "sent", "source" => "workbench_relay" }])
      expect(record.first["source"]).to eq("workbench_relay")
      expect(asked.last["wants"]).to eq(["relay"])
      { [jpeg(10, 10), "inst-2"] => "not_shown", [png(10, 10), "inst-1"] => "unsupported_kind",
        [jpeg(1281, 10), "inst-1"] => "too_large" }.each do |(bytes, instance), reason|
        other = op
        fixed[other] = { "relay" => Base64.strict_encode64(bytes), "relay_browser" => instance }
        press(item, op_id: other)
        expect(answer_for(other)).to include("status" => "refused", "reason" => reason)
      end
    end

    it "keeps the name and the path the Privacy Filter lets go, and when it was taken" do
      item = open_file("secret-plan.png", png(2, 2))
      allow(Monadic::Workbench::Look).to receive(:filtered).and_call_original
      allow(Monadic::Workbench::Look).to receive(:filtered).with(session, "secret-plan.png").and_return("<<NAME>>")
      op_id, = press(item)
      message = answer_for(op_id)
      expect(message["record"]).to include("name" => "<<NAME>>", "path" => "<<NAME>>")
      expect(message["record"]["at"]).to match(/\A\d{4}-\d\d-\d\dT/)
      expect(message["expires_in"]).to be <= shown::TTL
    end

    it "leaves nothing being prepared when no worker can take the press" do
      item = open_file("a.png", png(2, 2))
      stub_const("Monadic::Workbench::Show::WORKERS", 0)
      stub_const("Monadic::Workbench::Show::QUEUE", 0)
      op_id = op
      expect(press(item, op_id: op_id).last).to eq("busy")
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to be_nil
      expect(show.busy).to eq([0, 0])
    end

    it "gives the worker's room back when the press cannot be held" do
      item = open_file("a.png", png(2, 2))
      op_id, = press(item)
      answer_for(op_id)
      expect(press(item, op_id: op_id).last).to eq("unknown")
      until_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.05 until show.busy == [0, 0] || Process.clock_gettime(Process::CLOCK_MONOTONIC) > until_at
      expect(show.busy).to eq([0, 0])
    end

    it "takes a press back only for its own connection, and stops its work at once" do
      stub_const("Monadic::Workbench::Capture::RECHECK", 5)
      item = open_file("n.txt", "one\n")
      op_id = op
      press(item, op_id: op_id)
      until_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.05 until asked.any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > until_at
      show.remove(tab: "tab-1", generation: 2, op_id: op_id)
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("preparing")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      show.remove(tab: "tab-1", generation: 1, op_id: op_id)
      expect(answer_for(op_id)).to include("status" => "refused", "reason" => "cancelled")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end

    it "ends the press it made when no worker can be started" do
      item = open_file("a.png", png(2, 2))
      op_id = op
      allow(Thread).to receive(:new).and_raise(ThreadError, "no thread")
      expect(press(item, op_id: op_id).last).to eq("busy")
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("failed")
      expect(show.busy).to eq([0, 0])
    end

    it "stops waiting for a worker when the press is taken back, and gives its room back" do
      stub_const("Monadic::Workbench::Show::WORKERS", 0)
      item = open_file("a.png", png(2, 2))
      op_id = op
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      press(item, op_id: op_id)
      show.remove(tab: "tab-1", generation: 1, op_id: op_id)
      expect(answer_for(op_id)).to include("status" => "refused", "reason" => "cancelled")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      until_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.05 until show.busy == [0, 0] || Process.clock_gettime(Process::CLOCK_MONOTONIC) > until_at
      expect(show.busy).to eq([0, 0])
    end

    it "is refused when too much is being shown" do
      item = open_file("a.png", png(2, 2))
      stub_const("Monadic::Workbench::Shown::DRAFT_ENTRIES", 1)
      op_id, = press(item)
      answer_for(op_id)
      expect(press(item).last).to eq("busy")
    end
  end

  describe "taking what was shown with a message" do
    let(:host) { Class.new { include WebSocketHelper }.new }
    let(:errors) { [] }

    before do
      Thread.current[:websocket_session_id] = "tab-1"
      allow(host).to receive(:send_error) { |content, _tab, extra| errors << [content, extra] }
      allow(Monadic::Workbench::Look::Availability).to receive(:vision?).and_return(true)
    end

    after { Thread.current[:websocket_session_id] = nil }

    def ready_snapshot(name = "a.png")
      op_id, = press(open_file(name, png(4, 3)))
      answer_for(op_id)["snapshot_id"]
    end

    # As a message is accepted: handed, then recorded with the user's
    # message (the block runs between, as more of the message is made), or
    # given back. Returns [records or nil, request_id].
    def take(ids, request_id = Monadic::Workspace::Ids.generate(:request))
      hand = {}
      begin
        return [nil, request_id] unless host.send(:hand_workbench_shown, session, chat, request_id, ids, {}, hand)

        yield if block_given?
        recorded = host.send(:record_with_workbench_shown, hand, "tab-1") { session[:messages] << { "role" => "user" } }
        [recorded ? hand[:records] : nil, request_id]
      ensure
        host.send(:give_back_workbench_shown, hand, request_id) unless hand[:done]
      end
    end

    it "puts all of it in the request's looks as the user's, and gives the records for the user's message" do
      ids = [ready_snapshot("a.png"), ready_snapshot("b.png")]
      records, request_id = take(ids)
      expect(records.map { |r| r["name"] }).to eq(%w[a.png b.png])
      ledger = Monadic::Workbench::Look::Ledger.of_request(chat, request_id)
      expect(ledger.shown.map(&:origin)).to eq(%w[user user])
      expect(ledger.shown.first.result).to include('"status":"shown"')
      expect(ledger.records(origin: "tool")).to be_empty
    end

    it "takes none of it when any of it cannot go, and keeps the rest for another try" do
      good = ready_snapshot
      records, = take([good, "x" * 22])
      expect(records).to be_nil
      expect(errors.last.last).to include("not_accepted" => true)
      records, = take([good])
      expect(records.size).to eq(1)
    end

    it "is refused for a model that does not take images, keeping what was shown" do
      good = ready_snapshot
      allow(Monadic::Workbench::Look::Availability).to receive(:vision?).and_return(false)
      expect(take([good]).first).to be_nil
      expect(errors.last.last).to include("workbench_shown" => "vision_unsupported")
      allow(Monadic::Workbench::Look::Availability).to receive(:vision?).and_return(true)
      expect(take([good]).first.size).to eq(1)
    end

    it "is not taken twice, nor by another connection" do
      good = ready_snapshot
      take([good])
      expect(take([good]).first).to be_nil
      other = ready_snapshot
      session[:_ws_generation] = 2
      live_tabs["tab-1"] = 2
      expect(take([other]).first).to be_nil
    end

    it "gives back what was handed when the request's looks cannot take it, but not once it was let go" do
      good = ready_snapshot
      allow(Monadic::Workbench::Look::Ledger).to receive(:for).and_raise(Monadic::Workbench::Look::Refused.new("busy", "full"))
      expect(take([good]).first).to be_nil
      expect(errors.last.last).to include("workbench_shown" => "busy")
      allow(Monadic::Workbench::Look::Ledger).to receive(:for).and_call_original
      expect(take([good]).first.size).to eq(1)

      handed = ready_snapshot
      entries = shown.take_all(tab: "tab-1", generation: 1, chat_id: chat, epoch: epoch, snapshot_ids: [handed], images: true)
      shown.revoke_chat(chat)
      shown.give_back(entries)
      expect(shown.state(tab: "tab-1", generation: 1, op_id: entries.first.op_id)).to eq("removed")
    end

    it "takes none of it for good when any of it ended while it was handed, and records no message" do
      first = ready_snapshot("a.png")
      second = ready_snapshot("b.png")
      messages = session[:messages].size
      first_op = shown.instance_variable_get(:@entries).values.find { |e| e.snapshot_id == first }.op_id
      records, request_id = take([first, second]) { shown.remove(tab: "tab-1", generation: 1, op_id: first_op) }
      expect(records).to be_nil
      expect(session[:messages].size).to eq(messages)
      expect(errors.last.last).to include("workbench_shown" => "expired")
      expect(Monadic::Workbench::Look::Ledger.of_request(chat, request_id)).to be_nil
      expect(take([second]).first.size).to eq(1)
    end

    it "takes nothing that expired or was let go while it was handed" do
      good = ready_snapshot
      records, = take([good]) { shown.instance_variable_get(:@entries).each_value { |e| e.expires_at = -1 } }
      expect(records).to be_nil
      other = ready_snapshot("c.png")
      records, = take([other]) { shown.revoke_chat(chat) }
      expect(records).to be_nil
    end

    it "gives it back when the message stops before the user's message is recorded" do
      good = ready_snapshot
      allow(host).to receive(:sts_session_capable?).and_return(false)
      allow(host).to receive(:get_session_params).and_return({ "app_name" => "TestApp" })
      allow(host).to receive(:initialize_token_counting).and_raise(RuntimeError, "no counting")
      sent = { "message" => "look at this", "workbench_shown" => [good], "app_name" => "TestApp", "model" => "m" }
      expect { host.send(:handle_ws_streaming, nil, sent, session, Queue.new) }.to raise_error(RuntimeError, "no counting")
      expect(session[:messages]).to be_empty
      entry = shown.instance_variable_get(:@entries).values.find { |e| e.snapshot_id == good }
      expect(entry.state).to eq("ready")
      expect(take([good]).first.size).to eq(1)
    end

    it "ends the request when the message was recorded but its reply could not start" do
      good = ready_snapshot
      allow(host).to receive(:sts_session_capable?).and_return(false)
      allow(host).to receive(:get_session_params).and_return({ "app_name" => "TestApp" })
      allow(host).to receive(:send_or_broadcast)
      allow(host).to receive(:saved_as)
      allow(Thread).to receive(:new).and_raise(ThreadError, "no thread")
      sent = { "message" => "", "workbench_shown" => [good], "app_name" => "TestApp", "model" => "m" }
      expect { host.send(:handle_ws_streaming, nil, sent, session, Queue.new) }.to raise_error(ThreadError)
      turn = session[:messages].last
      expect(turn["workbench_shown"]).to match([a_hash_including("name" => "a.png", "state" => "unsent")])
      expect(Monadic::Workbench::Look::Ledger.of_request(chat, turn["request_id"])).to be_nil
      entry = shown.instance_variable_get(:@entries).values.find { |e| e.snapshot_id == good }
      expect(entry.state).to eq("taken")
    end

    it "lets go of what it held once a message took it" do
      good = ready_snapshot
      take([good])
      entry = shown.instance_variable_get(:@entries).values.find { |e| e.snapshot_id == good }
      expect(entry.state).to eq("taken")
      expect(entry.seen).to be_nil
      expect(entry.ended_at).not_to be_nil
    end

    it "takes no list that is empty or not a list" do
      expect(take([]).first).to be_nil
      expect(take("x" * 22).first).to be_nil
    end

    it "is let go when the chat becomes Private" do
      op_id, = press(open_file("a.png", png(4, 3)))
      good = answer_for(op_id)["snapshot_id"]
      Monadic::History::Policy.mark_private!(session)
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("removed")
      expect(take([good]).first).to be_nil
    end
  end

  describe "the records" do
    let(:host) { Class.new { include WebSocketHelper }.new }

    it "keep what the user showed on the user's message and the reply's looks on the reply, from one take" do
      request_id = Monadic::Workspace::Ids.generate(:request)
      session[:messages] << { "role" => "user", "mid" => "u1", "text" => "", "request_id" => request_id }
      ledger = Monadic::Workbench::Look::Ledger.for(chat, epoch, request_id, session: session, tab: "tab-1")
      image = Monadic::Workbench::Look::ImageValue.checked(png(2, 2), source: "workbench_file")
      ledger.add(id: "look_#{'a' * 16}", item_id: "i_1", kind: "image", name: "shown.png", path: "shown.png",
                 version: "a" * 64, scope: "visible", image: image, origin: "user")
      ledger.add(id: "look_#{'b' * 16}", item_id: "i_2", kind: "text", name: "looked.txt", path: "looked.txt",
                 version: "b" * 64, scope: "whole", text: "t")
      reply = host.send(:workbench_looks_of_reply, session, request_id)
      expect(reply.map { |r| r["name"] }).to eq(["looked.txt"])
      expect(session[:messages].first["workbench_shown"].map { |r| r["name"] }).to eq(["shown.png"])
      expect(Monadic::Workbench::Look::Ledger.of_request(chat, request_id)).to be_nil
    end

    it "keep a chat whose only user message shows something, with its record and nothing it gave" do
      record = { "id" => "look_#{'a' * 16}", "kind" => "image", "name" => "shown.png", "state" => "sent", "image" => true,
                 "snapshot_id" => "x" * 22, "result" => "secret" }
      kept = Monadic::History::Serializer.payload(
        { messages: [{ "role" => "user", "text" => "", "mid" => "u1", "workbench_shown" => [record] }], parameters: {} }
      )
      expect(kept).not_to be_nil
      user = kept["messages"].first
      expect(user["workbench_shown"]).to eq([record.slice("id", "kind", "name", "state", "image")])
    end
  end

  describe "what is held" do
    it "ends what has expired, and remembers the press" do
      item = open_file("a.png", png(2, 2))
      op_id, = press(item)
      answer_for(op_id)
      stub_const("Monadic::Workbench::Shown::TTL", -1)
      shown.instance_variable_get(:@entries).each_value { |e| e.expires_at = -1 }
      shown.sweep_now
      expect(shown.state(tab: "tab-1", generation: 1, op_id: op_id)).to eq("expired")
    end
  end
end
