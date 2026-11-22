# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/look/record"

# A look at the chat's browser on the work screen: a picture of its
# viewport, with the page's title and its address without what may
# identify the user.
RSpec.describe "looking at the browser on the work screen" do
  let(:look) { Monadic::Workbench::Look }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:view) { MonadicSharedTools::BrowserOwner::View.new(chat, epoch, "inst-1", "sess-1", "W1") }
  let(:shot) do
    { png: png(64, 40), url: "https://user:pw@example.com:8443/docs/page?q=secret#part", title: "Docs\npage",
      crop: { "x" => 0, "y" => 0, "width" => 1280, "height" => 800, "sent_width" => 64, "sent_height" => 40 } }
  end

  around do |example|
    Dir.mktmpdir("workbench-browser-spec") do |dir|
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@state)
      example.run
    end
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    Monadic::Workbench::Look::Ledger.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::WorkScreen).to receive(:available?).and_return(true)
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view)
    allow(WebSocketHelper).to receive(:live_generation).with("tab-1").and_return(1)
    allow(WebSocketHelper).to receive(:live_session).with("tab-1").and_return(session)
    allow(Monadic::WorkScreen::Snapshot).to receive(:take).and_return(shot)
  end

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  def open_browser
    Monadic::Workbench::Board.for(chat, store: store)
                             .add_browser(instance: "inst-1", origin: { actor: :agent, source: :browser, tab: "tab-1", generation: 1 },
                                          epoch: epoch)
  end

  def caller_for
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: request_id, session: session, tab: "tab-1",
                                   generation: 1)
  end

  def ledger
    Monadic::Workbench::Look::Ledger.find(chat, request_id)
  end

  it "gives a picture of the viewport, the page's title and its address without what may identify the user" do
    item = open_browser
    out = JSON.parse(look.run(caller_for).to_s)
    expect(Monadic::WorkScreen::Snapshot).to have_received(:take) do |binding, deadline:|
      expect(binding.to_a).to eq(["tab-1", 1, chat, epoch, "inst-1", "sess-1", "W1"])
      expect(deadline).to be_a(Float)
    end
    expect(out["item"]).to eq({ "kind" => "browser", "name" => "Docs page", "path" => "https://example.com:8443/docs/page" })
    expect(out["image"]).to include("viewport")
    record = Monadic::Workbench::Look::Record.clean(ledger.records).first
    expect(record).to include("kind" => "browser", "source" => "workbench_browser", "item_id" => item["id"],
                              "name" => "Docs page", "path" => "https://example.com:8443/docs/page", "image" => true)
    expect(record).not_to have_key("version")
    expect(record["crop"]).to include("sent_width" => 64, "sent_height" => 40)
    expect(JSON.generate(record)).not_to include("secret", "sess-1", "pw")
    expect(ledger.observations_with_content.first.image.source).to eq("workbench_browser")
  end

  it "passes the title and the address through the chat's Privacy Filter before they are kept" do
    open_browser
    allow(look).to receive(:filtered).and_call_original
    allow(look).to receive(:filtered).with(session, "Docs page").and_return("<<TITLE>>")
    allow(look).to receive(:filtered).with(session, "https://example.com:8443/docs/page").and_return("<<URL>>")
    out = JSON.parse(look.run(caller_for).to_s)
    expect(ledger.records.first).to include("name" => "<<TITLE>>", "path" => "<<URL>>")
    expect(out["item"]).to include("name" => "<<TITLE>>", "path" => "<<URL>>")
  end

  it "keeps only http(s) addresses, without user information, query or fragment" do
    browser = look::Browser
    expect(browser.address("https://example.com/a/b?x=1#y")).to eq("https://example.com/a/b")
    expect(browser.address("http://u:p@host.test/")).to eq("http://host.test/")
    expect(browser.address("data:text/html,<b>secret</b>")).to eq("")
    expect(browser.address("file:///etc/passwd")).to eq("")
    expect(browser.address("not a url")).to eq("")
    expect(browser.title("")).to eq("browser")
    expect(browser.title("t" * 500).length).to eq(200)
  end

  it "is refused where the browser cannot be reached, and for a browser closed or not ready" do
    open_browser
    allow(Monadic::WorkScreen).to receive(:available?).and_return(false)
    expect(look.run(caller_for)).to include("(browser_unavailable)")
    allow(Monadic::WorkScreen).to receive(:available?).and_return(true)
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view.dup.tap { |v| v.instance = "inst-2" })
    expect(look.run(caller_for)).to include("(changed)")
    allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view.dup.tap { |v| v.window = nil })
    expect(look.run(caller_for)).to include("(drawing)")
    expect(Monadic::WorkScreen::Snapshot).not_to have_received(:take)
  end

  it "keeps nothing when the browser's window changed after the picture was taken" do
    open_browser
    allow(Monadic::WorkScreen::Snapshot).to receive(:take) do
      allow(MonadicSharedTools::BrowserOwner).to receive(:view).with(chat).and_return(view.dup.tap { |v| v.window = "W2" })
      shot
    end
    expect(look.run(caller_for)).to include("(selection_changed)")
    expect(ledger.records).to be_empty
  end

  it "says why the picture could not be taken" do
    open_browser
    allow(Monadic::WorkScreen::Snapshot).to receive(:take)
      .and_raise(Monadic::WorkScreen::Snapshot::Failed.new("capture_timeout", "too slow"))
    expect(look.run(caller_for)).to include("(capture_timeout)")
  end
end
