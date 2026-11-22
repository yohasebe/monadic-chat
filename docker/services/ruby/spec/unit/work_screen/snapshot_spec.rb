# frozen_string_literal: true

require_relative "../../spec_helper"
require "base64"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/work_screen/snapshot"

# A picture of a chat's browser for a look, through a CDP connection of
# its own that the test answers for.
RSpec.describe Monadic::WorkScreen::Snapshot do
  let(:snapshot) { described_class }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:view) { MonadicSharedTools::BrowserOwner::View.new(chat, epoch, "inst-1", "sess-1", "W1") }
  let(:binding) { Monadic::WorkScreen::BrowserBinding.new("tab-1", 1, chat, epoch, "inst-1", "sess-1", "W1") }
  let(:metrics) do
    { "cssVisualViewport" => { "pageX" => 0, "pageY" => 120, "clientWidth" => 1280, "clientHeight" => 800 },
      "contentSize" => { "width" => 2560 }, "cssContentSize" => { "width" => 1280 } }
  end

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  # A CDP connection that answers as the browser would; replies can be
  # replaced (a value, or a lambda run when the command comes).
  class FakeBrowserCdp
    attr_reader :commands, :closed_with, :url, :limit

    def initialize(url, limit, replies)
      @url = url
      @limit = limit
      @replies = replies
      @commands = []
      @closed_with = nil
    end

    def command(method, params = {}, session_id: nil, timeout: 10)
      raise Monadic::WorkScreen::Cdp::Error, "closed" if @closed_with

      @commands << [method, params, session_id, timeout]
      reply = @replies.fetch(method, {})
      reply.respond_to?(:call) ? reply.call : reply
    end

    def close(limit:)
      @closed_with = limit
    end
  end

  let(:replies) do
    { "Target.attachToTarget" => { "sessionId" => "S1" },
      "Target.getTargetInfo" => { "targetInfo" => { "url" => "https://example.com/a?q=1", "title" => "Example" } },
      "Page.getLayoutMetrics" => metrics,
      "Page.captureScreenshot" => { "data" => Base64.strict_encode64(png(2048, 1280)) } }
  end
  let(:cdps) { [] }
  let(:connector) { ->(url, limit, _close_by) { FakeBrowserCdp.new(url, limit, replies).tap { |c| cdps << c } } }

  def soon(seconds = 30)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  end

  def take(deadline: soon)
    snapshot.take(binding, deadline: deadline, connector: connector)
  end

  def failure
    take
    nil
  rescue described_class::Failed => e
    e.reason
  end

  before do
    allow(WebSocketHelper).to receive(:live_generation).with("tab-1").and_return(1)
    allow(WebSocketHelper).to receive(:live_session).with("tab-1").and_return({ chat_id: chat })
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view)
  end

  it "attaches to the window on a connection of its own, takes the viewport within the limits, and lets go" do
    shot = take
    cdp = cdps.first
    expect(cdp.url).to eq("ws://selenium_service:4444/session/sess-1/se/cdp")
    expect(cdp.commands.map(&:first)).to eq(%w[Target.attachToTarget Target.getTargetInfo Page.getLayoutMetrics
                                                Page.captureScreenshot Target.detachFromTarget])
    expect(cdp.commands.first[1]).to eq({ targetId: "W1", flatten: true })
    params = cdp.commands[3][1]
    expect(params[:format]).to eq("png")
    expect(params[:captureBeyondViewport]).to be(false)
    # 1280 × 800 CSS pixels at 2 device pixels each: 2560 × 1600, made 2048 wide.
    expect(params[:clip]).to eq({ x: 0, y: 120, width: 1280, height: 800, scale: 0.8 })
    expect(cdp.commands.last[1]).to eq({ sessionId: "S1" })
    expect(cdp.closed_with).to be > 0
    expect(shot).to include(url: "https://example.com/a?q=1", title: "Example")
    expect(shot[:crop]).to eq({ "x" => 0, "y" => 120, "width" => 1280, "height" => 800, "sent_width" => 2048,
                                "sent_height" => 1280 })
    expect(snapshot.running).to eq(0)
  end

  it "never asks for the screencast the work screen's stream uses" do
    take
    expect(cdps.first.commands.map(&:first).grep(/Screencast/)).to be_empty
  end

  it "keeps a very tall or very wide viewport within the pixels allowed" do
    metrics["cssVisualViewport"].merge!("clientWidth" => 400, "clientHeight" => 20_000)
    replies["Page.captureScreenshot"] = { "data" => Base64.strict_encode64(png(40, 2000)) }
    take
    scale = cdps.first.commands[3][1][:clip][:scale]
    expect(20_000 * 2 * scale).to be <= described_class::MAX_SIDE
  end

  {
    "no viewport" => ->(m) { m.delete("cssVisualViewport") },
    "a width that is not a number" => ->(m) { m["cssVisualViewport"]["clientWidth"] = "1280" },
    "no height" => ->(m) { m["cssVisualViewport"]["clientHeight"] = 0 },
    "a position that is not finite" => ->(m) { m["cssVisualViewport"]["pageY"] = Float::NAN }
  }.each do |what, change|
    it "takes nothing for a viewport with #{what}" do
      change.call(metrics)
      expect(failure).to eq("browser_unavailable")
      expect(cdps.first.commands.map(&:first)).not_to include("Page.captureScreenshot")
      expect(cdps.first.closed_with).not_to be_nil
    end
  end

  it "refuses a picture larger than asked for, or too large to send, and one that is not a PNG" do
    replies["Page.captureScreenshot"] = { "data" => Base64.strict_encode64(png(2049, 10)) }
    expect(failure).to eq("too_large")
    replies["Page.captureScreenshot"] = { "data" => Base64.strict_encode64(png(8193, 10)) }
    expect(failure).to eq("too_large")
    replies["Page.captureScreenshot"] = { "data" => "A" * (described_class::MAX_BASE64 + 4) }
    expect(failure).to eq("too_large")
    replies["Page.captureScreenshot"] = { "data" => "not base64!" }
    expect(failure).to eq("browser_unavailable")
    replies["Page.captureScreenshot"] = { "data" => 5 }
    expect(failure).to eq("browser_unavailable")
  end

  it "takes nothing when the binding no longer holds, before attaching, once attached or once taken" do
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view.dup.tap { |v| v.window = "W2" })
    expect(failure).to eq("selection_changed")
    expect(cdps).to be_empty
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view)
    replies["Target.attachToTarget"] = lambda do
      allow(WebSocketHelper).to receive(:live_generation).with("tab-1").and_return(2)
      { "sessionId" => "S1" }
    end
    expect(failure).to eq("selection_changed")
    expect(cdps.last.commands.map(&:first)).to eq(%w[Target.attachToTarget Target.detachFromTarget])
    allow(WebSocketHelper).to receive(:live_generation).with("tab-1").and_return(1)
    replies["Target.attachToTarget"] = { "sessionId" => "S1" }
    replies["Page.captureScreenshot"] = lambda do
      Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS[chat] += 1 }
      { "data" => Base64.strict_encode64(png(10, 10)) }
    end
    expect(failure).to eq("selection_changed")
    expect(cdps.last.closed_with).not_to be_nil
  end

  it "says a command that ran out of time apart from one that failed, and lets go either way" do
    replies["Page.getLayoutMetrics"] = -> { raise Monadic::WorkScreen::Cdp::Error, "refused" }
    expect(failure).to eq("browser_unavailable")
    expect(cdps.last.closed_with).not_to be_nil
    expect { snapshot.take(binding, deadline: soon(described_class::CLEANUP - 1), connector: connector) }
      .to raise_error(described_class::Failed) { |e| expect(e.reason).to eq("capture_timeout") }
    expect(snapshot.running).to eq(0)
  end

  it "says a command that did not answer in its time ran out of time" do
    replies["Page.getLayoutMetrics"] = lambda do
      sleep 0.35
      raise Monadic::WorkScreen::Cdp::Timeout, "Page.getLayoutMetrics timed out"
    end
    expect { snapshot.take(binding, deadline: soon(described_class::CLEANUP + 0.3), connector: connector) }
      .to raise_error(described_class::Failed) { |e| expect(e.reason).to eq("capture_timeout") }
    expect(cdps.last.commands.find { |c| c.first == "Page.getLayoutMetrics" }.last).to be <= 0.3
    expect(cdps.last.closed_with).not_to be_nil
  end

  it "says why the browser could not be reached" do
    failing = ->(error) { ->(_url, _limit, _close_by) { raise error } }
    { Monadic::WorkScreen::Cdp::Timeout.new("connect timed out") => "capture_timeout",
      Monadic::WorkScreen::Cdp::Error.new("connect failed (Errno::ECONNREFUSED)") => "browser_unavailable" }
      .each do |error, reason|
        expect { snapshot.take(binding, deadline: soon, connector: failing.call(error)) }
          .to raise_error(described_class::Failed) { |e| expect(e.reason).to eq(reason) }
      end
    expect(snapshot.running).to eq(0)
  end

  it "does not detach and closes at once when no time is left for cleaning up" do
    cdp = FakeBrowserCdp.new("ws://x", 1, replies)
    snapshot.cleanup(cdp, "S1", soon(-1))
    expect(cdp.commands).to be_empty
    expect(cdp.closed_with).to be <= 0
  end

  it "closes even when detaching does not answer" do
    replies["Target.detachFromTarget"] = -> { raise Monadic::WorkScreen::Cdp::Timeout, "detach timed out" }
    take
    expect(cdps.last.closed_with).not_to be_nil
  end

  it "takes at most two pictures at once" do
    gate = Queue.new
    started = Queue.new
    replies["Page.captureScreenshot"] = lambda do
      started << true
      gate.pop
      { "data" => Base64.strict_encode64(png(10, 10)) }
    end
    two = Array.new(2) { Thread.new { take } }
    2.times { started.pop(timeout: 5) }
    expect(failure).to eq("busy")
    2.times { gate << true }
    two.each { |t| t.join(5) }
    expect(snapshot.running).to eq(0)
  end

  it "lets its slot go when the reply is stopped while it waits" do
    started = Queue.new
    replies["Page.captureScreenshot"] = lambda do
      started << true
      sleep
    end
    taking = Thread.new { take }
    started.pop(timeout: 5)
    taking.kill
    taking.join(5)
    expect(taking).not_to be_alive
    expect(snapshot.running).to eq(0)
  end
