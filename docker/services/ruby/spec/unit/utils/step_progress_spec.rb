# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/utils/step_progress"

# Mock WebSocketHelper for testing
module WebSocketHelper
  def self.send_progress_fragment(fragment, session_id = nil)
    # no-op in tests
  end
end unless defined?(WebSocketHelper)

RSpec.describe Monadic::Utils::StepProgress do
  let(:test_class) do
    Class.new do
      include Monadic::Utils::StepProgress
      public :send_step_progress
    end
  end
  let(:instance) { test_class.new }

  let(:steps) { ["Analyzing", "Generating", "Finalizing"] }

  describe "#send_step_progress" do
    context "with block" do
      it "yields the fragment to the block" do
        received = nil
        instance.send_step_progress(
          source: "TestAgent",
          steps: steps,
          current: 1,
          mode: "sequential"
        ) { |f| received = f }

        expect(received).not_to be_nil
        expect(received["type"]).to eq("wait")
        expect(received["source"]).to eq("TestAgent")
        expect(received["content"]).to eq("Generating")
      end

      it "includes step_progress structure" do
        received = nil
        instance.send_step_progress(
          source: "TestAgent",
          steps: steps,
          current: 0
        ) { |f| received = f }

        sp = received["step_progress"]
        expect(sp).not_to be_nil
        expect(sp["mode"]).to eq("sequential")
        expect(sp["current"]).to eq(0)
        expect(sp["total"]).to eq(3)
        expect(sp["steps"]).to eq(steps)
      end
    end

    context "with parallel mode" do
      it "sets mode to parallel" do
        received = nil
        instance.send_step_progress(
          source: "ParallelDispatch",
          steps: ["Task A", "Task B"],
          current: 1,
          mode: "parallel"
        ) { |f| received = f }

        expect(received["step_progress"]["mode"]).to eq("parallel")
        expect(received["step_progress"]["current"]).to eq(1)
      end
    end

    context "without block" do
      it "sends via WebSocketHelper" do
        expect(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _|
          expect(fragment["source"]).to eq("TestAgent")
          expect(fragment["step_progress"]["current"]).to eq(2)
        end

        instance.send_step_progress(
          source: "TestAgent",
          steps: steps,
          current: 2,
          ws_session_id: "session-123"
        )
      end
    end

    context "error handling" do
      it "does not raise on exception" do
        allow(WebSocketHelper).to receive(:send_progress_fragment).and_raise(StandardError)
        expect {
          instance.send_step_progress(source: "TestAgent", steps: steps, current: 0)
        }.not_to raise_error
      end
    end

    context "edge cases" do
      it "uses fallback content when current index exceeds steps" do
        received = nil
        instance.send_step_progress(
          source: "TestAgent",
          steps: steps,
          current: 99
        ) { |f| received = f }

        expect(received["content"]).to eq("Processing...")
      end
    end
  end
end
