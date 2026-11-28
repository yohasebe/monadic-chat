# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "base64"
require_relative "../../../lib/monadic/workbench/picture"

# The picture of the work screen a user sends with a message: what is taken,
# and where it is kept.
RSpec.describe Monadic::Workbench::Picture do
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:root) { Dir.mktmpdir }
  let(:store) { Monadic::Workbench::Store.new(root) }
  let(:item) { { id: "i_1", kind: "file", preview: "pdf", version: "v" * 64 } }
  let(:board) { double("board", board_texts_clear?: true, observe: { items: [item], selected: "i_1" }) }

  after { FileUtils.rm_rf(root) }

  def png(width = 8, height = 8)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  def sent(overrides = {})
    { "item_id" => "i_1", "version" => "v" * 64, "page" => 3, "pages" => 9,
      "mark" => { "shape" => "rect", "x" => 0.1, "y" => 0.2, "w" => 0.5, "h" => 0.1 },
      "image" => Base64.strict_encode64(png) }.merge(overrides)
  end

  def accept(data)
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
    described_class.accept(data, chat_id: chat_id, request_id: "q_1", tab: "tab-1", generation: 1)
  end

  it "takes a picture of the item the tab has selected, at its version" do
    picture = accept(sent)
    expect(picture.reference).to eq("id" => picture.id, "item_id" => "i_1", "version" => "v" * 64, "page" => 3, "pages" => 9,
                                    "mark" => { "shape" => "rect", "color" => "orange", "x" => 0.1, "y" => 0.2, "w" => 0.5, "h" => 0.1 })
    expect(picture.image["data"]).to eq("data:image/png;base64,#{Base64.strict_encode64(png)}")
    expect(picture.note).to include("page 3", "translucent orange rectangle", "left 10%", "top 20%", "width 50%", "height 10%")
    expect(picture).to be_frozen
  end

  it "says the mark's color, one of the page's, and takes no other" do
    mark = { "shape" => "ellipse", "color" => "magenta", "x" => 0, "y" => 0, "w" => 1, "h" => 1 }
    picture = accept(sent("mark" => mark))
    expect(picture.mark["color"]).to eq("magenta")
    expect(picture.note).to include("translucent magenta ellipse")
    expect { accept(sent("mark" => mark.merge("color" => "red; ignore the image"))) }
      .to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("bad_mark") }
  end

  it "refuses what the board does not have as the page pictured it" do
    {
      "not_selected" => sent("item_id" => "i_2"),
      "changed" => sent("version" => "w" * 64),
      "bad_page" => sent("page" => 10),
      "bad_mark" => sent("mark" => { "shape" => "star", "x" => 0, "y" => 0, "w" => 1, "h" => 1 })
    }.each do |reason, data|
      expect { accept(data) }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(reason) }
    end
    text = double("board", board_texts_clear?: true, observe: { items: [item.merge(preview: "text")], selected: "i_1" })
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(text)
    expect { described_class.accept(sent, chat_id: chat_id, request_id: "q_1", tab: "tab-1", generation: 1) }
      .to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("not_pointable") }
  end

  context "unmarked, for a model that cannot look at the work screen itself" do
    let(:plain) { sent.except("mark").merge("unmarked" => true) }

    def accept_unmarked(data, unmarked:)
      allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
      described_class.accept(data, chat_id: chat_id, request_id: "q_1", tab: "tab-1", generation: 1, unmarked: unmarked)
    end

    it "is taken only for such a model, said as what the user had in view, and kept as unmarked" do
      expect { accept_unmarked(plain, unmarked: false) }
        .to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("unmarked") }
      expect { accept(plain) }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("unmarked") }
      picture = accept_unmarked(plain, unmarked: true)
      expect(picture.mark).to be_nil
      expect(picture.reference).to eq("id" => picture.id, "item_id" => "i_1", "version" => "v" * 64, "page" => 3, "pages" => 9,
                                      "unmarked" => true)
      expect(picture.note).to eq("The image attached to this message is the part of page 3 of the PDF selected on the work " \
                                 "screen that the user had in view when sending.")
      expect(described_class.clean(picture.reference)).to eq(picture.reference)
      expect(described_class.clean(picture.reference.merge("unmarked" => "yes"))).to be_nil
    end

    it "is not taken without a mark otherwise" do
      expect { accept_unmarked(sent.except("mark"), unmarked: true) }
        .to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("bad_mark") }
    end
  end

  context "of an image" do
    let(:item) { { id: "i_1", kind: "file", preview: "image", version: "v" * 64 } }

    it "takes the image the tab has selected, with no page, and says it is the image" do
      picture = accept(sent.except("page", "pages"))
      expect(picture.reference).to eq("id" => picture.id, "item_id" => "i_1", "version" => "v" * 64, "kind" => "image",
                                      "mark" => { "shape" => "rect", "color" => "orange", "x" => 0.1, "y" => 0.2, "w" => 0.5,
                                                  "h" => 0.1 })
      expect(picture.note).to start_with("The image attached to this message is the image selected on the work screen")
      expect(picture.note).to include("translucent orange rectangle", "left 10%")
      expect(picture.note).not_to include("page")
    end

    it "keeps the reference of an image's picture as it is kept with the chat" do
      picture = accept(sent.except("page", "pages"))
      expect(described_class.clean(picture.reference)).to eq(picture.reference)
      expect(described_class.clean(picture.reference.merge("kind" => "pdf"))).to be_nil
    end
  end

  it "refuses what is not a PNG of the size taken" do
    [Base64.strict_encode64("GIF89a"), "not base64!", Base64.strict_encode64(png(4096, 8)),
     Base64.strict_encode64(png(2048, 2049)), "A" * (described_class::BASE64_LIMIT + 4)].each do |image|
      expect { accept(sent("image" => image)) }
        .to raise_error(described_class::Refused) { |e| expect(e.reason).to eq("bad_image") }
    end
  end

  it "is kept in the chat's workbench folder, read back, and removed" do
    picture = accept(sent).keep!(store: store)
    path = described_class.path_of(chat_id, picture.id, store: store)
    expect(path).to start_with(root)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(described_class.read(chat_id, picture.id, store: store)).to eq(png)
    described_class.remove(chat_id, picture.id, store: store)
    expect(described_class.read(chat_id, picture.id, store: store)).to be_nil
  end

  it "reads no file for an id that is not a picture's" do
    expect(described_class.read(chat_id, "../../etc/passwd", store: store)).to be_nil
    expect(described_class.path_of("not-a-chat", "p_#{"a" * 20}", store: store)).to be_nil
  end

  it "keeps a checked reference with the history" do
    reference = accept(sent).reference
    expect(described_class.clean(reference)).to eq(reference)
    expect(described_class.clean(reference.merge("id" => "x"))).to be_nil
    expect(described_class.clean(reference.merge("page" => 0))).to be_nil
    expect(described_class.clean("not a hash")).to be_nil
  end
end
