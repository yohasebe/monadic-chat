# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"

# Who acts on a chat's browser: its tools or the user from the work screen,
# one at a time, and what the user pressed is let go before a tool acts.
RSpec.describe MonadicSharedTools::BrowserOperator do
  let(:operator) { described_class }
  let(:stream) { Object.new }
  let(:threads) { [] }

  before do
    operator.reset!
    operator.enabled = true
  end

  after do
    # A thread's own failure was looked at in its example.
    threads.each do |t|
      t.kill
      begin
        t.join(1)
      rescue StandardError
        nil
      end
    end
    operator.reset!
    operator.enabled = false
  end

  # Waits (up to limit seconds) until the block holds.
  def wait_until(limit = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    until yield
      raise 'the condition did not come in time' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  def tool(chat = 'c1', recovery: false, &block)
    thread = Thread.new { operator.as_tool(chat, recovery: recovery, &block) }
    thread.report_on_exception = false
    threads << thread
    thread
  end

  it 'lets no one operate the browser while it is not turned on' do
    operator.enabled = false
    expect(operator.claim('c1', 1, stream)).to eq(:disabled)
  end

  it 'gives one stream at a time an operation, and the same one to it again' do
    op = operator.claim('c1', 1, stream)
    expect(op).to be_a(Integer)
    expect(operator.claim('c1', 1, stream)).to eq(op)
    expect(operator.claim('c1', 1, Object.new)).to eq(:taken)
    # Another browser of the chat is not the one being operated.
    expect(operator.claim('c1', 2, stream)).to eq(:taken)
    expect(operator.accept?('c1', op)).to be(true)
    expect(operator.accept?('c1', op + 1)).to be(false)
  end

  it 'ends the user\'s operation before a tool acts, and the user\'s inputs stop at once' do
    op = operator.claim('c1', 1, stream)
    ran = false
    thread = tool { ran = true }
    wait_until { operator.revoking?('c1', op) }
    # Reserved: no input is taken, and no one may start operating.
    expect(operator.accept?('c1', op)).to be(false)
    expect(operator.acted('c1', op)).to be(false)
    expect(operator.claim('c1', 1, Object.new)).to eq(:busy)
    expect(ran).to be(false)

    operator.released('c1', op, ok: true)
    expect(thread.join(2)).to eq(thread)
    expect(ran).to be(true)
    # The browser is the user's again once the tool is done.
    expect(operator.claim('c1', 1, stream)).to be_a(Integer)
  end

  it 'does not take the operation as let go when another browser is asked for meanwhile' do
    op = operator.claim('c1', 1, stream)
    operator.reserve('c1')
    expect(operator.claim('c1', 2, Object.new)).to eq(:busy)
    expect(operator.revoking?('c1', op)).to be(true)
    expect(operator.await_released('c1', timeout: 0)).to eq(:timeout)
  end

  it 'refuses a tool, and the user, when what was pressed could not be let go' do
    op = operator.claim('c1', 1, stream)
    thread = tool { :ran }
    wait_until { operator.revoking?('c1', op) }
    operator.released('c1', op, ok: false)
    expect { thread.value }.to raise_error(described_class::Unreleased)
    expect(operator.claim('c1', 1, stream)).to eq(:unavailable)
    # Asking for another browser does not make this one usable.
    expect(operator.claim('c1', 2, stream)).to eq(:unavailable)
    # A tool that closes or replaces the browser still runs.
    expect(operator.as_tool('c1', recovery: true) { :closed }).to eq(:closed)
  end

  it 'takes a wait that ends without a release as not let go' do
    op = operator.claim('c1', 1, stream)
    token = operator.reserve('c1')
    expect(operator.revoking?('c1', op)).to be(true)
    expect(operator.await_released('c1', timeout: 0.05)).to eq(:timeout)
    operator.done('c1', token)
    expect(operator.claim('c1', 1, stream)).to eq(:unavailable)
    # A release that comes later does not make it usable.
    operator.released('c1', op, ok: true)
    expect(operator.claim('c1', 1, stream)).to eq(:unavailable)
  end

  it 'starts afresh when the chat\'s browser is gone' do
    op = operator.claim('c1', 1, stream)
    operator.ending('c1', op)
    operator.released('c1', op, ok: false)
    expect(operator.claim('c1', 2, stream)).to eq(:unavailable)
    operator.forget('c1')
    expect(operator.claim('c1', 2, stream)).to be_a(Integer)
  end

  it 'keeps the browser reserved until every tool that reserved it is done' do
    first = operator.reserve('c1')
    second = operator.reserve('c1')
    operator.done('c1', first)
    expect(operator.claim('c1', 1, stream)).to eq(:busy)
    operator.done('c1', second)
    expect(operator.claim('c1', 1, stream)).to be_a(Integer)
  end

  it 'gives up its own reservation only, also when the tool fails' do
    other = operator.reserve('c1')
    expect { operator.as_tool('c1') { raise ArgumentError } }.to raise_error(ArgumentError)
    expect(operator.claim('c1', 1, stream)).to eq(:busy)
    operator.done('c1', other)
    expect(operator.claim('c1', 1, stream)).to be_a(Integer)
  end

  it 'lets a tool act at once when no one operates the browser' do
    expect(operator.as_tool('c1') { :ran }).to eq(:ran)
  end

  it 'counts the inputs taken, for the agent to be told once' do
    op = operator.claim('c1', 1, stream)
    expect(operator.pending_notice('c1')).to be_nil
    operator.acted('c1', op)
    operator.acted('c1', op)
    notice = operator.pending_notice('c1')
    expect(notice.count).to eq(2)
    operator.acted('c1', op)
    operator.consume('c1', notice)
    # An input taken after the request was settled is told next time.
    later = operator.pending_notice('c1')
    expect(later.count).to eq(3)
    operator.consume('c1', later)
    expect(operator.pending_notice('c1')).to be_nil
    # A request settled on fewer, later, does not bring them back.
    operator.consume('c1', notice)
    expect(operator.pending_notice('c1')).to be_nil
  end

  it 'tells nothing of a browser that is gone, and a request on it settles nothing of the next' do
    op = operator.claim('c1', 1, stream)
    3.times { operator.acted('c1', op) }
    old = operator.pending_notice('c1')
    token = operator.reserve('c1')
    operator.forget('c1')
    # The reservation stays; what was counted goes.
    expect(operator.pending_notice('c1')).to be_nil
    expect(operator.claim('c1', 2, stream)).to eq(:busy)
    operator.done('c1', token)

    op = operator.claim('c1', 2, stream)
    operator.acted('c1', op)
    operator.consume('c1', old)
    expect(operator.pending_notice('c1').count).to eq(1)
  end

  it 'lets the user end the operation, to be let go before another' do
    op = operator.claim('c1', 1, stream)
    operator.ending('c1', op)
    expect(operator.accept?('c1', op)).to be(false)
    expect(operator.claim('c1', 1, Object.new)).to eq(:busy)
    operator.released('c1', op, ok: true)
    expect(operator.claim('c1', 1, Object.new)).to be_a(Integer)
  end

  it 'lets another fiber of the same reactor let go while a tool waits' do
    require 'async'
    op = operator.claim('c1', 1, stream)
    order = []
    Sync do |task|
      waiting = task.async { operator.as_tool('c1') { order << :tool } }
      task.async do
        sleep 0.05
        order << :released
        operator.released('c1', op, ok: true)
      end
      waiting.wait
    end
    expect(order).to eq(%i[released tool])
  end

  describe 'tools acting on the browser (BrowserOwner.acting)' do
    let(:owner) { MonadicSharedTools::BrowserOwner }

    it 'tells a tool that could not act why, and runs one that recovers' do
      op = operator.claim('c1', 1, stream)
      operator.ending('c1', op)
      operator.released('c1', op, ok: false)
      expect(owner.acting('c1') { :ran }).to include(success: false, error: a_string_including('Close the browser'))
      expect(owner.acting('c1', recovery: true) { :ran }).to eq(:ran)
    end

    it 'runs the tools one at a time, and the user waits for them all' do
      inside = Queue.new
      go = Queue.new
      first = Thread.new { owner.acting('c1') { inside << :first; go.pop } }
      threads << first
      expect(inside.pop).to eq(:first)
      second = Thread.new { owner.acting('c1') { inside << :second } }
      threads << second
      wait_until { second.status == 'sleep' }
      expect(inside).to be_empty
      expect(operator.claim('c1', 1, stream)).to eq(:busy)
      go << :on
      expect(inside.pop).to eq(:second)
      [first, second].each { |t| expect(t.join(2)).to eq(t) }
      expect(operator.claim('c1', 1, stream)).to be_a(Integer)
    end

    it 'forgets what the user held when the chat stops holding its browser' do
      op = operator.claim('c1', 1, stream)
      operator.ending('c1', op)
      operator.released('c1', op, ok: false)
      owner.closed('c1')
      expect(operator.claim('c1', 1, stream)).to be_a(Integer)
    end
  end
end
