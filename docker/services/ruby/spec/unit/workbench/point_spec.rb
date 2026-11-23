# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/point"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"

# The AI points at a part of what the asking tab shows: the place is found
# in the item itself, the tab is told, and the reply records it.
RSpec.describe "pointing at the work screen" do
  let(:point) { Monadic::Workbench::Point }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:told) { [] }

  around do |example|
    transport = point.transport
    Dir.mktmpdir("workbench-point-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  ensure
    point.transport = transport
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Shown).to receive(:add)
    point.transport = ->(*args) { told << args }
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

  def open_file(name, bytes)
    File.binwrite(File.join(@data, name), bytes)
    Monadic::Workbench::Board.for(chat, store: store)
                             .add_file(path: name, origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                                       epoch: Monadic::Workspace::Chats.epoch(chat)).first
  end

  def caller_for
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: request_id,
                                   session: session, tab: "tab-1", generation: 1)
  end

  let(:code) { "def add(a, b)\n  a + b\nend\n\ndef total(items)\n  items.sum\nend\n" }

  it "points at lines of a text by their numbers, tells the tab, and records it for the reply" do
    item = open_file("calc.rb", code)
    done = point.run(caller_for, first_line: 5, last_line: 7, label: "the total")
    expect(done[:point]).to eq("lines" => [5, 7], "label" => "the total")
    tab, generation, chat_id, json = told.first
    expect([tab, generation, chat_id]).to eq(["tab-1", 1, chat])
    expect(JSON.parse(json)).to eq("type" => "workbench_point", "item_id" => item["id"], "version" => item["file"]["sha256"],
                                   "point" => { "lines" => [5, 7], "label" => "the total" })
    expect(Monadic::Workbench::Shown).to have_received(:add)
      .with(request_id, hash_including("id" => item["id"]), point: { "lines" => [5, 7], "label" => "the total" })
  end

  it "finds the lines of a quote in the file, any run of space in it matching any run of space" do
    open_file("calc.rb", code)
    expect(point.run(caller_for, quote: "def total(items)   items.sum")[:point]).to eq("lines" => [5, 6])
    expect(point.run(caller_for, quote: "a + b")[:point]).to eq("lines" => [2, 2])
  end

  it "refuses a quote the file does not have, and lines it does not have" do
    open_file("calc.rb", code)
    expect { point.run(caller_for, quote: "def subtract") }.to raise_error(point::Refused, /not in the file/)
    expect { point.run(caller_for, first_line: 8) }.to raise_error(point::Refused, /first_line \(1 to 7\)/)
    expect { point.run(caller_for, first_line: 3, last_line: 2) }.to raise_error(point::Refused, /last_line/)
    expect { point.run(caller_for) }.to raise_error(point::Refused, /first_line/)
    expect(told).to be_empty
  end

  it "finds the page of a quote in a PDF, the page named first, and gives the quote as found" do
    open_file("paper.pdf", "%PDF-1.4\n%%EOF\n")
    pages = Monadic::Workbench::PdfText::Pages.new(
      pages: [{ page: 1, text: "the eastern library", cut: false }, { page: 3, text: "the eastern\nlibrary again", cut: false }],
      total_pages: 3, stopped_at: nil
    )
    allow(Monadic::Workbench::PdfText).to receive(:extract).and_return(pages)
    expect(point.run(caller_for, quote: "eastern library")[:point]).to eq("page" => 1, "quote" => "eastern library")
    expect(point.run(caller_for, quote: "eastern library", page: 3)[:point]).to eq("page" => 3, "quote" => "eastern library")
    expect { point.run(caller_for, quote: "western") }.to raise_error(point::Refused, /not in the PDF/)
    expect { point.run(caller_for, first_line: 1) }.to raise_error(point::Refused, /quote/)
  end

  it "points at nothing else, and only for a reply that can" do
    open_file("photo.png", "\x89PNG\r\n\x1A\n".b)
    expect { point.run(caller_for, quote: "x") }.to raise_error(point::Refused, /text file or text of a PDF/)
    expect { point.run(nil, quote: "x") }.to raise_error(point::Refused, /cannot point/)
  end

  it "keeps the label to one short line" do
    open_file("calc.rb", code)
    label = point.run(caller_for, first_line: 1, label: "  the\nadd\tfunction #{'x' * 60}")[:point]["label"]
    expect(label).to start_with("the add function x")
    expect(label.length).to eq(point::LABEL_CHARS)
  end

  it "says what it pointed at to the model, or why not, as the tool" do
    open_file("calc.rb", code)
    tools = MonadicSharedTools::WorkbenchTools
    out = JSON.parse(tools.point(caller_for, quote: nil, first_line: "2", last_line: nil, page: nil, label: nil))
    expect(out).to eq("status" => "pointed", "name" => "calc.rb", "lines" => { "first" => 2, "last" => 2 })
    expect(tools.point(caller_for, quote: "nothing like it", first_line: nil, last_line: nil, page: nil, label: nil))
      .to start_with("❌ Nothing was pointed at")
  end

  it "keeps a point in a record of what a reply showed, and nothing that is not one" do
    shown = Monadic::Workbench::Shown
    base = { "path" => "calc.rb", "name" => "calc.rb", "sha256" => "a" * 64, "preview" => "text" }
    expect(shown.clean([base.merge("point" => { "lines" => [2, 3], "label" => "here" })]).first["point"])
      .to eq("lines" => [2, 3], "label" => "here")
    expect(shown.clean([base.merge("point" => { "page" => 2, "quote" => "eastern library" })]).first["point"])
      .to eq("page" => 2, "quote" => "eastern library")
    [{ "lines" => [3, 2] }, { "lines" => ["1", 2] }, { "page" => 0, "quote" => "x" }, { "page" => 1, "quote" => " " },
     { "page" => 1, "quote" => "x" * 301 }, "lines 1-2"].each do |bad|
      expect(shown.clean([base.merge("point" => bad)]).first).not_to have_key("point")
    end
    expect(shown.clean([base.merge("point" => { "lines" => [1, 1], "label" => "a\nb" })]).first["point"]).to eq("lines" => [1, 1])
  end
end
