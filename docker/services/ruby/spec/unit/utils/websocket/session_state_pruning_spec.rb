# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/websocket"

# A tab's saved state is kept for reloads and reconnects, but not forever:
# tabs without a connection are dropped after STATE_IDLE_TTL, and beyond
# STATE_MAX_IDLE the least recently used go first. Open tabs keep theirs.
RSpec.describe "WebSocketHelper tab state pruning" do
  let(:helper) { WebSocketHelper }
  let(:clock) { [1_000.0] }

  around do |example|
    saved_state = helper.class_variable_get(:@@session_state)
    saved_live = helper.class_variable_get(:@@live_sessions)
    helper.class_variable_set(:@@session_state, {})
    helper.class_variable_set(:@@live_sessions, {})
    example.run
  ensure
    helper.class_variable_set(:@@session_state, saved_state)
    helper.class_variable_set(:@@live_sessions, saved_live)
  end

  before { allow(helper).to receive(:monotonic_now) { clock[0] } }

  def save(id)
    helper.update_session_state(id, messages: [{ "text" => id }], parameters: {})
  end

  def ids
    helper.class_variable_get(:@@session_state).keys
  end

  it "drops a tab without a connection after the idle time, and keeps it before" do
    save("old")
    clock[0] += helper::STATE_IDLE_TTL - 1
    helper.claim_session_state("new")
    expect(ids).to include("old")

    clock[0] += 2
    helper.claim_session_state("new")
    expect(ids).not_to include("old")
    expect(ids).to include("new")
  end

  it "keeps the state of a tab whose connection is open, however old" do
    save("open")
    helper.register_live_session("open", {}, 1)
    clock[0] += helper::STATE_IDLE_TTL * 3
    helper.claim_session_state("other")
    expect(helper.fetch_session_state("open")[:messages]).to eq([{ "text" => "open" }])
  end

  it "keeps at most STATE_MAX_IDLE tabs without a connection, dropping the least recently used" do
    (helper::STATE_MAX_IDLE + 5).times do |i|
      clock[0] += 1
      save("tab#{i}")
    end
    clock[0] += 1
    helper.fetch_session_state("tab0") # used again: now the most recent
    helper.claim_session_state("current")
    expect(ids.size).to eq(helper::STATE_MAX_IDLE + 1)
    expect(ids).to include("tab0", "current")
    expect(ids).not_to include("tab1", "tab5")
    expect(ids).to include("tab6")
  end

  it "gives a tab that reconnects within the idle time its chat back" do
    save("tab")
    clock[0] += 3_600
    helper.claim_session_state("tab")
    expect(helper.fetch_session_state("tab")[:messages]).to eq([{ "text" => "tab" }])
  end
end
