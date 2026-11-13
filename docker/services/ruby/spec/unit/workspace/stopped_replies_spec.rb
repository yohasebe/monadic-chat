# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workspace/chats"
require_relative "../../../lib/monadic/workspace/stopped_replies"
require_relative "../../../lib/monadic/history/serializer"
require_relative "../../../lib/monadic/agents/ai_user_agent"

RSpec.describe Monadic::Workspace::StoppedReplies do
  let(:chat) { "c_one" }

  before { described_class.reset! }

  def session_with(*messages, chat_id: chat)
    { chat_id: chat_id, messages: messages }
  end

  def user(request_id, text = "Do it")
    { "role" => "user", "request_id" => request_id, "text" => text }
  end

  describe ".apply!" do
    it "marks the user message of a stopped request of the chat, once" do
      described_class.record(chat, "q_1")
      msg = user("q_1")
      session = session_with(msg, { "role" => "assistant", "request_id" => "q_1", "text" => "" })

      expect(described_class.apply!(session)).to be(true)
      expect(msg["reply_stopped"]).to be(true)
      expect(session[:messages].last).not_to have_key("reply_stopped")
      expect(described_class.apply!(session)).to be(false)
    end

    it "keeps the record after applying it (another copy of the chat is marked too)" do
      described_class.record(chat, "q_1")
      described_class.apply!(session_with(user("q_1")))
      other = user("q_1")

      expect(described_class.apply!(session_with(other))).to be(true)
      expect(other["reply_stopped"]).to be(true)
    end

    it "marks nothing of another chat, or of another request" do
      described_class.record(chat, "q_1")
      elsewhere = user("q_1")
      later = user("q_2")

      expect(described_class.apply!(session_with(elsewhere, chat_id: "c_two"))).to be(false)
      expect(described_class.apply!(session_with(later))).to be(false)
      expect(elsewhere).not_to have_key("reply_stopped")
      expect(later).not_to have_key("reply_stopped")
    end

    it "drops a compacted history only when it newly marks a message" do
      described_class.record(chat, "q_1")
      session = session_with(user("q_1")).merge(grok_compaction: { "blob" => {} })
      described_class.apply!(session)
      expect(session).not_to have_key(:grok_compaction)

      session[:grok_compaction] = { "blob" => {} }
      described_class.apply!(session)
      expect(session).to have_key(:grok_compaction)
    end
  end

  describe "capacity" do
    it "keeps PER_CHAT requests of a chat, the oldest going first" do
      stub_const("#{described_class}::PER_CHAT", 2)
      %w[q_1 q_2 q_3].each { |id| described_class.record(chat, id) }

      expect(described_class.recorded?(chat, "q_1")).to be(false)
      expect(described_class.recorded?(chat, "q_3")).to be(true)
    end

    it "keeps CHATS chats, the least recently touched going first" do
      stub_const("#{described_class}::CHATS", 2)
      described_class.record("c_a", "q_1")
      described_class.record("c_b", "q_1")
      described_class.record("c_a", "q_2")
      described_class.record("c_c", "q_1")

      expect(described_class.recorded?("c_b", "q_1")).to be(false)
      expect(described_class.recorded?("c_a", "q_1")).to be(true)
    end
  end

  describe ".with_note" do
    it "puts the line after a marked user message's text" do
      expect(described_class.with_note(user("q_1").merge("reply_stopped" => true), "Do it"))
        .to eq("Do it\n\n#{described_class::NOTE}")
      expect(described_class.with_note(user("q_1").merge("reply_stopped" => true), "")).to eq(described_class::NOTE)
    end

    it "leaves other messages as they are (a mark that is not true, an assistant's)" do
      expect(described_class.with_note(user("q_1").merge("reply_stopped" => "yes"), "Do it")).to eq("Do it")
      expect(described_class.with_note({ "role" => "assistant", "reply_stopped" => true }, "Done")).to eq("Done")
    end
  end

  describe "where the mark is kept" do
    it "goes into the history record as true only, for a user message" do
      kept = Monadic::History::Serializer.message(user("q_1").merge("reply_stopped" => true))
      not_true = Monadic::History::Serializer.message(user("q_1").merge("reply_stopped" => "true"))
      assistant = Monadic::History::Serializer.message({ "role" => "assistant", "text" => "x", "reply_stopped" => true })

      expect(kept["reply_stopped"]).to be(true)
      expect(not_true).not_to have_key("reply_stopped")
      expect(assistant).not_to have_key("reply_stopped")
    end
  end

  describe "AI User" do
    let(:agent) { Class.new { include AIUserAgent }.new }

    it "reads the line after a marked message of the conversation" do
      text = agent.send(:format_conversation, [user("q_1", "Search").merge("reply_stopped" => true),
                                               user("q_2", "Hello")])

      expect(text).to include("User: Search\n\n#{described_class::NOTE}\n\n")
      expect(text).to end_with("User: Hello\n\n")
    end
  end
end
