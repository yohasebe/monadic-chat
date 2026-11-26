# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/utils/app_names"
require_relative "../../../lib/monadic/turn_state/form"
require_relative "../../../lib/monadic/history/store"
require_relative "../../../lib/monadic/library/store"
require_relative "../../../lib/monadic/utils/progressive_tool_manager"

# An app that was merged into another: what was kept under its name is read
# as the other app's.
RSpec.describe Monadic::Utils::AppNames do
  let(:apps_dir) { File.expand_path("../../../apps", __dir__) }
  let(:defined_apps) { Dir.glob(File.join(apps_dir, "*", "*.mdsl")).flat_map { |f| File.read(f).scan(/^app "([^"]+)" do/) }.flatten }

  it "names an app that is defined for every former name, and no former name is still an app" do
    expect(described_class::RENAMED).not_to be_empty
    expect(described_class::RENAMED.values - defined_apps).to eq([])
    expect(described_class::RENAMED.keys & defined_apps).to eq([])
  end

  it "gives the current app for a former name and leaves every other value as it is" do
    expect(described_class.current("ChatPlusClaude")).to eq("ChatClaude")
    expect(described_class.current("ChatClaude")).to eq("ChatClaude")
    expect(described_class.current("MyChatPlusApp")).to eq("MyChatPlusApp")
    expect(described_class.current(nil)).to be_nil
  end

  it "lists an app with the names it took the place of" do
    expect(described_class.with_former("ChatClaude")).to eq(%w[ChatClaude ChatPlusClaude])
    expect(described_class.with_former("MathTutorClaude")).to eq(%w[MathTutorClaude])
  end

  it "gives Language Practice for the former Language Practice Plus" do
    expect(described_class.current("LanguagePracticePlusOpenAI")).to eq("LanguagePracticeOpenAI")
    expect(described_class.current("LanguagePracticePlusClaude")).to eq("LanguagePracticeClaude")
    expect(described_class.with_former("LanguagePracticeOpenAI")).to include("LanguagePracticeOpenAI", "LanguagePracticePlusOpenAI")
    expect(described_class.with_former("LanguagePracticeGemini")).to eq(%w[LanguagePracticeGemini])
  end

  describe "the state a chat keeps" do
    let(:form) { Monadic::TurnState::Form }
    let(:entry) { { "data" => { "topics" => ["a"] }, "version" => 1, "updated_at" => "2026-01-01T00:00:00Z" } }

    it "reads a reply's change of a former app as the current app's" do
      change = { "app" => "ChatPlusOpenAI", "kind" => "value", "key" => "context", "op" => "set", "data" => { "topics" => ["a"] } }
      expect(form.clean_changes([change]).first["app"]).to eq("ChatOpenAI")
    end

    it "reads the base of a former app as the current app's" do
      base, dropped = form.clean_base("ChatPlusOpenAI" => { "context" => entry })
      expect(base.keys).to eq(["ChatOpenAI"])
      expect(base["ChatOpenAI"].keys).to eq(["context"])
      expect(dropped).to eq(0)
    end

    it "keeps the keys of both names together, and counts a key both have" do
      base, dropped = form.clean_base("ChatOpenAI" => { "context" => entry, "own" => entry },
                                      "ChatPlusOpenAI" => { "context" => entry, "older" => entry })
      expect(base["ChatOpenAI"].keys).to contain_exactly("context", "own", "older")
      expect(dropped).to eq(1)
    end
  end

  describe "the kept chats" do
    around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }
    let(:store) { Monadic::History::Store.new(File.join(@dir, "history.sqlite3")) }

    before do
      store.save("chat_old", { "messages" => [{}] }, app_name: "ChatPlusOpenAI")
      store.save("chat_new", { "messages" => [{}] }, app_name: "ChatOpenAI")
      store.save("chat_other", { "messages" => [{}] }, app_name: "MathTutorOpenAI")
    end

    it "lists the chats of a former app under the current app, by its current name" do
      rows = store.list(app_name: "ChatOpenAI")
      expect(rows.map { |row| row["chat_id"] }).to contain_exactly("chat_old", "chat_new")
      expect(rows.map { |row| row["app_name"] }.uniq).to eq(["ChatOpenAI"])
    end

    it "names each app once among the apps of the kept chats" do
      expect(store.app_names).to eq(%w[ChatOpenAI MathTutorOpenAI])
    end
  end

  it "takes the tools a former app had unlocked as the current app's" do
    session = {}
    Monadic::Utils::ProgressiveToolManager.import_unlocked(session, { "ChatPlusGrok" => ["web_search"] })
    expect(session[:progressive_tools].keys).to eq(["ChatGrok"])
  end
end
