# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "base64"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/image_tool"
require_relative "../../../lib/monadic/utils/tool_image_utils"

# A video started from, or music made from, an image of the work screen the
# model named by its id: the image as it is now, and nothing in its place
# when the item is no image or is gone.
RSpec.describe "Images of the work screen for videos and music" do
  around do |example|
    Dir.mktmpdir("media-items-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:workbench) { Struct.new(:chat_id, :tab, :generation).new(chat, "tab-1", 1) }
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") }
  let(:job) do
    relative = "conversations/c/artifacts/j_1"
    FileUtils.mkdir_p(File.join(@data, relative))
    { path: File.join(@data, relative), relative: relative }
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def put(name, bytes)
    File.binwrite(File.join(@data, name), bytes)
    item, = Monadic::Workbench::Board.for(chat, store: store)
                                     .add_file(path: name, origin: origin, epoch: Monadic::Workspace::Chats.epoch(chat))
    item
  end

  describe "a video's first frame" do
    it "is the image named, written in the run folder, before an image uploaded with the message" do
      item = put("cat.png", png)
      uploaded = { messages: [{ "role" => "user", "images" => [{ "data" => "data:image/png;base64,AAAA", "type" => "image/png" }] }] }
      path = Monadic::Utils::ToolImageUtils.materialize_session_image(uploaded, into: job, item: item["id"], workbench: workbench)
      expect(path).to start_with("conversations/c/artifacts/j_1/").and end_with(".png")
      expect(File.binread(File.join(@data, path))).to eq(png)
    end

    it "is none when the item named is no image or not on the work screen" do
      notes = put("notes.md", "# notes")
      [notes["id"], "i_gone"].each do |id|
        expect do
          Monadic::Utils::ToolImageUtils.materialize_session_image({ messages: [] }, into: job, item: id, workbench: workbench)
        end.to raise_error(Monadic::Utils::ToolImageUtils::ImageMaterializationError, /nothing is made/)
      end
      expect(Dir.children(job[:path])).to be_empty
    end

    it "is none when the image changed after it was put, and no other is used" do
      item = put("cat.png", png)
      File.binwrite(File.join(@data, "cat.png"), "not an image now")
      expect do
        Monadic::Utils::ToolImageUtils.materialize_session_image({ messages: [] }, into: job, item: item["id"], workbench: workbench)
      end.to raise_error(Monadic::Utils::ToolImageUtils::ImageMaterializationError)
      expect(Dir.children(job[:path])).to be_empty
    end
  end

  describe "music made from images" do
    let(:helper) { Class.new { include GeminiHelper; public :lyria_item_parts }.new }

    it "takes the images named, in order, and stops at an item that is no image or past ten" do
      a = put("a.png", png)
      b = put("b.png", png)
      parts = helper.lyria_item_parts(workbench, [a["id"], b["id"], a["id"]])
      expect(parts.size).to eq(2)
      expect(parts.first[:inline_data]).to eq(mime_type: "image/png", data: Base64.strict_encode64(png))
      notes = put("notes.md", "# notes")
      expect { helper.lyria_item_parts(workbench, [a["id"], notes["id"]]) }
        .to raise_error(Monadic::Workbench::ImageTool::NoSource)
      expect { helper.lyria_item_parts(workbench, (1..11).map { |i| "i_#{i}" }) }
        .to raise_error(Monadic::Workbench::ImageTool::NoSource, /Up to 10/)
    end
  end
end
