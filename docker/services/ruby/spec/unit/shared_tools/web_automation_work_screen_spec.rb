# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"

# A browser action's screenshot is given to the model; the chat does not
# show it (the user watches the browser on the work screen).
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
    # The shared folder: a temporary one, never the user's.
    @shared = File.realpath(FileUtils.mkdir_p(File.join(root, "data")).first)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@shared)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@shared)
    # The work screen as start_browser tells it (a stand-in: each case says
    # what placing the browser does).
    stub_const("Monadic::WorkScreen", Module.new {
      const_set(:FULL_NOTE, "The work screen is full, so this browser is not shown there.")
      def self.browser_opened(_chat) = nil
    })
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

  describe "what stays in the shared folder" do
    let(:png) { "\x89PNG\r\n\x1A\n".b + "x" }
    let(:prefix) { Monadic::Utils::ToolImageUtils::FOR_MODEL_PREFIX }

    before { File.binwrite(File.join(@shared, "shot.png"), png) }

    it "is nothing of an action's screenshot once the model has been given it" do
      place(open_browser)
      result = act(:browser_scroll)

      expect(result[:_image]).to start_with(prefix)
      expect(Dir.children(@shared)).to eq([result[:_image]])
      expect(Monadic::Utils::ToolImageUtils.encode_image_for_api(result[:_image])).to include(media_type: "image/png")
      expect(Dir.children(@shared)).to eq([])
    end

    it "is a screenshot the model asked for, in the chat's folder and not at the top" do
      place(open_browser)
      FileUtils.mkdir_p(File.join(@shared, "conversations", "c", "artifacts", "j1"))
      job = { relative: "conversations/c/artifacts/j1", path: File.join(@shared, "conversations", "c", "artifacts", "j1") }
      allow(Monadic::Workbench::ChatOutput).to receive(:run_folder).and_return(job)

      result = act(:browser_screenshot)

      expect(result[:screenshot]).to eq("conversations/c/artifacts/j1/shot.png")
      expect(File.binread(File.join(@shared, result[:screenshot]))).to eq(png)
      expect(result[:work_screen]).to include("show_on_workbench")
      expect(Dir.children(@shared).sort).to eq(["conversations", result[:_image]].sort)
    end

    it "removes the model's images that were never read, when they are old" do
      stale = File.join(@shared, "#{prefix}1_aaaa.png")
      File.binwrite(stale, png)
      past = Time.now - Monadic::Utils::ToolImageUtils::FOR_MODEL_MAX_AGE - 1
      File.utime(past, past, stale)
      place(open_browser)

      act(:browser_scroll)

      expect(File.exist?(stale)).to be false
    end
  end

  ACTIONS.each do |tool, args|
    it "#{tool} gives the model the screenshot and leaves it out of the chat" do
      place(open_browser)
      result = act(tool, **args)
      expect(result[:_image]).to eq("shot.png")
      expect(result).not_to have_key(:screenshot)
      expect(result).not_to have_key(:gallery_html)
      expect(result[:work_screen]).to include("the chat does not show it")
    end
  end

  it "leaves the screenshot out of the chat also when the browser is not on the work screen" do
    open_browser
    result = act
    expect(result).not_to have_key(:gallery_html)
    expect(result[:_image]).to eq("shot.png")
  end

  describe "#start_browser" do
    before do
      app.mock_response = JSON.generate(success: true, session_id: "wd-new", screenshot: "start.png", page_info: {})
    end

    it "gives the model the screenshot and leaves it out of the chat" do
      allow(Monadic::WorkScreen).to receive(:browser_opened).and_return(nil)
      result = Monadic::Workspace::RequestContext.with(request) { app.start_browser(url: "https://example.com") }
      expect(result[:_image]).to eq("start.png")
      expect(result).not_to have_key(:gallery_html)
      expect(result[:work_screen]).to include("the chat does not show it")
    end

    it "says the browser is not on a full work screen, not that the user sees it there" do
      allow(Monadic::WorkScreen).to receive(:browser_opened).and_return(:full)
      result = Monadic::Workspace::RequestContext.with(request) { app.start_browser(url: "https://example.com") }
      expect(result[:work_screen]).to eq(Monadic::WorkScreen::FULL_NOTE)
    end
  end

  it "capture_viewport_screenshots leaves its pictures out of the chat and says how to show one" do
    allow(owner).to receive(:with_job).and_yield
    app.mock_response = "SUCCESS: captured\n- v1.png\n"
    result = Monadic::Workspace::RequestContext.with(request) { app.capture_viewport_screenshots(url: "https://example.com") }
    expect(result[:success]).to be(true)
    expect(result[:screenshots]).to eq(["v1.png"])
    expect(result).not_to have_key(:gallery_html)
    expect(result[:work_screen]).to include("show_on_workbench")
  end

  it "capture_viewport_screenshots shows what it kept in the chat's folder on the work screen, the first one in view" do
    allow(owner).to receive(:with_job).and_yield
    app.mock_response = "SUCCESS: captured\n- v1.png\n- v2.png\n"
    allow(app).to receive(:keep_captures) { |names, *| names.map { |name| "conversations/c/artifacts/j1/#{name}" } }
    shown = []
    allow(Monadic::Workbench::ChatOutput).to receive(:show) { |path, _| shown << path }

    result = Monadic::Workspace::RequestContext.with(request) { app.capture_viewport_screenshots(url: "https://example.com") }

    expect(shown).to eq(["conversations/c/artifacts/j1/v2.png", "conversations/c/artifacts/j1/v1.png"])
    expect(result[:work_screen]).to include("shown on the work screen")
    expect(result[:work_screen]).not_to include("show_on_workbench")
  end
end
