# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/session_context"

# Mock MonadicHelper for testing
module MonadicHelper
end

# Mock WebSocketHelper for testing
module WebSocketHelper
  def self.send_to_session(message, session_id)
    # Mock implementation - just log for testing
    true
  end
end

RSpec.describe "MonadicSharedTools::SessionContext" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::SessionContext

      attr_accessor :session

      def initialize
        @session = {
          parameters: { "session_id" => "test-session-123", "app_name" => "TestApp" },
          monadic_state: {}
        }
      end
    end
  end

  let(:app) { test_class.new }
  let(:session) { app.session }

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

  describe "WebSocket broadcasting" do
    it "broadcasts context update via WebSocket" do
      expect(WebSocketHelper).to receive(:send_to_session).with(
        anything,
        "test-session-123"
      )

      app.update_context(topics: ["AI"], session: session)
    end
  end

  describe "default_context" do
    it "returns hash with empty arrays for topics, people, notes" do
      default = app.send(:default_context)

      expect(default).to eq({
        "topics" => [],
        "people" => [],
        "notes" => []
      })
    end
  end

  describe "CONTEXT_KEY constant" do
    it "is defined as :conversation_context" do
      expect(MonadicSharedTools::SessionContext::CONTEXT_KEY).to eq(:conversation_context)
    end
  end
end
