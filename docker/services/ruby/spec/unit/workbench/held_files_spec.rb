# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/asset_server"
require_relative "../../../lib/monadic/workbench/look"

# A file the work screen only holds (an Office document, a MIDI file, audio
# or video it does not play): an item with its name, type, size and version,
# read in pieces, never shown, and looked at by no one.
RSpec.describe "Files the work screen only holds" do
  around do |example|
    Dir.mktmpdir("held-files-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:item_module) { Monadic::Workbench::FileItem }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:live) { ->(t) { t == "tab-1" ? 1 : nil } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = live
    Monadic::Workbench::ViewTokens.reset!
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

  it "holds one with its name, type, size and version, read in pieces" do
    stub_const("#{item_module}::CHUNK", 4)
    bytes = "MThd\x00\x00\x00\x06 a song".b
    item = put("song.mid", bytes)
    expect(item["file"]).to include("preview" => "file", "content_type" => "audio/midi", "size" => bytes.bytesize,
                                    "sha256" => Digest::SHA256.hexdigest(bytes))
  end

  it "holds none larger than it may, and reads one whole only for a use that takes its size" do
    stub_const("#{item_module}::FILE_LIMIT", 20)
    expect { put("big.docx", "PK" + ("x" * 30)) }.to raise_error(Monadic::Workbench::Board::Refused, /too large/)
    item = put("small.docx", "PK small")
    expect(board.file_read(item["id"], sha256: item.dig("file", "sha256"), limit: 100)[:bytes]).to eq("PK small")
    expect { board.file_read(item["id"], sha256: item.dig("file", "sha256"), limit: 3) }
      .to raise_error(item_module::TooLarge)
  end

  it "gives the page no address to show it, and says when it is too large to save" do
    item = put("report.docx", "PK a report")
    session = { chat_id: chat, _ws_generation: 1 }
    view = Monadic::Workbench::Channel.view(session, tab: "tab-1", generation: 1, live: live)
    expect(view["assets"]).not_to have_key(item["id"])
    expect(view["approvals"]).to have_key(item["id"])
    stub_const("#{item_module}::LIMIT", 4)
    answer = Monadic::Workbench::Channel.download({ "item_id" => item["id"], "sha256" => item.dig("file", "sha256") },
                                                  session, tab: "tab-1", generation: 1, live: live)
    server = Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, []] }, live: live)
    status, = server.call({ "PATH_INFO" => answer["url"], "REQUEST_METHOD" => "GET", "HTTP_SEC_FETCH_SITE" => "same-origin" })
    expect(status).to eq(413)
  end
end
