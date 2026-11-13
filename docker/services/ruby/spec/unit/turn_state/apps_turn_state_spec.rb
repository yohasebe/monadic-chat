# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/turn_state"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"
require_relative "../../../lib/monadic/substitution/vocabulary"
require_relative "../../../lib/monadic/utils/tool_image_utils"
require_relative "../../../apps/translate/translate_tools"
require_relative "../../../apps/research_assistant/research_assistant_tools"

# The Monadic apps keep their state by turn: a list's entries are items of
# their own (deleting the turn that added one takes it back), the rest of
# the state a value; what reads the state (a notebook's name, the image
# used last) reads it however the app keeps it.
RSpec.describe "the Monadic apps' state by turn" do
  around do |example|
    Dir.mktmpdir("apps-turn-state") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:app) { "TranslateOpenAI" }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app } }
  end

  before do
    Monadic::TurnState.reset!
    WebSocketHelper::Replies.reset!
    stub_const("APPS", { app => double(settings: { turn_state: true }) })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
  end

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

  def delete(message)
    session[:messages].delete(message)
    Monadic::TurnState.changed!(chat)
  end

  describe "Translate's vocabulary" do
    let(:translate) do
      Class.new do
        include TranslateTools

        def set_context_panel_field(**) = nil
        def add_to_context_panel(**) = nil
        def clear_context_panel_field(**) = nil
      end.new
    end

    def vocabulary
      JSON.parse(translate.load_translation_context(session: session))["data"]["vocabulary"]
    end

    it "keeps each entry apart: deleting the turn that added one takes it back, and the others stay" do
      first = run_reply { translate.add_vocabulary_entry(original_text: "猫", translation: "cat", session: session) }
      second = run_reply { translate.add_vocabulary_entry(original_text: "犬", translation: "dog", session: session) }
      expect(second["state_changes"].map { |c| c["data"]&.dig("original_text") }.compact).to eq(["犬"])

      delete(first)
      expect(vocabulary).to eq([{ "original_text" => "犬", "translation" => "dog" }])
    end

    it "changes an entry in place, and takes the change back with its turn" do
      run_reply { translate.add_vocabulary_entry(original_text: "猫", translation: "cat", session: session) }
      change = run_reply { translate.add_vocabulary_entry(original_text: "猫", translation: "kitty", session: session) }
      expect(vocabulary).to eq([{ "original_text" => "猫", "translation" => "kitty" }])
      delete(change)
      expect(vocabulary).to eq([{ "original_text" => "猫", "translation" => "cat" }])
    end

    it "clears the vocabulary by removing each entry, which deleting that turn brings back" do
      run_reply { translate.add_vocabulary_entry(original_text: "猫", translation: "cat", session: session) }
      cleared = run_reply { translate.clear_vocabulary(session: session) }
      expect(vocabulary).to eq([])
      delete(cleared)
      expect(vocabulary).to eq([{ "original_text" => "猫", "translation" => "cat" }])
    end

    it "turns the vocabulary of a file of an earlier version into items once, keeping their ids" do
      session[:monadic_state] = {
        app => { "translation_context" => { data: { "source_lang" => "Japanese", "target_lang" => "English",
                                                    "vocabulary" => [{ "original_text" => "猫", "translation" => "cat" }] },
                                            version: 1, updated_at: nil } }
      }
      expect(vocabulary).to eq([{ "original_text" => "猫", "translation" => "cat" }])
      ids = session[:monadic_state][app]["_ids"][:data]["vocabulary"]
      expect(vocabulary.size).to eq(1)
      expect(session[:monadic_state][app]["_ids"][:data]["vocabulary"]).to eq(ids)
      run_reply { translate.add_vocabulary_entry(original_text: "犬", translation: "dog", session: session) }
      expect(vocabulary.map { |v| v["original_text"] }).to eq(%w[猫 犬])
    end
  end

  describe "Research Assistant's lists" do
    let(:app) { "ResearchAssistantOpenAI" }
    let(:research) { Class.new { include ResearchAssistantSessionState }.new }

    def progress
      JSON.parse(research.load_research_progress(session: session))["data"]
    end

    it "keeps each finding apart, and the topic as a value" do
      first = run_reply { research.add_finding(finding: "A", source: "s1", session: session) }
      run_reply { research.add_finding(finding: "B", session: session) }
      run_reply do
        research.save_research_progress(message: "m", current_topic: "T", session: session)
      end
      delete(first)
      expect(progress["findings"]).to eq(["B"])
      expect(progress["sources"]).to eq([])
      expect(progress["current_topic"]).to eq("T")
    end
  end

  describe "an app that does not keep its state by turn" do
    it "reads and saves the whole state as one value, as before" do
      stub_const("APPS", { app => double(settings: {}) })
      tools = Class.new { include Monadic::SharedTools::MonadicSessionState }.new
      tools.monadic_save_record(key: "ctx", lists: { "items" => nil }, payload: { "a" => 1, "items" => ["x"] }, session: session)
      expect(session[:monadic_state][app]["ctx"][:data]).to eq({ "a" => 1, "items" => ["x"] })
      expect(JSON.parse(tools.monadic_load_record(key: "ctx", lists: { "items" => nil }, session: session))["data"])
        .to eq({ "a" => 1, "items" => ["x"] })
    end
  end

  describe "what reads the app's state" do
    let(:app) { "JupyterNotebookOpenAI" }

    it "finds the notebook a turn named, and none once that turn is deleted" do
      tools = Class.new { include Monadic::SharedTools::MonadicSessionState }.new
      named = run_reply { tools.monadic_save_state(key: "context", payload: { "notebook_filename" => "a.ipynb" }, session: session) }
      expect(Monadic::Substitution::Vocabulary.current_notebook(session)).to eq("a.ipynb")
      delete(named)
      expect(Monadic::Substitution::Vocabulary.current_notebook(session)).to be_nil
    end

    it "reuses the image the app's state names, never a key the session kept from a deleted turn" do
      tools = Class.new { include Monadic::SharedTools::MonadicSessionState }.new
      used = run_reply { tools.monadic_save_state(key: "last_images", payload: ["in.png"], session: session) }
      session[:grok_last_video_image] = "in.png"
      expect(Monadic::Utils::ToolImageUtils.materialize_session_image(session, last_image_key: :grok_last_video_image)).to eq("in.png")
      delete(used)
      expect(Monadic::Utils::ToolImageUtils.materialize_session_image(session, last_image_key: :grok_last_video_image)).to be_nil
    end

    it "reads the session's state as before for an app that does not keep it by turn" do
      stub_const("APPS", { app => double(settings: {}) })
      session[:monadic_state] = { app => { context: { data: { "notebook_filename" => "b.ipynb" } } } }
      session[:grok_last_video_image] = "old.png"
      expect(Monadic::Substitution::Vocabulary.current_notebook(session)).to eq("b.ipynb")
      expect(Monadic::Utils::ToolImageUtils.materialize_session_image(session, last_image_key: :grok_last_video_image)).to eq("old.png")
    end
  end
end
