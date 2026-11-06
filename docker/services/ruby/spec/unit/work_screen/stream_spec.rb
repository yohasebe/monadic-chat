# frozen_string_literal: true

require_relative "../../spec_helper"
require "async"
require "async/queue"
require_relative "../../../lib/monadic/utils/websocket/connection_manager"
require_relative "../../../lib/monadic/work_screen"

# The work screen socket, with a fake page socket and a fake CDP connection.
RSpec.describe Monadic::WorkScreen::Stream do
  # The page's side of the socket: what the test sends, and what it got.
  # A page that stops reading (stall!) leaves every write waiting.
  class FakeSocket
    attr_reader :sent

    def initialize
      @inbox = Async::Queue.new
      @sent = []
      @stalled = false
      @closed = false
    end

    def say(message) = @inbox.enqueue(message.is_a?(String) ? message : JSON.generate(message))
    def hang_up = @inbox.enqueue(nil)
    def read = @inbox.dequeue
    def stall! = (@stalled = true)
    def unstall! = (@stalled = false)
    def closed? = @closed

    def write(text)
      sleep 0.05 while @stalled
      @sent << JSON.parse(text)
    end

    def close
      @closed = true
      hang_up
    end

    def of(type) = @sent.select { |m| m['type'] == type }
  end

  # A browser's CDP connection: replies to the commands the stream uses,
  # and the frames and events the test pushes. on_close runs as it closes
  # (a stream stopping waits for it).
  class FakeCdp
    attr_reader :commands, :notices, :url
    attr_accessor :on_close

    def initialize(url)
      @url = url
      @commands = []
      @notices = []
      @events = Async::Queue.new
      @frame = nil
      @closed = false
    end

    def command(method, params = {}, session_id: nil, timeout: 10)
      raise Monadic::WorkScreen::Cdp::Error, 'closed' if @closed

      @commands << [method, params, session_id]
      case method
      when 'Target.attachToTarget' then { 'sessionId' => "S-#{params[:targetId]}" }
      when 'Page.getLayoutMetrics'
        { 'cssVisualViewport' => { 'pageX' => 0, 'pageY' => 0, 'clientWidth' => 1280, 'clientHeight' => 761 },
          'contentSize' => { 'width' => 2560 }, 'cssContentSize' => { 'width' => 1280 } }
      when 'Page.captureScreenshot' then { 'data' => 'FIRST' }
      else {}
      end
    end

    def notify(method, params = {}, session_id: nil) = @notices << [method, params, session_id]

    # As Cdp does: the newest frame is kept, and :frame tells it is there.
    def frame(data, session = 'S-W1')
      fresh = @frame.nil?
      @frame = { session: session, data: data }
      @events.enqueue(:frame) if fresh
    end

    def event(message) = @events.enqueue(message)

    def latest_frame
      frame = @frame
      @frame = nil
      frame
    end

    def next_event(timeout)
      Async::Task.current.with_timeout(timeout) { @events.dequeue }
    rescue Async::TimeoutError
      nil
    end

    def closed? = @closed

    def close
      on_close&.call
      @closed = true
    end
  end

  let(:owner) { MonadicSharedTools::BrowserOwner }
  let(:socket) { FakeSocket.new }
  let(:cdps) { [] }
  let(:session) { { chat_id: 'chat-1' } }

  before do
    owner.reset!
    Monadic::WorkScreen::Tokens.reset!
    described_class.reset!
    allow(owner).to receive(:observe).and_return({ sessions: [], max: 3 })
    allow(owner).to receive(:start_worker)
    allow(owner).to receive(:close_later)
    allow(Monadic::WorkScreen).to receive(:available?).and_return(true)
    WebSocketHelper.register_live_session('tab-1', session, 7)
    epoch = owner.epoch('chat-1')
    owner.begin_start('chat-1', epoch)
    owner.finish_start('chat-1', 'wd-1', epoch, window: 'W1')
  end

  after { WebSocketHelper.unregister_live_session('tab-1', 7) }

  def stream
    described_class.new(socket, connector: ->(url) { FakeCdp.new(url).tap { |c| cdps << c } })
  end

  def wait_until(limit = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    expect(yield).to be_truthy
  end

  # Runs the stream with a pass for tab-1, then the block, then hangs up.
  def watching(token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
    Sync do |task|
      runner = task.async { stream.run }
      begin
        socket.say(type: 'auth', token: token)
        yield
        socket.hang_up
        task.with_timeout(5) { runner.wait }
      ensure
        runner.stop
      end
    end
  end

  it 'sends nothing to a page without a pass' do
    Sync do |task|
      runner = task.async { stream.run }
      socket.say(type: 'subscribe', browser: 1)
      sleep 0.3
      runner.stop
    end
    expect(socket.sent).to be_empty
  end

  it 'refuses a pass issued on a connection that is no longer the tab\'s live one' do
    token = Monadic::WorkScreen::Tokens.issue('tab-1', 6)
    watching(token: token) { socket.say(type: 'subscribe', browser: 1); sleep 0.05 }
    expect(socket.sent).to be_empty
  end

  it 'takes a pass once' do
    token = Monadic::WorkScreen::Tokens.issue('tab-1', 7)
    expect(Monadic::WorkScreen::Tokens.redeem(token)).not_to be_nil
    expect(Monadic::WorkScreen::Tokens.redeem(token)).to be_nil
  end

  it 'shows the chat\'s browser: the page as it is first, then one frame at a time' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').size == 1 }
      expect(socket.of('state').last).to include('state' => 'live', 'browser' => 1)
      expect(socket.of('frame').first['data']).to eq('FIRST')
      expect(cdps.first.url).to eq('ws://selenium_service:4444/session/wd-1/se/cdp')

      cdps.first.frame('A')
      cdps.first.frame('B')
      sleep 0.3
      expect(socket.of('frame').size).to eq(1) # the first is not drawn yet

      first = socket.of('frame').first
      socket.say(type: 'frame-consumed', stream: first['stream'], n: first['n'])
      wait_until { socket.of('frame').size == 2 }
      expect(socket.of('frame').last['data']).to eq('B') # only the newest is kept
    end
  end

  it 'scales the first still to the screencast size' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
    end
    shot = cdps.first.commands.find { |c| c[0] == 'Page.captureScreenshot' }
    expect(shot[1][:clip][:scale]).to eq(0.5)
  end

  it 'ignores a consumed notice for another stream or frame' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').size == 1 }
      first = socket.of('frame').first
      cdps.first.frame('A')
      socket.say(type: 'frame-consumed', stream: first['stream'] + 1, n: first['n'])
      socket.say(type: 'frame-consumed', stream: first['stream'], n: first['n'] + 5)
      sleep 0.3
      expect(socket.of('frame').size).to eq(1)
    end
  end

  it 'ends when the chat is replaced (Reset)' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      Monadic::Workspace::Chats.replacing!(session)
      wait_until { socket.of('state').last['state'] == 'ended' }
      expect(socket.of('state').last['reason']).to eq('replaced')
      expect(cdps.first).to be_closed
    end
  end

  it 'ends when the browser closes' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      owner.release('chat-1', owner.epoch('chat-1'))
      wait_until { socket.of('state').last['state'] == 'ended' }
      expect(socket.of('state').last['reason']).to eq('browser_closed')
    end
  end

  it 'follows the window the tools act on, as a new stream' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      owner.note_window('chat-1', 'wd-1', 'W2')
      wait_until { cdps.size == 2 && socket.of('state').count { |s| s['state'] == 'live' } == 2 }
      expect(cdps.last.commands.first[1][:targetId]).to eq('W2')
      expect(socket.of('state').last['stream']).to eq(socket.of('state').first['stream'] + 1)
      expect(cdps.first).to be_closed
    end
  end

  it 'stops on unsubscribe and closes CDP' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      socket.say(type: 'unsubscribe')
      wait_until { socket.of('state').last['state'] == 'idle' }
      expect(cdps.first).to be_closed
    end
  end

  it 'waits when the chat has no browser' do
    owner.release('chat-1', owner.epoch('chat-1'))
    watching { socket.say(type: 'subscribe', browser: 1); wait_until { socket.of('state').any? } }
    expect(socket.of('state').last).to include('state' => 'waiting', 'reason' => 'no_browser')
    expect(cdps).to be_empty
  end

  it 'shows only the browser the page selected, not another browser of the chat' do
    epoch = owner.epoch('chat-1')
    owner.release('chat-1', epoch)
    owner.begin_start('chat-1', epoch)
    owner.finish_start('chat-1', 'wd-2', epoch, window: 'W2')
    watching { socket.say(type: 'subscribe', browser: 1); wait_until { socket.of('state').any? } }
    expect(socket.of('state').last).to include('state' => 'ended', 'reason' => 'browser_closed', 'browser' => 1)
    expect(cdps).to be_empty
  end

  it 'asks Selenium whether the browser is gone when its connection ends' do
    allow(owner).to receive(:confirm_gone_later)
    failing = described_class.new(socket, connector: ->(_url) { raise Monadic::WorkScreen::Cdp::Error, 'refused' })
    Sync do |task|
      runner = task.async { failing.run }
      socket.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('state').any? }
      runner.stop
    end
    expect(owner).to have_received(:confirm_gone_later).with('chat-1', 'wd-1')
  end

  it 'shows nothing where Selenium cannot be reached (development)' do
    allow(Monadic::WorkScreen).to receive(:available?).and_return(false)
    watching { socket.say(type: 'subscribe', browser: 1); wait_until { socket.of('state').any? } }
    expect(socket.of('state').last).to include('state' => 'ended', 'reason' => 'unavailable')
    expect(cdps).to be_empty
  end

  it "takes only the page's own messages, with their own fields" do
    check = ->(message) { stream.send(:valid?, message) }
    expect(check.call('type' => 'subscribe', 'browser' => 1)).to be(true)
    expect(check.call('type' => 'subscribe')).to be(false)
    expect(check.call('type' => 'subscribe', 'browser' => '1')).to be(false)
    expect(check.call('type' => 'frame-consumed', 'stream' => 1, 'n' => 2)).to be(true)
    expect(check.call('type' => 'subscribe', 'browser' => 1, 'url' => 'x')).to be(false)
    expect(check.call('type' => 'Runtime.evaluate')).to be(false)
    expect(check.call('type' => 'frame-consumed', 'stream' => '1', 'n' => 2)).to be(false)
    expect(check.call('type' => 'frame-consumed', 'stream' => -1, 'n' => 2)).to be(false)
    expect(check.call('type' => 'frame-consumed', 'stream' => 1)).to be(false)
    expect(check.call('type' => 'auth', 'token' => 1)).to be(false)
    expect(check.call('type' => 'auth')).to be(false)
  end

  it 'ends on a message that is not one of the page\'s, before anything is sent' do
    ['{"type":"subscribe","url":"x"}', 'not json', 'x' * 2000].each do |bad|
      socket2 = FakeSocket.new
      Sync do |task|
        runner = task.async { described_class.new(socket2, connector: ->(url) { FakeCdp.new(url) }).run }
        socket2.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
        socket2.say(bad)
        sleep 0.3
        runner.stop # a stream let through would otherwise run on
      end
      expect(socket2.sent).to be_empty
    end
  end

  it 'does not keep the browser from closing when idle, just by watching' do
    allow(owner).to receive(:close).and_return(true)
    # The browser was last used at opened; watching happens IDLE_LIMIT later.
    opened = owner.clock
    owner.reset!
    now = opened
    allow(owner).to receive(:clock) { now }
    epoch = owner.epoch('chat-1')
    owner.begin_start('chat-1', epoch)
    owner.finish_start('chat-1', 'wd-1', epoch, window: 'W1')
    now = opened + MonadicSharedTools::BrowserOwner::IDLE_LIMIT + 1
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      owner.reap(now: now)
      wait_until { socket.of('state').last['state'] == 'ended' }
    end
    expect(owner).to have_received(:close).with('wd-1')
  end

  it 'does not move to another browser that started while it changed windows' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      # While the old window's connection closes, the chat starts a new browser.
      cdps.first.on_close = lambda do
        epoch = owner.epoch('chat-1')
        owner.release('chat-1', epoch)
        owner.begin_start('chat-1', epoch)
        owner.finish_start('chat-1', 'wd-2', epoch, window: 'W9')
      end
      owner.note_window('chat-1', 'wd-1', 'W2')
      wait_until { socket.of('state').last['state'] == 'ended' }
      expect(socket.of('state').last).to include('reason' => 'browser_closed', 'browser' => 1)
      expect(cdps.size).to eq(1)
    end
  end

  it 'does not move to the chat a Reset made while it changed windows' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      cdps.first.on_close = -> { Monadic::Workspace::Chats.replacing!(session) }
      owner.note_window('chat-1', 'wd-1', 'W2')
      wait_until { socket.of('state').last['state'] == 'ended' }
      expect(socket.of('state').last['reason']).to eq('replaced')
      expect(cdps.size).to eq(1)
    end
  end

  it 'shows nothing while the window the tools act on is not known, and goes on once it is' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      owner.note_window('chat-1', 'wd-1', nil)
      wait_until { socket.of('state').last['state'] == 'waiting' }
      expect(socket.of('state').last['reason']).to eq('no_window')
      expect(cdps.first).to be_closed
      owner.note_window('chat-1', 'wd-1', 'W3')
      wait_until { socket.of('state').last['state'] == 'live' }
      expect(cdps.last.commands.first[1][:targetId]).to eq('W3')
    end
  end

  it 'answers unsubscribe once the browser connection is closed' do
    closed_at_idle = nil
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      cdps.first.on_close = -> { sleep 0.3 }
      socket.say(type: 'unsubscribe')
      wait_until { socket.of('state').last['state'] == 'idle' }
      closed_at_idle = cdps.first.closed?
    end
    expect(closed_at_idle).to be(true)
  end

  it 'closes the browser connection even when the socket ends while it is being closed' do
    Sync do |task|
      runner = task.async { stream.run }
      socket.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      cdps.first.on_close = -> { sleep 0.3 }
      socket.say(type: 'unsubscribe')
      sleep 0.1
      runner.stop # the page's connection dropped
      wait_until { cdps.first.closed? }
    end
  end

  it 'keeps checking while the page does not read, and closes its socket' do
    stub_const("#{described_class}::WRITE_LIMIT", 0.5)
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      socket.stall!
      cdps.first.frame('A')
      Monadic::Workspace::Chats.replacing!(session)
      wait_until { cdps.first.closed? }
      wait_until { socket.closed? }
    end
  end

  it 'closes the socket of a page that lets messages pile up' do
    stub_const("#{described_class}::WRITE_LIMIT", 60)
    watching do
      socket.stall!
      (described_class::OUTBOX_LIMIT + 2).times { socket.say(type: 'unsubscribe') }
      wait_until { socket.closed? }
    end
  end

  it 'gives a tab one work screen socket: a newer one closes the older' do
    other = FakeSocket.new
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      Async do
        described_class.new(other, connector: ->(url) { FakeCdp.new(url).tap { |c| cdps << c } }).run
      end
      other.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
      wait_until { socket.closed? }
      wait_until { cdps.first.closed? }
      other.hang_up
    end
  end

  it 'ends on a second auth' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      socket.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
      wait_until { cdps.first.closed? }
    end
  end

  it 'ends the stream when the browser connection cannot be made' do
    failing = described_class.new(socket, connector: ->(_url) { raise Monadic::WorkScreen::Cdp::Error, 'refused' })
    Sync do |task|
      runner = task.async { failing.run }
      socket.say(type: 'auth', token: Monadic::WorkScreen::Tokens.issue('tab-1', 7))
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('state').any? }
      runner.stop
    end
    expect(socket.of('state').last).to include('state' => 'ended', 'reason' => 'browser_gone')
  end

  it 'shows only frames of the page it attached to' do
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').size == 1 }
      first = socket.of('frame').first
      cdps.first.frame('OTHER', 'S-elsewhere')
      socket.say(type: 'frame-consumed', stream: first['stream'], n: first['n'])
      sleep 0.3
      expect(socket.of('frame').size).to eq(1)
    end
  end

  it 'ends as slow when the page does not draw a frame in time' do
    stub_const("#{described_class}::CONSUME_LIMIT", 0.3)
    watching do
      socket.say(type: 'subscribe', browser: 1)
      wait_until { socket.of('frame').any? }
      wait_until { socket.of('state').last['state'] == 'ended' }
      expect(socket.of('state').last['reason']).to eq('slow')
    end
  end

  it 'takes a pass only before it expires, and holds a limited number' do
    tokens = Monadic::WorkScreen::Tokens
    now = 1000.0
    old = tokens.issue('tab-1', 7, now: now)
    expect(tokens.redeem(old, now: now + tokens::TTL)).to be_nil
    first = tokens.issue('tab-1', 7, now: now)
    tokens::LIMIT.times { tokens.issue('tab-1', 7, now: now) }
    expect(tokens.redeem(first, now: now)).to be_nil # the oldest gave way
    last = tokens.issue('tab-1', 7, now: now)
    expect(tokens.redeem(last, now: now)).not_to be_nil
  end

  it 'closes a page that does not show its pass in time' do
    stub_const("#{described_class}::AUTH_LIMIT", 0.2)
    Sync do |task|
      runner = task.async { stream.run }
      begin
        task.with_timeout(2) { runner.wait }
      ensure
        runner.stop
      end
    end
    expect(socket.sent).to be_empty
  end

  # A main socket of a tab: what it was sent.
  class FakeChatSocket
    attr_reader :sent

    def initialize = (@sent = [])
    def write(text) = @sent << JSON.parse(text)
    def flush = nil
  end

  describe 'the opened notice' do
    let(:live) { FakeChatSocket.new }

    before { WebSocketHelper.register_live_session('tab-1', session, 7, connection: live) }

    it "reaches the tab's live connection, not one it reconnected from, nor another chat's tab" do
      older = FakeChatSocket.new
      other = FakeChatSocket.new
      WebSocketHelper.add_connection_with_session(older, 'tab-1')
      WebSocketHelper.add_connection_with_session(live, 'tab-1')
      WebSocketHelper.register_live_session('tab-2', { chat_id: 'chat-2' }, 1, connection: other)
      Monadic::WorkScreen.browser_opened('chat-1')
      expect(live.sent).to eq([{ 'type' => 'work_screen', 'event' => 'browser_opened', 'browser' => 1 }])
      expect(older.sent).to be_empty
      expect(other.sent).to be_empty
    ensure
      [older, live].each { |ws| WebSocketHelper.remove_connection_with_session(ws, 'tab-1') }
      WebSocketHelper.unregister_live_session('tab-2', 1)
    end

    it 'does not reach a tab that has moved to another chat' do
      allow(WebSocketHelper).to receive(:live_tabs_for_chat).and_return(['tab-1'])
      session[Monadic::Workspace::Chats::SESSION_KEY] = 'chat-2'
      Monadic::WorkScreen.browser_opened('chat-1')
      expect(live.sent).to be_empty
    end
  end

  describe 'what waits to be written' do
    before { stub_const("#{described_class}::WRITE_LIMIT", 60) }

    # The page stops reading while the first frame is queued behind the live state.
    def frame_queued_behind_a_stall
      socket.stall!
      socket.say(type: 'subscribe', browser: 1)
      wait_until { cdps.any? && cdps.first.commands.any? { |c| c[0] == 'Page.startScreencast' } }
      sleep 0.3
    end

    it 'drops a frame of a stream that was unsubscribed' do
      watching do
        frame_queued_behind_a_stall
        socket.say(type: 'unsubscribe')
        sleep 0.2
        socket.unstall!
        wait_until { socket.of('state').last&.dig('state') == 'idle' }
      end
      expect(socket.of('frame')).to be_empty
    end

    it 'drops a frame whose chat was replaced before it was written' do
      watching do
        frame_queued_behind_a_stall
        Monadic::Workspace::Chats.replacing!(session)
        socket.unstall!
        wait_until { socket.of('state').last&.dig('state') == 'ended' }
      end
      expect(socket.of('frame')).to be_empty
    end
  end
end
