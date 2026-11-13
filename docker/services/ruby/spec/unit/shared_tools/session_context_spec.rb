# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"

# Mock MonadicHelper for testing
module MonadicHelper
end

require_relative "../../../lib/monadic/shared_tools/session_context"
require_relative "../../../lib/monadic/turn_state/notes"

# The context a conversational app keeps (topics, people, notes): items of
# the app's state, changed by a running reply, taken back with its turn and
# shown as a page on the work screen.
RSpec.describe "MonadicSharedTools::SessionContext" do
  around do |example|
    Dir.mktmpdir("session-context") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:app_name) { "TestApp" }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app_name } }
  end
  let(:app) { Class.new { include MonadicSharedTools::SessionContext }.new }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

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

  def context
    app.get_context(session: session)[:context]
  end

  def delete_turn(message)
    index = session[:messages].index(message)
    session[:messages].slice!(index - 1, 2)
    Monadic::TurnState.changed!(chat)
  end

  describe "#get_context" do
    it "returns empty lists when nothing is kept" do
      result = app.get_context(session: session)

      expect(result[:success]).to be true
      expect(result[:context]).to eq("topics" => [], "people" => [], "notes" => [])
    end

    it "returns what earlier replies kept" do
      run_reply { app.update_context(topics: ["AI"], people: ["John"], notes: ["Important"], session: session) }

      expect(context).to eq("topics" => ["AI"], "people" => ["John"], "notes" => ["Important"])
    end

    it "shows the running reply its own changes" do
      result, = run_reply do
        app.update_context(topics: ["AI"], session: session)
        app.get_context(session: session)
      end

      expect(result[:context]["topics"]).to eq(["AI"])
    end
  end

  describe "#update_context" do
    it "adds to what is kept" do
      run_reply { app.update_context(topics: ["AI"], session: session) }
      result, = run_reply { app.update_context(topics: ["Ruby"], people: ["Alice"], session: session) }

      expect(result).to include(success: true, action: "merged")
      expect(result[:context]).to eq("topics" => %w[AI Ruby], "people" => ["Alice"], "notes" => [])
    end

    it "does not add a text that is kept already" do
      run_reply { app.update_context(topics: ["AI"], session: session) }
      _, message = run_reply { app.update_context(topics: ["AI", "AI", " AI "], session: session) }

      expect(context["topics"]).to eq(["AI"])
      expect(message).not_to have_key("state_changes")
    end

    it "keeps only what is given in all three fields when replace is true" do
      run_reply { app.update_context(topics: %w[Old1 Old2], people: ["OldPerson"], notes: ["Old"], session: session) }
      result, = run_reply { app.update_context(topics: ["New"], replace: true, session: session) }

      expect(result).to include(success: true, action: "replaced")
      expect(context).to eq("topics" => ["New"], "people" => [], "notes" => [])
    end

    it "changes nothing when nothing is given" do
      run_reply { app.update_context(topics: ["AI"], session: session) }
      result, = run_reply { app.update_context(session: session) }

      expect(result[:success]).to be true
      expect(context["topics"]).to eq(["AI"])
    end
  end

  describe "#remove_from_context" do
    before do
      run_reply do
        app.update_context(topics: %w[AI Ruby Python], people: %w[John Alice], notes: %w[Note1 Note2], session: session)
      end
    end

    it "removes the texts given and leaves the others" do
      result, = run_reply { app.remove_from_context(topics: ["Ruby"], people: ["John"], notes: ["Note1"], session: session) }

      expect(result).to include(success: true, action: "removed")
      expect(context).to eq("topics" => %w[AI Python], "people" => ["Alice"], "notes" => ["Note2"])
    end

    it "changes nothing for a text that is not kept" do
      _, message = run_reply { app.remove_from_context(topics: ["NonExistent"], session: session) }

      expect(context["topics"]).to eq(%w[AI Ruby Python])
      expect(message).not_to have_key("state_changes")
    end
  end

  describe "#clear_context" do
    it "removes everything" do
      run_reply { app.update_context(topics: ["AI"], people: ["John"], notes: ["Note"], session: session) }
      result, = run_reply { app.clear_context(session: session) }

      expect(result[:success]).to be true
      expect(context).to eq("topics" => [], "people" => [], "notes" => [])
    end
  end

  describe "a deleted turn" do
    it "takes back what the turn added and leaves the rest" do
      _, first = run_reply { app.update_context(topics: ["AI"], session: session) }
      run_reply { app.update_context(topics: ["Ruby"], session: session) }

      delete_turn(first)

      expect(context["topics"]).to eq(["Ruby"])
    end

    it "brings back what the turn removed" do
      run_reply { app.update_context(notes: %w[Keep Gone], session: session) }
      _, removal = run_reply { app.remove_from_context(notes: ["Gone"], session: session) }

      delete_turn(removal)

      expect(context["notes"]).to eq(%w[Keep Gone])
    end

    it "brings back everything a clearing turn removed" do
      run_reply { app.update_context(topics: ["AI"], people: ["John"], session: session) }
      _, clearing = run_reply { app.clear_context(session: session) }

      delete_turn(clearing)

      expect(context).to eq("topics" => ["AI"], "people" => ["John"], "notes" => [])
    end

    it "keeps one item when a removed text is added again and the removing turn is deleted" do
      run_reply { app.update_context(topics: ["AI"], session: session) }
      _, removal = run_reply { app.remove_from_context(topics: ["AI"], session: session) }
      run_reply { app.update_context(topics: ["AI"], session: session) }

      delete_turn(removal)

      expect(context["topics"]).to eq(["AI"])
    end
  end

  describe "a change that cannot be made" do
    it "is refused outside a running reply, and says so" do
      result = app.update_context(topics: ["AI"], session: session)

      expect(result[:success]).to be false
      expect(result[:error]).to start_with("Nothing was changed")
      expect(context["topics"]).to eq([])
    end

    it "makes none of one call's changes when they are more than a reply may make" do
      many = Array.new(Monadic::TurnState::Form::ENTRIES + 1) { |i| "topic #{i}" }
      result, message = run_reply do
        app.update_context(notes: ["kept"], session: session)
        app.update_context(topics: many, session: session)
      end

      expect(result[:success]).to be false
      expect(context).to eq("topics" => [], "people" => [], "notes" => ["kept"])
      expect(message["state_changes"].size).to eq(1)
    end
  end

  describe "the page on the work screen" do
    it "shows the context with the turn that added each text" do
      run_reply { app.update_context(topics: ["AI"], session: session) }
      run_reply { app.update_context(people: ["John - engineer"], session: session) }

      path = Monadic::TurnState::Notes.refresh(session, show: true)
      page = File.read(File.join(@data, path))

      expect(path).to end_with("notes/context.md")
      expect(page).to include("## Topics", "- AI (turn 1)", "## People", "- John - engineer (turn 2)")
      expect(page).not_to include("## Notes")
      expect(Monadic::TurnState::Notes.current(session)).to eq(path)
    end

    it "is not made, and its folder neither, while nothing is kept" do
      expect(Monadic::TurnState::Notes.refresh(session, show: true)).to be_nil
      expect(Monadic::Workspace::Folders.lookup(session)).to be_nil
      expect(Monadic::TurnState::Notes.current(session)).to be_nil
    end
  end
end
