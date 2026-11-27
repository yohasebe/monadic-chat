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
    board = double("board", observe: { items: [item], selected: nil })
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
