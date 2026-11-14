# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/turn_state"
require_relative "../../../lib/monadic/turn_state/notes"
require_relative "../../../lib/monadic/workbench/document"
require_relative "../../../apps/novel_writer/novel_writer_tools"

# An app's state as a page on the work screen: made by the server from what
# the conversation leaves, with the turn that changed each part, made again
# when a turn is deleted, and gone when nothing is left.
RSpec.describe Monadic::TurnState::Notes do
  around do |example|
    Dir.mktmpdir("turn-state-notes") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:app_name) { "NovelWriterOpenAI" }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app_name } }
  end
  let(:writer) do
    Class.new do
      include NovelWriterTools

      def settings = {}
    end.new
  end
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

  before do
    Monadic::TurnState.reset!
    Monadic::Workbench::Board.reset!
    stub_const("APPS", { app_name => writer })
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
    Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: app_name)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def run_reply
    request_id = Monadic::Workspace::Ids.generate(:request)
    @reply = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat),
                                            request_id: request_id, session: session, tab: "tab-1", generation: 1)
    yield
    message = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => "ok" }
    changes = Monadic::TurnState.seal(request_id, session)
    message["state_changes"] = changes if changes
    session[:messages] << { "mid" => SecureRandom.hex(4), "role" => "user", "text" => "go" } << message
    Monadic::TurnState.close(request_id)
    @reply = nil
    message
  end

  def page
    path = described_class.refresh(session, show: true)
    path && File.read(File.join(@data, path))
  end

  it "shows the story's settings and characters with the turn that changed each" do
    run_reply { writer.save_novel_context(grand_plot: "A quest", language: "English", session: session) }
    run_reply { writer.add_character(name: "Alice", specification: "brave", role: "hero", session: session) }

    text = page
    expect(text).to start_with("# Story notes\n")
    expect(text).to include("## Settings (turn 1)")
    expect(text).to include("- **Plot**: A quest")
    expect(text).to include("## Characters")
    expect(text).not_to include("§")
    expect(text).to include("### Alice (turn 2)\n- **Role**: hero\n- **Description**: brave")
  end

  it "begins with where the story itself is, once it has a document" do
    run_reply { writer.save_novel_context(grand_plot: "A quest", language: "English", session: session) }
    expect(page).not_to include("The story is a document")

    allow(Monadic::Workbench::Document).to receive(:titles)
      .and_return([["The Quest", "conversations/c/documents/the-quest.md"]])
    expect(page).to start_with("# Story notes\n\nThe story is a document of its own on the work screen: " \
                               "The Quest (`the-quest.md`).\n\n## Settings")
  end

  it "ends with the files the chat's replies made, by name and turn" do
    run_reply { writer.save_novel_context(grand_plot: "A quest", language: "English", session: session) }
    expect(page).not_to include("Files made in this chat")

    allow(Monadic::Workbench::Outputs).to receive(:in_chat)
      .and_return([{ path: "conversations/c/artifacts/j1/plot.png", turn: 2 }])
    expect(page).to end_with("## Files made in this chat\n\n- `plot.png` (turn 2)\n")
  end

  it "is not made of files alone" do
    allow(Monadic::Workbench::Outputs).to receive(:in_chat)
      .and_return([{ path: "conversations/c/artifacts/j1/plot.png", turn: 1 }])
    expect(described_class.refresh(session, show: true)).to be_nil
  end

  it "is made again when a turn is deleted, and goes when nothing is left" do
    run_reply { writer.save_novel_context(grand_plot: "A quest", session: session) }
    added = run_reply { writer.add_character(name: "Alice", specification: "brave", role: "hero", session: session) }
    path = described_class.refresh(session, show: true)
    expect(Monadic::Workbench::Board.for(chat).snapshot[:items].map { |i| i[:path] }).to include(path)

    session[:messages].delete(added)
    Monadic::TurnState.changed!(chat)
    expect(page).not_to include("Alice")

    session[:messages].clear
    Monadic::TurnState.changed!(chat)
    expect(described_class.refresh(session)).to be_nil
    expect(File.exist?(File.join(@data, path))).to be(false)
    expect(Monadic::Workbench::Board.for(chat).snapshot[:items].map { |i| i[:path] }).not_to include(path)
  end

  it "is not put on the work screen by a deleted turn, only made again where it is shown" do
    run_reply { writer.save_novel_context(grand_plot: "A quest", session: session) }
    path = described_class.refresh(session)
    expect(File.exist?(File.join(@data, path))).to be(true)
    expect(Monadic::Workbench::Board.existing(chat)).to be_nil.or(satisfy { |b| b.snapshot[:items].none? { |i| i[:path] == path } })
  end

  it "makes no page for an app that keeps its state otherwise, or declares none" do
    stub_const("APPS", { app_name => double(settings: { turn_state: false }) })
    expect(described_class.refresh(session, show: true)).to be_nil
    stub_const("APPS", { app_name => double(settings: {}) })
    expect(described_class.refresh(session, show: true)).to be_nil
  end
end
