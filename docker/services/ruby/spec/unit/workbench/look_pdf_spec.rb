# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "base64"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/look/record"
require_relative "../../../lib/monadic/adapters/base_vendor_helper"

# A look at a PDF: the part of the page in view as the tab drew it, the
# text of that page from the PDF, and the text the user selected, each
# kept apart; or the text of its first pages.
RSpec.describe "looking at a PDF on the work screen" do
  let(:capture) { Monadic::Workbench::Capture }
  let(:look) { Monadic::Workbench::Look }
  let(:pdf_text) { Monadic::Workbench::PdfText }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }

  around do |example|
    transport = capture.transport
    Dir.mktmpdir("workbench-pdf-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  ensure
    capture.transport = transport
    capture.reset!
  end

  before do
    capture.reset!
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { live_tabs[t] }
    Monadic::Workbench::Look::Ledger.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def open_pdf
    File.binwrite(File.join(@data, "paper.pdf"), pdf)
    board.add_file(path: "paper.pdf", origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                   epoch: Monadic::Workspace::Chats.epoch(chat)).first
  end

  def caller_for
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: request_id,
                                   session: session, tab: "tab-1", generation: 1)
  end

  def ledger
    Monadic::Workbench::Look::Ledger.find(chat, request_id)
  end

  # The tab's answer.
  def page(answer)
    capture.transport = lambda do |_tab, _generation, _chat, json|
      request = JSON.parse(json)
      @asked = request
      Thread.new { capture.reading(request["id"], 2) { answer } }
      true
    end
  end

  def drawn(width: 40, height: 30, page_number: 2, pages: 9, **extra)
    { "range" => { "page" => page_number, "pages" => pages }, "note" => nil,
      "image" => Base64.strict_encode64(png(width, height)),
      "crop" => { "x" => 0, "y" => 10.5, "width" => 400, "height" => 300, "sent_width" => width, "sent_height" => height } }
      .merge(extra)
  end

  def texts(*pages, total: 9, stopped_at: nil)
    pdf_text::Pages.new(pages: pages.map { |n, t| { page: n, text: t, cut: false } }, total_pages: total,
                        stopped_at: stopped_at)
  end

  def result(text)
    JSON.parse(text.to_s)
  end

  describe "scope visible" do
    it "gives the part of the page in view, the page's text and the selected text, each said apart" do
      item = open_pdf
      page(drawn("selection_text" => "chosen words"))
      allow(pdf_text).to receive(:extract).and_return(texts([2, "page two text"]))
      out = result(look.run(caller_for, scope: "visible"))
      expect(@asked).to include("item_id" => item["id"], "wants" => %w[range image selection])
      expect(out).to include("pages" => { "first" => 2, "last" => 2, "total" => 9 },
                             "parts" => { "image" => true, "page_text" => true, "selection" => true },
                             "page_text" => "page two text", "selected_text" => "chosen words")
      expect(out["image"]).to include("as the tab drew it")
      expect(pdf_text).to have_received(:extract).with(pdf.b, first: 2, last: 2, deadline: kind_of(Float),
                                                              chars: look::TEXT_CHARS - "chosen words".length)
      observation = ledger.observations_with_content.first
      expect(observation.image.source).to eq("workbench_capture")
      expect(observation.caption).to include('"page":2')
      record = ledger.records.first
      expect(record).to include("kind" => "pdf", "image" => true, "source" => "workbench_capture",
                                "version" => item["file"]["sha256"], "pages" => { "first" => 2, "last" => 2, "total" => 9 })
      expect(record["image_sha256"]).to eq(Digest::SHA256.hexdigest(png(40, 30)))
    end

    it "keeps the page's text when the image could not be had, and says why" do
      open_pdf
      page(drawn("image" => nil, "image_note" => "redrawn"))
      allow(pdf_text).to receive(:extract).and_return(texts([2, "two"]))
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["parts"]).to eq({ "image" => "redrawn", "page_text" => true, "selection" => "none" })
      expect(out).not_to have_key("image")
      expect(ledger.records.first).to include("image" => false)
    end

    it "gives the image alone when the PDF's text cannot be read" do
      open_pdf
      page(drawn)
      allow(pdf_text).to receive(:extract).and_raise(pdf_text::Unavailable.new("pdf_text_unavailable", "not running"))
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["parts"]).to include("image" => true, "page_text" => "pdf_text_unavailable")
      expect(out).not_to have_key("page_text")
    end

    it "gives the selected text alone, and refuses when nothing could be had" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_raise(pdf_text::Unavailable.new("pdf_text_unavailable", "not running"))
      page(drawn("image" => nil, "image_note" => "not_in_view", "selection_text" => "only this"))
      expect(result(look.run(caller_for, scope: "visible"))).to include("selected_text" => "only this")
      page(drawn("image" => nil, "image_note" => "not_in_view"))
      expect(look.run(caller_for, scope: "visible")).to include("(pdf_text_unavailable)")
    end

    it "takes no image that is not what the tab says it cut, or too large to send" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "two"]))
      page(drawn.merge("crop" => drawn["crop"].merge("sent_width" => 99)))
      expect(result(look.run(caller_for, scope: "visible"))["parts"]["image"]).to eq("failed")
      page(drawn(width: 3000, height: 10))
      expect(result(look.run(caller_for, scope: "visible"))["parts"]["image"]).to eq("too_large")
      page(drawn("image" => "not base64!"))
      expect(result(look.run(caller_for, scope: "visible"))["parts"]["image"]).to eq("failed")
      page(drawn.merge("crop" => drawn["crop"].merge("width" => -5)))
      expect(result(look.run(caller_for, scope: "visible"))["parts"]["image"]).to eq("failed")
    end

    it "refuses a page the PDF does not have, and a PDF of another length" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "two"], total: 4))
      page(drawn)
      expect(look.run(caller_for, scope: "visible")).to include("(changed)")
      page(drawn(page_number: 10, pages: 9))
      expect(look.run(caller_for, scope: "visible")).to include("(range_unknown)")
    end

    it "says why when the tab gives no page" do
      open_pdf
      { "not_shown" => "not_shown", "drawing" => "drawing", "changing" => "selection_changed", nil => "range_unknown" }
        .each do |note, reason|
          page({ "range" => nil, "note" => note })
          expect(look.run(caller_for, scope: "visible")).to include("(#{reason})")
        end
    end

    it "cuts a long selection, and counts it in the request's characters" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "two"]))
      page(drawn("image" => nil, "image_note" => "failed", "selection_text" => "s" * 9000))
      out = result(look.run(caller_for, scope: "visible"))
      expect(out["selected_text"].length).to eq(8000)
      expect(out["selected_text_cut"]).to be(true)
      expect(ledger.observations([ledger.records.first["id"]]).first.text_chars).to eq(8003)
    end

    it "says when the page's text or the selection was cut, in the result and in the record" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(
        pdf_text::Pages.new(pages: [{ page: 2, text: "t" * 10, cut: true }], total_pages: 9, stopped_at: nil)
      )
      page(drawn("selection_text" => "s" * 9000))
      out = result(look.run(caller_for, scope: "visible"))
      expect(pdf_text).to have_received(:extract).with(anything, hash_including(chars: look::TEXT_CHARS - 8000))
      expect(out).to include("page_text_cut" => true, "selected_text_cut" => true, "truncated" => true)
      taken = Monadic::Workbench::Look::Ledger.take(request_id)
      record = Monadic::Workbench::Look::Record.clean(taken.records).first
      expect(record).to include("cuts" => %w[page_text selection], "truncated" => true)
      expect(record["crop"]).to eq({ "x" => 0, "y" => 10.5, "width" => 400, "height" => 300, "sent_width" => 40,
                                     "sent_height" => 30 })
    end

    it "takes no answer whose parts besides the image are too large" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "two"]))
      stub_const("Monadic::Workbench::Capture::WAIT", 0.5)
      page(drawn("selection_text" => "s" * (capture::BODY_LIMIT + 1)))
      expect(look.run(caller_for, scope: "visible")).to include("(capture_timeout)")
    end

    it "lets the image and the texts go when the reply ends, and keeps what the parts were" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "secret page"]))
      page(drawn("selection_text" => "secret words"))
      look.run(caller_for, scope: "visible")
      taken = Monadic::Workbench::Look::Ledger.take(request_id)
      expect(taken.observations_with_content).to be_empty
      record = taken.records.first
      expect(record).to include("image" => true, "parts" => { "image" => true, "page_text" => true, "selection" => true })
      expect(JSON.generate(record)).not_to include("secret")
    end

    it "gives a request that left out an earlier round the look's text with its image" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([2, "page two text"]))
      page(drawn("selection_text" => "chosen"))
      look.run(caller_for, scope: "visible")
      helper = Class.new { include BaseVendorHelper }.new
      observation = ledger.observations_with_content.first
      now = helper.workbench_look_parts(observation)
      expect(now[:text]).not_to include("page two text")
      earlier = helper.workbench_look_parts(BaseVendorHelper::EarlierLook.new(observation))
      expect(earlier[:image]).to eq(observation.image)
      expect(earlier[:text]).to include(observation.caption, "page two text", "chosen")
    end
  end

  describe "scope whole" do
    it "gives the text of the first pages, says where they stop, and asks the tab nothing" do
      open_pdf
      capture.transport = ->(*) { raise "the tab is not asked" }
      allow(pdf_text).to receive(:extract).and_return(texts([1, "one"], [2, ""], total: 140))
      out = result(look.run(caller_for, scope: "whole"))
      expect(pdf_text).to have_received(:extract).with(pdf.b, first: 1, last: 100, deadline: kind_of(Float),
                                                              chars: look::TEXT_CHARS - (100 * look::Pdf::PAGE_LINE_CHARS))
      expect(out).to include("pages" => { "first" => 1, "last" => 2, "total" => 140 }, "truncated" => true)
      expect(out["page_text"]).to eq("--- page 1 ---\none\n--- page 2 ---\n\n")
      expect(out).not_to have_key("image")
    end

    it "gives no more characters than it gives for any look, with the lines that name the pages" do
      open_pdf
      allow(pdf_text).to receive(:extract) do |_bytes, chars:, **|
        texts(*(1..100).map { |n| [n, "w" * (chars / 100)] }, total: 100)
      end
      out = result(look.run(caller_for, scope: "whole"))
      expect(out["page_text"].length).to be <= look::TEXT_CHARS
    end

    it "says a PDF with no text extracted is empty, not that it is blank" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_return(texts([1, ""], total: 1))
      expect(result(look.run(caller_for, scope: "whole"))).to include("empty" => true, "truncated" => false)
    end

    it "is refused when the PDF's text cannot be read" do
      open_pdf
      allow(pdf_text).to receive(:extract).and_raise(pdf_text::Unavailable.new("pdf_text_unavailable", "not running"))
      expect(look.run(caller_for, scope: "whole")).to include("(pdf_text_unavailable)")
    end
  end
end
