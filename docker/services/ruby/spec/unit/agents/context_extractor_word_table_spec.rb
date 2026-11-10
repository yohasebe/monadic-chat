# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/agents/context_extractor_agent"
require_relative "../../../lib/monadic/utils/privacy/words"

# The context of a chat that hides its words with a word table: what the
# extracting model is sent, and what the context is put back with.
RSpec.describe "The context of a chat with a word table" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }
  let(:agent) { Class.new { include ContextExtractorAgent }.new }
  let(:sent) { [] }

  before do
    table.confirm!("Ada Lovelace", "PERSON")
    stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => "test-not-sent"))
  end

  after { words::LOCK.synchronize { words::TABLES.clear } }

  def extracting(reply)
    allow(agent).to receive(:call_provider_api) do |_provider, _model, system_message, _key|
      sent << system_message
      reply.respond_to?(:call) ? reply.call : reply
    end
    agent.extract_context(session, "Tell me about Ada Lovelace", "Ada Lovelace wrote literal <<PERSON_1>>.", "openai")
  end

  it "sends the conversation with the words hidden, and puts the context back" do
    context = extracting(JSON.generate("topics" => ["notes of <<PERSON_1>>"], "people" => ["<<PERSON_1>>"], "notes" => []))
    expect(sent.join).to include("User: Tell me about <<PERSON_1>>", "Assistant: <<PERSON_1>> wrote literal ‹‹PERSON_1››.")
    expect(sent.join).not_to include("Ada Lovelace")
    expect(context).to eq("topics" => ["notes of Ada Lovelace"], "people" => ["Ada Lovelace"], "notes" => [])
  end

  it "extracts nothing once the words change while it is being sent" do
    context = extracting(lambda {
      table.confirm!("Grace Hopper", "PERSON")
      words.check_sending!
      JSON.generate("topics" => [], "people" => ["<<PERSON_1>>"], "notes" => [])
    })
    expect(context).to be_nil
  end

  describe "keeping and showing the context" do
    let(:chats) { Monadic::Workspace::Chats }
    let(:store) { Monadic::Workspace::ChatContext }
    let(:shown) { [] }
    let(:chat_id) { session[chats::SESSION_KEY] }
    let(:extraction) { { chat: store.work_chat(session), job: "j1" } }

    before do
      stub_const("WebSocketHelper", Module.new)
      messages = shown
      WebSocketHelper.define_singleton_method(:send_to_live_connection) do |_tab, json, chat_id:|
        messages << JSON.parse(json).merge("to_chat" => chat_id)
        true
      end
    end

    after { store::LOCK.synchronize { store::STORE.clear } }

    def extract_while(&meanwhile)
      allow(agent).to receive(:call_provider_api) do
        meanwhile&.call
        JSON.generate("topics" => [], "people" => ["<<PERSON_1>>"], "notes" => [])
      end
      agent.process_and_broadcast_context(session.dup, "Tell me about Ada Lovelace", "A pioneer.", "openai", "tab",
                                          nil, extraction: extraction)
    end

    def people(of)
      store.read(of)&.dig("people")&.map { |p| p["text"] }
    end

    it "keeps the context for the chat it was extracted for, and shows it with the chat, its version and the job" do
      extract_while
      expect(people(session)).to eq(["Ada Lovelace"])
      expect(shown.map { |m| m.values_at("type", "chat", "version", "job", "to_chat") })
        .to eq([["context_update", "#{chat_id}.#{chats.epoch(chat_id)}", 1, "j1", chat_id]])
    end

    it "keeps nothing once the tab has left the chat, and tells the page the job ended" do
      left = chat_id
      extract_while { chats.begin_new!(session) }
      expect(people(session)).to be_nil
      expect(people({ chats::SESSION_KEY => left })).to be_nil
      expect(shown.map { |m| m.values_at("type", "job") }).to eq([%w[context_extraction_ended j1]])
    end

    it "keeps nothing for a chat left and continued again" do
      id = chat_id
      extract_while do
        chats.replacing!(session)
        chats.resume!(session, id)
      end
      expect(people(session)).to be_nil
    end

    it "keeps the context for the chat when the tab continues it over a new connection" do
      id = chat_id
      extract_while do
        chats.clear_chat_state!(session)
        chats.resume!(session, id)
      end
      reconnected = { chats::SESSION_KEY => id }
      expect(people(reconnected)).to eq(["Ada Lovelace"])
    end

    it "lets a chat be left only after a change begun in it, which leaving then drops" do
      entered = Queue.new
      release = Queue.new
      writer = Thread.new do
        store.update(session, chat: extraction[:chat]) do |_context|
          entered << true
          release.pop
          { "people" => [{ "text" => "Ada Lovelace", "turn" => 1 }] }
        end
      end
      entered.pop(timeout: 5) or raise 'the change did not begin'
      leaving = Thread.new { chats.begin_new!(session) }
      sleep 0.05
      begin
        expect(leaving).to be_alive
      ensure
        release << true # the change ends whatever was found
      end
      [writer, leaving].each { |thread| thread.join(5) or raise 'a thread did not end' }

      expect(people({ chats::SESSION_KEY => extraction[:chat][:id] })).to be_nil
      expect(people(session)).to be_nil
    end

    it "loses no change when two are made at once" do
      threads = %w[Ada Grace].map do |name|
        Thread.new do
          store.update(session) do |context|
            sleep 0.01
            store.add_texts(context, "people", [name], 1)
          end
        end
      end
      threads.each(&:join)
      expect(people(session)).to contain_exactly("Ada", "Grace")
      expect(store.current(session).version).to eq(2)
    end
  end

  it "sends nothing when the chat's table is not there" do
    words::LOCK.synchronize { words::TABLES.clear }
    expect(extracting(JSON.generate("topics" => [], "people" => [], "notes" => []))).to be_nil
    expect(sent).to be_empty
  end
end
