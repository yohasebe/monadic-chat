# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/item_text"
require_relative "../../../lib/monadic/utils/websocket"

# The text of a document on the work screen for the user's message: of the
# version the tab shows, converted as an imported document is, and only when
# the file was that version before and after.
RSpec.describe Monadic::Workbench::ItemText do
  around do |example|
    Dir.mktmpdir("item-text-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:converted) { ->(path) { "text of #{File.basename(path)}" } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def board = Monadic::Workbench::Board.for(chat, store: store)

  def put(name, bytes)
    File.binwrite(File.join(@data, name), bytes)
    item, = board.add_file(path: name, origin: origin, epoch: Monadic::Workspace::Chats.epoch(chat))
    item
  end

  it "gives the text of a document of the version shown, as the message takes it, and flags documents" do
    item = put("report.docx", "PK a report")
    text = described_class.of(board, item["id"], item.dig("file", "sha256"), converter: converted)
    expect(text).to eq("\n---\nFilename: report.docx\n---\ntext of report.docx")
    expect(board.snapshot[:items].first[:text]).to be(true)
  end

  it "flags the documents the Library takes, by the Library's own rule" do
    doc = put("notes.md", "# Notes")
    picture = put("b.png", "\x89PNG\r\n\x1A\n".b + "y")
    items = board.snapshot[:items]
    expect(items.find { |i| i[:id] == doc["id"] }[:library]).to be(true)
    expect(items.find { |i| i[:id] == picture["id"] }[:library]).to be_nil
  end

  it "gives none for another kind, another version, a file changed while converted, or no text" do
    picture = put("a.png", "\x89PNG\r\n\x1A\n".b + "x")
    expect(board.snapshot[:items].find { |i| i[:id] == picture["id"] }[:text]).to be_nil
    expect { described_class.of(board, picture["id"], picture.dig("file", "sha256"), converter: converted) }
      .to raise_error(described_class::Failed, "not_a_document")
    item = put("notes.md", "# Notes")
    expect { described_class.of(board, item["id"], "0" * 64, converter: converted) }
      .to raise_error(described_class::Failed, "changed")
    changing = lambda do |path|
      File.write(File.join(@data, path), "# Changed")
      "text"
    end
    expect { described_class.of(board, item["id"], item.dig("file", "sha256"), converter: changing) }
      .to raise_error(described_class::Failed, "changed")
    fresh = put("notes.md", "# Notes again")
    expect { described_class.of(board, fresh["id"], fresh.dig("file", "sha256"), converter: ->(_) { "  " }) }
      .to raise_error(described_class::Failed, "empty")
  end

  describe "asked from the page" do
    let(:host) do
      Class.new do
        include WebSocketHelper
        def sent_out = (@sent_out ||= Queue.new)
        def send_to_client(_connection, payload) = sent_out << payload
      end.new
    end
    let(:session) { { chat_id: chat, _ws_generation: 1 } }

    before do
      Thread.current[:websocket_session_id] = "tab-1"
      allow(WebSocketHelper).to receive(:live_generation) { |t| t == "tab-1" ? 1 : nil }
    end

    after { Thread.current[:websocket_session_id] = nil }

    def ask(item, sha256: item.dig("file", "sha256"))
      host.send(:handle_ws_workbench_item_text, :conn, { "item_id" => item["id"], "sha256" => sha256, "request" => 3 }, session)
      Timeout.timeout(5) { host.sent_out.pop }
    end

    it "converts in a thread and gives the text to this connection, or says the converter is starting" do
      item = put("report.docx", "PK a report")
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).with(:python).and_return(true)
      stub_const("MonadicApp", Class.new { def self.doc2markdown(path) = "converted #{File.basename(path)}" })
      expect(ask(item)).to include("type" => "workbench_item_text", "request" => 3,
                                   "content" => "\n---\nFilename: report.docx\n---\nconverted report.docx")
      expect(ask(item, sha256: "0" * 64)).to include("error" => "changed")
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).with(:python).and_return(false)
      expect(Monadic::Utils::ContainerDependencies).to receive(:start_service_async).with(:python, anything)
      expect(ask(item)).to include("error" => "converter_starting")
    end
  end
end
