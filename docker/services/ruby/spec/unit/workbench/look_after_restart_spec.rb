# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

# A tab that was showing a file on the work screen, after the app restarts
# (the server's memory is gone; what it saved stays): the tab connects again
# with its own id and is in a new chat. The first view it is sent says that
# chat's work screen is empty, so that the page lets the board it still
# shows go, and a look finds what the page then shows: nothing. The app runs
# for real in a child process, twice with the same home.
RSpec.describe "The work screen after the app restarts" do
  include AppProbe

  HEADER = <<~'RUBY'
    require "rack"
    require "json"
    require "socket"
    require "async"
    require "async/http/endpoint"
    require "async/http/server"
    require "async/websocket/client"
    require "protocol/rack"
    app, = Rack::Builder.parse_file("config.ru")
    out = {}
    looks = []
    APPS["ChatOpenAI"].define_singleton_method(:api_request) do |_role, session, &_block|
      caller_now = Monadic::Workbench::Caller.current(session)
      looks << { "chat" => session[Monadic::Workspace::Chats::SESSION_KEY],
                 "caller_chat" => caller_now&.chat_id,
                 "result" => Monadic::Workbench::Look.run(caller_now, scope: "whole").then { |r| r.respond_to?(:text) ? "looked" : r.to_s } }
      [{ "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }] }]
    end
    port = (probe = TCPServer.new("127.0.0.1", 0)).addr[1]
    probe.close
    base = "http://127.0.0.1:#{port}"
    endpoint = Async::HTTP::Endpoint.parse(base)
  RUBY

  DRIVE = <<~'RUBY'
    Async do |task|
      server = task.async { Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), endpoint).run }
      task.sleep(0.2)
      ws = nil
      begin
        ws = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{base}/?tab_id=tab-a"), headers: [["origin", base]])
        frames = []
        read = lambda do |&wanted|
          task.with_timeout(10) do
            loop do
              raw = ws.read
              raise EOFError, "connection closed" if raw.nil?

              frame = (JSON.parse(raw.to_str) rescue {})
              frames << frame["type"]
              break frame if wanted.call(frame)
            end
          end
        end
        say = ->(obj) { ws.write(obj.to_json); ws.flush }
        STEPS
      rescue StandardError => e
        out["stopped_at"] = "#{e.class}: #{e.message}"
      ensure
        # The connection goes first (the server's stop waits for it).
        ws&.close
        task.sleep(0.5)
        server.stop
      end
    end
    STDOUT.puts "PROBE #{out.to_json}"
    STDOUT.flush
    exit!(0)
  RUBY

  # Before the restart: a file of the shared folder is opened on the work
  # screen and selected from this tab, and a look at it is asked for.
  FIRST = <<~'RUBY'
    task.sleep(0.5)
    say.call({ "message" => "WORKBENCH_OPEN", "path" => "notes.txt" })
    opened = read.call { |f| f["type"] == "workbench_opened" }
    out["opened"] = opened["item_id"]
    view = read.call { |f| f["type"] == "workbench" && f.dig("board", "items").to_a.any? }
    out["board_chat"] = view.dig("board", "chat_id")
    say.call({ "message" => "WORKBENCH_SELECT", "item_id" => opened["item_id"], "seq" => 1 })
    read.call { |f| f["type"] == "workbench_selected" }
    say.call({ "message" => "look", "app_name" => "ChatOpenAI" })
    read.call { |f| f["type"] == "streaming_complete" }
    out["looks"] = looks
  RUBY

  # After the restart: the same tab connects again; the first view it is
  # sent is recorded, and a look is asked for.
  SECOND = <<~'RUBY'
    first = read.call { |f| f["type"] == "workbench" }
    out["first_view"] = { "chat" => first.dig("board", "chat_id"), "items" => first.dig("board", "items").to_a.size,
                          "initial" => first["initial"] }
    say.call({ "message" => "look", "app_name" => "ChatOpenAI" })
    read.call { |f| f["type"] == "streaming_complete" }
    out["looks"] = looks
  RUBY

  def script(steps)
    HEADER + DRIVE.sub("STEPS", steps)
  end

  before(:all) do
    @home = Dir.mktmpdir("restart-home")
    FileUtils.mkdir_p(File.join(@home, "monadic", "data"))
    File.write(File.join(@home, "monadic", "data", "notes.txt"), "one\ntwo\nthree\n")
    @before, = run_app_probe(script(FIRST), home: @home)
    @after, = run_app_probe(script(SECOND), home: @home)
  end

  after(:all) { FileUtils.rm_rf(@home) if @home }

  it "runs every step, and looks at the file before the restart" do
    expect(@before["stopped_at"]).to be_nil
    expect(@after["stopped_at"]).to be_nil
    expect(@before["looks"].map { |l| l["result"] }).to eq(["looked"])
  end

  it "tells the tab, first thing after the restart, that its chat's work screen is empty" do
    expect(@after["first_view"]["chat"]).not_to eq(@before["board_chat"])
    expect(@after["first_view"]).to include("items" => 0, "initial" => true)
  end

  it "finds nothing to look at, as the page then shows" do
    look = @after["looks"].last
    expect(look["caller_chat"]).to eq(@after["first_view"]["chat"])
    expect(look["result"]).to include("nothing is shown in the work screen")
  end
end
