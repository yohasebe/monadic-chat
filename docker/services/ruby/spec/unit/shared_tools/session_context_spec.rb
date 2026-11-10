# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/session_context"

# Mock MonadicHelper for testing
module MonadicHelper
end

RSpec.describe "MonadicSharedTools::SessionContext" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::SessionContext

      attr_accessor :session

      def initialize
        @session = { parameters: { "session_id" => "test-session-123", "app_name" => "TestApp" } }
        Monadic::Workspace::Chats.start_new!(@session)
      end
    end
  end

  let(:app) { test_class.new }
  let(:session) { app.session }
  let(:sent) { [] }

  after { Monadic::Workspace::ChatContext::LOCK.synchronize { Monadic::Workspace::ChatContext::STORE.clear } }

  before do
    stub_const("WebSocketHelper", Module.new)
    messages = sent
    WebSocketHelper.define_singleton_method(:send_to_live_connection) do |tab, json, chat_id:|
      messages << [tab, JSON.parse(json), chat_id]
      true
    end
  end

  describe "#get_context" do
    context "when context is empty" do
      it "returns default context with empty arrays" do
        result = app.get_context(session: session)

        expect(result[:success]).to be true
        expect(result[:context]["topics"]).to eq([])
        expect(result[:context]["people"]).to eq([])
        expect(result[:context]["notes"]).to eq([])
      end
    end

    context "when context has data" do
      before do
        app.update_context(topics: ["AI"], people: ["John"], notes: ["Important"], session: session)
      end

      it "returns the stored context" do
        result = app.get_context(session: session)

        expect(result[:success]).to be true
        expect(result[:context]["topics"]).to include("AI")
        expect(result[:context]["people"]).to include("John")
        expect(result[:context]["notes"]).to include("Important")
      end
    end
  end

  describe "#update_context" do
    context "with merge mode (default)" do
      it "adds topics to existing context" do
        app.update_context(topics: ["AI"], session: session)
        result = app.update_context(topics: ["Ruby"], session: session)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("merged")
        expect(result[:context]["topics"]).to contain_exactly("AI", "Ruby")
      end

      it "adds people to existing context" do
        app.update_context(people: ["John"], session: session)
        result = app.update_context(people: ["Mary"], session: session)

        expect(result[:context]["people"]).to contain_exactly("John", "Mary")
      end

      it "avoids duplicates when merging" do
        app.update_context(topics: ["AI"], session: session)
        result = app.update_context(topics: ["AI", "Ruby"], session: session)

        expect(result[:context]["topics"]).to contain_exactly("AI", "Ruby")
      end
    end

    context "with replace mode" do
      before do
        app.update_context(topics: ["AI", "ML"], people: ["John"], session: session)
      end

      it "replaces entire context when replace is true" do
        result = app.update_context(topics: ["Ruby"], replace: true, session: session)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("replaced")
        expect(result[:context]["topics"]).to eq(["Ruby"])
        expect(result[:context]["people"]).to eq([])
        expect(result[:context]["notes"]).to eq([])
      end
    end

    context "with nil parameters" do
      it "handles nil topics gracefully" do
        result = app.update_context(topics: nil, people: ["John"], session: session)

        expect(result[:success]).to be true
        expect(result[:context]["people"]).to include("John")
      end

      it "handles all nil parameters" do
        result = app.update_context(session: session)

        expect(result[:success]).to be true
      end
    end
  end

  describe "#remove_from_context" do
    before do
      app.update_context(
        topics: ["AI", "Ruby", "Python"],
        people: ["John", "Mary"],
        notes: ["Note 1", "Note 2"],
        session: session
      )
    end

    it "removes specified topics" do
      result = app.remove_from_context(topics: ["Ruby"], session: session)

      expect(result[:success]).to be true
      expect(result[:action]).to eq("removed")
      expect(result[:context]["topics"]).to contain_exactly("AI", "Python")
    end

    it "removes specified people" do
      result = app.remove_from_context(people: ["John"], session: session)

      expect(result[:context]["people"]).to eq(["Mary"])
    end

    it "removes specified notes" do
      result = app.remove_from_context(notes: ["Note 1"], session: session)

      expect(result[:context]["notes"]).to eq(["Note 2"])
    end

    it "handles removing non-existent items" do
      result = app.remove_from_context(topics: ["Java"], session: session)

      expect(result[:success]).to be true
      expect(result[:context]["topics"]).to contain_exactly("AI", "Ruby", "Python")
    end
  end

  describe "#clear_context" do
    before do
      app.update_context(
        topics: ["AI"],
        people: ["John"],
        notes: ["Important"],
        session: session
      )
    end

    it "clears all context" do
      result = app.clear_context(session: session)

      expect(result[:success]).to be true
      expect(result[:context]["topics"]).to eq([])
      expect(result[:context]["people"]).to eq([])
      expect(result[:context]["notes"]).to eq([])
    end
  end

  describe "the chat's context" do
    it "sends the change to the tab, with the chat it is of and its version" do
      app.update_context(topics: ["AI"], session: session)
      app.update_context(people: ["John"], session: session)

      chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
      expect(sent.map(&:first)).to all(eq("test-session-123"))
      expect(sent.map(&:last)).to all(eq(chat_id))
      expect(sent.map { |_, message, _| message["version"] }).to eq([1, 2])
      expect(sent.last[1]["chat"]).to eq("#{chat_id}.#{Monadic::Workspace::Chats.epoch(chat_id)}")
    end

    it "keeps what the context panel shows: items with the turn they came from" do
      session[:messages] = [{ "role" => "user", "text" => "q" }, { "role" => "assistant", "text" => "a" }]
      app.update_context(topics: ["AI"], session: session)

      expect(Monadic::Workspace::ChatContext.read(session)["topics"]).to eq([{ "text" => "AI", "turn" => 2 }])
    end

    it "removes an item an extraction added, by its text" do
      Monadic::Workspace::ChatContext.update(session) { { "topics" => [{ "text" => "AI", "turn" => 1, "edited" => true }] } }

      expect(app.remove_from_context(topics: ["AI"], session: session)[:context]["topics"]).to eq([])
    end

    it "changes nothing once the chat the reply began in has been left" do
      guard = Monadic::Utils::Privacy::EgressGuard
      left = session[Monadic::Workspace::Chats::SESSION_KEY]
      Fiber[guard::CHAT_KEY] = guard::Scope.of(session)
      # The reply runs in its own thread, begun in the chat; the tab's
      # connection then starts another (which moves the connection's scope).
      go = Queue.new
      reply = Thread.new { go.pop && app.update_context(topics: ["AI"], session: session) }
      Monadic::Workspace::Chats.begin_new!(session)
      go << true
      result = reply.value

      expect(result[:success]).to be false
      expect(Monadic::Workspace::ChatContext.read(session)).to be_nil
      expect(Monadic::Workspace::ChatContext.read({ Monadic::Workspace::Chats::SESSION_KEY => left })).to be_nil
    ensure
      Fiber[guard::CHAT_KEY] = nil
    end
  end
end
