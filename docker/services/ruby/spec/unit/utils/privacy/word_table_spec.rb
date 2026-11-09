# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../lib/monadic/utils/privacy/word_table"

RSpec.describe Monadic::Utils::Privacy::WordTable do
  let(:table) { described_class.new }

  describe "confirming words" do
    it "gives each word one placeholder for the chat, numbered by type" do
      expect(table.confirm!("Ada Lovelace", "PERSON")).to eq("PERSON_1")
      expect(table.confirm!("Acme", "ORGANIZATION")).to eq("ORGANIZATION_1")
      expect(table.confirm!("Grace Hopper", "PERSON")).to eq("PERSON_2")
      expect(table.confirm!("Ada Lovelace", "PERSON")).to eq("PERSON_1")
    end

    it "keeps a word's placeholder when its type is changed, and changes only how it is shown" do
      table.confirm!("Acme", "PERSON")
      before = table.revision
      expect(table.confirm!("Acme", "ORGANIZATION")).to eq("PERSON_1")
      expect(table.active_words).to eq([{ word: "Acme", id: "PERSON_1", type: "ORGANIZATION" }])
      expect(table.revision).to eq(before + 1)
      expect(table.apply("Acme")).to eq("<<PERSON_1>>")
    end

    it "never gives a number again, whatever words are taken off" do
      table.confirm!("Ada", "PERSON")
      table.confirm!("Grace", "PERSON")
      table.disable!("Grace")
      table.disable!("Ada")
      expect(table.confirm!("Linus", "PERSON")).to eq("PERSON_3")
      # A word confirmed again has its placeholder back.
      expect(table.confirm!("Ada", "PERSON")).to eq("PERSON_1")
    end

    it "grows the revision with every change, and not with what changes nothing" do
      expect(table.revision).to eq(0)
      table.confirm!("Ada", "PERSON")
      table.confirm!("Ada", "PERSON")
      expect(table.revision).to eq(1)
      expect(table.disable!("nobody")).to be(false)
      expect(table.revision).to eq(1)
      table.disable!("Ada")
      expect(table.revision).to eq(2)
    end

    it "refuses words it could not hide or read back" do
      ["", "  ", "a\nb", "x" * 201, "a<<b", "b>>", 7, nil].each do |word|
        expect { table.confirm!(word, "PERSON") }.to raise_error(described_class::Invalid), word.inspect
      end
      ["person", "", "PER SON", "1X"].each do |type|
        expect { table.confirm!("Ada", type) }.to raise_error(described_class::Invalid), type.inspect
      end
    end

    it "takes at most 200 active words" do
      200.times { |i| table.confirm!("word#{i}", "PERSON") }
      expect { table.confirm!("one more", "PERSON") }.to raise_error(described_class::Invalid, /200/)
    end

    it "gives one word one placeholder when confirmed at once from several threads" do
      ids = Array.new(8) { Thread.new { table.confirm!("Ada", "PERSON") } }.map(&:value)
      expect(ids.uniq).to eq(["PERSON_1"])
      others = Array.new(8) { |i| Thread.new { table.confirm!("name#{i}", "PERSON") } }.map(&:value)
      expect(others.uniq.size).to eq(8)
    end
  end

  describe "applying the words to a text" do
    before do
      table.confirm!("Ada Lovelace", "PERSON")
      table.confirm!("Acme", "ORGANIZATION")
    end

    it "replaces each active word, as written, wherever it is" do
      expect(table.apply("Ada Lovelace works at Acme. Acme likes Ada Lovelace."))
        .to eq("<<PERSON_1>> works at <<ORGANIZATION_1>>. <<ORGANIZATION_1>> likes <<PERSON_1>>.")
    end

    it "takes case and form as written, and no word inside another script's text is changed by normalizing" do
      expect(table.apply("ACME and acme and Ａｃｍｅ")).to eq("ACME and acme and Ａｃｍｅ")
    end

    it "finds words inside text without spaces, such as Japanese" do
      table.confirm!("江戸川今太郎", "PERSON")
      expect(table.apply("担当は江戸川今太郎さんです")).to eq("担当は<<PERSON_2>>さんです")
    end

    it "leaves a word inside a longer one to the longer" do
      table.confirm!("Ada", "PERSON")
      expect(table.apply("Ada Lovelace and Ada")).to eq("<<PERSON_1>> and <<PERSON_2>>")
    end

    it "reads the same word again left to right, as a replacement does" do
      table.confirm!("aa", "PERSON")
      expect(table.apply("aaa")).to eq("<<PERSON_2>>a")
    end

    it "hides nothing when two words overlap in part, and names them" do
      table.confirm!("ABC", "PERSON")
      table.confirm!("CDE", "PERSON")
      expect { table.apply("xABCDEx") }.to raise_error(described_class::Overlap) { |e| expect(e.pairs).to eq([%w[ABC CDE]]) }
      # Each alone is fine.
      expect(table.apply("ABC and CDE")).to eq("<<PERSON_2>> and <<PERSON_3>>")
    end

    it "keeps text that looks like a placeholder as text" do
      expect(table.apply("write <<PERSON_1>> and << PERSON_9 >> for Acme"))
        .to eq("write ‹‹PERSON_1›› and ‹‹ PERSON_9 ›› for <<ORGANIZATION_1>>")
    end

    it "no longer hides a word taken off, from the next text" do
      table.disable!("Acme")
      expect(table.apply("Acme")).to eq("Acme")
    end
  end

  describe "reading placeholders back" do
    before do
      table.confirm!("Ada Lovelace", "PERSON")
      table.confirm!("Acme", "ORGANIZATION")
    end

    it "puts back each placeholder the chat gave, in its clean form and as a model mangles it lightly" do
      expect(table.restore("<<PERSON_1>> at << ORGANIZATION_1 >> and <<?PERSON_1?>>"))
        .to eq("Ada Lovelace at Acme and Ada Lovelace")
    end

    it "leaves placeholders it did not give, and forms it does not take" do
      expect(table.restore("<<PERSON_7>> <PERSON_1> PERSON_1 <<person_1>>")).to eq("<<PERSON_7>> <PERSON_1> PERSON_1 <<person_1>>")
    end

    it "reads a word taken off back still, so what was sent with it reads back" do
      table.disable!("Ada Lovelace")
      expect(table.restore("<<PERSON_1>>")).to eq("Ada Lovelace")
    end

    it "puts back once: a word is not looked into again" do
      table.confirm!("<PERSON_1>", "PERSON")
      expect(table.restore("<<PERSON_2>>")).to eq("<PERSON_1>")
    end

    it "reads back what it sent as it was (but for text that looked like a placeholder)" do
      text = "Ada Lovelace and Acme, 江戸川"
      expect(table.restore(table.apply(text))).to eq(text)
    end
  end

  describe "keeping what it holds its own" do
    it "is not changed through the words given to it, the ids it gives, its lists or to_h" do
      word = +"Ada"
      type = +"PERSON"
      id = table.confirm!(word, type)
      word.replace("Eve")
      type.replace("PLACE")
      expect { id.replace("PERSON_99") }.to raise_error(FrozenError)
      expect { table.active_words.first[:word].replace("Eve") }.to raise_error(FrozenError)
      expect { table.active_words << {} }.to raise_error(FrozenError)
      data = table.to_h
      data["high"]["PERSON"] = 0
      data["mapping"]["PERSON_1"]["word"].replace("Eve")
      data["active"].first["id"].replace("PERSON_9")
      expect(table.apply("Ada")).to eq("<<PERSON_1>>")
      expect(table.restore("<<PERSON_1>>")).to eq("Ada")
      expect(table.confirm!("Eve", "PERSON")).to eq("PERSON_2")
    end

    it "is not changed through the data it was read from" do
      data = described_class.new.tap { |t| t.confirm!("Ada", "PERSON") }.to_h
      again = described_class.from_h(data)
      data["mapping"]["PERSON_1"]["word"].replace("Eve")
      data["high"]["PERSON"] = 0
      data["active"].first["word"].replace("Eve")
      expect(again.restore("<<PERSON_1>>")).to eq("Ada")
      expect(again.apply("Ada")).to eq("<<PERSON_1>>")
      expect(again.confirm!("Grace", "PERSON")).to eq("PERSON_2")
    end
  end

  describe "numbers" do
    it "refuses to give a number past the last, before changing anything" do
      data = { "schema" => 1, "mapping" => {}, "active" => [], "high" => { "PERSON" => described_class::MAX_NUMBER },
               "revision" => 0 }
      full = described_class.from_h(data)
      expect { full.confirm!("Ada", "PERSON") }.to raise_error(described_class::Invalid, /no number left/)
      expect(full.to_h).to eq(data)
      expect(full.confirm!("Acme", "ORGANIZATION")).to eq("ORGANIZATION_1")
      expect(described_class.from_h(full.to_h).to_h).to eq(full.to_h)
    end
  end

  describe "keeping the table" do
    it "comes back from what it gives as it was" do
      table.confirm!("Ada", "PERSON")
      table.confirm!("Grace", "PERSON")
      table.confirm!("Acme", "ORGANIZATION")
      table.disable!("Grace")
      again = described_class.from_h(JSON.parse(JSON.generate(table.to_h)))
      expect(again.to_h).to eq(table.to_h)
      expect(again.restore("<<PERSON_2>>")).to eq("Grace")
      expect(again.confirm!("Linus", "PERSON")).to eq("PERSON_3")
    end

    it "refuses a table not of its form" do
      good = described_class.new.tap { |t| t.confirm!("Ada", "PERSON") }.to_h
      bad = [
        nil, [], good.merge("schema" => 2), good.merge("mapping" => []), good.merge("revision" => -1),
        good.merge("mapping" => { "person_1" => { "word" => "Ada", "type" => "PERSON" } }),
        good.merge("mapping" => { "PERSON_1" => { "word" => "Ada", "type" => "ORGANIZATION" } }),
        good.merge("high" => { "PERSON" => 0 }),
        good.merge("active" => [{ "word" => "Ada", "id" => "PERSON_9", "type" => "PERSON" }]),
        good.merge("active" => [{ "word" => "Eve", "id" => "PERSON_1", "type" => "PERSON" }]),
        good.merge("active" => good["active"] * 2),
        good.merge("mapping" => { "PERSON_1" => { "word" => "a<<b", "type" => "PERSON" } }),
        # One word, two placeholders: the next confirm would not know which.
        good.merge("mapping" => { "PERSON_1" => { "word" => "Ada", "type" => "PERSON" },
                                  "PERSON_2" => { "word" => "Ada", "type" => "PERSON" } },
                   "high" => { "PERSON" => 2 }),
        # Numbers only in the form the table gives them, and within range.
        good.merge("mapping" => { "PERSON_01" => { "word" => "Ada", "type" => "PERSON" } }, "active" => []),
        good.merge("mapping" => { "PERSON_0" => { "word" => "Ada", "type" => "PERSON" } }, "active" => []),
        good.merge("high" => { "PERSON" => described_class::MAX_NUMBER + 1 }),
        good.merge("high" => (1..101).to_h { |i| ["T#{'A' * (i % 30)}#{i}".tr('0-9', 'A-J'), 0] }.merge("PERSON" => 1)),
        good.merge("active" => [{ "word" => "Ada", "id" => 1, "type" => "PERSON" }])
      ]
      bad.each { |data| expect { described_class.from_h(data) }.to raise_error(described_class::Invalid), data.inspect }
    end
  end
end
