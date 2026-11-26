# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/library/conversation_draft"

RSpec.describe Monadic::Library::ConversationDraft do
  around do |example|
    Dir.mktmpdir("conversation-draft-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:live) { ->(t) { t == "tab-1" ? 1 : nil } }
  let(:messages) { [{ "role" => "user", "text" => "Why are there tides?" }, { "role" => "assistant", "text" => "The moon." }] }
  let(:session) { { chat_id: chat, _ws_generation: 1, messages: messages, parameters: { "app_name" => "Chat" } } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = live
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def put(sess = session, generation: 1)
    described_class.put(sess, tab: "tab-1", generation: generation, live: live)
  end

  def board = Monadic::Workbench::Board.for(chat, store: store)

  it "writes the chat's record into its folder and puts it on the board, naming the chat" do
    item_id = put
    item = board.item(item_id)

    expect(item["draft"]).to eq("source_chat_id" => chat)
    path = item.dig("file", "path")
    expect(path).to match(%r{\Aconversations/.+/workbench/conversation-\d{8}-\d{6}\.md\z})
    text = File.read(File.join(@data, path))
    expect(text).to include("# Why are there tides?", "## User", "## Assistant", "The moon.")
    expect(board.snapshot[:items].first).to include(draft: true)
  end

  it "keeps naming the chat once the record is edited" do
    item_id = put
    path = board.item(item_id).dig("file", "path")
    File.write(File.join(@data, path), "# My title\n\nEdited.\n")
    board.add_file(path: path, origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                   epoch: Monadic::Workspace::Chats.epoch(chat), wait: 0)

    expect(board.item(item_id)["draft"]).to eq("source_chat_id" => chat)
  end

  it "puts nothing for a tab that is not live, a chat with nothing said, or an app that keeps no chats" do
    expect { put(generation: 2) }.to raise_error(described_class::Refused, "not_allowed")
    expect { put(session.merge(messages: [])) }.to raise_error(described_class::Refused, "empty")
    allow(described_class).to receive(:app_allows?).with("Chat").and_return(false)
    expect { put }.to raise_error(described_class::Refused, "not_saved_by_app")
    expect(board.snapshot[:items]).to be_empty
  end

  it "leaves no record behind when the board does not take it" do
    allow_any_instance_of(Monadic::Workbench::Board).to receive(:add_file).and_raise(Monadic::Workbench::Board::Refused, "full")

    expect { put }.to raise_error(described_class::Refused, "full")
    expect(Dir.glob(File.join(@data, "conversations", "**", "workbench", "*.md"))).to be_empty
  end

  it "says an app keeps its chats unless its MDSL says library_save false" do
    stub_const("MonadicApp", Class.new)
    allow(MonadicApp).to receive(:app_settings) do |name|
      Struct.new(:settings).new(name == "Images" ? { library_save: false } : { library_save: true })
    end

    expect(described_class.app_allows?("Chat")).to be true
    expect(described_class.app_allows?("Images")).to be false
  end
end