end

# The same, through the CDP connection itself on a WebSocket transport that
# acts as the browser: a reply stopped on its way, the reply's thread
# stopped meanwhile, a close that does not finish.
RSpec.describe Monadic::WorkScreen::Snapshot, "through the CDP connection" do
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:view) { MonadicSharedTools::BrowserOwner::View.new(chat, epoch, "inst-1", "sess-1", "W1") }
  let(:binding) { Monadic::WorkScreen::BrowserBinding.new("tab-1", 1, chat, epoch, "inst-1", "sess-1", "W1") }

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  # The browser: each command is answered unless held; held ones are told
  # (asked); the framer is what an abrupt close closes.
  class BrowserTransport
    Framer = Struct.new(:closed) do
      def close = (self.closed = true)
    end

    attr_reader :asked, :closes, :framer
    attr_accessor :held, :close_hangs

    def initialize(replies)
      @replies = replies
      @inbox = Async::Queue.new
      @asked = Queue.new
      @held = []
      @closes = 0
      @close_hangs = false
      @framer = Framer.new(false)
    end

    def read = @inbox.dequeue

    def write(message)
      data = JSON.parse(message.to_str)
      @asked << data["method"]
      return if @held.include?(data["method"])

      @inbox.enqueue(JSON.generate({ id: data["id"], result: @replies.fetch(data["method"], {}) }))
    end

    def flush = nil

    def close
      @closes += 1
      sleep if @close_hangs
      @inbox.enqueue(nil)
    end
  end

  let(:transport) do
    BrowserTransport.new(
      "Target.attachToTarget" => { "sessionId" => "S1" },
      "Target.getTargetInfo" => { "targetInfo" => { "url" => "https://example.com/", "title" => "E" } },
      "Page.getLayoutMetrics" => { "cssVisualViewport" => { "pageX" => 0, "pageY" => 0, "clientWidth" => 100,
                                                             "clientHeight" => 50 } },
      "Page.captureScreenshot" => { "data" => Base64.strict_encode64(png(100, 50)) }
    )
  end

  before do
    allow(WebSocketHelper).to receive(:live_generation).with("tab-1").and_return(1)
    allow(WebSocketHelper).to receive(:live_session).with("tab-1").and_return({ chat_id: chat })
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view)
    allow(Async::WebSocket::Client).to receive(:connect).and_return(transport)
  end

  def soon(seconds = 30)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  end

  def take(deadline = soon)
    described_class.take(binding, deadline: deadline)
  end

  it "takes a picture and closes" do
    shot = take
    expect(shot[:crop]).to include("sent_width" => 100, "sent_height" => 50)
    expect(transport.closes).to eq(1)
    expect(described_class.running).to eq(0)
  end

  %w[Target.attachToTarget Page.captureScreenshot Target.detachFromTarget].each do |waiting|
    it "lets go of the connection and its slot when the reply is stopped while #{waiting} waits" do
      transport.held << waiting
      taking = Thread.new { take }
      # Until the held command was sent (or the browser asked nothing more).
      loop do
        method = transport.asked.pop(timeout: 3)
        break if method.nil? || method == waiting
      end
      taking.kill
      taking.join(3)
      expect(taking).not_to be_alive
      expect(transport.closes + (transport.framer.closed ? 1 : 0)).to be >= 1
      expect(described_class.running).to eq(0)
    end
  end

  it "says a connection that does not open in time ran out of time, and lets its slot go" do
    allow(Async::WebSocket::Client).to receive(:connect) { sleep }
    stub_const("Monadic::WorkScreen::Snapshot::CLEANUP", 0.2)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { take(soon(0.6)) }.to raise_error(described_class::Failed) { |e| expect(e.reason).to eq("capture_timeout") }
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.5
    expect(described_class.running).to eq(0)
  end

