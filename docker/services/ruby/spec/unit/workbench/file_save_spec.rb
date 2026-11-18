# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require "uri"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"

RSpec.describe "saving a file of the work screen under its own name" do
  around do |example|
    Dir.mktmpdir("workbench-save-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, _ws_generation: 1, messages: [] } }
  let(:channel) { Monadic::Workbench::Channel }
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:live) { ->(t) { live_tabs[t] } }
  let(:server) { Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, ["app"]] }, live: live) }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = live
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::ViewTokens.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def write(path, bytes)
    full = File.join(@data, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, bytes)
    full
  end

  # Opens path on the work screen and returns its item (id, sha256).
  def open_item(path, on: session)
    id = channel.open_file({ "path" => path }, on, tab: "tab-1", generation: 1, live: live)["item_id"]
    return nil unless id

    item = Monadic::Workbench::Board.for(on[:chat_id], store: store).snapshot[:items].find { |i| i[:id] == id }
    { "id" => item[:id], "sha256" => item[:sha256] }
  end

  def save(item, on: session, sha256: item["sha256"], generation: 1)
    channel.download({ "item_id" => item["id"], "sha256" => sha256 }, on, tab: "tab-1", generation: generation,
                                                                          live: live)
  end

  def play_address(item)
    channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][item["id"]]
  end

  def fetch(url, method: "GET", range: nil)
    env = { "PATH_INFO" => url, "REQUEST_METHOD" => method, "HTTP_SEC_FETCH_SITE" => "same-origin" }
    env["HTTP_RANGE"] = range if range
    server.call(env)
  end

  # The name filename* gives, decoded.
  def encoded_name(header)
    URI.decode_www_form_component(header[/filename\*=UTF-8''(\S+)\z/, 1].gsub("+", "%2B")).force_encoding("UTF-8")
  end

  describe "the address" do
    it "names the file by its own name and serves its bytes once, to save" do
      item = open_item("music/曲 1.mp3".tap { |p| write(p, "ID3 bytes") })
      answer = save(item)
      expect(answer).to include("type" => "workbench_download", "item_id" => item["id"], "name" => "曲 1.mp3")
      status, headers, body = fetch(answer["url"])
      expect(status).to eq(200)
      expect(body.join).to eq("ID3 bytes")
      expect(headers).to include("content-type" => "application/octet-stream", "x-content-type-options" => "nosniff",
                                 "cache-control" => "no-store", "content-length" => "9")
      expect(headers["content-disposition"]).to start_with("attachment;")
      expect(encoded_name(headers["content-disposition"])).to eq(answer["name"])
      expect(fetch(answer["url"]).first).to eq(404)
    end

    it "serves the whole file, not a range, and keeps the token after a HEAD" do
      item = open_item("clip.mp3".tap { |p| write(p, "0123456789") })
      url = save(item)["url"]
      expect(fetch(url, method: "HEAD").first).to eq(200)
      status, headers, body = fetch(url, range: "bytes=2-4")
      expect(status).to eq(200)
      expect(body.join).to eq("0123456789")
      expect(headers).not_to have_key("content-range")
    end

    it "saves bytes as they are: a BOM, CRLF, bytes that are not UTF-8, an empty file, a notebook" do
      {
        "bom.txt" => "\xEF\xBB\xBFone\r\ntwo".b,
        "latin.txt" => "caf\xE9\n".b,
        "empty.txt" => "".b,
        "nb.ipynb" => '{"cells":[],"metadata":{},"nbformat":4,"nbformat_minor":5}'.b
      }.each do |name, bytes|
        write(name, bytes)
        item = open_item(name)
        expect(item).not_to be_nil, name
        expect(fetch(save(item)["url"])[2].join.b).to eq(bytes)
      end
    end

    it "saves a text larger than the work screen shows of it" do
      stub_const("Monadic::Workspace::SharedFolderPreview::TEXT_LIMIT", 4)
      item = open_item("long.txt".tap { |p| write(p, "abcdefgh") })
      expect(fetch(save(item)["url"])[2].join).to eq("abcdefgh")
    end

    it "serves a page or an SVG as bytes to save, never as something the browser shows" do
      { "page.html" => "<script>alert(1)</script>", "pic.svg" => "<svg xmlns='http://www.w3.org/2000/svg'/>" }
        .each do |name, bytes|
          item = open_item(name.tap { |p| write(p, bytes) })
          _status, headers, = fetch(save(item)["url"])
          expect(headers["content-type"]).to eq("application/octet-stream")
          expect(headers["content-disposition"]).to start_with("attachment;")
        end
    end
  end

  describe "the name in the header" do
    [
      %(quote"d.txt), "semi;colon.txt", "tab\tname.txt", "bell\a.txt", ".hidden.txt",
      "日本語・記号（1）＆.txt", "#{'長' * 80}.txt"
    ].each do |name|
      it "stays one line with no new parameter, and decodes to the name, for #{name.inspect[0, 30]}" do
        item = open_item(name.tap { |p| write(p, "x") })
        _status, headers, = fetch(save(item)["url"])
        header = headers["content-disposition"]
        expect(header).not_to match(/[\r\n\0]/)
        expect(header.scan(";").size).to eq(2)
        expect(header[/filename="([^"]*)"/, 1]).to match(/\A[A-Za-z0-9._\-()+ ]+\z/)
        expect(header[/filename="([^"]*)"/, 1]).not_to start_with(".")
        expect(encoded_name(header)).to eq(name)
      end
    end

    it "cuts what it cannot hold and never breaks the header" do
      server = Monadic::Workbench::AssetServer.allocate
      header = server.send(:disposition, "attachment", "a\r\nb\"c;d\\e\0f#{'é' * 200}")
      expect(header).not_to match(/[\r\n]/)
      expect(header.scan(";").size).to eq(2)
      expect(header[/filename="([^"]*)"/, 1].size).to be <= Monadic::Workbench::AssetServer::FALLBACK_CHARS
      expect(encoded_name(header).bytesize).to be <= Monadic::Workbench::AssetServer::NAME_BYTES
      expect(encoded_name(header)).to be_valid_encoding
    end
  end

  describe "what each token serves" do
    it "plays inline under the file's name and never as an attachment" do
      item = open_item("clip.mp3".tap { |p| write(p, "0123456789") })
      _status, headers, = fetch(play_address(item))
      expect(headers["content-disposition"]).to start_with("inline;")
      expect(headers["content-type"]).to eq("audio/mpeg")
      expect(encoded_name(headers["content-disposition"])).to eq("clip.mp3")
    end

    it "does not take a token for saving in place of one for playing, or the other way" do
      item = open_item("clip.mp3".tap { |p| write(p, "0123456789") })
      play = play_address(item)
      expect(fetch(play)[1]["content-disposition"]).not_to start_with("attachment")
      expect(fetch(play).first).to eq(200)
      expect(fetch(save(item)["url"])[1]["content-type"]).to eq("application/octet-stream")
    end
  end

  describe "what it refuses" do
    it "refuses another chat's item, and both ids or neither" do
      other = { chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: 1, messages: [] }
      theirs = open_item("theirs.txt".tap { |p| write(p, "x") }, on: other)
      open_item("mine.txt".tap { |p| write(p, "y") })
      expect(save(theirs)).to include("status" => "refused", "reason" => "not_allowed")
      mine = open_item("mine.txt")
      both = { "item_id" => mine["id"], "sha256" => mine["sha256"], "artifact_id" => "a" }
      expect(channel.download(both, session, tab: "tab-1", generation: 1, live: live)).to include("status" => "refused")
      expect(channel.download({}, session, tab: "tab-1", generation: 1, live: live)).to include("status" => "refused")
    end

    it "refuses a version the board does not have, a malformed one, and a replaced connection" do
      item = open_item("a.txt".tap { |p| write(p, "x") })
      expect(save(item, sha256: "0" * 64)).to include("status" => "refused", "reason" => "changed")
      expect(save(item, sha256: "../x")).to include("status" => "refused", "reason" => "not_allowed")
      expect(save(item, generation: 2)).to include("status" => "refused", "reason" => "not_allowed")
    end

    it "answers 409 for a file changed after it was shown, never its newer bytes" do
      item = open_item("a.txt".tap { |p| write(p, "first") })
      url = save(item)["url"]
      write("a.txt", "second")
      status, _headers, body = fetch(url)
      expect(status).to eq(409)
      expect(body.join).not_to include("second")
    end

    it "answers 410 for a file no longer there, and 404 for a link put in its place" do
      item = open_item("a.txt".tap { |p| write(p, "x") })
      url = save(item)["url"]
      File.delete(File.join(@data, "a.txt"))
      expect(fetch(url).first).to eq(410)

      item = open_item("b.txt".tap { |p| write(p, "x") })
      url = save(item)["url"]
      write("elsewhere.txt", "x")
      File.delete(File.join(@data, "b.txt"))
      File.symlink(File.join(@data, "elsewhere.txt"), File.join(@data, "b.txt"))
      expect([404, 409, 410]).to include(fetch(url).first)
    end

    it "stops serving when the tab's connection changed, the chat was replaced, or the token expired" do
      item = open_item("a.txt".tap { |p| write(p, "x") })
      url = save(item)["url"]
      live_tabs["tab-1"] = 2
      expect(fetch(url).first).to eq(404)

      live_tabs["tab-1"] = 1
      url = save(item)["url"]
      now = Monadic::Workbench::ViewTokens.clock
      allow(Monadic::Workbench::ViewTokens).to receive(:clock).and_return(now + Monadic::Workbench::ViewTokens::TTL + 1)
      expect(fetch(url).first).to eq(404)
    end
  end
end
