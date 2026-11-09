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

  describe "a snapshot (what one request is changed with)" do
    before do
      table.confirm!("Ada Lovelace", "PERSON")
      table.confirm!("Acme", "ORGANIZATION")
    end

    it "holds the words and the revision of the moment it was taken" do
      snap = table.snapshot
      table.confirm!("Grace", "PERSON")
      table.disable!("Acme")
      expect(snap.revision).to be < table.revision
      expect(snap.raw("Grace at Acme")).to eq("Grace at <<ORGANIZATION_1>>")
      expect(table.snapshot.raw("Grace at Acme")).to eq("<<PERSON_2>> at Acme")
    end

    it "sends a model's text again with the chat's placeholders, not as text, and words found since hidden too" do
      sent = table.apply("Ada Lovelace at Acme")
      table.confirm!("London", "LOCATION")
      snap = table.snapshot
      expect(snap.from_model("#{sent} in London")).to eq("<<PERSON_1>> at <<ORGANIZATION_1>> in <<LOCATION_1>>")
      # Applied once more, the same: nothing becomes text.
      expect(snap.from_model(snap.from_model(sent))).to eq(sent)
      # A placeholder the chat did not give is kept as text.
      expect(snap.from_model("<<PERSON_9>>")).to eq("\u2039\u2039PERSON_9\u203A\u203A")
    end

    it "sends a word taken off as it is, from the next request" do
      sent = table.apply("Acme")
      table.disable!("Acme")
      expect(table.snapshot.from_model(sent)).to eq("Acme")
    end

    describe "changing a tool's data" do
      let(:snap) { table.snapshot }

      it "changes every string, the values of name and id too, and strings of JSON inside, keeping keys" do
        result = {
          "name" => "Ada Lovelace", "id" => "Acme-1", "type" => "Acme",
          "rows" => [{ "text" => "Ada Lovelace at Acme", "n" => 3, "ok" => true, "none" => nil }],
          "saved" => JSON.generate({ "who" => "Ada Lovelace" })
        }
        out = snap.data(result)
        expect(out["name"]).to eq("<<PERSON_1>>")
        expect(out["id"]).to eq("<<ORGANIZATION_1>>-1")
        expect(out["type"]).to eq("<<ORGANIZATION_1>>")
        expect(out["rows"]).to eq([{ "text" => "<<PERSON_1>> at <<ORGANIZATION_1>>", "n" => 3, "ok" => true, "none" => nil }])
        expect(JSON.parse(out["saved"])).to eq("who" => "<<PERSON_1>>")
        expect(result["rows"][0]["text"]).to eq("Ada Lovelace at Acme")
      end

      it "changes a word inside a hash under any key" do
        expect(snap.data({ "name" => { "text" => "Acme" } })).to eq("name" => { "text" => "<<ORGANIZATION_1>>" })
      end

      it "changes a string that is JSON as what it decodes to" do
        table.confirm!("O\"Brien\\x", "PERSON")
        snap = table.snapshot
        expect(JSON.parse(snap.data('"\\u0041cme"'))).to eq("<<ORGANIZATION_1>>")
        expect(JSON.parse(snap.data(JSON.generate("see O\"Brien\\x")))).to eq("see <<PERSON_2>>")
        expect(JSON.parse(snap.data(JSON.generate({ "q" => JSON.generate("Acme") })))).to eq("q" => JSON.generate("<<ORGANIZATION_1>>"))
      end

      it "reads a model's tool call back before sending it again (origin :model)" do
        args = JSON.generate({ "query" => "<<PERSON_1>> biography" })
        expect(JSON.parse(snap.data(args, origin: :model))).to eq("query" => "<<PERSON_1>> biography")
        expect(JSON.parse(snap.data(args))).to eq("query" => "\u2039\u2039PERSON_1\u203A\u203A biography")
        expect(JSON.parse(snap.data(JSON.generate("<<PERSON_1>>"), origin: :model))).to eq("<<PERSON_1>>")
      end

      it "refuses a key that holds a word, without saying the word" do
        expect { snap.data({ "rows" => [{ "Acme" => 1 }] }) }.to raise_error(described_class::Unreplaceable) { |e|
          expect(e.message).not_to include("Acme")
          expect(e.place).to eq("an object key")
          expect(e.path).to eq(["rows", 0])
        }
      end

      it "refuses JSON nested too deeply, data nested too deeply, and what JSON cannot hold" do
        deep = "Acme"
        6.times { deep = JSON.generate([deep]) }
        expect { snap.data(deep) }.to raise_error(described_class::TooLarge, /JSON too deeply/)
        nested = "x"
        (described_class::MAX_NESTING + 1).times { nested = [nested] }
        expect { snap.data(nested) }.to raise_error(described_class::TooLarge, /nested too deeply/)
        looped = []
        looped << looped
        expect { snap.data(looped) }.to raise_error(described_class::TooLarge)
        at_limit = "#{"[" * described_class::MAX_NESTING}\"\\u0041cme\"#{"]" * described_class::MAX_NESTING}"
        expect(snap.data(at_limit)).to include("<<ORGANIZATION_1>>")
        over_limit = "[#{at_limit}]"
        expect { snap.data(over_limit) }.to raise_error(described_class::TooLarge)
        beyond_parser = "#{"[" * 101}\"\\u0041cme\"#{"]" * 101}"
        expect { snap.data(beyond_parser) }.to raise_error(described_class::TooLarge)
        expect { described_class.json_value(beyond_parser) }.to raise_error(described_class::TooLarge)
        expect { snap.data({ "at" => Time.now }) }.to raise_error(ArgumentError)
        [Float::NAN, Float::INFINITY].each { |n| expect { snap.data([n]) }.to raise_error(ArgumentError) }
        expect(snap.data([1.5])).to eq([1.5])
        expect { snap.data("x", origin: :assistant) }.to raise_error(ArgumentError)
      end

      it "counts every string and key as given, before decoding it" do
        stub_const("#{described_class}::MAX_CHARS", 10)
        expect { snap.data(%w[Acme Acme Acme]) }.to raise_error(described_class::TooLarge, /characters/)
        expect { snap.data({ "x" * 11 => 1 }) }.to raise_error(described_class::TooLarge, /characters/)
        expect { snap.data("#{" " * 11}{}") }.to raise_error(described_class::TooLarge, /characters/)
        budget = described_class::Budget.new
        snap.raw("Acme Acme", budget)
        expect { snap.from_model("Acme", budget) }.to raise_error(described_class::TooLarge, /characters/)
      end

      it "refuses more values and more replacements than it takes" do
        stub_const("#{described_class}::MAX_NODES", 3)
        expect { snap.data([1, 2, 3]) }.to raise_error(described_class::TooLarge, /values/)
        stub_const("#{described_class}::MAX_SPANS", 3)
        expect { snap.data("Acme " * 4) }.to raise_error(described_class::TooLarge, /words/)
        expect(snap.data("Acme " * 3)).to eq("<<ORGANIZATION_1>> " * 3)
      end
    end

    it "is frozen, with what it holds" do
      snap = table.snapshot
      expect(snap).to be_frozen
      expect { snap.instance_variable_get(:@mapping)["PERSON_1"][:word] = "Eve" }.to raise_error(FrozenError)
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
