# frozen_string_literal: true

require "spec_helper"
require "json"

# One answer runs at a time on a connection (a tab that reconnects gets a
# new connection; this does not cover two at once). The app runs in a child
# process with a home of its own; the provider call is held open, so a
# second send arrives while the first answer runs, and Cancel and a closed
# connection can be seen to stop it.
RSpec.describe "WebSocket sends while an answer runs" do
  include AppProbe

  def probe_script
    <<~'RUBY'
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

    # The provider call: it says which request it runs under and what the
    # chat holds, then waits until it is let go (or the thread is stopped).
    entered = Thread::Queue.new
    release = Thread::Queue.new
    ended = Thread::Queue.new
    calls = []
    APPS["ChatOpenAI"].define_singleton_method(:api_request) do |_role, session, &_block|
      users = session[:messages].select { |m| m["role"] == "user" }
      calls << { "request_id" => Monadic::Workspace::RequestContext.current&.request_id,
                 "user_texts" => users.map { |m| m["text"] },
                 "last_request_id" => users.last&.dig("request_id") }
      entered << true
      begin
        release.pop
      ensure
        ended << true
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
      # A step that times out ends the probe with what it saw so far.
      begin
        ws = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{base}/?tab_id=tab-a"), headers: [["origin", base]])
        task.with_timeout(10) { ws.read }
        say = lambda do |obj|
          ws.write(obj.to_json)
          ws.flush
        end
        # The next frame of a type; a closed connection or the time limit
        # ends the probe (only a frame that is not JSON is skipped).
        frame_of = lambda do |type|
          task.with_timeout(10) do
            loop do
              raw = ws.read
              raise EOFError, "connection closed" if raw.nil?

              frame = begin
                JSON.parse(raw.to_str)
              rescue JSON::ParserError
                {}
              end
              break frame if frame["type"] == type
            end
          end
        end
        waited = ->(queue) { task.with_timeout(10) { queue.pop } && true }

        say.call({ "message" => "first", "app_name" => "ChatOpenAI" })
        out["first_started"] = waited.call(entered)

        say.call({ "message" => "again", "app_name" => "ChatOpenAI" })
        error = frame_of.call("error")
        out["second"] = { "busy" => error["busy"], "not_accepted" => error["not_accepted"], "calls" => calls.size }

        say.call({ "message" => "CANCEL" })
        out["cancel_stops_it"] = waited.call(ended)

        say.call({ "message" => "third", "app_name" => "ChatOpenAI" })
        out["after_cancel_started"] = waited.call(entered)

        # This answer finishes as usual: the page asks for it once streaming
        # is complete, and the next send is accepted.
        release << true
        out["third_ended"] = waited.call(ended)
        frame_of.call("streaming_complete")
        say.call({ "message" => "HTML" })
        frame_of.call("html")
        say.call({ "message" => "fourth", "app_name" => "ChatOpenAI" })
        out["after_finish_started"] = waited.call(entered)
        out["calls"] = calls

        ws.close
        out["close_stops_it"] = waited.call(ended)
      rescue StandardError => e
        out["stopped_at"] = e.class.name
      ensure
        server.stop
      end
    end
    STDOUT.puts "PROBE #{out.to_json}"
    STDOUT.flush
    exit!(0)
    RUBY
  end

  before(:all) { @result, @group_left = run_app_probe(probe_script) }

  it "runs every step" do
    expect(@result["stopped_at"]).to be_nil
    expect(@result["first_started"]).to be(true)
  end

  it "leaves no process behind" do
    expect(@group_left).to be(false)
  end

  it "does not accept a send while the answer runs, and says so as busy" do
    expect(@result["second"]).to eq("busy" => true, "not_accepted" => true, "calls" => 1)
  end

  it "stops the running answer on Cancel, and accepts the next send" do
    expect(@result["cancel_stops_it"]).to be(true)
    expect(@result["after_cancel_started"]).to be(true)
  end

  it "accepts the next send once an answer has finished as usual" do
    expect(@result["third_ended"]).to be(true)
    expect(@result["after_finish_started"]).to be(true)
  end

  it "records only the sends it accepted, each under a request of its own" do
    calls = @result["calls"]
    expect(calls.size).to eq(3)
    expect(calls.last["user_texts"]).to eq(%w[first third fourth])
    ids = calls.map { |c| c["request_id"] }
    expect(ids).to all(start_with("q_"))
    expect(ids.uniq.size).to eq(3)
    expect(calls.map { |c| c["last_request_id"] }).to eq(ids)
  end

  it "stops the running answer when the connection closes" do
    expect(@result["close_stops_it"]).to be(true)
  end
end
