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

# A look at an image the user marked: the image as the tab has it, with the
# mark drawn on it, and where the mark is; the image itself otherwise.
RSpec.describe "looking at an image the user marked on the work screen" do
  let(:capture) { Monadic::Workbench::Capture }
  let(:look) { Monadic::Workbench::Look }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }

  around do |example|
    transport = capture.transport
    Dir.mktmpdir("workbench-image-mark-spec") do |dir|
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

  def open_image
    File.binwrite(File.join(@data, "photo.png"), png(80, 60))
    board.add_file(path: "photo.png", origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
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

  def drawn(width: 40, height: 30, **extra)
    { "range" => {}, "note" => nil, "image" => Base64.strict_encode64(png(width, height)),
      "crop" => { "x" => 0, "y" => 0, "width" => 80, "height" => 60, "sent_width" => width, "sent_height" => height } }
      .merge(extra)
  end

  def result(text)
    JSON.parse(text.to_s)
  end

  let(:mark) { { "shape" => "ellipse", "color" => "cyan", "x" => 0.1, "y" => 0.25, "w" => 0.5, "h" => 0.2 } }

  it "gives the image as the tab has it with the mark drawn on it, and says where the mark is" do
    item = open_image
    page(drawn("mark" => mark))
    out = result(look.run(caller_for, scope: "visible"))
    expect(@asked).to include("item_id" => item["id"], "wants" => ["image"])
    expect(out["image"]).to eq("The image is attached after this result.")
    expect(out["marked"]).to eq("The user marked a part of it with a translucent cyan ellipse (left 10%, top 25%, width 50%, " \
                                "height 20% of the image) to point at it; the image attached is the one the tab shows, " \
                                "with the mark drawn on it.")
    observation = ledger.observations_with_content.first
    expect(observation.image.source).to eq("workbench_capture")
    expect([observation.image.width, observation.image.height]).to eq([40, 30])
  end

  it "gives the image itself when nothing is marked" do
    open_image
    page(drawn)
    out = result(look.run(caller_for, scope: "visible"))
    expect(out).not_to have_key("marked")
    expect(ledger.observations_with_content.first.image.source).to eq("workbench_file")
  end

  it "gives the image itself, and where the mark is, when the tab's image is not of the file's shape" do
    open_image
    page(drawn(width: 40, height: 40, "crop" => { "x" => 0, "y" => 0, "width" => 80, "height" => 60, "sent_width" => 40,
                                                  "sent_height" => 40 }, "mark" => mark))
    out = result(look.run(caller_for, scope: "visible"))
    expect(out["marked"]).to eq("The user marked a part of the image with a cyan ellipse (left 10%, top 25%, width 50%, " \
                                "height 20% of the image) to point at it.")
    expect(ledger.observations_with_content.first.image.source).to eq("workbench_file")
  end

  it "gives the image itself when the tab does not answer" do
    open_image
    capture.transport = ->(*) { false }
    out = result(look.run(caller_for, scope: "visible"))
    expect(out).not_to have_key("marked")
    expect(out["image"]).to eq("The image is attached after this result.")
  end

  it "says where the mark is to a conversation that takes no images" do
    open_image
    page(drawn("mark" => mark))
    out = result(look.run(caller_for, scope: "visible", images: false))
    expect(out["image"]).to eq(look::NO_IMAGE)
    expect(out["marked"]).to start_with("The user marked a part of the image with a cyan ellipse")
  end

  it "does not ask the tab when the whole is looked at" do
    open_image
    capture.transport = ->(*) { raise "asked" }
    out = result(look.run(caller_for, scope: "whole"))
    expect(out).not_to have_key("marked")
  end
end
