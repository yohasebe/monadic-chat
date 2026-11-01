# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/mcp/cost_guard"

RSpec.describe Monadic::MCP::CostGuard do
  before { described_class.reset! }
  after { described_class.reset! }

  describe "budget_total" do
    it "uses the default when unconfigured" do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => nil))
      expect(described_class.budget_total).to eq(described_class::DEFAULT_TOKEN_BUDGET)
    end

    it "honors a positive CONFIG override" do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => "5000"))
      expect(described_class.budget_total).to eq(5000)
    end

    it "ignores a non-positive override" do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => "0"))
      expect(described_class.budget_total).to eq(described_class::DEFAULT_TOKEN_BUDGET)
    end
  end

  describe "reservations" do
    before do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => "1000"))
    end

    def spend(tokens)
      described_class.reserve!(tokens).settle(tokens)
    end

    it "holds what a call reserved until it is settled, then keeps only what it spent" do
      r = described_class.reserve!(400)
      expect(described_class.remaining).to eq(600)
      expect(described_class.status).to include(tokens_spent: 0, tokens_reserved: 400, tokens_remaining: 600)
      r.settle(150)
      expect(described_class.status).to include(tokens_spent: 150, tokens_reserved: 0, tokens_remaining: 850)
    end

    it "does not let two calls reserve the same remaining budget" do
      described_class.reserve!(700)
      expect { described_class.reserve!(400) }
        .to raise_error(described_class::BudgetExceeded, /exceeds remaining budget/)
    end

    it "lets only as many calls through at once as the budget can hold" do
      granted = Queue.new
      Array.new(8) do
        Thread.new do
          granted << described_class.reserve!(300)
        rescue described_class::BudgetExceeded
          nil
        end
      end.each(&:join)
      expect(granted.size).to eq(3)
      expect(described_class.reserved).to eq(900)
    end

    it "charges a call that ends without settling what it reserved" do
      r = described_class.reserve!(300)
      r.close
      expect(described_class.status).to include(tokens_spent: 300, tokens_reserved: 0)
    end

    it "gives back what a call charged as it sends never sent" do
      r = described_class.reserve!(300, pay_as_sent: true)
      r.charge(100)
      r.close
      expect(described_class.status).to include(tokens_spent: 100, tokens_reserved: 0)
    end

    it "leaves a settled call as it was when it is closed" do
      r = described_class.reserve!(300)
      r.settle(100)
      r.close
      expect(described_class.spent).to eq(100)
    end

    it "spends from the reservation as requests go out and holds more while the budget allows" do
      r = described_class.reserve!(100)
      expect(r.charge(60)).to be(true)
      expect(r.charge(90)).to be(true) # 40 held, 50 more taken from the budget
      expect(described_class.status).to include(tokens_spent: 150, tokens_reserved: 0)
      r.settle(10) # the reply
      expect(described_class.spent).to eq(160)
    end

    it "refuses a request the budget cannot cover, spending nothing for it" do
      spend(850)
      r = described_class.reserve!(100)
      expect(r.charge(150)).to be(true) # 100 held and the 50 left over
      expect(r.charge(1)).to be(false)
      expect(described_class.spent).to eq(1000)
    end

    it "refuses a projection that would exceed the ceiling (fail-closed)" do
      spend(900)
      expect { described_class.reserve!(100) }.not_to raise_error
      expect { described_class.reserve!(1) }.to raise_error(described_class::BudgetExceeded)
    end

    it "clamps remaining at zero when a reply overspent" do
      described_class.reserve!(100).settle(1500)
      expect(described_class.remaining).to eq(0)
    end

    it "keeps the reply's share out of what the requests may spend" do
      spend(500)
      r = described_class.reserve!(500, pay_as_sent: true, keep: 100)
      expect(r.charge(400)).to be(true)
      expect(r.charge(1)).to be(false) # only the reply's 100 is left, and it is kept
      r.settle(80)
      expect(described_class.status).to include(tokens_spent: 980, tokens_reserved: 0)
    end
  end

  describe "reserving" do
    before do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => "1000"))
    end

    it "closes the reservation when the call returns without settling" do
      value = described_class.reserving(300) { |r| r.held }
      expect(value).to eq(300)
      expect(described_class.status).to include(tokens_spent: 300, tokens_reserved: 0)
    end

    it "closes the reservation when the call raises" do
      expect { described_class.reserving(300) { raise "boom" } }.to raise_error("boom")
      expect(described_class.status).to include(tokens_spent: 300, tokens_reserved: 0)
    end

    it "does not run the call when the budget is short" do
      ran = false
      expect { described_class.reserving(2000) { ran = true } }.to raise_error(described_class::BudgetExceeded)
      expect(ran).to be(false)
      expect(described_class.reserved).to eq(0)
    end

    it "closes the reservation when the thread is killed during the call" do
      inside = Queue.new
      t = Thread.new { described_class.reserving(300) { inside << true; sleep } }
      inside.pop
      t.kill.join
      expect(described_class.status).to include(tokens_spent: 300, tokens_reserved: 0)
    end

    # The kill arrives while the ledger is being changed: it waits for the
    # change, so the ledger and the reservation never disagree.
    def kill_inside(method, thread_body)
      entered = Queue.new
      gate = Queue.new
      allow(described_class).to receive(method).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs)
        entered << true # the ledger has changed; the rest of the step has not run
        gate.pop
        result
      end
      t = Thread.new(&thread_body)
      entered.pop
      t.kill
      10.times { gate << true }
      t.join
    end

    it "does not leave tokens held when the kill comes while they are being held" do
      kill_inside(:reserve!, -> { described_class.reserving(300) { sleep } })
      expect(described_class.reserved).to eq(0)
    end

    it "does not give back more than is held when the kill comes during a charge" do
      kill_inside(:move, -> { described_class.reserving(300, pay_as_sent: true) { |r| r.charge(100) } })
      expect(described_class.status).to include(tokens_spent: 100, tokens_reserved: 0)
    end
  end

  describe "estimate_tokens" do
    it "returns 0 for empty input" do
      expect(described_class.estimate_tokens("")).to eq(0)
      expect(described_class.estimate_tokens(nil)).to eq(0)
    end

    it "returns a positive count for real text" do
      expect(described_class.estimate_tokens("Hello, Monadic Conduit!")).to be > 0
    end
  end
end
