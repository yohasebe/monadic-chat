# frozen_string_literal: true

require "spec_helper"
require "base64"
require "zlib"
require "tmpdir"
require_relative "../../../lib/monadic/workbench/picture"
require_relative "../../../lib/monadic/workbench/drawings"
require_relative "../../../lib/monadic/utils/privacy/words"

# What the user draws on an image of the work screen: sent as the image's
# picture (with or without marks), checked against the image, kept by the
# message as the shapes it added, shown lighter on later turns, and taken off
# again when that message is deleted or the drawing erased.
RSpec.describe Monadic::Workbench::Drawings do
  around do |example|
    Dir.mktmpdir("workbench-drawings-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:board) { Monadic::Workbench::Board.for(chat) }
  let(:picture) { Monadic::Workbench::Picture }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed) if defined?(Monadic::Workbench::Channel)
  end

  after do
    Monadic::Workspace::Ledger.clear_unsettled!
    Monadic::Utils::Privacy::Words::LOCK.synchronize { Monadic::Utils::Privacy::Words::TABLES.clear }
  end

  def png(width = 300, height = 400)
    chunk = ->(type, body) { [body.bytesize].pack("N") + type.b + body + [Zlib.crc32(type.b + body)].pack("N") }
    rows = ("\x00".b + ([200] * 3 * width).pack("C*")) * height
    "\x89PNG\r\n\x1A\n".b + chunk.call("IHDR", [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate(rows)) + chunk.call("IEND", "".b)
  end

  def photo(name = "photo.png")
    File.binwrite(File.join(@data, name), png)
    board.add_file(path: name, origin: origin, epoch: epoch).first
  end

  def stroke(id, text: nil)
    shape = { "id" => id, "type" => text ? "text" : "pen", "color" => "red" }
    text ? shape.merge("x" => 10, "y" => 10, "text" => text) : shape.merge("points" => [[10, 10], [200, 300]])
  end

  def sent(item, shapes, marks: [])
    { "item_id" => item["id"], "version" => item.dig("file", "sha256"), "image" => Base64.strict_encode64(png(8, 8)),
      "marks" => marks, "drawing" => { "shapes" => shapes } }
  end

  def take(list, words: [])
    picture.accept_marked(list, chat_id: chat, request_id: Monadic::Workspace::Ids.generate(:request), tab: "tab-1",
                                generation: 1, words: words)
  end

  def refused(reason)
    raise_error(picture::Refused) { |e| expect(e.reason).to eq(reason) }
  end

  it "takes a drawing alone as the image's picture, checked against the image, and tells the model the user drew on it" do
    item = photo
    taken = take([sent(item, [stroke("s1")])]).first
    expect(taken.drawing.map { |shape| [shape["id"], shape["type"], shape["by"]] }).to eq([%w[s1 pen user]])
    expect(taken.marks).to eq([])
    expect(taken.note).to include("The user drew on it")
    reference = taken.reference
    expect(reference).to include("drawn" => true, "kind" => "image")
    expect(reference).not_to have_key("mark")
    expect(picture.clean(reference)).to eq(reference)
  end

  it "refuses a drawing that is not one, or not on an image, and one whose text holds a hidden word" do
    item = photo
    expect { take([sent(item, [])]) }.to refused("bad_drawing")
    expect { take([sent(item, "not shapes")]) }.to refused("bad_drawing")
    expect { take([sent(item, [stroke("t1", text: "plain")])], words: nil) }.to refused("hides_words")
    session = { chat_id: chat, parameters: {} }
    Monadic::Utils::Privacy::Words.start!(session).confirm_all!([["Zebulon Quartzfield", "PERSON"]])
    Monadic::Utils::Privacy::Outbound.chat_session!(session)
    words = Monadic::Utils::Privacy::Outbound.terms_of(session)
    expect { take([sent(item, [stroke("t1", text: "call Zebulon Quartzfield")])], words: words) }.to refused("hides_words")
    expect(take([sent(item, [stroke("t2", text: "the door")])], words: words).first.drawing.size).to eq(1)
  end

  it "keeps what each message drew, lighter under the next, and takes off only what a deleted message added" do
    item = photo
    version = item.dig("file", "sha256")
    first = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(first, marks: { pictures: take([sent(item, [stroke("s1")])]), erased: [] })
    board.end_reply(first)
    board.accept(item_id: item["id"], action: "bring", operation_id: "op-bring-0001", epoch: epoch, sha256: version)
    second = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(second, marks: { pictures: take([sent(item, [stroke("s2")])]), erased: [] })
    drawing = board.snapshot[:items].first[:drawing]
    expect(drawing[:digests].size).to eq(2)
    expect(drawing[:shapes].map { |shape| shape["id"] }).to eq(%w[s1 s2])
    expect(described_class.read(chat, drawing[:digests].first).map { |shape| shape["id"] }).to eq(["s1"])
    # The turn's record names the drawings, not their shapes.
    kept = Monadic::Workbench::TurnRecords.read(chat, second, "user")["items"].first["drawing"]
    expect(kept).to eq("digests" => drawing[:digests])
    board.end_reply(second)
    board.undo_marks(first)
    expect(board.snapshot[:items].first[:drawing][:shapes].map { |shape| shape["id"] }).to eq(["s2"])
  end

  it "erases the drawings the user saw, and leaves one drawn later elsewhere" do
    item = photo
    version = item.dig("file", "sha256")
    first = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(first, marks: { pictures: take([sent(item, [stroke("s1")])]), erased: [] })
    board.end_reply(first)
    seen = board.snapshot[:items].first[:drawing][:digests]
    board.accept(item_id: item["id"], action: "bring", operation_id: "op-bring-0001", epoch: epoch, sha256: version)
    second = Monadic::Workspace::Ids.generate(:request)
    board.begin_reply(second, marks: { pictures: take([sent(item, [stroke("s2")])]),
                                       erased: [{ "item_id" => item["id"], "version" => version, "targets" => [], "drawings" => seen }] })
    expect(board.snapshot[:items].first[:drawing][:shapes].map { |shape| shape["id"] }).to eq(["s2"])
  end

  it "keeps what was drawn when old marks' operations are trimmed" do
    ops = [{ "kind" => "draw", "request_id" => "q", "digest" => "a" * 64 }]
    ops += (1..Monadic::Workbench::Marks::OPS_LIMIT + 5).map do |n|
      { "kind" => "add", "id" => "m_#{format('%06d', n)}", "rev" => 1, "request_id" => "q" }
    end
    ops << { "kind" => "erase", "request_id" => "q", "targets" => ops.select { |op| op["kind"] == "add" }.map { |op| [op["id"], 1] } }
    Monadic::Workbench::Marks.trim!(ops)
    expect(ops.first).to include("kind" => "draw")
  end
end
