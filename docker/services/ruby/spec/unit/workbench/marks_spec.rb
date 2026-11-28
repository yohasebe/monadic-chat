# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workbench/marks"

# The marks kept on the board as operations of the messages that sent them:
# what is shown, and what deleting a message brings back or takes off.
RSpec.describe Monadic::Workbench::Marks do
  let(:data) { {} }
  let(:origin) { "file:notes/plan.pdf" }
  let(:version) { "v" * 64 }

  def mark(id, rev = 1, page: 1)
    { "id" => id, "rev" => rev, "shape" => "rect", "color" => "orange", "page" => page,
      "rect" => { "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2 }, origin: origin, version: version }
  end

  def shown = described_class.shown(data, origin, version).map { |m| [m["id"], m["rev"]] }

  it "shows what the messages sent, and takes off what a deleted message added" do
    described_class.record!(data, "q_a", sent: [mark("m_aaaaaa")])
    described_class.record!(data, "q_b", sent: [mark("m_bbbbbb")])
    expect(shown).to eq([["m_aaaaaa", 1], ["m_bbbbbb", 1]])
    expect(described_class.undo!(data, "q_a")).to eq(0)
    expect(shown).to eq([["m_bbbbbb", 1]])
  end

  it "keeps a mark a later message used or changed when the message that added it is deleted" do
    described_class.record!(data, "q_a", sent: [mark("m_aaaaaa"), mark("m_cccccc")])
    described_class.record!(data, "q_b", sent: [mark("m_aaaaaa"), mark("m_cccccc", 2)])
    described_class.undo!(data, "q_a")
    expect(shown).to eq([["m_aaaaaa", 1], ["m_cccccc", 2]])
    described_class.undo!(data, "q_b")
    expect(shown).to eq([])
  end

  it "brings back what a deleted message erased, and keeps what later messages added" do
    described_class.record!(data, "q_a", sent: [mark("m_aaaaaa")])
    described_class.record!(data, "q_b", erased: [{ origin: origin, version: version, targets: [["m_aaaaaa", 1]] }])
    described_class.record!(data, "q_c", sent: [mark("m_cccccc")])
    expect(shown).to eq([["m_cccccc", 1]])
    described_class.undo!(data, "q_b")
    expect(shown).to eq([["m_aaaaaa", 1], ["m_cccccc", 1]])
  end

  it "keeps the marks of each version of an original apart" do
    described_class.record!(data, "q_a", sent: [mark("m_aaaaaa")])
    expect(described_class.shown(data, origin, "w" * 64)).to eq([])
    expect(described_class.shown(data, "file:notes/other.pdf", version)).to eq([])
  end

  it "records no new mark past the most shown, and refuses a deletion that would show more again" do
    limit = described_class::SHOWN_LIMIT
    ids = (1..limit).map { |i| format("m_%06d", i) }
    recorded = described_class.record!(data, "q_a", sent: ids.map { |id| mark(id) } + [mark("m_extra1")])
    expect(recorded).to eq(limit)
    described_class.record!(data, "q_b", erased: [{ origin: origin, version: version, targets: ids.map { |id| [id, 1] } }])
    described_class.record!(data, "q_c", sent: (1..limit).map { |i| mark(format("m_new%03d", i)) })
    expect(described_class.undo!(data, "q_b")).to eq(limit)
    expect(shown.size).to eq(limit)
  end

  it "counts the marks a message sent as new, and the others as earlier" do
    described_class.record!(data, "q_a", sent: [mark("m_aaaaaa")])
    described_class.record!(data, "q_b", sent: [mark("m_bbbbbb", page: 2)])
    expect(described_class.counts(data, origin, version, "q_b")).to eq("new" => 1, "earlier" => 1)
  end

  it "knows the original of a file, an image the AI made and a Library entry, and none of a browser" do
    expect(described_class.origin_of({ "kind" => "file", "file" => { "path" => "a.png" } })).to eq("file:a.png")
    expect(described_class.origin_of({ "kind" => "image", "artifact" => { "id" => "r_1" } })).to eq("artifact:r_1")
    expect(described_class.origin_of({ "kind" => "library", "library" => { "id" => "e1" } })).to eq("library:e1")
    expect(described_class.origin_of({ "kind" => "browser" })).to be_nil
  end
end
