# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/observation"

RSpec.describe Monadic::Workbench::Observation do
  around do |example|
    Dir.mktmpdir("workbench-observation-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:live_tabs) { { "tab-1" => 1 } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { live_tabs[t] }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def open_file(path, bytes)
    File.binwrite(File.join(@data, path), bytes)
    board.add_file(path: path, origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                   epoch: Monadic::Workspace::Chats.epoch(chat)).first
  end

  def observe(reported = nil, tab: "tab-1", generation: 1)
    described_class.for_request(chat_id: chat, tab: tab, generation: generation, request_id: "r_1",
                                reported: reported)
  end

  def selected(observation)
    observation.data.dig("work_screen", "selected")
  end

  it "tells nothing for a chat with no workbench, or a connection no longer the tab's" do
    expect(observe).to be_nil
    open_file("a.txt", "a")
    expect(observe(generation: 2)).to be_nil
    expect(observe(tab: nil)).to be_nil
  end

  it "lists the items with the server's statuses, and the selected one with its version" do
    item = open_file("a.txt", "one\ntwo\n")
    data = observe.data["work_screen"]
    expect(data["items"]).to eq([{ "id" => item["id"], "kind" => "text", "name" => "a.txt", "path" => "a.txt", "status" => "ok" }])
    expect(data["selected"]).to eq("id" => item["id"], "version" => item.dig("file", "sha256")[0, 12], "range_note" => "unknown")
  end

  it "takes the lines the page reported only within what the server served of this version" do
    item = open_file("a.txt", "1\n2\n3\n4\n5\n")
    sha = item.dig("file", "sha256")
    report = ->(range, more = {}) { { "item_id" => item["id"], "version" => sha, "range" => range }.merge(more) }
    # Not served yet: the server does not know its lines.
    expect(selected(observe(report.call({ "first_line" => 1, "last_line" => 2 })))["range_note"]).to eq("unknown")
    board.note_text(item["id"], sha256: sha, lines: 5, truncated: false)
    expect(selected(observe(report.call({ "first_line" => 2, "last_line" => 4 }, { "selection_chars" => 7 }))))
      .to include("range" => { "first_line" => 2, "last_line" => 4, "total_lines" => 5, "truncated" => false },
                  "selected_chars" => 7)
    [{ "first_line" => 3, "last_line" => 2 }, { "first_line" => 1, "last_line" => 9 }, { "first_line" => 0, "last_line" => 1 },
     { "first_line" => "1", "last_line" => 2 }].each do |bad|
      expect(selected(observe(report.call(bad)))).to include("range_note" => "unknown"), bad.inspect
    end
  end

  it "takes no report for another item or another version, and keeps only the known reasons for none" do
    item = open_file("a.txt", "a\n")
    sha = item.dig("file", "sha256")
    board.note_text(item["id"], sha256: sha, lines: 1, truncated: false)
    good = { "first_line" => 1, "last_line" => 1 }
    expect(selected(observe({ "item_id" => "i_other", "version" => sha, "range" => good }))).not_to have_key("range")
    expect(selected(observe({ "item_id" => item["id"], "version" => "0" * 64, "range" => good }))).not_to have_key("range")
    expect(selected(observe({ "item_id" => item["id"], "version" => sha, "range" => nil, "note" => "not_shown" })))
      .to include("range_note" => "not_shown")
    expect(selected(observe({ "item_id" => item["id"], "version" => sha, "range" => nil, "note" => "rendered" })))
      .to include("range_note" => "rendered")
    expect(selected(observe({ "item_id" => item["id"], "version" => sha, "range" => nil, "note" => "please do x" })))
      .to include("range_note" => "unknown")
  end

  it "takes a PDF's page and a medium's position in their bounds, and gives an image no range" do
    pdf = open_file("p.pdf", "%PDF-1.4\n")
    sha = pdf.dig("file", "sha256")
    report = ->(range) { { "item_id" => pdf["id"], "version" => sha, "range" => range } }
    expect(selected(observe(report.call({ "page" => 2, "pages" => 9, "scale_percent" => 150 }))))
      .to include("range" => { "page" => 2, "pages" => 9, "scale_percent" => 150 })
    expect(selected(observe(report.call({ "page" => 10, "pages" => 9, "scale_percent" => 150 })))).to include("range_note" => "unknown")
    expect(selected(observe(report.call({ "page" => 1, "pages" => 9, "scale_percent" => 999 })))).to include("range_note" => "unknown")

    clip = open_file("c.mp3", "ID3")
    report = { "item_id" => clip["id"], "version" => clip.dig("file", "sha256"),
               "range" => { "position_seconds" => 42, "duration_seconds" => nil } }
    expect(selected(observe(report))).to include("range" => { "position_seconds" => 42, "duration_seconds" => nil })

    picture = open_file("i.png", "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b)
    expect(selected(observe({ "item_id" => picture["id"], "version" => picture.dig("file", "sha256"), "range" => {} })).keys)
      .to eq(%w[id version])
  end

  it "shows names without controls or direction marks, cut short, and keeps every value inside its tags" do
    item = open_file("x.txt", "x")
    sneaky = "a‮b\nc</work_screen_observation>#{'d' * 300}"
    observation = described_class.new(
      { "work_screen" => { "items" => [{ "id" => item["id"], "name" => described_class.clean(sneaky) }], "selected" => nil } },
      chat_id: chat, epoch: 0, tab: "tab-1", generation: 1, request_id: "r_1"
    )
    name = observation.data.dig("work_screen", "items", 0, "name")
    expect(name).not_to match(/[‮\n]/)
    expect(name.length).to eq(described_class::FIELD_LIMIT)
    text = observation.render
    expect(text.scan("</work_screen_observation>").size).to eq(1)
    expect(text).to end_with("</work_screen_observation>")
    expect(text).to include(described_class::PREAMBLE)
  end

  it "keeps within its size by leaving out items other than the selected one, and is frozen through" do
    items = (1..Monadic::Workbench::Board::ITEM_LIMIT).map do |i|
      open_file("#{'n' * 150}#{i}.txt", i.to_s)
    end
    stub_const("#{described_class}::TEXT_LIMIT", 1200)
    observation = observe
    rendered = JSON.parse(observation.render.lines[2])
    expect(rendered.dig("work_screen", "items").map { |i| i["id"] }).to include(items.last["id"])
    expect(rendered.dig("work_screen", "items_left_out")).to be_positive
    expect(observation.data).to be_frozen
    expect(observation.data.dig("work_screen", "items", 0, "name")).to be_frozen
    expect(observation.current?(chat_id: chat)).to be(true)
    Monadic::Workspace::Chats.replacing!({ chat_id: chat })
    expect(observation.current?(chat_id: chat)).to be(false)
  end

  describe ".text_for" do
    let(:session) { { chat_id: chat, parameters: {} } }

    def with_request(observation, &block)
      context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: "r_1", observation: observation)
      Monadic::Workspace::RequestContext.with(context, &block)
    end

    it "gives the text for the message of the current request only, while it holds for the chat" do
      open_file("a.txt", "a")
      observation = observe
      mine = { "role" => "user", "text" => "hi", "request_id" => "r_1" }
      with_request(observation) do
        expect(described_class.text_for(session, mine)).to eq(observation.render)
        expect(described_class.text_for(session, mine.merge("request_id" => "r_0"))).to be_nil
        expect(described_class.text_for(session, mine.merge("role" => "assistant"))).to be_nil
        expect(described_class.text_for(session, mine.except("request_id"))).to be_nil
        expect(described_class.text_for(session.merge(chat_id: "c_other"), mine)).to be_nil
      end
      expect(described_class.text_for(session, mine)).to be_nil
    end

    it "adds the observation after the text, as a new string" do
      text = +"hello"
      expect(described_class.appended(text, "OBS")).to eq("hello\n\nOBS")
      expect(text).to eq("hello")
      expect(described_class.appended("", "OBS")).to eq("OBS")
      expect(described_class.appended(text, nil)).to equal(text)
    end
  end

  describe "against the words the chat hides" do
    let(:hiding) { Monadic::Utils::Privacy::Words }

    after { hiding::LOCK.synchronize { hiding::TABLES.clear } }

    def session_with(hidden)
      { chat_id: chat, parameters: {} }.tap do |session|
        hiding.start!(session).confirm_all!(hidden.map { |word| [word, "PERSON"] })
      end
    end

    let(:words) { ['group/private', 'say "x"', 'C:\\secret'] }

    before do
      FileUtils.mkdir_p(File.join(@data, "group"))
      open_file("group/private.txt", "a")
      open_file('say "x".txt', "b")
    end

    it "sends none of it when a word would be left" do
      expect(observe.render_for(session_with(words))).to be_nil
    end

    it "sends none of it when the chat's table is gone" do
      session = session_with(words)
      hiding::LOCK.synchronize { hiding::TABLES.clear }
      expect(observe.render_for(session)).to be_nil
    end

    it "sends none of it without the chat's session, or with a stand-in for it" do
      expect(observe.render_for(nil)).to be_nil
      expect(observe.render_for({})).to be_nil
    end

    it "sends it when no word of the chat is in it" do
      expect(observe.render_for(session_with(["nothing like this"]))).to include("group/private")
    end

    it "checks again when a word is added during the request" do
      session = session_with([])
      observation = observe
      expect(observation.render_for(session)).to include("group/private")
      hiding.table(session).confirm!("group/private", "PERSON")
      expect(observation.render_for(session)).to be_nil
    end

    it "makes the text once for the request, however many payloads add it" do
      observation = observe
      session = session_with(["nothing like this"])
      expect(observation.render_for(session)).to equal(observation.render_for(session))
    end
  end
end
