# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/item_text"
require_relative "../../../lib/monadic/workbench/board"

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

  it "gives the text of a document of the version given" do
    item = put("report.docx", "PK a report")
    expect(described_class.text_of(board, item["id"], item.dig("file", "sha256"), converter: converted)).to eq("text of report.docx")
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
    expect { described_class.text_of(board, picture["id"], picture.dig("file", "sha256"), converter: converted) }
      .to raise_error(described_class::Failed, "not_a_document")
    item = put("notes.md", "# Notes")
    expect { described_class.text_of(board, item["id"], "0" * 64, converter: converted) }
      .to raise_error(described_class::Failed, "changed")
    changing = lambda do |path|
      File.write(File.join(@data, path), "# Changed")
      "text"
    end
    expect { described_class.text_of(board, item["id"], item.dig("file", "sha256"), converter: changing) }
      .to raise_error(described_class::Failed, "changed")
    fresh = put("notes.md", "# Notes again")
    expect { described_class.text_of(board, fresh["id"], fresh.dig("file", "sha256"), converter: ->(_) { "  " }) }
      .to raise_error(described_class::Failed, "empty")
  end

end
