# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/turn_state"
require_relative "../../../lib/monadic/workbench/document"
require_relative "../../../lib/monadic/history/serializer"
require_relative "../../../apps/novel_writer/novel_writer_tools"

# Novel Writer keeps its story's settings, its characters (one item each)
# and the amount written by turn: deleting a turn takes back what it
# changed, and the amount is counted from the story's sections.
RSpec.describe "Novel Writer's state by turn" do
  around do |example|
    Dir.mktmpdir("novel-writer-turn-state") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:app) { "NovelWriterOpenAI" }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app } }
  end
  let(:writer) { Class.new { include NovelWriterTools }.new }

  before do
    Monadic::TurnState.reset!
    Monadic::Workbench::Made.reset!
    Monadic::Workbench::Shown.reset!
    WebSocketHelper::Replies.reset!
    stub_const("APPS", { app => double(settings: { turn_state: true }) })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def run_reply
    request_id = Monadic::Workspace::Ids.generate(:request)
    handle, = WebSocketHelper::Replies.open(request_id: request_id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    @reply = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat),
                                            request_id: request_id, session: session, tab: "tab-1", generation: 1)
  end

  def finish
    request_id = @reply.request_id
    message = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => "ok" }
    made = Monadic::Workbench::Made.clean(Monadic::Workbench::Made.seal(request_id))
    message["workbench_made"] = made if made
    changes = Monadic::TurnState.seal(request_id, session)
    message["state_changes"] = changes if changes
    session[:messages] << { "mid" => SecureRandom.hex(4), "role" => "user", "text" => "go" } << message
    Monadic::TurnState.close(request_id)
    @reply = nil
    message
  end

  def delete(message)
    session[:messages].delete(message)
    Monadic::TurnState.changed!(chat)
  end

  def context
    JSON.parse(writer.load_novel_context(session: session))["data"]
  end

  def write_section(section, text)
    Monadic::Workbench::Document.write(session: session, workbench: @reply, app_name: app, document: "The Story",
                                       section: section, content: text)
  end

  it "takes back a character with the turn that added it, though a later turn changed the settings" do
    run_reply
    writer.save_novel_context(grand_plot: "A voyage", total_text_amount: 100, session: session)
    writer.add_character(name: "Ann", specification: "a sailor", role: "hero", session: session)
    t1 = finish
    run_reply
    writer.update_summary(summary: "They sail.", session: session)
    finish
    expect(context["characters"]).to eq("Ann" => { "specification" => "a sailor", "role" => "hero" })
    expect(context["summary_so_far"]).to eq("They sail.")

    delete(t1)
    expect(context["characters"]).to eq({})
    expect(context["summary_so_far"]).to eq("They sail.")
  end

  it "keeps only the characters that changed when they are given in full" do
    run_reply
    writer.add_character(name: "Ann", specification: "a sailor", role: "hero", session: session)
    writer.add_character(name: "Bob", specification: "a cook", role: "friend", session: session)
    finish
    run_reply
    writer.save_novel_context(characters: { "Ann" => { "specification" => "a sailor", "role" => "hero" },
                                            "Cid" => { "specification" => "a pirate", "role" => "foe" } },
                              session: session)
    t2 = finish
    expect(t2["state_changes"].map { |c| [c["op"], c.dig("data", "name")] })
      .to contain_exactly(["set", "Cid"], ["remove", nil])
    expect(context["characters"].keys).to eq(%w[Ann Cid])
    delete(t2)
    expect(context["characters"].keys).to eq(%w[Ann Bob])
  end

  it "counts what is written from the story's sections, headings left out, and takes back a deleted turn's section" do
    run_reply
    writer.save_novel_context(total_text_amount: 10, session: session)
    write_section("1", "# Chapter One\n\none two three four five")
    writer.update_progress(new_text: "one two three four five", session: session)
    expect(context).to include("text_amount_so_far" => 5, "progress" => "50%")
    finish
    run_reply
    write_section("2", "six seven")
    t2 = finish
    expect(context).to include("text_amount_so_far" => 7, "progress" => "70%")
    delete(t2)
    expect(context).to include("text_amount_so_far" => 5)

    run_reply
    writer.update_progress(new_text: "", use_chars: true, session: session)
    finish
    expect(context["text_amount_so_far"]).to eq("onetwothreefourfive".size)
  end

  it "makes the characters of a file of an earlier version items of the base once, with the same ids after the history" do
    session[:monadic_state] = { app => { "novel_context" => { data: { "grand_plot" => "Old", "characters" => {
      "Ann" => { "specification" => "a sailor", "role" => "hero" }
    } }, version: 3, updated_at: nil } } }
    expect(context).to include("grand_plot" => "Old", "characters" => { "Ann" => { "specification" => "a sailor", "role" => "hero" } })
    ids = session[:monadic_state][app]["_ids"][:data]["characters"]
    run_reply
    writer.add_character(name: "Bob", specification: "a cook", role: "friend", session: session)
    finish

    payload = Monadic::History::Serializer.payload(session)
    resumed = session.merge(messages: payload["messages"],
                            monadic_state: Monadic::TurnState::Form.to_session(Monadic::TurnState::Form.clean_base(payload["monadic_state"]).first))
    Monadic::TurnState.changed!(chat)
    expect(JSON.parse(writer.load_novel_context(session: resumed))["data"]["characters"].keys).to eq(%w[Ann Bob])
    expect(resumed[:monadic_state][app]["_ids"][:data]["characters"]).to eq(ids)
  end
end
