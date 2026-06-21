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

  describe "accounting" do
    before do
      stub_const("CONFIG", (defined?(CONFIG) ? CONFIG : {}).merge("CONDUIT_TOKEN_BUDGET" => "1000"))
    end

    it "tracks spend and remaining" do
      expect(described_class.spent).to eq(0)
      expect(described_class.remaining).to eq(1000)
      described_class.record(300)
      expect(described_class.spent).to eq(300)
      expect(described_class.remaining).to eq(700)
    end

    it "permits a projection within budget" do
      described_class.record(900)
      expect { described_class.ensure_within!(100) }.not_to raise_error
    end

    it "refuses a projection that would exceed the ceiling (fail-closed)" do
      described_class.record(900)
      expect { described_class.ensure_within!(200) }
        .to raise_error(described_class::BudgetExceeded, /exceeds remaining budget/)
    end

    it "clamps remaining at zero when overspent" do
      described_class.record(1500)
      expect(described_class.remaining).to eq(0)
    end

    it "reports a status hash" do
      described_class.record(250)
      expect(described_class.status).to eq(
        token_budget: 1000, tokens_spent: 250, tokens_remaining: 750
      )
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
