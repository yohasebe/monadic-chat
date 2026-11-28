# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/board"

# What a turn places once (a whiteboard, an address): taken before anything
# is made, refused the second time in the turn, given back only by the
# reservation that took it.
RSpec.describe Monadic::Workbench::Board do
  around do |example|
    Dir.mktmpdir("workbench-turn-slots-spec") do |dir|
      @state = dir
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:board) { described_class.for(chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:user) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }

  before do
    described_class.reset!
    described_class.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  def reserve(kind, origin = user) = board.reserve_slot(kind, origin: origin, epoch: epoch)

  it "takes one address a turn, apart from the turn's whiteboard" do
    expect(reserve("url")).to match(/\A\h{16}\z/)
    expect(reserve("whiteboard")).to match(/\A\h{16}\z/)
    expect { reserve("url") }.to raise_error(described_class::Refused, described_class::URL_USED)
    expect { reserve("whiteboard") }.to raise_error(described_class::Refused, described_class::WHITEBOARD_USED)
  end

  it "gives a turn's address back only with the reservation that took it" do
    token = reserve("url")
    board.release_slot("url", "another")
    expect { reserve("url") }.to raise_error(described_class::Refused, described_class::URL_USED)

    board.release_slot("url", token)
    expect(reserve("url")).to match(/\A\h{16}\z/)
  end

  it "gives the reply its own address, and a late release of the user's turn does not free it" do
    request = Monadic::Workspace::Ids.generate(:request)
    late = reserve("url")
    board.begin_reply(request)

    agent = { actor: "agent", source: "browser", request_id: request }
    reserve("url", agent)
    board.release_slot("url", late)
    expect { reserve("url", agent) }.to raise_error(described_class::Refused, described_class::URL_USED)

    board.end_reply(request)
    expect(reserve("url")).to match(/\A\h{16}\z/)
  end

  it "does not take the turn's address when nothing can be placed" do
    request = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(request)

    expect { reserve("url") }.to raise_error(described_class::Refused, described_class::BUSY)
    board.end_reply(request)
    expect(reserve("url")).to match(/\A\h{16}\z/)
  end
end
