# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"

# Who acts on a chat's browser: its tools or the user from the work screen,
# one at a time, and what the user pressed is let go before a tool acts.
RSpec.describe MonadicSharedTools::BrowserOperator do
  let(:operator) { described_class }
  let(:stream) { Object.new }

  before do
    operator.reset!
    operator.enabled = true
  end

  after do
    operator.reset!
    operator.enabled = false
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
    expect(operator.accept?('c1', op)).to be(true)
    expect(operator.accept?('c1', op + 1)).to be(false)
  end

  it 'ends the user\'s operation before a tool acts, and the user\'s inputs stop at once' do
    op = operator.claim('c1', 1, stream)
    ran = false
    tool = Thread.new { operator.as_tool('c1') { ran = true } }
    sleep 0.05 until operator.revoking?('c1', op)
    # Reserved: no input is taken, and no one may start operating.
    expect(operator.accept?('c1', op)).to be(false)
    expect(operator.acted('c1', op)).to be(false)
    expect(operator.claim('c1', 1, Object.new)).to eq(:busy)
    expect(ran).to be(false)

    operator.released('c1', op, ok: true)
    tool.join(2)
    expect(ran).to be(true)
    # The browser is the user's again once the tool is done.
    expect(operator.claim('c1', 1, stream)).to be_a(Integer)
  end

  it 'refuses a tool, and the user, when what was pressed could not be let go' do
    op = operator.claim('c1', 1, stream)
    tool = Thread.new { operator.as_tool('c1') { :ran } }
    tool.report_on_exception = false
    sleep 0.05 until operator.revoking?('c1', op)
    operator.released('c1', op, ok: false)
    expect { tool.value }.to raise_error(described_class::Unreleased)
    expect(operator.claim('c1', 1, stream)).to eq(:unavailable)
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

  it 'starts afresh when the chat\'s browser is gone, or for a newer browser' do
    op = operator.claim('c1', 1, stream)
    operator.reserve('c1')
    operator.await_released('c1', timeout: 0.01)
    expect(operator.claim('c1', 1, stream)).to eq(:busy)
    operator.reset!
    op = operator.claim('c1', 1, stream)
    operator.ending('c1', op)
    operator.released('c1', op, ok: false)
    expect(operator.claim('c1', 1, stream)).to eq(:unavailable)
    expect(operator.claim('c1', 2, stream)).to be_a(Integer)

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

  it 'lets a tool act at once when no one operates the browser' do
    expect(operator.as_tool('c1') { :ran }).to eq(:ran)
  end

  it 'counts the inputs taken, for the agent to be told once' do
    op = operator.claim('c1', 1, stream)
    expect(operator.pending_notice('c1')).to be_nil
    operator.acted('c1', op)
    operator.acted('c1', op)
    count = operator.pending_notice('c1')
    expect(count).to eq(2)
    operator.acted('c1', op)
    operator.consume('c1', count)
    # An input taken after the request was settled is told next time.
    expect(operator.pending_notice('c1')).to eq(3)
    operator.consume('c1', 3)
    expect(operator.pending_notice('c1')).to be_nil
    # A request settled on fewer, later, does not bring them back.
    operator.consume('c1', 2)
    expect(operator.pending_notice('c1')).to be_nil
  end

  it 'lets the user end the operation, to be let go before another' do
    op = operator.claim('c1', 1, stream)
    operator.ending('c1', op)
    expect(operator.accept?('c1', op)).to be(false)
    expect(operator.claim('c1', 1, Object.new)).to eq(:busy)
    operator.released('c1', op, ok: true)
    expect(operator.claim('c1', 1, Object.new)).to be_a(Integer)
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

    it 'forgets what the user held when the chat stops holding its browser' do
      op = operator.claim('c1', 1, stream)
      operator.ending('c1', op)
      operator.released('c1', op, ok: false)
      owner.closed('c1')
      expect(operator.claim('c1', 1, stream)).to be_a(Integer)
    end
  end
end
