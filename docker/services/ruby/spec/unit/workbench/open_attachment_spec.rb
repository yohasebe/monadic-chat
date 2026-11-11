# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"

RSpec.describe "an attachment opened on the work screen" do
  around do |example|
    Dir.mktmpdir("workbench-attachment-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, _ws_generation: 1 } }
  let(:live) { ->(tab) { { "tab-1" => 1 }[tab] } }
  let(:records) { {} }
  let(:ledger) do
    double("ledger").tap { |l| allow(l).to receive(:attachment) { |id| records[id]&.merge(attachment_id: id) } }
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = live
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  # An attachment of a chat, written where uploads go, and its ledger record.
  def attach(name, bytes, of: chat, size: nil, status: "ready")
    id = Monadic::Workspace::Ids.generate(:attachment)
    relative = "conversations/c_#{of}/inputs/#{id}__#{name}"
    full = File.join(@data, relative)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, bytes)
    records[id] = { chat_id: of, status: status, relative_path: relative, original_name: name,
                    size: size || bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
    id
  end

  def open_attachment(id, tab: "tab-1", generation: 1, request: 7, on: session)
    Monadic::Workbench::Channel.open_attachment({ "attachment_id" => id, "request" => request }, on,
                                                tab: tab, generation: generation, live: live, ledger: ledger)
  end

  def items
    Monadic::Workbench::Board.for(chat, store: store).snapshot[:items]
  end

  it "puts the chat's audio on the board, at the version the ledger holds, and names the request" do
    id = attach("talk.mp3", "ID3 audio bytes".b)
    answer = open_attachment(id)
    expect(answer).to include("type" => "workbench_attachment_opened", "attachment_id" => id, "request" => 7,
                              "status" => "accepted", "added" => true)
    file = items.find { |i| i[:id] == answer["item_id"] }
    expect(file).to include(kind: "file", path: records[id][:relative_path], sha256: records[id][:sha256])
  end

  it "refuses an attachment of another chat, an unknown id and one not ready" do
    other = attach("talk.mp3", "other chat".b, of: Monadic::Workspace::Ids.generate(:chat))
    waiting = attach("wait.mp3", "waiting".b, status: "validating")
    expect(open_attachment(other)).to include("status" => "refused", "reason" => "unknown")
    expect(open_attachment("a_#{'z' * 16}")).to include("status" => "refused", "reason" => "unknown")
    expect(open_attachment(waiting)).to include("status" => "refused", "reason" => "not_ready")
    expect(items).to be_empty
  end

  it "refuses a kind it does not play and a file too large to read whole, before reading the file" do
    odd = attach("clip.mkv", "matroska".b)
    big = attach("long.mp4", "small on disk".b, size: Monadic::Workbench::FileItem::LIMIT + 1)
    expect(Monadic::Workspace::Attachments).not_to receive(:resolve!)
    expect(open_attachment(odd)).to include("status" => "refused", "reason" => "not_playable")
    expect(open_attachment(big)).to include("status" => "refused", "reason" => "too_large")
  end

  it "does not put a file that changed after it was attached" do
    id = attach("talk.mp3", "first".b)
    File.binwrite(File.join(@data, records[id][:relative_path]), "second".b)
    expect(open_attachment(id)).to include("status" => "refused", "reason" => "changed")
    expect(items).to be_empty
  end

  it "does not put a version that replaced the file after the ledger's was checked" do
    id = attach("talk.mp3", "first".b)
    allow(Monadic::Workspace::Attachments).to receive(:resolve!).and_wrap_original do |original, **args|
      found = original.call(**args)
      File.binwrite(File.join(@data, records[id][:relative_path]), "second".b)
      found
    end
    expect(open_attachment(id)).to include("status" => "refused", "reason" => "changed")
    expect(items).to be_empty
  end

  it "answers nothing for a connection a newer one replaced, nor for a session without a chat" do
    id = attach("talk.mp3", "bytes".b)
    expect(open_attachment(id, generation: 0)).to include("status" => "refused", "reason" => "not_allowed")
    expect(open_attachment(id, on: { _ws_generation: 1 })).to include("status" => "refused", "reason" => "not_allowed")
    expect(items).to be_empty
  end

  it "puts it at the epoch the chat had when asked, not after a Reset meanwhile" do
    id = attach("talk.mp3", "bytes".b)
    allow(Monadic::Workspace::Attachments).to receive(:resolve!).and_wrap_original do |original, **args|
      found = original.call(**args)
      Monadic::Workspace::Chats.renew_epoch!(chat)
      found
    end
    expect(open_attachment(id)).to include("status" => "refused")
    expect(items).to be_empty
  end
end
