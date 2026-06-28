# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/progress_broadcaster'

RSpec.describe Monadic::Utils::ProgressBroadcaster do
  describe '.with_progress' do
    it 'returns the value the block returns' do
      result = described_class.with_progress(
        source: "Test", label: "Test op", interval: 1
      ) { 42 }

      expect(result).to eq(42)
    end

    it 'preserves complex return values' do
      payload = { "success" => true, "data" => [1, 2, 3] }
      result = described_class.with_progress(
        source: "Test", label: "Test op", interval: 1
      ) { payload }

      expect(result).to eq(payload)
    end

    it 'propagates exceptions from the block' do
      expect {
        described_class.with_progress(source: "Test", label: "Test op", interval: 1) do
          raise StandardError, "boom"
        end
      }.to raise_error(StandardError, "boom")
    end

    it 'does not leak the progress thread when the block completes quickly' do
      before_count = Thread.list.size

      described_class.with_progress(source: "Test", label: "Test op", interval: 1) { :ok }

      # Allow any short-lived thread to fully exit. ensure-kill in the helper
      # is synchronous via thread.join(2), but Ruby's Thread.list can lag a
      # tick on completion — sleep(0) yields the scheduler.
      sleep 0.05

      after_count = Thread.list.size
      expect(after_count).to be <= before_count
    end

    it 'does not leak the progress thread on block exception' do
      before_count = Thread.list.size

      expect {
        described_class.with_progress(source: "Test", label: "Test op", interval: 1) do
          raise "boom"
        end
      }.to raise_error("boom")

      sleep 0.05
      after_count = Thread.list.size
      expect(after_count).to be <= before_count
    end

    it 'does not broadcast when WebSocketHelper is undefined' do
      hide_const("WebSocketHelper") if defined?(::WebSocketHelper)

      expect {
        described_class.with_progress(source: "Test", label: "Test op", interval: 1) do
          sleep 0.1
          :done
        end
      }.not_to raise_error
    end

    it 'broadcasts at least one progress fragment when block exceeds interval' do
      fake = Module.new do
        def self.broadcasts
          @broadcasts ||= []
        end

        def self.send_progress_fragment(fragment, _session_id)
          broadcasts << fragment
        end
      end
      stub_const("WebSocketHelper", fake)

      # 1 second interval + 2.5 second block guarantees at least one tick.
      described_class.with_progress(source: "ImgTest", label: "rendering", interval: 1) do
        sleep 2.5
      end

      expect(fake.broadcasts.size).to be >= 1
      first = fake.broadcasts.first
      expect(first["type"]).to eq("wait")
      expect(first["source"]).to eq("ImgTest")
      expect(first["content"]).to include("rendering")
      expect(first["elapsed"]).to be >= 1
    end
  end

  describe '.report_to_job (Conduit job bridge)' do
    it 'is a no-op when there is no job id' do
      expect { described_class.send(:report_to_job, nil, { "content" => "x" }) }.not_to raise_error
    end

    it 'mirrors the fragment content into JobStore when a job id is present' do
      fake = Class.new do
        def self.calls
          @calls ||= []
        end

        def self.report(id, msg)
          calls << [id, msg]
        end
      end
      stub_const("Monadic::MCP::JobStore", fake)

      described_class.send(:report_to_job, "job-1", { "content" => "rendering — 1s elapsed" })
      expect(fake.calls).to eq([["job-1", "rendering — 1s elapsed"]])
    end
  end

  describe '.build_fragment' do
    it 'formats elapsed seconds under one minute' do
      f = described_class.build_fragment(source: "X", label: "Y", elapsed: 45)
      expect(f["content"]).to include("45s")
      expect(f["minutes"]).to eq(0)
    end

    it 'formats elapsed time over one minute' do
      f = described_class.build_fragment(source: "X", label: "Y", elapsed: 125)
      expect(f["content"]).to include("2m 5s")
      expect(f["minutes"]).to eq(2)
    end
  end
end
