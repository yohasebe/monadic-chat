# frozen_string_literal: true

require "spec_helper"
require "base64"
require "zlib"
require "tmpdir"
require_relative "../../../lib/monadic/workbench/whiteboard"
require_relative "../../../lib/monadic/workbench/image_tool"
require_relative "../../../lib/monadic/workbench/caller"
require_relative "../../../lib/monadic/utils/boolean_parser"

# A whiteboard that left Now becomes an image: a page paints its last version,
# the first image taken is kept beside the board, and the item becomes it.
RSpec.describe "a whiteboard made an image" do
  around do |example|
    Dir.mktmpdir("workbench-whiteboard-image-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:whiteboard) { Monadic::Workbench::Whiteboard }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:board) { Monadic::Workbench::Board.for(chat) }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  # A whole PNG of width × height (one color, salt in its pixels).
  def png(width = 1600, height = 1000, salt: 0)
    chunk = ->(type, body) { [body.bytesize].pack("N") + type.b + body + [Zlib.crc32(type.b + body)].pack("N") }
    rows = ("\x00".b + ([salt % 256] * 3 * width).pack("C*")) * height
    "\x89PNG\r\n\x1A\n".b + chunk.call("IHDR", [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate(rows)) + chunk.call("IEND", "".b)
  end

  def next_turn!
    request = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(request)
    board.end_reply(request)
  end

  def take(item, image, version: item.dig("file", "sha256"))
    whiteboard.take_image(chat, item_id: item["id"], version: version, image: Base64.strict_encode64(image),
                                app_name: "ChatOpenAI", epoch: epoch)
  end

  def left_now
    item = whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
    item = whiteboard.save(chat, item_id: item["id"], version: item.dig("file", "sha256"), app_name: "ChatOpenAI",
                                 origin: origin, epoch: epoch, data: { "shapes" => [{ "id" => "a", "type" => "rect", "x" => 1,
                                                                                    "y" => 1, "w" => 9, "h" => 9 }] })
    next_turn!
    board.item(item["id"])
  end

  def refused(reason)
    raise_error(whiteboard::Refused) { |e| expect(e.message).to eq(reason) }
  end

  it "waits for its image once it left Now, and takes the first a page paints at that version" do
    item = left_now
    version = item.dig("file", "sha256")
    expect(board.image_pending(item["id"])).to eq(version)
    expect(board.snapshot[:items].first).to include(frozen: true, image_pending: version)

    first = png(salt: 1)
    made = take(item, first)
    expect(made).to include("id" => item["id"], "place" => item["place"], "by" => "user")
    expect(made["file"]).to include("preview" => "image")
    expect(made.dig("file", "path")).to end_with("/whiteboards/whiteboard-1.png")
    expect(made["board_source"]).to eq("path" => item.dig("file", "path"), "sha256" => version)
    expect(File.binread(File.join(@data, made.dig("file", "path")))).to eq(first)
    # Another tab's image of the same version comes too late: the first stays.
    expect { take(item, png(salt: 2)) }.to refused("done")
    expect(File.binread(File.join(@data, made.dig("file", "path")))).to eq(first)
    expect(board.image_pending(item["id"])).to be_nil
    # Now an image: no longer a board in the view.
    expect(board.snapshot[:items].first).to include(frozen: nil, image_pending: nil)
  end

  it "takes no image of a board in Now, of another version, or of bytes that are not one" do
    item = whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
    expect { take(item, png) }.to refused("stale")
    next_turn!
    expect { take(item, png, version: "0" * 64) }.to refused("stale")
    expect { take(item, png(800, 500)) }.to refused("bad_image")
    expect { take(item, png[0...-12]) }.to refused("bad_image")
    expect { take(item, "GIF89a not a png".b) }.to refused("bad_image")
    expect do
      whiteboard.take_image(chat, item_id: item["id"], version: item.dig("file", "sha256"), image: "not base64!",
                                  app_name: "ChatOpenAI", epoch: epoch)
    end.to refused("bad_image")
    expect(Dir.glob(File.join(@data, "**", "*.png"))).to be_empty
  end

  it "keeps the image under the next free name when the board's is taken, leaving that file as it is" do
    item = left_now
    taken = File.join(@data, File.dirname(item.dig("file", "path")), "whiteboard-1.png")
    File.binwrite(taken, "the user's own")
    made = take(item, png)
    expect(made.dig("file", "path")).to end_with("/whiteboards/whiteboard-1-2.png")
    expect(File.binread(taken)).to eq("the user's own")
  end

  it "does not give a board's number again while its image is there" do
    item = left_now
    made = take(item, png)
    File.delete(File.join(@data, item.dig("file", "path")))
    expect(whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch).dig("file", "path"))
      .to end_with("whiteboard-2.wb.json")
    expect(File.exist?(File.join(@data, made.dig("file", "path")))).to be true
  end

  it "keeps a board drawn on a picture a board when it leaves Now" do
    item = whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch,
                                   background: { "sha256" => "a" * 64, "content_type" => "image/png", "pixel_width" => 300,
                                                 "pixel_height" => 400, "orientation" => 1 })
    next_turn!
    expect(board.image_pending(item["id"])).to be_nil
    expect { take(item, png) }.to refused("stale")
  end

  it "keeps the image's text as sent through what every message of a page goes through" do
    text = Base64.strict_encode64(png)
    parsed = BooleanParser.parse_hash({ "message" => "WORKBENCH_WHITEBOARD_IMAGE", "item_id" => "i_1", "png" => text })
    expect(parsed["png"]).to eq(text)
  end

  it "edits nothing from a board waiting for its image" do
    item = left_now
    caller = Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                            session: {}, tab: "tab-1", generation: 1)
    expect do
      Monadic::Workbench::ImageTool.edit_source(session: { chat_id: chat, messages: [] }, workbench: caller, images: nil,
                                                item: item["id"])
    end.to raise_error(Monadic::Workbench::ImageTool::NoSource, /being made an image/)
  end
end
