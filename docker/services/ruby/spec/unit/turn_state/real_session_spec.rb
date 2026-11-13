# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "rack"
require "rack/session/pool"
require_relative "../../../lib/monadic/utils/unlimited_session_store"
require_relative "../../../lib/monadic/shared_tools/session_context"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"
require_relative "../../../lib/monadic/turn_state/notes"
require_relative "../../../lib/monadic/substitution/vocabulary"
require_relative "../../../lib/monadic/workbench/outputs"

# The session of a real chat is the object the app's session middleware
# (config.ru) makes, which is not a Hash: an app's state is kept and read
# with it as with a Hash.
RSpec.describe "An app's state with the session a real chat has" do
  around do |example|
    Dir.mktmpdir("real-session-state") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:app_name) { "TestApp" }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:app) { Class.new { include MonadicSharedTools::SessionContext }.new }
  let(:tools) { Class.new { include Monadic::SharedTools::MonadicSessionState }.new }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:session) do
    real_session(Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app_name })
  end

  # The session object of a request through the same middleware as config.ru.
  def real_session(values)
    made = nil
    inner = lambda do |env|
      made = env["rack.session"]
      values.each { |k, v| made[k] = v }
      [200, {}, ["ok"]]
    end
    Rack::Session::CappedPool.new(inner, key: "monadic.session").call(Rack::MockRequest.env_for("/"))
    made
  end

  before do
    Monadic::TurnState.reset!
    Monadic::Workbench::Board.reset!
    stub_const("APPS", { app_name => app })
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  # A reply that runs the block and is saved with what it changed.
  def run_reply
    request_id = Monadic::Workspace::Ids.generate(:request)
    @reply = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat),
                                            request_id: request_id, session: session, tab: "tab-1", generation: 1)
    result = yield
    message = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => "ok" }
    changes = Monadic::TurnState.seal(request_id, session)
    message["state_changes"] = changes if changes
    session[:messages] << { "mid" => SecureRandom.hex(4), "role" => "user", "text" => "go" } << message
    Monadic::TurnState.close(request_id)
    @reply = nil
    [result, message]
  end

  it "is not a Hash" do
    expect(session).not_to be_a(Hash)
  end

  it "keeps what a reply changed, and reads it back after the reply" do
    result, message = run_reply { app.update_context(topics: ["AI"], session: session) }

    expect(result).to include(success: true)
    expect(message["state_changes"].size).to eq(1)
    expect(app.get_context(session: session)[:context]["topics"]).to eq(["AI"])
  end

  it "takes back what a deleted turn changed" do
    _, first = run_reply { app.update_context(topics: ["AI"], session: session) }
    run_reply { app.update_context(topics: ["Ruby"], session: session) }

    index = session[:messages].index(first)
    session[:messages].slice!(index - 1, 2)
    Monadic::TurnState.changed!(chat)

    expect(app.get_context(session: session)[:context]["topics"]).to eq(["Ruby"])
  end

  it "shows the state as a page on the work screen" do
    run_reply { app.update_context(topics: ["AI"], session: session) }

    path = Monadic::TurnState::Notes.refresh(session, show: true, tab: "tab-1")

    expect(path).to end_with("notes/context.md")
    expect(File.read(File.join(@data, path))).to include("- AI (turn 1)")
    expect(Monadic::TurnState::Notes.current(session)).to eq(path)
  end

  it "selects the page for the tab it was shown for, once" do
    run_reply { app.update_context(topics: ["AI"], session: session) }
    path = Monadic::TurnState::Notes.refresh(session, show: true, tab: "tab-1")
    board = Monadic::Workbench::Board.for(chat)
    item = board.snapshot[:items].find { |i| i[:path] == path }
    first = board.selection(tab: "tab-1", generation: nil)

    run_reply { app.update_context(topics: ["Ruby"], session: session) }
    Monadic::TurnState::Notes.refresh(session, show: true, tab: "tab-1")

    expect(first.first).to eq(item[:id])
    expect(board.selection(tab: "tab-1", generation: nil)).to eq(first)
    expect(board.snapshot[:items].count { |i| i[:path] == path }).to eq(1)
  end

  it "selects a page already there for a tab that shows nothing" do
    run_reply { app.update_context(topics: ["AI"], session: session) }
    path = Monadic::TurnState::Notes.refresh(session, show: true, tab: "tab-1")
    board = Monadic::Workbench::Board.for(chat)
    item = board.snapshot[:items].find { |i| i[:path] == path }

    run_reply { app.update_context(topics: ["Ruby"], session: session) }
    Monadic::TurnState::Notes.refresh(session, show: true, tab: "tab-2")

    expect(board.selected(tab: "tab-2", generation: nil)).to eq(item[:id])
  end

  it "gives a value of the state to what reads it outside the tools" do
    run_reply { tools.monadic_save_state(key: "context", payload: { "notebook_filename" => "a.ipynb" }, session: session) }

    expect(Monadic::Substitution::Vocabulary.current_notebook(session)).to eq("a.ipynb")
  end
end
