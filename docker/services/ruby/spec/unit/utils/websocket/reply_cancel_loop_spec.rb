# frozen_string_literal: true

require "spec_helper"
require "json"

# Stopping an answer by HTTP while the connection's own loop waits for it
# (the page asked for its HTML), with the app served for real in a child
# process. The provider call is held open; when it is stopped, the end of
# the answer can be held too, past the time a stop is noted at.
RSpec.describe "Stopping an answer while the connection waits for it" do
  include AppProbe

  def probe_script
    <<~'RUBY'
    require "rack"
    require "json"
    require "socket"
    require "async"
    require "async/http/client"
    require "async/http/endpoint"
    require "async/http/server"
    require "async/websocket/client"
    require "protocol/rack"
    app, = Rack::Builder.parse_file("config.ru")
    out = {}

    # What is noted, and a stop noted at once rather than after 15 seconds.
    notes = []
    Monadic::Utils::ExtraLogger.define_singleton_method(:log) do |message = nil, &block|
      notes << (block ? block.call : message).to_s
      nil
    end
    WebSocketHelper.send(:remove_const, :REPLY_STOP_WAIT)
    WebSocketHelper.const_set(:REPLY_STOP_WAIT, 0.3)

    # The provider call waits until it is let go; one that is stopped says
    # so, and when its end is held (hold_next) the answer ends only once
    # let go.
    entered = Thread::Queue.new
    release = Thread::Queue.new
    ended = Thread::Queue.new
    hold = Thread::Queue.new
    hold_next = [false]
    calls = []
    APPS["ChatOpenAI"].define_singleton_method(:api_request) do |_role, session, &_block|
      users = session[:messages].select { |m| m["role"] == "user" }
      calls << { "user_texts" => users.map { |m| m["text"] },
                 "assistant_texts" => session[:messages].select { |m| m["role"] == "assistant" }.map { |m| m["text"] } }
      held = hold_next[0]
      hold_next[0] = false
      entered << true
      begin
        release.pop
      ensure
        ended << true
        hold.pop if held
      end
      [{ "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }] }]
    end

    port = (probe = TCPServer.new("127.0.0.1", 0)).addr[1]
    probe.close
    base = "http://127.0.0.1:#{port}"
    endpoint = Async::HTTP::Endpoint.parse(base)
    Async do |task|
      server = task.async { Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), endpoint).run }
      task.sleep(0.2)
      client = Async::HTTP::Client.new(endpoint)
      # A step that times out ends the probe with what it saw so far.
      begin
        connect = lambda do |tab|
          ws = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{base}/?tab_id=#{tab}"), headers: [["origin", base]])
          task.with_timeout(10) { ws.read }
          ws
        end
        say = lambda do |ws, obj|
          ws.write(obj.to_json)
          ws.flush
        end
        # The next frame the block takes; a closed connection or the time
        # limit ends the probe.
        frame = lambda do |ws, &wanted|
          task.with_timeout(10) do
            loop do
              raw = ws.read
              raise EOFError, "connection closed" if raw.nil?

              parsed = begin
                JSON.parse(raw.to_str)
              rescue JSON::ParserError
                {}
              end
              break parsed if wanted.call(parsed)
            end
          end
        end
        waited = ->(queue) { task.with_timeout(10) { queue.pop } && true }
        stop = lambda do |token|
          response = task.with_timeout(10) { client.post("/reply/cancel/#{token}", [["sec-fetch-site", "same-origin"]]) }
          response.status.tap { response.close }
        end

        # The page asks for the HTML while the answer runs: the loop waits.
        a = connect.call("tab-a")
        hold_next[0] = true
        say.call(a, { "message" => "first", "app_name" => "ChatOpenAI" })
        out["first_started"] = waited.call(entered)
        token = frame.call(a) { |f| f["type"] == "reply_cancel" }["token"]
        say.call(a, { "message" => "HTML" })
        task.sleep(0.1)

        # Stopped by HTTP, with its end held: the request is answered, the
        # provider call is stopped, and another connection is served.
        out["http_status"] = stop.call(token)
        out["call_stopped"] = waited.call(ended)
        b = connect.call("tab-b")
        out["other_connection_served"] = true

        # What the page sends next waits until the answer ended, past the
        # time a stop is noted at.
        say.call(a, { "message" => "CANCEL" })
        say.call(a, { "message" => "RESET" })
        say.call(a, { "message" => "second", "app_name" => "ChatOpenAI" })
        task.sleep(0.8)
        out["next_waited"] = entered.empty?
        out["noted_while_held"] = notes.count { |n| n.include?("is still stopping after") }

        hold << true
        out["first_outcome"] = frame.call(a) { |f| f["type"] == "reply_state" && f["state"] == "finished" }["outcome"]
        out["next_started"] = waited.call(entered)
        out["noted_when_ended"] = notes.count { |n| n.include?("ended after a stop that went past") }
        out["second_call"] = calls.last
        out["token_gone"] = stop.call(token)

        a.close
        out["close_stops_second"] = waited.call(ended)
        b.close

        # A reload while the old connection waits for its answer to end:
        # the new connection is served, and what the old one does once it
        # ends does not undo it.
        hold_next[0] = true
        c = connect.call("tab-c")
        say.call(c, { "message" => "before reload", "app_name" => "ChatOpenAI" })
        waited.call(entered)
        c.close
        waited.call(ended)
        d = connect.call("tab-c")
        say.call(d, { "message" => "after reload", "app_name" => "ChatOpenAI" })
        out["reload_started"] = waited.call(entered)
        hold << true
        task.sleep(0.3)
        release << true
        waited.call(ended)
        frame.call(d) { |f| f["type"] == "streaming_complete" }
        say.call(d, { "message" => "HTML" })
        frame.call(d) { |f| f["type"] == "html" }
        say.call(d, { "message" => "next", "app_name" => "ChatOpenAI" })
        out["after_reload_started"] = waited.call(entered)
        out["after_reload_call"] = calls.last
        d.close
        waited.call(ended)
      rescue StandardError => e
        out["stopped_at"] = "#{e.class}: #{e.message}"
      ensure
        client.close
        server.stop
      end
    end
    STDOUT.puts "PROBE #{out.to_json}"
    STDOUT.flush
    exit!(0)
    RUBY
  end

  before(:all) { @result, @group_left = run_app_probe(probe_script) }

  it "runs every step and leaves no process behind" do
    expect(@result["stopped_at"]).to be_nil
    expect(@result["first_started"]).to be(true)
    expect(@group_left).to be(false)
  end

  it "stops the answer by HTTP while the connection waits for its HTML, and serves another connection meanwhile" do
    expect(@result["http_status"]).to eq(204)
    expect(@result["call_stopped"]).to be(true)
    expect(@result["other_connection_served"]).to be(true)
  end

  it "takes up what the page sent next only once the answer ended, noting the long stop once" do
    expect(@result["next_waited"]).to be(true)
    expect(@result["noted_while_held"]).to eq(1)
    expect(@result["first_outcome"]).to eq("no_reply")
    expect(@result["next_started"]).to be(true)
    expect(@result["noted_when_ended"]).to eq(1)
  end

  it "records nothing for the stopped answer, and the Reset sent after it holds" do
    expect(@result["second_call"]).to eq("user_texts" => ["second"], "assistant_texts" => [])
  end

  it "does not take the token once its answer ended" do
    expect(@result["token_gone"]).to eq(404)
  end

  it "stops the next answer when the connection closes" do
    expect(@result["close_stops_second"]).to be(true)
  end

  it "serves a reload while the old connection waits, and the old one's end does not undo it" do
    expect(@result["reload_started"]).to be(true)
    expect(@result["after_reload_started"]).to be(true)
    expect(@result["after_reload_call"]["user_texts"].last(2)).to eq(["after reload", "next"])
    expect(@result["after_reload_call"]["assistant_texts"].last).to eq("ok")
  end
end
