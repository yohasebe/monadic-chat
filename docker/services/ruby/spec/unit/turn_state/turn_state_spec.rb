# frozen_string_literal: true

require_relative "../../spec_helper"
require "json"
require_relative "../../../lib/monadic/turn_state"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"
require_relative "../../../lib/monadic/history/serializer"

# An app's state made from what each reply changed: kept with the reply's
# message, so deleting a turn takes its changes back.
RSpec.describe Monadic::TurnState do
  let(:ts) { described_class }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:app) { "NovelWriterOpenAI" }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => app } }
  end
  let(:tools) { Class.new { include Monadic::SharedTools::MonadicSessionState }.new }

  before do
    ts.reset!
    stub_const("APPS", { app => double(settings: {}) })
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
  end

  # A reply of the chat running now (nil: none).
  def run_reply(chat_id = chat)
    @reply = Monadic::Workbench::Caller.new(chat_id: chat_id, epoch: Monadic::Workspace::Chats.epoch(chat_id),
                                            request_id: Monadic::Workspace::Ids.generate(:request), session: session)
    @reply.request_id
  end

  # The running reply ends with its message, as the server records it.
  def finish(text = "ok")
    request_id = @reply.request_id
    changes = ts.seal(request_id, session)
    message = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => text }
    message["state_changes"] = changes if changes
    session[:messages] << { "mid" => SecureRandom.hex(4), "role" => "user", "text" => "go" } << message
    ts.close(request_id)
    @reply = nil
    message
  end

  # A turn: the user's message and the reply, deleted as the page does.
  def delete(message)
    session[:messages].delete(message)
    ts.changed!(chat)
  end

  def load(key, default = nil)
    JSON.parse(tools.monadic_load_state(key: key, default: default, session: session))
  end

  def save(key, payload)
    JSON.parse(tools.monadic_save_state(key: key, payload: payload, session: session))
  end

  def names
    JSON.parse(tools.monadic_load_items(collection: "characters", session: session))["items"].map { |i| i["data"]["name"] }
  end

  def put(name, id: nil)
    JSON.parse(tools.monadic_put_item(collection: "characters", id: id, data: { "name" => name }, session: session))["id"]
  end

  describe "a value" do
    it "is seen by the reply that changed it at once, by others once its message has it, and taken back with its turn" do
      run_reply
      save("novel_context", { "plot" => "v1" })
      expect(load("novel_context")["data"]).to eq("plot" => "v1")
      t1 = finish
      expect(t1["state_changes"]).to eq([{ "app" => app, "kind" => "value", "key" => "novel_context", "op" => "set",
                                           "data" => { "plot" => "v1" } }])
      expect(load("novel_context")).to include("data" => { "plot" => "v1" }, "version" => 1)

      run_reply
      save("novel_context", { "plot" => "v2" })
      t2 = finish
      expect(load("novel_context")).to include("data" => { "plot" => "v2" }, "version" => 2)

      delete(t2)
      expect(load("novel_context")["data"]).to eq("plot" => "v1")
      delete(t1)
      expect(load("novel_context", "none")["data"]).to eq("none")
    end

    it "keeps what a later turn carried over when an earlier turn is deleted (the newest value of a key wins)" do
      run_reply
      save("novel_context", { "plot" => "p", "progress" => "0%" })
      t1 = finish
      run_reply
      save("novel_context", { "plot" => "p", "progress" => "50%" })
      finish
      delete(t1)
      expect(load("novel_context")["data"]).to eq("plot" => "p", "progress" => "50%")
    end

    it "is a value when null, false or empty, and a removal stops the base from showing through until its turn goes" do
      session[:monadic_state] = { app => { "novel_context" => { data: { "plot" => "base" }, version: 1, updated_at: nil } } }
      expect(load("novel_context")["data"]).to eq("plot" => "base")
      [nil, false, {}].each do |data|
        run_reply
        save("novel_context", data)
        message = finish
        expect(load("novel_context", "default")["data"]).to eq(data)
        delete(message)
      end
      run_reply
      ts.remove_value(session, "novel_context")
      removal = finish
      expect(load("novel_context", "default")["data"]).to eq("default")
      delete(removal)
      expect(load("novel_context")["data"]).to eq("plot" => "base")
    end

    it "comes back from the base once every change is deleted, never from the state the changes made" do
      session[:monadic_state] = { app => { "novel_context" => { data: { "plot" => "base" }, version: 1 } } }
      run_reply
      save("novel_context", { "plot" => "mine" })
      message = finish
      payload = Monadic::History::Serializer.payload(session)
      expect(payload["monadic_state"][app]["novel_context"]["data"]).to eq("plot" => "base")
      delete(message)
      expect(load("novel_context")["data"]).to eq("plot" => "base")
    end
  end

  describe "items" do
    it "takes back the turn that added one, unless a later turn put it again" do
      run_reply
      ann = put("Ann")
      t1 = finish
      run_reply
      save("novel_context", { "progress" => "10%" })
      finish
      expect(names).to eq(["Ann"])
      delete(t1)
      expect(names).to eq([])

      run_reply
      put("Bob")
      t3 = finish
      run_reply
      put("Bob (older)", id: JSON.parse(tools.monadic_load_items(collection: "characters", session: session))["items"].first["id"])
      finish
      delete(t3)
      expect(names).to eq(["Bob (older)"])
      expect(ann).to match(Monadic::TurnState::Form::ID)
    end

    it "brings back an item when the turn that removed it is deleted, and lets a put revive it" do
      run_reply
      id = put("Ann")
      finish
      run_reply
      tools.monadic_remove_item(collection: "characters", id: id, session: session)
      removal = finish
      expect(names).to eq([])
      delete(removal)
      expect(names).to eq(["Ann"])

      run_reply
      tools.monadic_remove_item(collection: "characters", id: id, session: session)
      finish
      run_reply
      put("Ann again", id: id)
      finish
      expect(names).to eq(["Ann again"])
    end

    it "keeps the base's items in order, under the ids it has" do
      session[:monadic_state] = { app => { "_items" => { data: { "characters" => { "c_1" => { "name" => "Ann" }, "c_2" => { "name" => "Bob" } } } } } }
      run_reply
      put("Cid")
      tools.monadic_remove_item(collection: "characters", id: "c_1", session: session)
      finish
      expect(names).to eq(%w[Bob Cid])
    end

    it "keeps items and values apart, with names that cannot meet" do
      run_reply
      put("Ann")
      save("characters", { "note" => "a value" })
      finish
      expect(names).to eq(["Ann"])
      expect(load("characters")["data"]).to eq("note" => "a value")
    end
  end

  describe "one reply at a time" do
    it "refuses a second reply of the chat while the first changes the state, and lets it once the first ends" do
      run_reply
      save("novel_context", { "a" => 1 })
      first = @reply
      second = run_reply
      expect(save("novel_context", { "a" => 2 })).to include("success" => false, "error" => /another reply/)
      @reply = first
      finish
      @reply = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: second, session: session)
      expect(save("novel_context", { "a" => 2 })).to include("success" => true)
    end

    it "keeps both of two changes a reply's parallel tools make to one value" do
      run_reply
      threads = Array.new(2) do
        reply = @reply
        Thread.new do
          allow(Monadic::Workbench::Caller).to receive(:current).and_return(reply)
          10.times { tools.monadic_update_state(key: "count", default: 0, session: session) { |n| n + 1 } }
        end
      end
      threads.each(&:join)
      finish
      expect(load("count")["data"]).to eq(20)
    end

    it "changes nothing when an update raises, and refuses one inside another" do
      run_reply
      save("count", 1)
      expect { tools.monadic_update_state(key: "count", session: session) { raise "no" } }.to raise_error("no")
      expect do
        tools.monadic_update_state(key: "count", session: session) do |n|
          tools.monadic_update_state(key: "count", session: session) { n }
        end
      end.to raise_error(Monadic::TurnState::Refused)
      finish
      expect(load("count")["data"]).to eq(1)
    end
  end

  describe "the reply's end" do
    it "lets go what a reply changed when it ends without its message, and refuses changes after its end" do
      request_id = run_reply
      save("novel_context", { "a" => 1 })
      ts.close(request_id)
      expect(save("novel_context", { "a" => 2 })).to include("success" => false)
      @reply = nil
      expect(load("novel_context", "none")["data"]).to eq("none")
    end

    it "gives the changes to one message only" do
      request_id = run_reply
      save("novel_context", { "a" => 1 })
      expect(ts.seal(request_id, session)).not_to be_nil
      expect(ts.seal(request_id, session)).to be_nil
    end

    it "lets go a reply's changes when the chat changed under it (a turn deleted, the chat left)" do
      run_reply
      save("novel_context", { "a" => 1 })
      ts.changed!(chat)
      expect(finish).not_to have_key("state_changes")

      run_reply
      save("novel_context", { "a" => 1 })
      Monadic::Workspace::Chats.replacing!(session)
      expect(finish).not_to have_key("state_changes")
    end

    it "refuses a change that would make the reply's changes too large, keeping the ones before" do
      run_reply
      save("small", "x")
      expect(save("big", "x" * Monadic::TurnState::Form::SAVE_BYTES)).to include("success" => false, "error" => /larger/)
      expect(finish["state_changes"].map { |c| c["key"] }).to eq(["small"])
    end

    it "makes several changes together or none of them, and no more than a reply may make" do
      run_reply
      item = ->(id, data) { { "kind" => "item", "collection" => "notes", "id" => id, "op" => "set", "data" => data } }
      ts.change_all!(session, [item.call("a", "one"), item.call("b", "two")])

      expect { ts.change_all!(session, [item.call("c", "three"), { "kind" => "item", "collection" => "Not A Name", "id" => "d", "op" => "set", "data" => "four" }]) }
        .to raise_error(described_class::Refused)
      many = Array.new(described_class::Form::ENTRIES) { |i| item.call("m#{i}", i) }
      expect { ts.change_all!(session, many) }.to raise_error(described_class::Refused, /at most/)

      expect(ts.items(session, "notes").map { |i| i[:data] }).to eq(%w[one two])
      expect(finish["state_changes"].size).to eq(2)
    end

    it "refuses a change without a running reply, and to another app's state" do
      expect(save("novel_context", { "a" => 1 })).to include("success" => false)
      run_reply
      result = JSON.parse(tools.monadic_save_state(app: "OtherApp", key: "x", payload: 1, session: session))
      expect(result).to include("success" => false, "error" => /own app/)
    end
  end

  describe "the history" do
    it "makes the same state again from the messages and the base it keeps" do
      session[:monadic_state] = { app => { "goal" => { data: 1000, version: 1 } } }
      run_reply
      save("novel_context", { "plot" => "p" })
      put("Ann")
      finish
      payload = Monadic::History::Serializer.payload(session)

      resumed = { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => app },
                  messages: payload["messages"],
                  monadic_state: Monadic::TurnState::Form.to_session(Monadic::TurnState::Form.clean_base(payload["monadic_state"]).first) }
      ts.changed!(chat)
      expect(JSON.parse(tools.monadic_load_state(key: "novel_context", session: resumed))["data"]).to eq("plot" => "p")
      expect(JSON.parse(tools.monadic_load_state(key: "goal", session: resumed))["data"]).to eq(1000)
      expect(JSON.parse(tools.monadic_load_items(collection: "characters", session: resumed))["items"].size).to eq(1)
    end
  end
end
