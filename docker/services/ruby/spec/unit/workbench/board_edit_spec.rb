# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "base64"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/board_edit"

# An edit of the picture under a whiteboard: the picture the board keeps
# (the original) and the board as the tab draws it at its saved version
# (the reference), or nothing.
RSpec.describe Monadic::Workbench::BoardEdit do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00".b * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("board-edit-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      transport = capture.transport
      example.run
    ensure
      capture.transport = transport
      capture.reset!
    end
  end

  let(:capture) { Monadic::Workbench::Capture }
  let(:whiteboard) { Monadic::Workbench::Whiteboard }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:caller_for) do
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                   session: session, tab: "tab-1", generation: 1)
  end
  let(:photo_bytes) { png(300, 400, "photo") }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after do
    Monadic::Workspace::Ledger.clear_unsettled!
    Monadic::Utils::Privacy::Words::LOCK.synchronize { Monadic::Utils::Privacy::Words::TABLES.clear }
  end

  def board = Monadic::Workbench::Board.for(chat, store: store)

  def board_on_photo
    FileUtils.mkdir_p(File.join(@data, "photos"))
    File.binwrite(File.join(@data, "photos/a.png"), photo_bytes)
    photo, = board.add_file(path: "photos/a.png", origin: origin, epoch: epoch)
    whiteboard.create_on(chat, item_id: photo["id"], version: photo.dig("file", "sha256"), app_name: "ChatOpenAI",
                               origin: origin, epoch: epoch)
  end

  def save(item, shapes)
    whiteboard.save(chat, item_id: item["id"], version: item.dig("file", "sha256"), data: { "version" => 2, "shapes" => shapes },
                          app_name: "ChatOpenAI", origin: origin, epoch: epoch)
  end

  # The tab answers each capture with the next of answers (the last one
  # again when they run out); asked counts them.
  def page(*answers)
    @asked = 0
    capture.transport = lambda do |_tab, _generation, _chat, json|
      request = JSON.parse(json)
      answer = answers[[@asked, answers.size - 1].min]
      @asked += 1
      Thread.new { capture.reading(request["id"], 2) { answer } }
      true
    end
  end

  def picture(width, height)
    { "range" => {}, "image" => Base64.strict_encode64(png(width, height, "drawn")),
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 1600, "sent_width" => width, "sent_height" => height } }
  end

  it "gives the picture the board keeps as the original and the board as the tab draws it as the reference" do
    board_on_photo
    page(picture(600, 800))
    original, reference = described_class.inputs(caller_for)
    expect(original.to_h).to include(role: "original", bytes: photo_bytes, content_type: "image/png")
    expect(reference.role).to eq("reference")
    expect(reference.bytes).to eq(png(600, 800, "drawn"))
  end

  it "asks the tab again when it was saving what was drawn last, for the version saved" do
    board_on_photo
    page({ "range" => {}, "image_note" => "saving" }, picture(600, 800))
    expect(described_class.inputs(caller_for).map(&:role)).to eq(%w[original reference])
    expect(@asked).to eq(2)
  end

  it "takes no picture of other proportions, and none from a board the tab does not show" do
    item = board_on_photo
    page(picture(800, 500))
    expect { described_class.inputs(caller_for) }.to raise_error(described_class::NoSource, /could not be drawn/)
    expect { described_class.inputs(caller_for, item_id: "i_#{'0' * 20}") }.to raise_error(described_class::NoSource, /open the whiteboard/)
    expect(item["id"]).not_to be_nil
  end

  it "edits nothing for a plain board" do
    whiteboard.create(chat, app_name: "ChatOpenAI", origin: origin, epoch: epoch)
    page(picture(600, 800))
    expect { described_class.inputs(caller_for) }.to raise_error(described_class::NoSource, /no picture/)
    expect(@asked).to eq(0)
  end

  it "keeps the whole edit back when any text of the board holds a word the chat hides, asking the tab nothing" do
    item = board_on_photo
    shapes = Array.new(205) { |i| { "id" => "t#{i}", "type" => "text", "x" => 10, "y" => 10, "text" => "note #{i}" } }
    shapes << { "id" => "last", "type" => "text", "x" => 10, "y" => 10, "text" => "Ada Lovelace" }
    save(item, shapes)
    Monadic::Utils::Privacy::Words.start!(session).confirm_all!([["Ada Lovelace", "PERSON"]])
    page(picture(600, 800))
    expect { described_class.inputs(caller_for) }.to raise_error(described_class::NoSource, /hides/)
    expect(@asked).to eq(0)
  end

  it "edits nothing when the copy under the board is no longer the picture" do
    item = board_on_photo
    assets = File.join(File.dirname(File.join(@data, item.dig("file", "path"))), "assets")
    Dir.children(assets).each { |name| File.binwrite(File.join(assets, name), png(300, 400, "other")) }
    page(picture(600, 800))
    expect { described_class.inputs(caller_for) }.to raise_error(described_class::NoSource, /no longer/)
  end
end
