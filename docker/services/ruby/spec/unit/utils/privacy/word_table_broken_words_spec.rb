# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/privacy/word_table"

# A word the chat hides, broken in a text by a line break, an indentation or
# a character that shows nothing: what an exact match does not find.
RSpec.describe "finding a hidden word that whitespace breaks" do
  let(:table) { Monadic::Utils::Privacy::WordTable }
  let(:words) { ["Ada Lovelace", "Babbage"] }

  it "finds a word broken by a line break, an indentation or an unseen character" do
    expect(table.broken_words("met Ada\nLovelace today", words)).to eq(["Ada Lovelace"])
    expect(table.broken_words("met Ada\n    Lovelace today", words)).to eq(["Ada Lovelace"])
    expect(table.broken_words("met Ada ​Lovelace", words)).to eq(["Ada Lovelace"])
    expect(table.broken_words("Bab­bage", words)).to eq(["Babbage"])
  end

  it "finds a word broken somewhere even where it is also whole elsewhere" do
    expect(table.broken_words("Ada Lovelace wrote to\nAda\nLovelace again", words)).to eq(["Ada Lovelace"])
    expect(table.broken_words("met Ada\nLovelace, and Ada Lovelace", words)).to eq(["Ada Lovelace"])
    expect(table.broken_words("Ada Lovelace and Ada Lovelace", words)).to eq([])
  end

  it "leaves out a word found as it is, and a word not there" do
    expect(table.broken_words("met Ada Lovelace today", words)).to eq([])
    expect(table.broken_words("met Ada\ntoday", words)).to eq([])
    expect(table.broken_words("", words)).to eq([])
  end
end
