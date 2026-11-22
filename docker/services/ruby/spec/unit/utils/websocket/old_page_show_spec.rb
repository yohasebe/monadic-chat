# frozen_string_literal: true

require "spec_helper"
require "json"

# A page from before "Show to the assistant" was taken out may still send
# its press (WORKBENCH_SHOW), its removal (WORKBENCH_SHOW_REMOVE) and what
# it showed with a message (workbench_shown). The press and the removal are
# dropped: never taken as a message, and they neither stop nor wait on an
# answer running. A message with workbench_shown is taken as the message
# alone. The app runs in a child process with a home of its own.
RSpec.describe "Sends of a page from before Show was taken out" do
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

    entered = Thread::Queue.new
    release = Thread::Queue.new
    ended = Thread::Queue.new
    calls = []
    APPS["ChatOpenAI"].define_singleton_method(:api_request) do |_role, session, &_block|
      users = session[:messages].select { |m| m["role"] == "user" }
      calls << { "user_texts" => users.map { |m| m["text"] },
                 "kept_keys" => users.flat_map(&:keys).uniq,
                 "parameters_has_shown" => session[:parameters].key?("workbench_shown") }
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
      ws = nil
      begin
        ws = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{base}/?tab_id=tab-a"), headers: [["origin", base]])
        task.with_timeout(10) { ws.read }
        frames = []
        reader = task.async do
          loop do
            raw = ws.read
            break if raw.nil?

            frames << (JSON.parse(raw.to_str) rescue {})
          end
        end
        say = ->(obj) { ws.write(obj.to_json); ws.flush }
        waited = ->(queue) { task.with_timeout(10) { queue.pop } && true }
        # Whether queue gets something within seconds.
        within = lambda do |queue, seconds|
          task.with_timeout(seconds) { queue.pop }
          true
        rescue Async::TimeoutError
          false
        end
        frame_of = lambda do |type|
          task.with_timeout(10) do
            loop do
              found = frames.find { |f| f["type"] == type }
              if found
                frames.delete(found)
                break found
              end
              task.sleep(0.05)
            end
          end
        end
        old_sends = lambda do
          say.call({ "message" => "WORKBENCH_SHOW", "op_id" => "op-1", "item_id" => "i_x", "version" => "v", "serial" => 1 })
          say.call({ "message" => "WORKBENCH_SHOW_REMOVE", "op_id" => "op-1" })
        end

        # While an answer runs.
        say.call({ "message" => "first", "app_name" => "ChatOpenAI" })
        out["first_started"] = waited.call(entered)
        old_sends.call
        task.sleep(0.5)
        out["while_running"] = { "ended" => within.call(ended, 0.5), "errors" => frames.count { |f| f["type"] == "error" },
                                 "calls" => calls.size }
        release << true
        waited.call(ended)
        frame_of.call("streaming_complete")
        say.call({ "message" => "HTML" })
        frame_of.call("html")

        # With nothing running.
        old_sends.call
        out["idle_started"] = within.call(entered, 1)
        out["idle_errors"] = frames.count { |f| f["type"] == "error" }

        # A message with what the old page showed.
        say.call({ "message" => "second", "app_name" => "ChatOpenAI", "workbench_shown" => ["snap-1", { "x" => 1 }] })
        out["second_started"] = waited.call(entered)
        release << true
        waited.call(ended)
        out["calls"] = calls
        reader.stop
      rescue StandardError => e
        out["stopped_at"] = "#{e.class}: #{e.message}"
      ensure
        ws&.close
        task.sleep(0.3)
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

  it "leaves the answer running as it is, and says nothing of the old sends" do
    expect(@result["while_running"]).to eq("ended" => false, "errors" => 0, "calls" => 1)
  end

  it "starts no answer for them when nothing runs" do
    expect(@result["idle_started"]).to be(false)
    expect(@result["idle_errors"]).to eq(0)
  end

  it "takes a message sent with what the old page showed as the message alone" do
    expect(@result["second_started"]).to be(true)
    last = @result["calls"].last
    expect(last["user_texts"]).to eq(%w[first second])
    expect(last["kept_keys"]).not_to include("workbench_shown")
    expect(last["parameters_has_shown"]).to be(false)
  end
end
