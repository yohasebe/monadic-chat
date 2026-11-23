# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workbench/selection"

# Text the user selected in the work screen, sent with a message: what is
# taken, and what the model is told of it.
RSpec.describe Monadic::Workbench::Selection do
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:item) { { id: "i_1", kind: "file", preview: "pdf", version: "v" * 64 } }
  let(:board) { double("board", observe: { items: [item], selected: "i_1" }) }

  def sent(overrides = {})
    { "item_id" => "i_1", "version" => "v" * 64, "page" => 3, "pages" => 9,
      "text" => "The committee approved\nthe budget." }.merge(overrides)
  end

  def accept(data)
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
    described_class.accept(data, chat_id: chat_id, request_id: "q_1", tab: "tab-1", generation: 1)
  end

  it "takes the text the tab selected in the PDF it has selected, at its version, and quotes it" do
    selection = accept(sent)
    expect(selection.reference).to eq("item_id" => "i_1", "version" => "v" * 64, "page" => 3, "pages" => 9,
                                      "text" => "The committee approved\nthe budget.", "cut" => false)
    expect(selection.note).to start_with("The user selected the following text on page 3 of the PDF")
    expect(selection.note).to end_with("\n> The committee approved\n> the budget.")
    expect(selection.note).not_to include("only its first")
    expect(selection).to be_frozen
  end

  it "says when the page cut a longer selection" do
    expect(accept(sent("cut" => true)).note).to include("(only its first 2000 characters are given)")
  end

  it "takes no control characters but tabs and line breaks, and no space around the text" do
    expect(accept(sent("text" => "  a\u0000b\tc\u001Bd\r\ne  ")).text).to eq("ab\tcd\r\ne")
  end

  it "refuses what the board does not have as the page sent it, and text that is none or too long" do
    {
      "not_selected" => sent("item_id" => "i_2"),
      "changed" => sent("version" => "w" * 64),
      "bad_page" => sent("page" => 10),
      "bad_text" => sent("text" => "  \u0000 "),
      "not_a_picture" => "text"
    }.each do |reason, data|
      expect { accept(data) }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(reason) }
    end
    expect { accept(sent("text" => "x" * 2001)) }.to raise_error(described_class::Refused)
    expect { accept(sent("text" => 42)) }.to raise_error(described_class::Refused)
    expect(accept(sent("text" => "x" * 2000)).text.length).to eq(2000)
  end

  it "keeps a checked reference with the history" do
    reference = accept(sent).reference
    expect(described_class.clean(reference)).to eq(reference)
    expect(described_class.clean(reference.merge("text" => ""))).to be_nil
    expect(described_class.clean(reference.merge("page" => 0))).to be_nil
    expect(described_class.clean("not a hash")).to be_nil
  end
end
