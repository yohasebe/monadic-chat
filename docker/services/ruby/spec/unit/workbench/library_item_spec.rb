# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/library/entry_text"

# An entry of the Library opened on the work screen: its text, read from
# the Library when it is shown or looked at, and only at the version it was
# opened at.
RSpec.describe "a Library entry on the work screen" do
  around do |example|
    Dir.mktmpdir("library-item-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, _ws_generation: 1, messages: [] } }
  let(:live) { ->(t) { t == "tab-1" ? 1 : nil } }
  let(:channel) { Monadic::Workbench::Channel }
  let(:text) { "[User]\nWhat are tides?\n\n[Assistant]\nThe moon pulls the sea.\n" }
  let(:entry) do
    { id: "conv-1", title: "Tides", text: text, version: Digest::SHA256.hexdigest(text), original: nil }
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::ViewTokens.reset!
    Monadic::Workbench::Board.live = live
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Library::EntryText).to receive(:of).with("conv-1").and_return(entry)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def board = Monadic::Workbench::Board.for(chat, store: store)

  def open_entry(id = "conv-1", generation: 1)
    channel.open_library({ "library_id" => id }, session, tab: "tab-1", generation: generation, live: live)
  end

  def fetch(path)
    Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, []] }, live: live)
                                   .call({ "PATH_INFO" => path, "REQUEST_METHOD" => "GET", "HTTP_SEC_FETCH_SITE" => "same-origin" })
  end

  it "opens the entry as an item of its own, once for the same version, described by its title and version" do
    first = open_entry
    again = open_entry

    expect(first).to include("type" => "workbench_opened", "library_id" => "conv-1", "added" => true)
    expect(again).to include("item_id" => first["item_id"], "added" => false)
    item = board.snapshot[:items].first
    expect(item).to include(kind: "library", name: "Tides", library_id: "conv-1", version: entry[:version],
                            preview: "text", status: "ok")
    expect(item).not_to have_key(:path)
  end

  it "opens nothing for a tab that is not live, or an entry that is gone or not kept whole" do
    expect(open_entry(generation: 2)).to include("status" => "refused", "reason" => "not_allowed")
    allow(Monadic::Library::EntryText).to receive(:of).with("gone").and_raise(Monadic::Library::EntryText::Missing)
    expect(open_entry("gone")).to include("status" => "refused", "reason" => "missing")
    allow(Monadic::Library::EntryText).to receive(:of).with("cut").and_raise(Monadic::Library::EntryText::Incomplete)
    expect(open_entry("cut")).to include("status" => "refused", "reason" => "incomplete")
    expect(board.snapshot[:items]).to be_empty
  end

  it "serves its text as a text file is shown, and keeps how many lines it is" do
    item_id = open_entry["item_id"]
    address = channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][item_id]

    status, headers, body = fetch(address)

    expect(status).to eq(200)
    expect(headers["content-type"]).to eq("text/plain; charset=utf-8")
    expect(body.join).to eq(text)
    expect(board.observe(tab: "tab-1", generation: 1)[:text]).to include(lines: 5)
  end

  it "serves nothing once the entry is another version, or gone, and says so on the item" do
    item_id = open_entry["item_id"]
    address = channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][item_id]
    allow(Monadic::Library::EntryText).to receive(:of).with("conv-1").and_return(entry.merge(version: "b" * 64))

    expect(fetch(address).first).to eq(409)
    expect(board.snapshot[:items].first[:status]).to eq("changed")

    # A changed item is given no address; the one given before finds the
    # entry gone.
    expect(channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"]).not_to have_key(item_id)
    allow(Monadic::Library::EntryText).to receive(:of).with("conv-1").and_raise(Monadic::Library::EntryText::Missing)
    expect(fetch(address).first).to eq(410)
  end

  it "is read by the AI as text, at the version it was opened at only" do
    item_id = open_entry["item_id"]
    selection = Struct.new(:item).new(board.item(item_id))
    look = Monadic::Workbench::Look

    seen = look.send(:read, board, selection, "whole", caller: nil, deadline: nil)
    expect(seen).to include(item_id: item_id, kind: "text", name: "Tides", version: entry[:version])
    expect(seen[:text]).to include("The moon pulls the sea.")

    allow(Monadic::Library::EntryText).to receive(:of).with("conv-1").and_return(entry.merge(version: "c" * 64))
    expect { look.send(:read, board, selection, "whole", caller: nil, deadline: nil) }
      .to raise_error(look::Refused) { |e| expect(e.reason).to eq("changed") }
  end

  it "is told to the AI as a Library entry, by its kind" do
    open_entry

    expect(Monadic::Workbench::Observation.send(:kind_of, board.snapshot[:items].first)).to eq("library")
  end
end
