# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../../lib/monadic/workbench/picture"
require_relative "../../../lib/monadic/utils/privacy/words"

# The item's name in the note of a marked item's picture: every kind of space
# made a plain one, cut at a word's end, and left out when it holds a word
# the chat hides (the picture is then named by its item only).
RSpec.describe "the name in a marked picture's note" do
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:words_module) { Monadic::Utils::Privacy::Words }
  let(:outbound) { Monadic::Utils::Privacy::Outbound }
  let(:png) { "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [8, 8].pack("NN") + "\x08\x02\x00\x00\x00".b }
  let(:hidden) { "Zebulon Quartzfield" }

  after { words_module::LOCK.synchronize { words_module::TABLES.clear } }

  def words
    session = { chat_id: chat, parameters: {} }
    words_module.start!(session).confirm_all!([[hidden, "PERSON"]])
    outbound.chat_session!(session)
    outbound.terms_of(session)
  end

  def note_for(name, with_words)
    item = { id: "i_1", kind: "file", preview: "image", version: "v" * 64, place: "current", name: name }
    board = double("board", board_texts_clear?: true, observe: { items: [item], selected: nil })
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat).and_return(board)
    data = { "item_id" => "i_1", "version" => "v" * 64, "mark_id" => "m_aaaaaaaa", "mark_rev" => 1,
             "mark" => { "shape" => "rect", "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2 },
             "image" => Base64.strict_encode64(png) }
    Monadic::Workbench::Picture.accept_marked([data], chat_id: chat, request_id: "q_1", tab: "tab-1", generation: 1,
                                                      words: with_words).first.note
  end

  [" ", "　", " ", " ", " ", "  ", "​", "\n"].each do |space|
    it "leaves out a name that holds a hidden word written with #{space.dump}" do
      note = note_for("report #{hidden.sub(' ', space)} 2026.png", words)
      expect(note).to include("the image (work screen item i_1)")
      %w[Zebulon Quartzfield].each { |part| expect(note).not_to include(part) }
    end
  end

  it "tells a name that holds none, with every space made a plain one" do
    expect(note_for("Screenshot 2026-11-28 at　9.png", words))
      .to include('the image "Screenshot 2026-11-28 at 9.png" (work screen item i_1)')
  end

  it "does not tell half of a hidden word where a long name is cut" do
    name = "#{'x' * (Monadic::Workbench::Picture::NAME_LIMIT - 8)} #{hidden}.png"
    note = note_for(name, words)
    expect(note).not_to include("Zebulon")
    long = note_for("#{'word ' * 40}end.png", [])
    expect(long[/the image "([^"]*)"/, 1]).to end_with("word…")
  end

  it "tells no name when the chat's words are not known" do
    expect(note_for("plain.png", nil)).to include("the image (work screen item i_1)")
  end
end

# A picture with several marks: each with its own id, change count and place,
# numbered in the note as on the picture.
RSpec.describe "a marked picture with several marks" do
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:png) { "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [8, 8].pack("NN") + "\x08\x02\x00\x00\x00".b }
  let(:picture) { Monadic::Workbench::Picture }

  def mark(id, rev, shape, x)
    { "id" => id, "rev" => rev, "mark" => { "shape" => shape, "color" => "cyan", "x" => x, "y" => 0.1, "w" => 0.2, "h" => 0.3 },
      "rect" => { "x" => x, "y" => 0.2, "w" => 0.1, "h" => 0.1 } }
  end

  def accept(marks)
    item = { id: "i_1", kind: "file", preview: "image", version: "v" * 64, place: "current", name: "plan.png" }
    board = double("board", board_texts_clear?: true, observe: { items: [item], selected: nil })
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat).and_return(board)
    data = { "item_id" => "i_1", "version" => "v" * 64, "marks" => marks, "image" => Base64.strict_encode64(png) }
    picture.accept_marked([data], chat_id: chat, request_id: "q_1", tab: "tab-1", generation: 1, words: []).first
  end

  def refused(marks)
    expect { accept(marks) }.to raise_error(picture::Refused) { |e| expect(e.reason).to eq("bad_mark") }
  end

  it "keeps each mark, numbers them in the note, and keeps them in the message's reference" do
    taken = accept([mark("m_aaaaaaaa", 1, "rect", 0.1), mark("m_bbbbbbbb", 3, "ellipse", 0.5)])
    expect(taken.marks.map { |m| [m["id"], m["rev"], m["shape"], m["rect"]["x"]] })
      .to eq([["m_aaaaaaaa", 1, "rect", 0.1], ["m_bbbbbbbb", 3, "ellipse", 0.5]])
    expect(taken.note).to include("marked 2 parts of it")
    expect(taken.note).to include("mark 1, a cyan rectangle at left 10%")
    expect(taken.note).to include("mark 2, a cyan ellipse at left 50%")
    reference = taken.reference
    expect(reference["marks"].map { |m| m["id"] }).to eq(%w[m_aaaaaaaa m_bbbbbbbb])
    expect(picture.clean(reference)).to eq(reference)
  end

  it "says one mark of the list as one mark is said" do
    taken = accept([mark("m_aaaaaaaa", 1, "rect", 0.1)])
    expect(taken.note).not_to include("parts of it")
    expect(taken.reference).not_to have_key("marks")
    expect(taken.reference["mark_id"]).to eq("m_aaaaaaaa")
  end

  it "refuses an empty list, more marks than a picture takes, an id twice, and a mark that is not one" do
    refused([])
    refused((1..(picture::MARKS_LIMIT + 1)).map { |n| mark("m_#{'a' * 7}#{n}", 1, "rect", 0.1) })
    refused([mark("m_aaaaaaaa", 1, "rect", 0.1), mark("m_aaaaaaaa", 2, "rect", 0.5)])
    refused([mark("m_aaaaaaaa", 1, "rect", 0.1), mark("bad", 1, "rect", 0.5)])
    refused([mark("m_aaaaaaaa", 1, "rect", 0.1).merge("rect" => { "x" => 2 })])
    refused(["not a mark"])
  end

  it "drops a kept list that is not one when checking a reference" do
    reference = accept([mark("m_aaaaaaaa", 1, "rect", 0.1), mark("m_bbbbbbbb", 1, "rect", 0.5)]).reference
    expect(picture.clean(reference.merge("marks" => [reference["marks"].first]))).not_to have_key("marks")
    expect(picture.clean(reference.merge("marks" => [{ "id" => "x" }, {}]))).not_to have_key("marks")
  end
end
