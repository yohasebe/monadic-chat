# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "rack/mock"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/capture_server"
require_relative "../../../lib/monadic/history/policy"
require_relative "../../../lib/monadic/utils/websocket"

# A look asks the page of the tab it was made for what the work screen
# shows (Capture); the page answers by HTTP (CaptureServer).
RSpec.describe "asking the page what the work screen shows" do
  let(:capture) { Monadic::Workbench::Capture }
  let(:look) { Monadic::Workbench::Look }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:live_tabs) { { "tab-1" => 1, "tab-2" => 1 } }
  let(:asked) { Queue.new }

  around do |example|
    transport = capture.transport
    Dir.mktmpdir("workbench-capture-spec") do |dir|
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
    capture.reset!
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { live_tabs[t] }
    Monadic::Workbench::Look::Ledger.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def epoch
    Monadic::Workspace::Chats.epoch(chat)
  end

  def open_text(text, name: "notes.txt", tab: "tab-1")
    File.binwrite(File.join(@data, name), text)
    board.add_file(path: name, origin: { actor: :user, source: :panel, tab: tab, generation: 1 }, epoch: epoch).first
  end

  def caller_for(tab: "tab-1", generation: 1)
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: request_id, session: session, tab: tab,
                                   generation: generation)
  end

  # The page: what each request asks is kept, and the block (given what
  # was asked) gives the answer, sent as the page sends it (nil: no answer).
  def page(&block)
    answering = block
    capture.transport = lambda do |tab, generation, chat_id, json|
      request = JSON.parse(json).merge("_to" => [tab, generation, chat_id])
      asked << request
      Thread.new do
        answer = answering.call(request)
        capture.reading(request["id"], 2) { answer } if answer
      end
      true
    end
  end

  def lines_text(count)
    (1..count).map { |n| "line #{n}" }.join("\n") + "\n"
  end

  def result(text)
    JSON.parse(text.to_s)
  end

  describe "a look at the lines in view of a text" do
    it "gives the lines the page has in view and a few around them, and records both" do
      item = open_text(lines_text(20))
      page { { "range" => { "first_line" => 8, "last_line" => 10 }, "note" => nil } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["lines"]).to include("first" => 5, "last" => 13, "total" => 20, "in_view" => { "first" => 8, "last" => 10 })
      expect(out["text"]).to eq((5..13).map { |n| "line #{n}\n" }.join)
      request = asked.pop(timeout: 5)
      expect(request).to include("type" => "workbench_capture", "item_id" => item["id"],
                                 "version" => item["file"]["sha256"], "wants" => ["range"])
      expect(request["_to"]).to eq(["tab-1", 1, chat])
      expect(request["serial"]).to be_a(Integer)
      record = Monadic::Workbench::Look::Ledger.find(chat, request_id).records.first
      expect(Monadic::Workbench::Look::Record.clean([record]).first["lines"]).to include("asked_first" => 8, "asked_last" => 10)
    end

    it "keeps the margins inside the text and gives up the margins first when it is long" do
      open_text(lines_text(5))
      page { { "range" => { "first_line" => 1, "last_line" => 5 } } }
      expect(result(look.run(caller_for, scope: "visible"))["lines"]).to include("first" => 1, "last" => 5)
      stub_const("Monadic::Workbench::Look::TEXT_CHARS", "line 2\nline 3\nline 4\n".length)
      page { { "range" => { "first_line" => 2, "last_line" => 4 } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["lines"]).to include("first" => 2, "last" => 4)
    end

    it "says the lines it gave when the lines in view are more than it gives" do
      long = "x" * 40_000
      open_text("#{long}\n#{long}\n#{long}\n")
      page { { "range" => { "first_line" => 1, "last_line" => 3 } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["text"].length).to eq(look::TEXT_CHARS)
      expect(out["lines"]).to include("first" => 1, "last" => 2, "last_line_cut" => true,
                                      "in_view" => { "first" => 1, "last" => 3 })
      expect(out["truncated"]).to be(true)
    end

    it "gives one line's beginning when that line alone is more than it gives" do
      open_text("#{'y' * 70_000}\nshort\n")
      page { { "range" => { "first_line" => 1, "last_line" => 1 } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["lines"]).to include("first" => 1, "last" => 1, "last_line_cut" => true)
    end

    it "gives whole lines when the cut falls at a line's end" do
      open_text("aaaa\nbbbb\ncccc\n")
      stub_const("Monadic::Workbench::Look::TEXT_CHARS", 10)
      page { { "range" => { "first_line" => 1, "last_line" => 3 } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["text"]).to eq("aaaa\nbbbb\n")
      expect(out["lines"]).to include("first" => 1, "last" => 2, "last_line_cut" => false)
    end

    it "says the last line the work screen shows of a long file is only its beginning" do
      shown = Monadic::Workspace::SharedFolderPreview::TEXT_LIMIT
      open_text(("z" * 99 + "\n") * ((shown / 100) + 10))
      count = Monadic::Workspace::SharedFolderPreview.text_lines(
        Monadic::Workspace::SharedFolderPreview.text_view(("z" * 99 + "\n") * ((shown / 100) + 10))[:text]
      ).size
      page { { "range" => { "first_line" => count - 1, "last_line" => count } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["lines"]).to include("last" => count, "total" => nil, "last_line_cut" => true)
      expect(out["truncated"]).to be(false)
    end

    it "gives the last line the work screen shows whole when what it shows ends at a line's end" do
      shown = Monadic::Workspace::SharedFolderPreview::TEXT_LIMIT
      open_text("x\n" * (shown / 2) + "more\n")
      count = shown / 2
      page { { "range" => { "first_line" => count, "last_line" => count } } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["lines"]).to include("last" => count, "total" => nil, "last_line_cut" => false)
    end

    it "refuses lines the work screen does not show" do
      open_text(lines_text(3))
      page { { "range" => { "first_line" => 2, "last_line" => 9 } } }
      expect(look.run(caller_for, scope: "visible")).to include("(range_unknown)")
    end

    it "says why when the page does not give the lines" do
      open_text(lines_text(3))
      { "not_shown" => "not_shown", "drawing" => "drawing", "changing" => "selection_changed",
        "failed" => "range_unknown" }.each do |note, reason|
        page { { "range" => nil, "note" => note } }
        expect(look.run(caller_for, scope: "visible")).to include("(#{reason})")
      end
    end

    it "looks at a text with no line as empty" do
      open_text("")
      page { { "range" => nil, "note" => "empty" } }
      out = result(look.run(caller_for, scope: "visible"))
      expect(out).to include("empty" => true, "text" => "")
    end

    it "takes nothing when the tab selected again while the page answered" do
      item = open_text(lines_text(3))
      page do
        board.select(tab: "tab-1", generation: 1, item_id: nil)
        board.select(tab: "tab-1", generation: 1, item_id: item["id"])
        { "range" => { "first_line" => 1, "last_line" => 2 } }
      end
      expect(look.run(caller_for, scope: "visible")).to include("(selection_changed)")
    end

    it "is refused when the page does not answer in time, and a late answer is not taken" do
      open_text(lines_text(3))
      stub_const("Monadic::Workbench::Capture::WAIT", 0.3)
      page { nil }
      expect(look.run(caller_for, scope: "visible")).to include("(capture_timeout)")
      expect(capture.reading(asked.pop(timeout: 5)["id"], 2) { {} }).to be_nil
      expect(capture.waiting).to eq(0)
    end

    it "is refused when the tab's page cannot be asked" do
      open_text(lines_text(3))
      capture.transport = ->(*) { false }
      expect(look.run(caller_for, scope: "visible")).to include("(connection_gone)")
    end
  end

  describe "a capture waiting" do
    def ask(valid: -> { true }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5)
      Thread.new do
        capture.request(tab: "tab-1", generation: 1, chat_id: chat, request_id: request_id, item_id: "i", version: "v",
                        serial: 1, wants: ["range"], deadline: deadline, valid: valid)
      rescue capture::Failed => e
        e.reason
      end
    end

    before { page { nil } }

    it "takes the first answer once" do
      waiting = ask
      id = asked.pop(timeout: 5)["id"]
      inner = nil
      expect(capture.reading(id, 2) { |deadline| inner = capture.reading(id, 2) { {} }; deadline.is_a?(Float) && { "range" => nil } }).to be(true)
      expect(inner).to be_nil
      expect(capture.reading(id, 2) { { "range" => nil } }).to be_nil
      expect(waiting.value).to eq({ "range" => nil })
    end

    {
      "the tab has a newer connection" => ->(c, _chat, _req) { c.revoke_tab("tab-1", except_generation: 2) },
      "the connection closed" => ->(c, _chat, _req) { c.revoke_tab("tab-1", generation: 1) },
      "the reply ended" => ->(c, _chat, req) { c.revoke_request(req) },
      "the chat became Private" => ->(_c, chat, _req) { Monadic::History::Policy.mark_private!({ chat_id: chat }) }
    }.each do |what, change|
      it "stops waiting when #{what}" do
        waiting = ask
        id = asked.pop(timeout: 5)["id"]
        change.call(capture, chat, request_id)
        expect(waiting.join(1)&.value).to eq("cancelled")
        expect(capture.reading(id, 2) { {} }).to be_nil
      end
    end

    it "stops waiting when the tab's newer connection is registered, and when the reply's end is said" do
      waiting = ask
      asked.pop(timeout: 5)
      WebSocketHelper.register_live_session("tab-1", { chat_id: chat }, 2)
      expect(waiting.join(1)&.value).to eq("cancelled")
      WebSocketHelper.unregister_live_session("tab-1", 2)

      waiting = ask
      asked.pop(timeout: 5)
      host = Class.new { include WebSocketHelper }.new
      allow(host).to receive(:send_or_broadcast)
      host.send(:finish_reply, request_id, "done", "tab-1")
      expect(waiting.join(1)&.value).to eq("cancelled")
    end

    it "keeps waiting for another tab's connection going" do
      waiting = ask
      id = asked.pop(timeout: 5)["id"]
      capture.revoke_tab("tab-2")
      capture.revoke_tab("tab-1", except_generation: 1)
      expect(capture.reading(id, 2) { { "note" => "ok" } }).to be(true)
      expect(waiting.value).to eq({ "note" => "ok" })
    end

    it "stops waiting when what it was asked for no longer holds" do
      holds = true
      waiting = ask(valid: -> { holds })
      asked.pop(timeout: 5)
      holds = false
      expect(waiting.join(1)&.value).to eq("selection_changed")
    end

    it "is refused when too many are waiting" do
      stub_const("Monadic::Workbench::Capture::PENDING", 1)
      first = ask
      asked.pop(timeout: 5)
      expect(ask.value).to eq("busy")
      capture.revoke_request(request_id)
      first.join
    end

    it "holds the room to read an answer until the reading ends, also when the capture ended meanwhile" do
      stub_const("Monadic::Workbench::Capture::READING", 2)
      go_on = Queue.new
      started = Queue.new
      readers = Array.new(2) do
        ask
        id = asked.pop(timeout: 5)["id"]
        Thread.new do
          capture.reading(id, 2) do
            started << true
            go_on.pop
            { "range" => nil }
          end
        end
      end
      2.times { started.pop(timeout: 5) }
      capture.revoke_request(request_id)
      sleep 0.05 while capture.waiting.positive?
      late = ask
      id = asked.pop(timeout: 5)["id"]
      expect(capture.reading(id, 2) { { "range" => nil } }).to be_nil
      2.times { go_on << true }
      expect(readers.map { |r| r.join(5)&.value }).to eq([false, false])
      expect(capture.reading(id, 2) { { "range" => nil } }).to be(true)
      expect(late.value).to eq({ "range" => nil })
    end

    it "gives the room back once when reading fails or is stopped" do
      stub_const("Monadic::Workbench::Capture::READING", 1)
      waiting = ask
      id = asked.pop(timeout: 5)["id"]
      expect { capture.reading(id, 2) { raise IOError, "gone" } }.to raise_error(IOError)
      started = Queue.new
      stopped = Thread.new { capture.reading(id, 2) { started << true; sleep } }
      started.pop(timeout: 5)
      stopped.kill
      stopped.join(5)
      expect(capture.reading(id, 2) { { "range" => nil } }).to be(true)
      expect(waiting.value).to eq({ "range" => nil })
    end

    it "does not take an answer that is not an object" do
      waiting = ask
      id = asked.pop(timeout: 5)["id"]
      expect(capture.reading(id, 2) { nil }).to be(false)
      expect(capture.reading(id, 2) { [1] }).to be(false)
      expect(capture.reading(id, 2) { { "range" => nil } }).to be(true)
      expect(waiting.value).to eq({ "range" => nil })
    end
  end

  describe "the page's answer by HTTP" do
    let(:app) { Monadic::Workbench::CaptureServer.new(->(_env) { [200, {}, ["app"]] }) }

    def post(id, body, headers = {})
      env = { "REQUEST_METHOD" => "POST", "HTTP_SEC_FETCH_SITE" => "same-origin",
              "CONTENT_TYPE" => "application/json; charset=utf-8", :input => body }.merge(headers)
      Rack::MockRequest.new(app).request(env.delete("REQUEST_METHOD"), "/workbench/capture/#{id}", env)
    end

    def waiting_id
      thread = Thread.new do
        capture.request(tab: "tab-1", generation: 1, chat_id: chat, request_id: request_id, item_id: "i", version: "v",
                        serial: 1, wants: ["range"], deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5,
                        valid: -> { true })
      rescue capture::Failed => e
        e.reason
      end
      [asked.pop(timeout: 5)["id"], thread]
    end

    before { page { nil } }

    it "hands the answer over once, and answers nothing else" do
      id, thread = waiting_id
      response = post(id, '{"range":null,"note":"not_shown"}')
      expect(response.status).to eq(204)
      expect(response.headers["cache-control"]).to eq("no-store")
      expect(thread.value).to eq({ "range" => nil, "note" => "not_shown" })
      expect(post(id, "{}").status).to eq(404)
    end

    it "gives the same not found to anything that is not a page's answer to a waiting capture" do
      id, thread = waiting_id
      body = '{"range":null}'
      [
        ["GET", body, {}],
        ["POST", body, { "HTTP_SEC_FETCH_SITE" => "cross-site" }],
        ["POST", body, { "HTTP_SEC_FETCH_SITE" => nil }],
        ["POST", body, { "CONTENT_TYPE" => "text/plain" }],
        ["POST", body, { "CONTENT_LENGTH" => "" }],
        ["POST", body, { "CONTENT_LENGTH" => "-1" }],
        ["POST", body, { "CONTENT_LENGTH" => (capture::BODY_LIMIT + 1).to_s }],
        ["POST", body, { "CONTENT_LENGTH" => (body.bytesize + 5).to_s }],
        ["POST", "[1]", {}],
        ["POST", "{not json", {}]
      ].each do |method, sent, headers|
        env = { "REQUEST_METHOD" => method }.merge(headers)
        response = post(id, sent, env)
        expect(response.status).to eq(404), "#{method} #{headers}"
        expect(response.body).to eq("Not found")
      end
      expect(post("x" * 43, body).status).to eq(404)
      expect(post("../#{id}", body).status).to eq(404)
      expect(post(id, body).status).to eq(204)
      thread.join
    end

    it "takes a longer answer only from a capture that asked for an image" do
      id, thread = waiting_id
      big = JSON.generate({ "image" => "x" * capture::BODY_LIMIT })
      expect(post(id, big).status).to eq(404)
      expect(post(id, '{"range":null}').status).to eq(204)
      thread.join
      imaged = Thread.new do
        capture.request(tab: "tab-1", generation: 1, chat_id: chat, request_id: request_id, item_id: "i", version: "v",
                        serial: 1, wants: %w[range image], deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5,
                        valid: -> { true })
      end
      id = asked.pop(timeout: 5)["id"]
      expect(post(id, big).status).to eq(204)
      expect(imaged.value.keys).to eq(["image"])
      too_big = JSON.generate({ "pad" => "x" * (capture::IMAGE_LIMIT + capture::BODY_LIMIT) })
      expect(post("y" * 43, too_big).status).to eq(404)
    end

    it "passes other paths on" do
      expect(Rack::MockRequest.new(app).get("/other").body).to eq("app")
    end
  end

  describe "the selection's number" do
    it "is new for each selection, also of the same item, and told with the view and the answer to a selection" do
      item = open_text("a\n")
      first = board.selection(tab: "tab-1", generation: 1).last
      board.select(tab: "tab-1", generation: 1, item_id: item["id"])
      again = board.selection(tab: "tab-1", generation: 1).last
      expect(again).to be > first
      expect(board.selection(tab: "tab-2", generation: 1)).to eq([nil, nil])
      live = ->(t) { live_tabs[t] }
      answer = Monadic::Workbench::Channel.select({ "item_id" => item["id"], "seq" => 3 }, session, tab: "tab-1",
                                                                                                      generation: 1, live: live)
      expect(answer).to include("item_id" => item["id"], "seq" => 3, "serial" => be > again)
      view = Monadic::Workbench::Channel.view(session, tab: "tab-1", generation: 1, live: live)
      expect(view).to include("selected" => item["id"], "selection_serial" => answer["serial"])
    end
  end
end
