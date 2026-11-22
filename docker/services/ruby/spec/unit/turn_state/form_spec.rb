# frozen_string_literal: true

require_relative "../../spec_helper"
require "json"
require_relative "../../../lib/monadic/turn_state/form"
require_relative "../../../lib/monadic/history/serializer"
require_relative "../../../lib/monadic/utils/websocket/privacy_handler"

# The form of an app's state as a chat keeps it: a reply's changes and the
# base the chat began with, checked the same way wherever they come from.
RSpec.describe Monadic::TurnState::Form do
  let(:value) { { "app" => "NovelWriterOpenAI", "kind" => "value", "key" => "novel_context", "op" => "set", "data" => { "plot" => "x" } } }
  let(:item) { { "app" => "NovelWriterOpenAI", "kind" => "item", "collection" => "characters", "id" => "c_1", "op" => "set", "data" => { "name" => "Ann" } } }
  let(:removed) { { "app" => "NovelWriterOpenAI", "kind" => "item", "collection" => "characters", "id" => "c_1", "op" => "remove" } }

  describe ".clean_changes" do
    it "keeps values, items and removals in their checked, frozen form" do
      kept = described_class.clean_changes([value, item, removed])
      expect(kept).to eq([value, item, removed])
      expect(kept).to be_frozen
      expect(kept.first["data"]).to be_frozen
    end

    it "keeps null, false and empty data as values, apart from a removal" do
      [nil, false, {}, [], ""].each do |data|
        expect(described_class.clean_changes([value.merge("data" => data)]).first["data"]).to eq(data)
      end
      expect(described_class.clean_changes([removed]).first).not_to have_key("data")
    end

    it "takes symbols as text and copies what it keeps" do
      source = { "plot" => +"x" }
      kept = described_class.clean_changes([value.merge("data" => source)])
      source["plot"] << "y"
      expect(kept.first["data"]).to eq("plot" => "x")
      expect(described_class.clean_changes([value.merge("data" => { name: :ann })]).first["data"]).to eq("name" => "ann")
    end

    it "refuses the whole list when one change does not fit its form" do
      bad = [
        value.merge("app" => "privacy"), value.merge("app" => "../x"), value.merge("kind" => "file"),
        value.merge("op" => "merge"), value.merge("key" => "Novel Context"), value.merge("key" => "_items"),
        value.merge("collection" => "characters"), item.merge("id" => "Ann"), item.merge("key" => "x"),
        removed.merge("data" => {}), value.reject { |k, _| k == "data" }, value.merge("data" => Object.new),
        value.merge("data" => Float::NAN), value.merge("data" => { 1 => "x" }), value.merge("data" => { "k" * 201 => 1 }),
        "not a change"
      ]
      bad.each { |change| expect(described_class.clean_changes([value, change])).to be_nil, change.inspect }
      expect(described_class.clean_changes([])).to be_nil
      expect(described_class.clean_changes("x")).to be_nil
    end

    it "refuses changes too deep, too many or too large" do
      deep = (0..described_class::DEPTH + 1).reduce("x") { |inner, _| { "a" => inner } }
      expect(described_class.clean_changes([value.merge("data" => deep)])).to be_nil
      expect(described_class.clean_changes([value] * (described_class::ENTRIES + 1))).to be_nil
      big = value.merge("data" => "x" * described_class::SAVE_BYTES)
      expect(described_class.clean_changes([big], limit: described_class::SAVE_BYTES)).to be_nil
      expect(described_class.clean_changes([big])).not_to be_nil
    end
  end

  describe ".clean_base" do
    it "keeps the app state a chat began with, leaves out and counts what does not fit, and never the reserved names" do
      state = {
        "MyApp" => { "notes" => { data: %w[x], version: 2, updated_at: "t" }, "bad key" => { data: 1 },
                     "nodata" => { version: 1 }, "_items" => { "data" => { "characters" => {} } } },
        :privacy => { registry: { "<<P>>" => "secret" } },
        "context_schema" => { "fields" => [] },
        "conversation_context" => { "topics" => [{ "text" => "x", "turn" => 1 }] },
        "../x" => { "a" => { data: 1 } }
      }
      base, dropped = described_class.clean_base(state)
      expect(base).to eq("MyApp" => { "notes" => { "data" => %w[x], "version" => 2, "updated_at" => "t" },
                                       "_items" => { "data" => { "characters" => {} }, "version" => 0 } })
      expect(dropped).to eq(3)
      expect(described_class.clean_base(nil)).to eq([nil, 0])
    end

    it "gives a session the base in the form its app state is kept in" do
      base, = described_class.clean_base("MyApp" => { "notes" => { "data" => { "a" => 1 }, "version" => 1 } })
      session_form = described_class.to_session(base)
      expect(session_form).to eq("MyApp" => { "notes" => { data: { "a" => 1 }, version: 1, updated_at: nil } })
      session_form["MyApp"]["notes"][:data]["b"] = 2
      expect(base["MyApp"]["notes"]["data"]).to eq("a" => 1)
    end
  end

  describe "the history" do
    it "keeps a reply's changes and the base, in their checked form" do
      session = {
        messages: [{ "role" => "user", "text" => "go" },
                   { "role" => "assistant", "text" => "ok", "state_changes" => [value] },
                   { "role" => "assistant", "text" => "bad", "state_changes" => [value.merge("app" => "privacy")] }],
        monadic_state: { "MyApp" => { "notes" => { data: 1, version: 1 } }, privacy: { registry: {} } }
      }
      payload = Monadic::History::Serializer.payload(session)
      expect(payload["messages"][1]["state_changes"]).to eq([value])
      expect(payload["messages"][2]).not_to have_key("state_changes")
      expect(payload["monadic_state"]).to eq("MyApp" => { "notes" => { "data" => 1, "version" => 1 } })
      expect(payload["turn_state_schema"]).to eq(described_class::SCHEMA)
    end
  end

  describe "a shared file" do
    let(:exporter) { Class.new { include WebSocketHelper }.new }

    it "keeps a reply's changes in their checked form" do
      messages = [{ "role" => "assistant", "text" => "ok", "state_changes" => [value, { "app" => "privacy" }] },
                  { "role" => "assistant", "text" => "ok", "state_changes" => [item] }]
      cleaned = exporter.send(:privacy_clean_messages, messages)
      expect(cleaned[0]).not_to have_key("state_changes")
      expect(cleaned[1]["state_changes"]).to eq([item])
    end

    it "masks the data of a reply's changes, its names among it, and keeps their form" do
      registry = { "<<PERSON_1>>" => "Ann Lee" }
      change = item.merge("data" => { "Ann Lee" => { "role" => "friend of Ann Lee" } })
      masked = exporter.send(:privacy_mask_messages_everywhere, [{ "role" => "assistant", "state_changes" => [change, removed] }], registry)
      expect(masked.first["state_changes"]).to eq([
        item.merge("data" => { "<<PERSON_1>>" => { "role" => "friend of <<PERSON_1>>" } }),
        removed
      ])
    end
  end
end
