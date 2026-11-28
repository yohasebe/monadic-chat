# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/board"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/observation"
require_relative "../../../lib/monadic/shared_tools/browser_owner"
require_relative "../../../lib/monadic/work_screen/snapshot"
require_relative "../../../lib/monadic/work_screen"

# The chat's open browser stays in Now when a turn ends; the page as that
# turn left it goes down with the turn, as a picture in the chat's folder,
# or as a link when no picture can be taken.
RSpec.describe Monadic::Workbench::PagePictures do
  def png(width = 1280, height = 800)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  around do |example|
    Dir.mktmpdir("workbench-page-pictures-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:board) { Monadic::Workbench::Board.for(chat) }
  let(:owner) { MonadicSharedTools::BrowserOwner }
  let(:open_instance) { [1] }
  let(:shots) { [] }
  let(:user) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }

  before do
    Monadic::Workbench::Board.reset!
    described_class.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
    allow(Monadic::WorkScreen).to receive(:available?).and_return(true)
    allow(owner).to receive(:view) do |c|
      next nil unless c == chat && open_instance.first

      MonadicSharedTools::BrowserOwner::View.new(chat, epoch, open_instance.first, "s-1", "w-1")
    end
    # The pictures are taken in place, in the order the turns end.
    @spawn = described_class.spawn
    described_class.spawn = ->(&work) { work.call }
    allow(Monadic::WorkScreen::Snapshot).to receive(:take) do |binding, **|
      shot = shots.shift
      raise Monadic::WorkScreen::Snapshot::Failed.new("browser_unavailable", "gone") unless shot

      expect(binding.broken).to be_nil
      shot
    end
  end

  after do
    described_class.spawn = @spawn
    Monadic::Workbench::Board.live = nil
    Monadic::Workspace::Ledger.clear_unsettled!
  end

  def open_browser = board.add_browser(instance: open_instance.first, origin: user, epoch: epoch)

  def items = board.snapshot[:items]

  def user_turn!(request = Monadic::Workspace::Ids.generate(:request))
    board.begin_reply(request)
    request
  end

  it "keeps the open browser in Now and puts the page the turn left down with it, as a picture in the chat's folder" do
    browser = open_browser
    shots << { png: png, url: "https://user:pw@example.com/search?q=secret#top", title: "Results\nof the search" }
    user_turn!

    expect(items.find { |item| item[:id] == browser["id"] }).to include(kind: "browser", place: "current", status: "open")
    page = items.find { |item| item[:kind] == "file" }
    expect(page).to include(place: "latest", by: "user", preview: "image", page: { "url" => "https://example.com/search",
                                                                                 "title" => "Results of the search" })
    expect(page[:path]).to match(%r{/pages/page-1\.png\z})
    expect(File.binread(File.join(@data, page[:path]))).to eq(png)
    expect(described_class.taking?(chat)).to be(false)
  end

  it "makes the page a link when no picture can be taken, and keeps the browser in Now" do
    open_browser
    user_turn!

    expect(items.map { |item| [item[:kind], item[:place]] }).to eq([%w[browser current], %w[page latest]])
    expect(items.last).to include(kind: "page", status: "link", version: "page:link")
  end

  it "keeps the address and title a tool last reported for a page kept without a picture" do
    open_browser
    described_class.note(chat, { page_info: { url: "https://u:p@example.com/a?token=x#f", title: "Page A" } })
    user_turn!

    expect(items.last).to include(kind: "page", status: "link", name: "Page A", url: "https://example.com/a")
  end

  it "leaves a picture of each turn: the reply's goes into Latest and the user's moves to Before" do
    open_browser
    shots << { png: png, url: "https://example.com/a", title: "A" } << { png: png(1280, 801), url: "https://example.com/b", title: "B" }
    request = user_turn!
    board.end_reply(request)

    pages = items.select { |item| item[:kind] == "file" }
    expect(pages.map { |item| [item.dig(:page, "title"), item[:place], item[:by]] })
      .to eq([["A", "previous", "user"], ["B", "latest", "agent"]])
    expect(pages.map { |item| File.basename(item[:path]) }).to eq(%w[page-1.png page-2.png])
    expect(items.count { |item| item[:kind] == "browser" && item[:place] == "current" }).to eq(1)
  end

  it "makes the page a link at once, taking no picture, where the browser cannot be reached from here" do
    allow(Monadic::WorkScreen).to receive(:available?).and_return(false)
    open_browser
    user_turn!

    expect(items.last).to include(kind: "page", status: "link")
    expect(Monadic::WorkScreen::Snapshot).not_to have_received(:take)
  end

  it "moves a closed browser down as any item, with no page" do
    open_browser
    open_instance[0] = nil
    user_turn!

    expect(items.map { |item| [item[:kind], item[:place]] }).to eq([%w[browser latest]])
    expect(Monadic::WorkScreen::Snapshot).not_to have_received(:take)
  end

  it "makes a page a restart left waiting a link to it" do
    open_browser
    described_class.spawn = ->(&_work) {}
    user_turn!
    expect(items.last).to include(kind: "page", status: "pending")

    Monadic::Workbench::Board.reset!
    described_class.reset!
    expect(Monadic::Workbench::Board.for(chat).snapshot[:items].map { |item| [item[:kind], item[:status]] })
      .to eq([%w[page link]])
  end

  it "holds the browser's tools until the turn's pictures are taken" do
    open_browser
    taken = []
    described_class.spawn = ->(&work) { Thread.new { sleep 0.2; work.call } }
    allow(Monadic::WorkScreen::Snapshot).to receive(:take) { taken << :picture; { png: png, url: "https://example.com", title: "x" } }
    user_turn!

    owner.acting(chat) { taken << :tool }
    expect(taken).to eq(%i[picture tool])
  end

  it "keeps the last page where the browser was when a tool closes it, before it is let go" do
    browser = open_browser
    shots << { png: png, url: "https://example.com/last", title: "Last" }
    described_class.before_close(chat)

    page = items.find { |item| item[:id] == browser["id"] }
    expect(page).to include(kind: "file", place: "current", preview: "image",
                            page: { "url" => "https://example.com/last", "title" => "Last" })
    expect(items.size).to eq(1)
    expect(described_class.taking?(chat)).to be(false)
  end

  it "makes the item of a browser that closed some other way a link to its page" do
    browser = open_browser
    open_instance[0] = nil
    owner.closed(chat)

    expect(items).to contain_exactly(include(id: browser["id"], kind: "page", status: "link", place: "current"))
  end

  it "leaves the item of the browser open now when an earlier one is told closed" do
    open_browser
    owner.closed(chat)

    expect(items).to contain_exactly(include(kind: "browser", status: "open"))
  end

  it "puts a browser the user opened from the work screen on it as the user's" do
    Thread.current[:workbench_opener] = { tab: "tab-1", generation: 1 }
    view = MonadicSharedTools::BrowserOwner::View.new(chat, epoch, 1, "s-1", "w-1")
    Monadic::WorkScreen.put_on_workbench(chat, view)

    expect(items).to contain_exactly(include(kind: "browser", by: "user"))
    expect(board.selected(tab: "tab-1", generation: 1)).to eq(items.first[:id])
  ensure
    Thread.current[:workbench_opener] = nil
  end

  it "says a page with no picture cannot be looked at, and tells its title and address" do
    open_browser
    shots << nil
    user_turn!
    page = items.last
    expect(page).to include(kind: "page", status: "link")

    shown = Monadic::Workbench::Observation.send(:shown_item, page.merge(name: "Results", url: "https://example.com/a"))
    expect(shown).to include("kind" => "page", "name" => "Results", "url" => "https://example.com/a")
    expect(Monadic::Workbench::Look::REASONS).to include("no_picture")
  end
end
