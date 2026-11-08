# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"

# A browser action's screenshot is always given to the model; the chat shows
# it too unless the tab the request came from has that browser selected on
# its work screen.
RSpec.describe "MonadicSharedTools::WebAutomation screenshots and the work screen" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::WebAutomation

      def check_selenium_or_error
        nil
      end

      attr_accessor :mock_response

      private

      def send_command(command:, container:)
        @mock_response || '{"success": true, "session_id": "wd-spec"}'
      end
    end
  end

  let(:app) { test_class.new }
  let(:root) { Dir.mktmpdir }
  let(:store) { Monadic::Workbench::Store.new(File.join(root, "state", "workbench").tap { |d| FileUtils.mkdir_p(File.dirname(d)) }) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:board) { Monadic::Workbench::Board.for(chat, store: store) }
  let(:owner) { MonadicSharedTools::BrowserOwner }
  let(:request) { Monadic::Workspace::RequestContext.new(chat_id: chat, tab: "t1", generation: 1) }
  let(:shot) { JSON.generate(success: true, screenshot: "shot.png", page_info: { url: "https://example.com" }) }

  before do
    Monadic::Workbench::Board.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    Monadic::Workbench::Board.live = ->(tab) { { "t1" => 1, "t2" => 2 }[tab] }
    owner.reset!
    allow(owner).to receive(:current_work).and_return([chat, Monadic::Workspace::Chats.epoch(chat)])
    allow(owner).to receive(:observe).and_return({ sessions: [], max: 3 })
    allow(owner).to receive(:start_worker)
    owner.runner = ->(_, _) { '{"success": true}' }
    app.instance_variable_set(:@browser_action_count, 0)
    # The work screen as start_browser tells it (a stand-in: each case says
    # what placing the browser does).
    stub_const("Monadic::WorkScreen", Module.new { def self.browser_opened(_chat) = nil })
  end

  after do
    Monadic::Workbench::Board.live = nil
    owner.reset!
    FileUtils.rm_rf(root)
  end

  def open_browser
    epoch = Monadic::Workspace::Chats.epoch(chat)
    owner.begin_start(chat, epoch)
    owner.finish_start(chat, "wd-spec", epoch)
    owner.view(chat).instance
  end

  def place(instance, tab: "t1", generation: 1)
    board.add_browser(instance: instance, epoch: Monadic::Workspace::Chats.epoch(chat),
                      origin: { actor: "agent", source: "browser", tab: tab, generation: generation })
  end

  def act(tool = :browser_scroll, **args)
    app.mock_response = shot
    Monadic::Workspace::RequestContext.with(request) { app.public_send(tool, **args) }
  end

  ACTIONS = {
    browser_navigate: { url: "https://example.com" }, browser_click: { selector: "#b" },
    browser_type: { selector: "#i", text: "x" }, browser_screenshot: {}, browser_scroll: {},
    browser_press_key: { key: "Enter" }, browser_select: { selector: "#s", value: "v" },
    browser_back: {}, browser_forward: {}, annotate_elements: { selectors: ["#a"] }
  }.freeze

  context "when the tab has the browser selected" do
    before { place(open_browser) }

    ACTIONS.each do |tool, args|
      it "#{tool} gives the model the screenshot and leaves it out of the chat" do
        result = act(tool, **args)
        expect(result[:_image]).to eq("shot.png")
        expect(result[:screenshot]).to eq("shot.png")
        expect(result).not_to have_key(:gallery_html)
        expect(result[:work_screen]).to include("selected on the work screen")
        expect(result.keys).not_to include(:browser_instance, :browser_chat)
      end
    end
  end

  context "when the screenshot is shown in the chat" do
    it "the tab selected something else" do
      item = place(open_browser)
      other = board.add_browser(instance: 999, epoch: Monadic::Workspace::Chats.epoch(chat), origin: { actor: "agent" })
      board.select(tab: "t1", generation: 1, item_id: other["id"])
      expect(item).not_to be_nil
      expect(act[:gallery_html]).to include("shot.png")
    end

    it "the tab has nothing selected" do
      place(open_browser)
      board.select(tab: "t1", generation: 1, item_id: nil)
      expect(act[:gallery_html]).to include("shot.png")
    end

    it "the browser is not on the work screen (a full board, or taken off)" do
      open_browser
      result = act
      expect(result[:gallery_html]).to include("shot.png")
      expect(result).not_to have_key(:work_screen)
    end

    it "only another tab has it selected" do
      place(open_browser, tab: "t2", generation: 2)
      board.select(tab: "t1", generation: 1, item_id: nil)
      expect(act[:gallery_html]).to include("shot.png")
    end

    it "the selected browser item is an earlier browser of the chat" do
      first = open_browser
      place(first)
      # The chat's browser is replaced by a new one, not on the work screen.
      owner.release(chat, Monadic::Workspace::Chats.epoch(chat))
      open_browser
      expect(act[:gallery_html]).to include("shot.png")
    end

    it "the request's connection is no longer the tab's" do
      place(open_browser)
      Monadic::Workbench::Board.live = ->(tab) { tab == "t1" ? 5 : nil }
      expect(act[:gallery_html]).to include("shot.png")
    end

    it "the action runs outside a request" do
      place(open_browser)
      app.mock_response = shot
      expect(app.browser_scroll[:gallery_html]).to include("shot.png")
    end
  end

  describe "#start_browser" do
    before do
      app.mock_response = JSON.generate(success: true, session_id: "wd-new", screenshot: "start.png", page_info: {})
    end

    it "leaves the screenshot out of the chat when the new browser is selected for the tab" do
      allow(Monadic::WorkScreen).to receive(:browser_opened) do |c|
        place(owner.view(c).instance)
        nil
      end
      result = Monadic::Workspace::RequestContext.with(request) { app.start_browser(url: "https://example.com") }
      expect(result[:_image]).to eq("start.png")
      expect(result).not_to have_key(:gallery_html)
    end

    it "shows it when the tab kept its own selection (switching off)" do
      kept = board.add_browser(instance: 999, epoch: Monadic::Workspace::Chats.epoch(chat), origin: { actor: "agent" })
      allow(Monadic::WorkScreen).to receive(:browser_opened) do |c|
        place(owner.view(c).instance)
        # The page tells what it still shows before the result is made.
        board.select(tab: "t1", generation: 1, item_id: kept["id"])
        nil
      end
      result = Monadic::Workspace::RequestContext.with(request) { app.start_browser(url: "https://example.com") }
      expect(result[:gallery_html]).to include("start.png")
    end
  end

  it "capture_viewport_screenshots shows its pictures in the chat as before" do
    place(open_browser)
    allow(owner).to receive(:with_job).and_yield
    app.mock_response = "SUCCESS: captured\n- v1.png\n"
    result = Monadic::Workspace::RequestContext.with(request) { app.capture_viewport_screenshots(url: "https://example.com") }
    expect(result[:success]).to be(true)
    expect(result[:gallery_html]).to include("v1.png")
  end
end
