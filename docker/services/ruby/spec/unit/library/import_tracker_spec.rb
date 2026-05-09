# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library/import_tracker'

RSpec.describe Monadic::Library::ImportTracker do
  before(:each) { described_class.reset! }
  after(:each) { described_class.reset! }

  describe ".create" do
    it "returns a UUID-shaped string" do
      id = described_class.create
      expect(id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "registers the entry with stage='queued' and timestamps" do
      id = described_class.create
      entry = described_class.get(id)
      expect(entry[:stage]).to eq('queued')
      expect(entry[:started_at]).to be_a(Time)
      expect(entry[:updated_at]).to be_a(Time)
    end

    it "isolates concurrent ids" do
      id1 = described_class.create
      id2 = described_class.create
      expect(id1).not_to eq(id2)
      expect(described_class.size).to eq(2)
    end
  end

  describe ".update" do
    it "merges new fields into the entry" do
      id = described_class.create
      described_class.update(id, stage: 'extracting', filename: 'foo.pdf')
      entry = described_class.get(id)
      expect(entry[:stage]).to eq('extracting')
      expect(entry[:filename]).to eq('foo.pdf')
    end

    it "advances :updated_at on each call" do
      id = described_class.create
      first_ts = described_class.get(id)[:updated_at]
      sleep 0.01
      described_class.update(id, stage: 'embedding_storing')
      second_ts = described_class.get(id)[:updated_at]
      expect(second_ts).to be > first_ts
    end

    it "is a no-op for an unknown id" do
      expect { described_class.update('nope', stage: 'done') }.not_to raise_error
      expect(described_class.get('nope')).to be_nil
    end
  end

  describe ".get" do
    it "returns a snapshot copy (mutating it does not affect tracker state)" do
      id = described_class.create
      snapshot = described_class.get(id)
      snapshot[:stage] = 'tampered'
      expect(described_class.get(id)[:stage]).to eq('queued')
    end
  end

  describe ".delete" do
    it "removes the entry" do
      id = described_class.create
      described_class.delete(id)
      expect(described_class.get(id)).to be_nil
    end
  end

  describe "TTL purging" do
    it "purges entries with :finished_at older than TTL on next create" do
      ancient = described_class.create
      described_class.update(
        ancient,
        stage: 'done',
        finished_at: Time.now - described_class::TTL_SECONDS - 60
      )
      # New create triggers purge
      described_class.create
      expect(described_class.get(ancient)).to be_nil
    end

    it "keeps in-flight entries (no :finished_at) regardless of age" do
      slow = described_class.create
      described_class.update(slow, started_at: Time.now - 10_000) # 10000 s ago
      described_class.create  # triggers purge
      expect(described_class.get(slow)).not_to be_nil
    end

    it "keeps recently-finished entries within the TTL window" do
      fresh = described_class.create
      described_class.update(fresh, stage: 'done', finished_at: Time.now)
      described_class.create
      expect(described_class.get(fresh)).not_to be_nil
    end
  end

  describe "thread safety" do
    it "tolerates concurrent create + update without raising" do
      threads = 20.times.map do
        Thread.new do
          id = described_class.create
          described_class.update(id, stage: 'extracting')
          described_class.update(id, stage: 'done', finished_at: Time.now)
        end
      end
      threads.each(&:join)
      expect(described_class.size).to eq(20)
    end
  end
end
