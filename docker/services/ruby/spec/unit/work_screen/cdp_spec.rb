# frozen_string_literal: true

require_relative "../../spec_helper"
require "async"
require "async/queue"
require_relative "../../../lib/monadic/work_screen/cdp"

# The CDP connection, on a fake WebSocket transport.
RSpec.describe Monadic::WorkScreen::Cdp do
  # The browser's side: what the test pushes is read; what is written is kept.
  class FakeTransport
    attr_reader :written, :closes
    attr_accessor :flush_delay

    def initialize
      @inbox = Async::Queue.new
      @written = []
      @closes = 0
      @flush_delay = 0
    end

    def push(message) = @inbox.enqueue(message.is_a?(String) ? message : JSON.generate(message))
    def hang_up = @inbox.enqueue(nil)
    def read = @inbox.dequeue
    def write(message) = @written << JSON.parse(message.to_str)
    def flush = (sleep(flush_delay) if flush_delay.positive?)

    def close
      @closes += 1
      @inbox.enqueue(nil)
    end

    def sent(method) = @written.select { |m| m['method'] == method }
  end

  let(:transport) { FakeTransport.new }

  def wait_until(limit = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    expect(yield).to be_truthy
  end

  def connected
    allow(Async::WebSocket::Client).to receive(:connect).and_return(transport)
    Sync do
      cdp = described_class.open('ws://selenium_service:4444/session/x/se/cdp')
      yield cdp
    ensure
      cdp&.close
    end
  end

  def frame(n) = { 'method' => 'Page.screencastFrame', 'sessionId' => 'S1',
                   'params' => { 'data' => "IMG#{n}", 'sessionId' => n } }

  it 'answers a command with its reply' do
    connected do |cdp|
      Async do
        wait_until { transport.written.any? }
        transport.push(id: transport.written.last['id'], result: { 'sessionId' => 'S1' })
      end
      expect(cdp.command('Target.attachToTarget', { targetId: 'W' })).to eq('sessionId' => 'S1')
    end
  end

  it 'acknowledges every frame as it arrives and keeps the newest' do
    connected do |cdp|
      transport.push(frame(1))
      transport.push(frame(2))
      wait_until { transport.sent('Page.screencastFrameAck').size == 2 }
      expect(transport.sent('Page.screencastFrameAck').map { |m| m['params']['sessionId'] }).to eq([1, 2])
      expect(transport.sent('Page.screencastFrameAck').map { |m| m['sessionId'] }).to all(eq('S1'))
      expect(cdp.next_event(1)).to eq(:frame)
      expect(cdp.latest_frame).to eq(session: 'S1', data: 'IMG2')
      expect(cdp.latest_frame).to be_nil
    end
  end

  it 'keeps a frame however many other events come after it' do
    connected do |cdp|
      transport.push(frame(1))
      (described_class::EVENT_LIMIT - 1).times { |i| transport.push(method: 'Page.loadEventFired', params: { i: i }) }
      sleep 0.1
      expect(cdp).not_to be_closed
      expect(cdp.next_event(1)).to eq(:frame)
      expect(cdp.latest_frame[:data]).to eq('IMG1')
    end
  end

  it 'holds any number of frames as one' do
    connected do |cdp|
      (described_class::EVENT_LIMIT * 2).times { |n| transport.push(frame(n)) }
      transport.push(method: 'Page.loadEventFired')
      wait_until { transport.sent('Page.screencastFrameAck').size == described_class::EVENT_LIMIT * 2 }
      sleep 0.05
      expect(cdp).not_to be_closed
    end
  end

  it 'ends rather than drop an event when the reader falls too far behind' do
    connected do |cdp|
      (described_class::EVENT_LIMIT + 1).times { transport.push(method: 'Page.loadEventFired') }
      wait_until { cdp.closed? }
      expect(transport.closes).to eq(1)
    end
  end

  it 'releases the transport once, however the connection ended' do
    ['not json', 'x' * (described_class::MESSAGE_LIMIT + 1), nil].each do |last|
      transport = FakeTransport.new
      allow(Async::WebSocket::Client).to receive(:connect).and_return(transport)
      Sync do
        cdp = described_class.open('ws://selenium_service:4444/session/x/se/cdp')
        last.nil? ? transport.hang_up : transport.push(last)
        wait_until { cdp.closed? }
        cdp.close
        expect(transport.closes).to eq(1)
      end
    end
  end

  it 'wakes a command waiting for a reply when the connection ends' do
    connected do |cdp|
      Async do
        wait_until { transport.written.any? }
        transport.hang_up
      end
      expect { cdp.command('Page.getLayoutMetrics', {}, timeout: 5) }.to raise_error(described_class::Error, 'closed')
    end
  end

  it 'counts the time to send a command in its time limit, and gives up the connection' do
    connected do |cdp|
      transport.flush_delay = 0.5
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { cdp.command('Page.getLayoutMetrics', {}, timeout: 0.05) }.to raise_error(described_class::Error)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.3
      expect(cdp).to be_closed
    end
  end

  it 'reports a connection that cannot be made as its own error' do
    allow(Async::WebSocket::Client).to receive(:connect).and_raise(Errno::ECONNREFUSED)
    Sync do
      expect { described_class.open('ws://selenium_service:4444/session/x/se/cdp') }
        .to raise_error(described_class::Error)
    end
  end
end
