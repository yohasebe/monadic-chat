# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/verification"

# Mock MonadicHelper for testing
module MonadicHelper
end unless defined?(MonadicHelper)

RSpec.describe "MonadicSharedTools::Verification" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::Verification
    end
  end

  let(:app) { test_class.new }

  let(:base_params) do
    {
      result_summary: "Generated a bar chart from sales data",
      checks_performed: ["Verified chart renders", "Checked axis labels"],
      status: "passed"
    }
  end

  describe "#report_verification" do
    context "with status 'passed'" do
      let(:session) { {} }

      it "returns instruction to present results" do
        result = app.report_verification(**base_params, session: session)

        expect(result).to include("VERIFICATION PASSED")
        expect(result).to include("present your results")
      end

      it "records the verification in session history" do
        app.report_verification(**base_params, session: session)

        expect(session[:verification_history]).to be_an(Array)
        expect(session[:verification_history].length).to eq(1)

        entry = session[:verification_history].first
        expect(entry[:result_summary]).to eq("Generated a bar chart from sales data")
        expect(entry[:checks_performed]).to eq(["Verified chart renders", "Checked axis labels"])
        expect(entry[:status]).to eq("passed")
        expect(entry[:attempt]).to eq(1)
      end

      it "records a timestamp" do
        before_time = Time.now.to_f
        app.report_verification(**base_params, session: session)
        after_time = Time.now.to_f

        entry = session[:verification_history].first
        expect(entry[:verified_at]).to be_between(before_time, after_time)
      end
    end

    context "with status 'issues_found'" do
      let(:session) { {} }
      let(:params) do
        base_params.merge(
          status: "issues_found",
          issues: ["Chart title missing", "Y-axis scale incorrect"]
        )
      end

      it "returns instruction to fix issues" do
        result = app.report_verification(**params, session: session)

        expect(result).to include("ISSUES FOUND")
        expect(result).to include("Fix the issues")
        expect(result).to include("Do NOT present results")
      end

      it "includes the issues in the return value" do
        result = app.report_verification(**params, session: session)

        expect(result).to include("Chart title missing")
        expect(result).to include("Y-axis scale incorrect")
      end

      it "stores issues in session history" do
        app.report_verification(**params, session: session)

        entry = session[:verification_history].first
        expect(entry[:issues]).to eq(["Chart title missing", "Y-axis scale incorrect"])
      end
    end

    context "with status 'fixed'" do
      let(:session) { {} }
      let(:params) do
        base_params.merge(
          status: "fixed",
          issues: ["Chart title missing"],
          fixes_applied: ["Added chart title 'Monthly Sales'"]
        )
      end

      it "returns instruction to present corrected results" do
        result = app.report_verification(**params, session: session)

        expect(result).to include("ISSUES FIXED")
        expect(result).to include("Present the corrected results")
      end

      it "includes the fixes in the return value" do
        result = app.report_verification(**params, session: session)

        expect(result).to include("Added chart title 'Monthly Sales'")
      end

      it "stores fixes_applied in session history" do
        app.report_verification(**params, session: session)

        entry = session[:verification_history].first
        expect(entry[:fixes_applied]).to eq(["Added chart title 'Monthly Sales'"])
      end
    end

    context "multiple verification attempts" do
      let(:session) { {} }

      it "increments the attempt number" do
        app.report_verification(**base_params.merge(status: "issues_found", issues: ["bug"]), session: session)
        app.report_verification(**base_params.merge(status: "fixed", fixes_applied: ["fixed bug"]), session: session)
        app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(session[:verification_history].length).to eq(3)
        expect(session[:verification_history][0][:attempt]).to eq(1)
        expect(session[:verification_history][1][:attempt]).to eq(2)
        expect(session[:verification_history][2][:attempt]).to eq(3)
      end

      it "preserves history from earlier attempts" do
        app.report_verification(**base_params.merge(status: "issues_found", issues: ["bug"]), session: session)
        app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(session[:verification_history][0][:status]).to eq("issues_found")
        expect(session[:verification_history][1][:status]).to eq("passed")
      end
    end

    context "without session" do
      it "does not raise an error" do
        expect { app.report_verification(**base_params) }.not_to raise_error
      end

      it "does not raise when session is nil" do
        expect { app.report_verification(**base_params, session: nil) }.not_to raise_error
      end

      it "still returns the appropriate instruction" do
        result = app.report_verification(**base_params, session: nil)

        expect(result).to include("VERIFICATION PASSED")
      end
    end

    context "loop termination via call_depth_per_turn" do
      let(:session) { { call_depth_per_turn: 3 } }

      it "sets call_depth_per_turn to 99_999 when status is 'passed'" do
        app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(session[:call_depth_per_turn]).to eq(99_999)
      end

      it "sets call_depth_per_turn to 99_999 when status is 'fixed'" do
        params = base_params.merge(status: "fixed", fixes_applied: ["Fixed bug"])
        app.report_verification(**params, session: session)

        expect(session[:call_depth_per_turn]).to eq(99_999)
      end

      it "does not modify call_depth_per_turn when status is 'issues_found'" do
        params = base_params.merge(status: "issues_found", issues: ["bug"])
        app.report_verification(**params, session: session)

        expect(session[:call_depth_per_turn]).to eq(3)
      end

      it "does not raise when session is nil" do
        expect {
          app.report_verification(**base_params.merge(status: "passed"), session: nil)
        }.not_to raise_error
      end
    end

    context "consecutive issues_found retry limit" do
      let(:session) { { call_depth_per_turn: 3 } }
      let(:issues_params) { base_params.merge(status: "issues_found", issues: ["bug"]) }

      it "does not force-stop on fewer than MAX_VERIFICATION_RETRIES consecutive failures" do
        2.times { app.report_verification(**issues_params, session: session) }
        expect(session[:call_depth_per_turn]).to eq(3)
      end

      it "force-stops on MAX_VERIFICATION_RETRIES consecutive failures" do
        3.times { app.report_verification(**issues_params, session: session) }
        expect(session[:call_depth_per_turn]).to eq(99_999)
      end

      it "returns VERIFICATION LIMIT REACHED message on force-stop" do
        2.times { app.report_verification(**issues_params, session: session) }
        result = app.report_verification(**issues_params, session: session)
        expect(result).to include("VERIFICATION LIMIT REACHED")
        expect(result).to include("Do NOT call any more tools")
      end

      it "resets consecutive count when a non-issues_found entry intervenes" do
        2.times { app.report_verification(**issues_params, session: session) }
        app.report_verification(**base_params.merge(status: "fixed", fixes_applied: ["fix"]), session: session)
        session[:call_depth_per_turn] = 3 # Reset for test
        2.times { app.report_verification(**issues_params, session: session) }
        expect(session[:call_depth_per_turn]).to eq(3) # Only 2 consecutive, not 3
      end

      it "includes notebook URL in limit message when available" do
        session_with_url = {
          call_depth_per_turn: 3,
          last_notebook_url: "http://127.0.0.1:8889/lab/tree/test.ipynb"
        }
        2.times { app.report_verification(**issues_params, session: session_with_url) }
        result = app.report_verification(**issues_params, session: session_with_url)
        expect(result).to include("VERIFICATION LIMIT REACHED")
        expect(result).to include("http://127.0.0.1:8889/lab/tree/test.ipynb")
      end
    end

    context "notebook URL from session" do
      it "includes notebook URL in 'passed' result when available in session" do
        session = { last_notebook_url: "http://127.0.0.1:8889/lab/tree/test_20260216_110808.ipynb" }
        result = app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(result).to include("http://127.0.0.1:8889/lab/tree/test_20260216_110808.ipynb")
      end

      it "includes notebook URL in 'fixed' result when available in session" do
        session = { last_notebook_url: "http://127.0.0.1:8889/lab/tree/test_20260216_110808.ipynb" }
        params = base_params.merge(status: "fixed", fixes_applied: ["Fixed bug"])
        result = app.report_verification(**params, session: session)

        expect(result).to include("http://127.0.0.1:8889/lab/tree/test_20260216_110808.ipynb")
      end

      it "does not include notebook URL in 'issues_found' result" do
        session = { last_notebook_url: "http://127.0.0.1:8889/lab/tree/test.ipynb" }
        params = base_params.merge(status: "issues_found", issues: ["bug"])
        result = app.report_verification(**params, session: session)

        expect(result).not_to include("Notebook URL")
      end

      it "does not include notebook URL line when not in session" do
        session = {}
        result = app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(result).not_to include("Notebook URL")
      end
    end

    context "with optional parameters as nil" do
      let(:session) { {} }

      it "handles nil issues gracefully" do
        result = app.report_verification(**base_params.merge(status: "issues_found", issues: nil), session: session)

        expect(result).to include("ISSUES FOUND")
        entry = session[:verification_history].first
        expect(entry[:issues]).to be_nil
      end

      it "handles nil fixes_applied gracefully" do
        result = app.report_verification(**base_params.merge(status: "fixed", fixes_applied: nil), session: session)

        expect(result).to include("ISSUES FIXED")
        entry = session[:verification_history].first
        expect(entry[:fixes_applied]).to be_nil
      end
    end

    context "verification wait message for temp card UI" do
      let(:session) { {} }

      it "sets wait message with Passed label when status is 'passed'" do
        app.report_verification(**base_params.merge(status: "passed"), session: session)

        expect(session[:verification_wait_message]).to include("Verification: Passed")
        expect(session[:verification_wait_message]).to include("fa-clipboard-check")
      end

      it "sets wait message with attempt count when status is 'issues_found'" do
        app.report_verification(**base_params.merge(status: "issues_found", issues: ["bug"]), session: session)

        expect(session[:verification_wait_message]).to include("Verification: Issues Found (attempt 1/3)")
      end

      it "sets wait message with Fixed label when status is 'fixed'" do
        app.report_verification(**base_params.merge(status: "fixed", fixes_applied: ["fix"]), session: session)

        expect(session[:verification_wait_message]).to include("Verification: Fixed")
      end

      it "sets wait message with Limit Reached on consecutive failures" do
        issues_params = base_params.merge(status: "issues_found", issues: ["bug"])
        3.times { app.report_verification(**issues_params, session: session) }

        expect(session[:verification_wait_message]).to include("Verification: Limit Reached")
      end

      it "does not set wait message when session is nil" do
        expect {
          app.report_verification(**base_params, session: nil)
        }.not_to raise_error
      end
    end
  end
end
