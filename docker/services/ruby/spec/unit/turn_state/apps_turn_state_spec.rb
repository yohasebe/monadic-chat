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
require_relative "../../../apps/language_practice_plus/language_practice_plus_tools"
require_relative "../../../apps/voice_interpreter/voice_interpreter_tools"
require_relative "../../../lib/monadic/turn_state/notes"

# The Monadic apps keep their state by turn: a list's entries are items of
# their own (deleting the turn that added one takes it back), the rest of
# the state a value; what reads the state (a notebook's name, the image
# used last) reads what the turns left in the chat changed.
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
    stub_const("APPS", { app => double(settings: {}) })
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
      Class.new { include TranslateTools }.new
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

  describe "Language Practice Plus's advice" do
    let(:app) { "LanguagePracticePlusOpenAI" }
    let(:practice) { Class.new { include LanguagePracticePlusTools }.new }

    def advice
      Monadic::TurnState.items(session, "language_advice").map { |item| item[:data] }
    end

    it "adds each turn's advice to the log, which the model does not read back, and takes a turn's advice back with it" do
      first = run_reply do
        practice.save_response(message: "Bonjour", target_lang: "French", language_advice: ["Say 'tu' to a friend"], session: session)
      end
      run_reply { practice.save_response(message: "Bien", language_advice: ["'bien' is an adverb", "Say 'tu' to a friend"], session: session) }

      expect(advice).to eq(["Say 'tu' to a friend", "'bien' is an adverb"])
      loaded = JSON.parse(practice.load_context(session: session))["data"]
      expect(loaded).to eq("target_lang" => "French", "last_message" => "Bien")

      delete(first)
      expect(advice).to eq(["'bien' is an adverb"])
    end

    it "keeps advice given as objects as texts, and the message without its speech directive" do
      run_reply do
        practice.save_response(message: "<<TTS:Voice: warm.>>\nGood try!", target_lang: "English",
                               language_advice: [{ "original" => "goed", "correction" => "went", "explanation" => "irregular" }],
                               session: session)
      end

      expect(advice).to eq(["goed — went — irregular"])
      expect(JSON.parse(practice.load_context(session: session))["data"]["last_message"]).to eq("Good try!")
    end

    it "gives the model what load_context returns, and names that tool" do
      run_reply { practice.save_response(message: "Hola", target_lang: "Spanish", language_advice: ["Roll the r"], session: session) }

      declared = practice.send(:state_for_model, session)

      expect(declared[:load_tool]).to eq("load_context")
      expect(JSON.parse(JSON.generate(declared[:data]))).to eq(JSON.parse(practice.load_context(session: session))["data"])
    end

    it "shows the language and the advice on its notes" do
      run_reply { practice.save_response(message: "Hola", target_lang: "Spanish", language_advice: ["Roll the r"], session: session) }

      page = Monadic::TurnState::Notes.render(session, practice.send(:state_notes), practice)
      expect(page).to include("# Practice notes", "- **Language**: Spanish", "## Advice", "- Roll the r (turn 1)")
    end
  end

  describe "Voice Interpreter's phrases" do
    let(:app) { "VoiceInterpreterOpenAI" }
    let(:interpreter) { Class.new { include VoiceInterpreterTools }.new }

    def phrases
      Monadic::TurnState.items(session, "phrases").map { |item| item[:data] }
    end

    it "keeps each phrase whole with its translation in the log, once, and the languages as a value" do
      long = ("word " * 30).strip
      run_reply { interpreter.save_translation(message: long, original: "ことば", source_lang: "Japanese", target_lang: "English", session: session) }
      run_reply { interpreter.save_translation(message: long, original: "ことば", session: session) }
      run_reply { interpreter.set_target_language(target_lang: "French", session: session) }

      expect(phrases).to eq(["ことば → #{long}"])
      loaded = JSON.parse(interpreter.load_context(session: session))["data"]
      expect(loaded).to eq("source_lang" => "Japanese", "target_lang" => "French", "last_translation" => long)
      page = Monadic::TurnState::Notes.render(session, interpreter.send(:state_notes), interpreter)
      expect(page).to include("- **From**: Japanese", "- **To**: French", "## Phrases", "- ことば → #{long} (turn 1)")
    end

    it "keeps a phrase without the speech directive it was given with" do
      run_reply { interpreter.save_translation(message: "<<TTS:Voice: calm.>>\nBonjour", original: "Hello", session: session) }

      expect(phrases).to eq(["Hello → Bonjour"])
    end

    it "does not list a message of the interpreter's own as a phrase" do
      run_reply { interpreter.save_translation(message: "OK, I'll translate to English.", session: session) }

      expect(phrases).to eq([])
    end

    it "does not list words given back as they were said" do
      run_reply do
        interpreter.save_translation(message: "There\u2019s a  giant.", original: "there's a giant.", session: session)
      end

      expect(phrases).to eq([])
    end
  end

  describe "the notes of Math Tutor and Research Assistant" do
    it "show Research Assistant's topic, findings and sources" do
      session[:parameters]["app_name"] = "ResearchAssistantOpenAI"
      stub_const("APPS", { "ResearchAssistantOpenAI" => double(settings: {}) })
      research = Class.new { include ResearchAssistantSessionState }.new
      run_reply { research.add_finding(finding: "A", source: "s1", session: session) }

      page = Monadic::TurnState::Notes.render(session, research.send(:state_notes), research)
      expect(page).to include("# Research notes", "## Findings", "- A [Source: s1] (turn 1)", "## Sources", "- s1 (turn 1)")
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

    it "reuses the image a tool used, and none once that turn is deleted" do
      tools = Class.new { include Monadic::SharedTools::MonadicSessionState }.new
      used = run_reply { Monadic::Utils::ToolImageUtils.remember_image(tools, session, "work/in.png") }
      expect(Monadic::Utils::ToolImageUtils.materialize_session_image(session)).to eq("in.png")
      delete(used)
      expect(Monadic::Utils::ToolImageUtils.materialize_session_image(session)).to be_nil
    end
  end
end