end

# The CDP connection's close on the WebSocket gem's own connection, over a
# socket whose other end reads nothing (what is written is never flushed).
RSpec.describe Monadic::WorkScreen::Cdp, "closing a connection that cannot be written to" do
  require "socket"
  require "io/stream"
  require "protocol/websocket"
  require "async/websocket/client"

  # The HTTP client the decorator owns: it is closed after the connection.
  class StubClient
    attr_reader :closed

    def close = (@closed = true)
  end

  let(:pair) { UNIXSocket.pair }
  let(:client) { StubClient.new }
  let(:connection) do
    framer = Protocol::WebSocket::Framer.new(IO::Stream::Buffered.wrap(pair.first))
    Async::WebSocket::Client::ClientCloseDecorator.new(client, Async::WebSocket::Connection.new(framer))
  end

  after { pair.each { |io| io.close unless io.closed? } }

  # Fills the socket so that the next flush waits for the other end.
  def fill
    loop { pair.first.write_nonblock("x" * 65_536) }
  rescue IO::WaitWritable
    nil
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  before { allow(Async::WebSocket::Client).to receive(:connect).and_return(connection) }

  it "closes the socket at once, then the client, when no time is left for the closing handshake" do
    fill
    started = clock
    Sync do
      cdp = described_class.open("ws://selenium_service:4444/session/x/se/cdp")
      cdp.close(limit: 0)
    end
    expect(clock - started).to be < 1
    expect(pair.first).to be_closed
    expect(client.closed).to be(true)
  end

  it "closes no later than close_by when a command cannot be sent" do
    fill
    started = clock
    Sync do
      cdp = described_class.open("ws://selenium_service:4444/session/x/se/cdp", close_by: clock + 0.3)
      expect { cdp.command("Target.detachFromTarget", { sessionId: "S1" }, timeout: 0.2) }
        .to raise_error(described_class::Error)
      expect(cdp).to be_closed
    end
    expect(clock - started).to be < 1
    expect(pair.first).to be_closed
  end
end
