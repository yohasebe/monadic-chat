# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/workbench/url_file"

RSpec.describe Monadic::Workbench::UrlFile do
  let(:pdf_bytes) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b }

  # An answer as the http gem gives it: its body read in pieces (nil at
  # the end).
  def answer_of(code, headers, bytes, piece, on_close)
    pieces = bytes.b.scan(/.{1,#{piece}}/mn)
    body = Object.new
    body.define_singleton_method(:readpartial) { |_size = nil| pieces.shift }
    connection = Object.new
    connection.define_singleton_method(:close) { on_close.call }
    Struct.new(:code, :headers, :body, :connection).new(code, headers, body, connection)
  end

  # What the fetch asks: each address answers with what answers names
  # ([code, headers, body]); the addresses asked are kept.
  let(:asked) { [] }
  let(:connected_to) { [] }
  let(:closed) { [] }
  let(:answers) { {} }
  let(:client) do
    asked_list = asked
    table = answers
    closes = closed
    addresses = connected_to
    spec = self
    getter = Object.new
    getter.define_singleton_method(:get) do |url|
      asked_list << url
      code, headers, bytes, piece = table.fetch(url)
      spec.answer_of(code, headers, bytes.to_s, piece || 16, -> { closes << url })
    end
    lambda do |address|
      addresses << address
      getter
    end
  end
  let(:public_check) { ->(_host) { ["93.184.216.34"] } }

  def fetch(url, limit: 1024, check: public_check)
    described_class.fetch(url, limit: limit, client: client, check: check)
  end

  describe "whether an address serves a PDF" do
    it "takes a PDF by its content type" do
      answers["https://example.com/get?id=1"] = [200, { "Content-Type" => "application/pdf; charset=binary" }, pdf_bytes]
      expect(fetch("https://example.com/get?id=1")).to eq(name: "get.pdf", bytes: pdf_bytes)
    end

    it "takes a PDF by its first bytes when the type says otherwise" do
      answers["https://example.com/file"] = [200, { "Content-Type" => "application/octet-stream" }, pdf_bytes]
      expect(fetch("https://example.com/file")).to include(bytes: pdf_bytes)
    end

    it "leaves a page to the browser, after its first bytes only" do
      page = "<!doctype html><html>#{'x' * 500}</html>"
      answers["https://example.com/"] = [200, { "Content-Type" => "text/html" }, page]
      expect(fetch("https://example.com/")).to eq(:browser)
      expect(closed).to eq(["https://example.com/"])
    end

    it "leaves an answer that is not a success to the browser" do
      answers["https://example.com/gone.pdf"] = [404, { "Content-Type" => "application/pdf" }, ""]
      expect(fetch("https://example.com/gone.pdf")).to eq(:browser)
    end
  end

  describe "the connection" do
    it "goes to the address that was checked, not to a new look-up of the name" do
      answers["https://example.com/a.pdf"] = [200, { "Content-Type" => "application/pdf" }, pdf_bytes]
      fetch("https://example.com/a.pdf", check: ->(_host) { ["93.184.216.34", "93.184.216.35"] })
      expect(connected_to).to eq(["93.184.216.34"])
    end

    it "stops reading an answer that takes longer than the deadline" do
      stub_const("#{described_class}::DEADLINE", -1)
      answers["https://example.com/slow.pdf"] = [200, { "Content-Type" => "application/pdf" }, pdf_bytes]
      expect { fetch("https://example.com/slow.pdf") }.to raise_error(described_class::Failed, "unreachable")
    end

    it "connects a socket to the given address while the request names the host" do
      opened = []
      allow(TCPSocket).to receive(:open) { |*args| opened << args; raise Errno::ECONNREFUSED }
      socket_class = described_class::Asker.new("93.184.216.34").instance_variable_get(:@socket_class)
      expect { socket_class.open("example.com", 443) }.to raise_error(Errno::ECONNREFUSED)
      expect(opened).to eq([["93.184.216.34", 443]])
    end
  end

  describe "limits" do
    it "refuses a PDF larger than the limit, by its stated length or as it is read" do
      big = pdf_bytes + ("0" * 2000)
      answers["https://example.com/stated.pdf"] = [200, { "Content-Type" => "application/pdf",
                                                          "Content-Length" => big.bytesize.to_s }, big]
      answers["https://example.com/unstated.pdf"] = [200, { "Content-Type" => "application/pdf" }, big, 256]
      expect { fetch("https://example.com/stated.pdf") }.to raise_error(described_class::Failed, "too_large")
      expect { fetch("https://example.com/unstated.pdf") }.to raise_error(described_class::Failed, "too_large")
    end

    it "follows a few redirects, each checked, and no more" do
      answers["http://example.com/a"] = [302, { "Location" => "/b" }, ""]
      answers["http://example.com/b"] = [301, { "Location" => "https://cdn.example.org/paper.pdf" }, ""]
      answers["https://cdn.example.org/paper.pdf"] = [200, { "Content-Type" => "application/pdf" }, pdf_bytes]
      checked = []
      check = ->(host) { checked << host }
      expect(fetch("http://example.com/a", check: check)).to include(name: "paper.pdf")
      expect(checked).to eq(%w[example.com example.com cdn.example.org])

      asked.clear
      (0..4).each { |i| answers["https://loop.example.com/#{i}"] = [302, { "Location" => "/#{i + 1}" }, ""] }
      expect(fetch("https://loop.example.com/0")).to eq(:browser)
      expect(asked.size).to eq(described_class::REDIRECTS + 1)
    end

    it "does not follow a redirect to an address that is not http or https" do
      answers["https://example.com/a"] = [302, { "Location" => "file:///etc/passwd" }, ""]
      expect(fetch("https://example.com/a")).to eq(:browser)
      expect(asked).to eq(["https://example.com/a"])
    end

    it "does not ask a host that is not public, nor follow a redirect to one" do
      private_check = lambda do |host|
        raise Monadic::Utils::PublicAddress::Refused, "not public" if host == "internal.example.com"

        ["93.184.216.34"]
      end
      answers["https://example.com/a"] = [302, { "Location" => "https://internal.example.com/x.pdf" }, ""]
      expect(fetch("https://internal.example.com/x.pdf", check: private_check)).to eq(:browser)
      expect(asked).to be_empty
      expect(fetch("https://example.com/a", check: private_check)).to eq(:browser)
      expect(asked).to eq(["https://example.com/a"])
    end

    it "says the address could not be reached when the connection fails" do
      failing = ->(_address) { Object.new.tap { |o| o.define_singleton_method(:get) { |_url| raise HTTP::ConnectionError, "refused" } } }
      expect { described_class.fetch("https://example.com/x.pdf", limit: 1024, client: failing, check: public_check) }
        .to raise_error(described_class::Failed, "unreachable")
    end
  end

  describe "the file's name" do
    let(:uri) { URI.parse("https://example.com/papers/On%20Monads.PDF?x=1") }

    it "comes from Content-Disposition, plain or encoded" do
      expect(described_class.file_name('attachment; filename="report 2026.pdf"', uri)).to eq("report 2026.pdf")
      expect(described_class.file_name("inline; filename*=UTF-8''%E8%AB%96%E6%96%87.pdf", uri)).to eq("論文.pdf")
    end

    it "comes from the address's last part otherwise, and ends in .pdf" do
      expect(described_class.file_name(nil, uri)).to eq("On Monads.pdf")
      expect(described_class.file_name(nil, URI.parse("https://example.com/download"))).to eq("download.pdf")
      expect(described_class.file_name(nil, URI.parse("https://example.com/"))).to eq("document.pdf")
    end

    it "keeps no folder, control character or leading dot" do
      expect(described_class.file_name("attachment; filename=\"../../.secret\u0007.pdf\"", uri)).to eq("secret.pdf")
      expect(described_class.file_name('attachment; filename="a\\\\b.exe"', uri)).to eq("b.exe.pdf")
    end
  end

  describe "a PDF put on the work screen" do
    around do |example|
      Dir.mktmpdir("url-file-spec") do |dir|
        @data = File.join(dir, "data")
        @state = File.join(dir, "state")
        FileUtils.mkdir_p([@data, @state])
        example.run
      end
    end

    let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
    let(:session) { { chat_id: chat, parameters: { "app_name" => "ChatOpenAI" } } }
    let(:live) { ->(tab) { { "tab-1" => 1 }[tab] } }
    let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, "ledger.json")) }
    let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
      allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
      allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
      allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
      allow(Monadic::Workbench::Channel).to receive(:changed)
      Monadic::Workbench::Board.reset!
      Monadic::Workbench::Board.live = live
    end

    def put(fetched)
      described_class.put("https://example.com/paper.pdf", session, tab: "tab-1", generation: 1, live: live,
                                                                    fetcher: ->(_url, limit:) { fetched })
    end

    it "is a file of the chat's inputs on the board, selected for the tab" do
      answer = put(name: "paper.pdf", bytes: pdf_bytes)
      expect(answer).to include("as_file" => true, "item_id" => a_string_starting_with("i_"))
      board = Monadic::Workbench::Board.for(chat, store: store)
      item = board.snapshot[:items].find { |i| i[:id] == answer["item_id"] }
      expect(item).to include(kind: "file", name: "paper.pdf")
      expect(item[:path]).to match(%r{\Aconversations/[^/]+/inputs/a_[^/]+__paper\.pdf\z})
      expect(File.binread(File.join(@data, item[:path]))).to eq(pdf_bytes)
      expect(board.selected(tab: "tab-1", generation: 1)).to eq(answer["item_id"])
    end

    it "is nothing when the address is not a PDF (the browser opens it)" do
      expect(put(:browser)).to be_nil
      expect(Dir.glob(File.join(@data, "**", "*.pdf"))).to be_empty
    end

    it "is refused when the bytes are not a PDF after all" do
      expect(put(name: "paper.pdf", bytes: "not a pdf".b)).to eq("as_file" => true, "error" => "open_failed")
    end
  end
end
