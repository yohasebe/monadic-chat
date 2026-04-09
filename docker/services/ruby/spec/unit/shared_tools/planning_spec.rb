# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/planning"

# Mock MonadicHelper for testing
module MonadicHelper
end unless defined?(MonadicHelper)

RSpec.describe "MonadicSharedTools::Planning" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::Planning
    end
  end

  let(:app) { test_class.new }

  describe "#propose_plan" do
    let(:plan_text) do
      <<~PLAN
        1. Read the CSV file using pandas
        2. Clean and validate the data
        3. Generate summary statistics
        4. Create visualization charts
      PLAN
    end
    let(:summary) { "Analyze sales data and generate report" }

    context "with session" do
      let(:session) { {} }

      it "stores the plan in session[:proposed_plan]" do
        app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(session[:proposed_plan]).to be_a(Hash)
        expect(session[:proposed_plan][:plan]).to eq(plan_text)
        expect(session[:proposed_plan][:summary]).to eq(summary)
      end

      it "sets status to pending" do
        app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(session[:proposed_plan][:status]).to eq("pending")
      end

      it "records a timestamp" do
        before_time = Time.now.to_f
        app.propose_plan(plan: plan_text, summary: summary, session: session)
        after_time = Time.now.to_f

        expect(session[:proposed_plan][:proposed_at]).to be_between(before_time, after_time)
      end

      it "overwrites a previous plan" do
        app.propose_plan(plan: "old plan", summary: "old", session: session)
        app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(session[:proposed_plan][:summary]).to eq(summary)
        expect(session[:proposed_plan][:plan]).to eq(plan_text)
      end
    end

    context "without session" do
      it "does not raise an error" do
        expect { app.propose_plan(plan: plan_text, summary: summary) }.not_to raise_error
      end

      it "does not raise when session is nil" do
        expect { app.propose_plan(plan: plan_text, summary: summary, session: nil) }.not_to raise_error
      end
    end

    context "return value" do
      it "includes the plan summary" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: {})

        expect(result).to include(summary)
      end

      it "includes the plan details" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: {})

        expect(result).to include(plan_text)
      end

      it "instructs the model to present the plan and wait for approval" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: {})

        expect(result).to include("PLAN REGISTERED")
        expect(result).to include("Present the plan")
        expect(result).to include("Do NOT execute")
      end
    end

    context "with autonomy high" do
      let(:session) { { parameters: { "autonomy" => "high" } } }

      it "auto-approves the plan" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(result).to include("PLAN AUTO-APPROVED")
        expect(result).to include("high autonomy mode")
        expect(result).to include(summary)
        expect(result).to include(plan_text)
      end

      it "sets status to auto_approved" do
        app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(session[:proposed_plan][:status]).to eq("auto_approved")
      end

      it "does not instruct to wait for user approval" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(result).not_to include("Do NOT execute")
        expect(result).not_to include("Ask the user")
      end

      it "works with symbol key for autonomy" do
        session_sym = { parameters: { autonomy: "high" } }
        result = app.propose_plan(plan: plan_text, summary: summary, session: session_sym)

        expect(result).to include("PLAN AUTO-APPROVED")
        expect(session_sym[:proposed_plan][:status]).to eq("auto_approved")
      end
    end

    context "with autonomy medium" do
      let(:session) { { parameters: { "autonomy" => "medium" } } }

      it "uses normal approval flow" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(result).to include("PLAN REGISTERED")
        expect(result).to include("Do NOT execute")
        expect(session[:proposed_plan][:status]).to eq("pending")
      end
    end

    context "with no autonomy setting" do
      let(:session) { { parameters: {} } }

      it "uses normal approval flow" do
        result = app.propose_plan(plan: plan_text, summary: summary, session: session)

        expect(result).to include("PLAN REGISTERED")
        expect(result).to include("Do NOT execute")
        expect(session[:proposed_plan][:status]).to eq("pending")
      end
    end
  end
end
