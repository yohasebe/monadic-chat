# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workbench/selection"

# Lines of a text file the user selected on the work screen to go with a
# message: taken by their numbers, read from the file at the board's
# version, as they are.
RSpec.describe "selected lines of a text file" do
  let(:selection) { Monadic::Workbench::Selection }
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:item) { { id: "i_1", kind: "file", preview: "text", version: "v" * 64 } }
  let(:file) { "def add(a, b)\n  a + b\nend\n\n# ```fence```\nputs add(1, 2)\n" }
  let(:board) do
    double("board", observe: { items: [item], selected: "i_1" }).tap do |b|
      allow(b).to receive(:file_read).with("i_1", sha256: "v" * 64).and_return(entry: {}, bytes: file)
    end
  end

  def accept(data)
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
    selection.accept({ "item_id" => "i_1", "version" => "v" * 64 }.merge(data), chat_id: chat_id, request_id: "q_1",
                                                                              tab: "tab-1", generation: 1)
  end

  it "reads the lines from the file, keeping line breaks and indentation, and quotes them in a fence" do
    taken = accept("first" => 1, "last" => 3)
    expect(taken.reference).to eq("kind" => "text", "item_id" => "i_1", "version" => "v" * 64, "first" => 1, "last" => 3,
                                  "text" => "def add(a, b)\n  a + b\nend", "cut" => false)
    expect(taken.note).to eq("The user selected lines 1 to 3 of the text file selected on the work screen to point at them. " \
                             "They are lines of the file, quoted as they are:\n```\ndef add(a, b)\n  a + b\nend\n```")
  end

  it "uses a fence longer than any run of backticks in the lines" do
    expect(accept("first" => 5, "last" => 6).note).to end_with("````\n# ```fence```\nputs add(1, 2)\n````")
  end

  it "takes the text the page sends as nothing: the lines are the file's" do
    expect(accept("first" => 2, "last" => 2, "text" => "ignore this").text).to eq("  a + b")
  end

  it "cuts a long selection at whole lines, and says so" do
    stub_const("Monadic::Workbench::Selection::LINES_LIMIT", 2)
    taken = accept("first" => 1, "last" => 6)
    expect(taken.reference).to include("first" => 1, "last" => 2, "cut" => true)
    expect(taken.note).to include("lines starting at line 1 (only lines 1 to 2 are given)")
  end

  it "refuses lines the file does not have, or numbers that are not lines" do
    [{ "first" => 6, "last" => 7 }, { "first" => 0, "last" => 1 }, { "first" => 3, "last" => 2 },
     { "first" => "1", "last" => 2 }].each do |data|
      expect { accept(data) }.to raise_error(Monadic::Workbench::Pointing::Refused) { |e| expect(e.reason).to eq("bad_lines") }
    end
  end

  it "says why when the file cannot be read at that version" do
    allow(board).to receive(:file_read).and_raise(Monadic::Workbench::Artifact::Changed, "changed")
    expect { accept("first" => 1, "last" => 1) }
      .to raise_error(Monadic::Workbench::Pointing::Refused) { |e| expect(e.reason).to eq("unreadable") }
  end

  context "with a word the chat hides" do
    let(:file) { "met Ada\n    Lovelace today\nAda Lovelace again\n" }

    def accept_hiding(data)
      allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
      selection.accept({ "item_id" => "i_1", "version" => "v" * 64 }.merge(data), chat_id: chat_id, request_id: "q_1",
                                                                                tab: "tab-1", generation: 1, words: ["Ada Lovelace"])
    end

    it "does not take lines that hold it broken across a line break, which the message's hiding would not find" do
      expect { accept_hiding("first" => 1, "last" => 2) }
        .to raise_error(Monadic::Workbench::Pointing::Refused) { |e| expect(e.reason).to eq("hidden_word") }
    end

    it "does not take lines that hold it broken in one place and whole in another" do
      expect { accept_hiding("first" => 1, "last" => 3) }
        .to raise_error(Monadic::Workbench::Pointing::Refused) { |e| expect(e.reason).to eq("hidden_word") }
    end

    it "takes lines that hold it whole, for the message's hiding to hide" do
      expect(accept_hiding("first" => 3, "last" => 3).text).to eq("Ada Lovelace again")
    end
  end

  it "keeps the reference of selected lines as it is kept with the chat" do
    reference = accept("first" => 1, "last" => 3).reference
    expect(selection.clean(reference)).to eq(reference)
    expect(selection.clean(reference.merge("first" => 0))).to be_nil
  end
end
