# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require "json"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/board"
require_relative "../../../lib/monadic/workbench/approvals"
require_relative "../../../lib/monadic/workbench/record"

RSpec.describe "the workbench (board, artifact, approvals, record)" do
  # A PNG header of the given size: what the check reads.
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("workbench-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:ledger) { Monadic::Workspace::Ledger.default }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:request) { Monadic::Workspace::Ids.generate(:request) }
  let(:origin) { { actor: :agent, source: :tool, request_id: request } }
  let(:artifact) { Monadic::Workbench::Artifact }

  def board(private: false)
    Monadic::Workbench::Board.for(chat, private: private, store: store)
  end

  def run_id
    "j_#{SecureRandom.hex(10)}"
  end

  def add(name = "cat.png", salt = "", on: board, run: run_id, **opts)
    on.add_image(bytes: png(64, 48, salt), epoch: epoch, origin: origin, name: name, run: run, app_name: "Image Generator",
                 **opts)
  end

  def file_of(item)
    File.join(@data, item.dig("artifact", "path"))
  end

  def remove(item, operation_id = "op-00000001", on: board)
    on.accept(item_id: item["id"], action: "remove", operation_id: operation_id, epoch: epoch,
              sha256: item.dig("artifact", "sha256"))
  end

  def shared_files
    Dir.glob(File.join(@data, "**", "*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }
  end

  describe "placing an image" do
    it "places it in the chat's folder under its time and name, records it, and puts it on the board" do
      item = add("grok_image_1.png", "1")
      path = item.dig("artifact", "path")
      expect(path).to match(%r{\Aconversations/\d{8}-\d{6}_image-generator_w_[a-z0-9]{16}/artifacts/\d{8}-\d{6}_grok_image_1\.png\z})
      expect(File.binread(file_of(item))).to eq(png(64, 48, "1"))
      record = ledger.artifact(item.dig("artifact", "id"))
      expect(record).to include(kind: "image", chat_id: chat, copy_path: path, sha256: Digest::SHA256.hexdigest(png(64, 48, "1")),
                                content_type: "image/png", width: 64, height: 48, request_id: request)
      expect(board.snapshot[:items].first).to include(id: item["id"], artifact_id: record[:artifact_id], path: path, status: "ok")
      # Nothing of the image is kept in the state folder.
      expect(Dir.glob(File.join(@state, "**", "*.png"))).to be_empty
    end

    it "keeps the images in the order they came, the latest last" do
      first = add("a.png", "1")
      second = add("b.png", "2")
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq([first["id"], second["id"]])
      expect(board.latest_image["id"]).to eq(second["id"])
    end

    it "never writes over a file: a name that is taken gets -2" do
      first = add("cat.png", "1")
      allow(Time).to receive(:now).and_return(Time.now)
      taken = File.join(File.dirname(file_of(first)), "#{Time.now.strftime('%Y%m%d-%H%M%S')}_cat.png")
      File.binwrite(taken, "the user's own file")
      second = add("cat.png", "2")
      expect(second.dig("artifact", "name")).to end_with("_cat-2.png")
      expect(File.binread(taken)).to eq("the user's own file")
      expect(File.binread(file_of(second))).to eq(png(64, 48, "2"))
    end

    it "places a run once: the same run again gives its item, with no second file or tab, even on a full board" do
      run = run_id
      first = add("cat.png", "1", run: run)
      (2..Monadic::Workbench::Board::ITEM_LIMIT).each { |i| add("i#{i}.png", i.to_s) }
      before = board.snapshot[:items].map { |i| i[:id] }
      again = add("cat.png", "1", run: run)
      expect(again["id"]).to eq(first["id"])
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq(before)
      expect(shared_files.size).to eq(Monadic::Workbench::Board::ITEM_LIMIT)
    end

    it "does not put back an image the user took off when its run comes again" do
      run = run_id
      first = add("cat.png", "1", run: run)
      remove(first)
      expect { add("cat.png", "1", run: run) }.to raise_error(Monadic::Workbench::Board::PlacedOnly) { |e|
        expect(e.path).to eq(first.dig("artifact", "path"))
      }
      expect(board.snapshot[:items]).to be_empty
      expect(shared_files.size).to eq(1)
    end

    it "refuses a run placed for another image, reply or chat, and places nothing for it" do
      run = run_id
      first = add("cat.png", "1", run: run)
      expect { add("cat.png", "2", run: run) }.to raise_error(Monadic::Workbench::Board::Refused, /another image/)
      other_request = origin.merge(request_id: Monadic::Workspace::Ids.generate(:request))
      expect do
        board.add_image(bytes: png(64, 48, "1"), epoch: epoch, origin: other_request, name: "cat.png", run: run, app_name: "x")
      end.to raise_error(Monadic::Workbench::Board::Refused, /another image/)
      other = Monadic::Workspace::Ids.generate(:chat)
      expect do
        Monadic::Workbench::Board.for(other, store: store).add_image(
          bytes: png(64, 48, "1"), epoch: Monadic::Workspace::Chats.epoch(other), origin: origin, name: "cat.png",
          run: run, app_name: "x"
        )
      end.to raise_error(Monadic::Workbench::Board::Refused, /another image/)
      expect(shared_files).to eq([file_of(first)])
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq([first["id"]])
    end

    it "records a run once in the ledger, refusing it for another image" do
      run = run_id
      add("cat.png", "1", run: run)
      expect do
        ledger.register_image(artifact_id: Monadic::Workspace::Ids.generate(:artifact), chat_id: chat, name: "x.png",
                              size: 1, sha256: "0" * 64, content_type: "image/png", width: 1, height: 1, run: run,
                              request_id: request)
      end.to raise_error(Monadic::Workspace::Ledger::Conflict)
      expect(JSON.parse(File.read(ledger.path))["artifacts"].size).to eq(1)
    end

    it "finishes an image it began when a Cancel and a Reset come while it is placed: the image is the chat's" do
      stopped = false
      paused = Queue.new
      gate = Queue.new
      allow(Monadic::Workspace::Folders).to receive(:ensure_for_chat!).and_wrap_original do |original, *args, **kw|
        paused << true
        gate.pop
        original.call(*args, **kw)
      end
      at = epoch
      thread = Thread.new do
        board.add_image(bytes: png(64, 48), epoch: at, origin: origin, name: "cat.png", run: run_id,
                        app_name: "Image Generator", unless_closed: -> { stopped })
      end
      paused.pop
      stopped = true
      Monadic::Workspace::Chats.replacing!({ Monadic::Workspace::Chats::SESSION_KEY => chat })
      gate << :go
      item = thread.value
      record = ledger.artifact(item.dig("artifact", "id"))
      expect(record).to include(chat_id: chat, workspace_id: ledger.workspace_for_chat(chat)[:workspace_id])
      expect(shared_files).to eq([file_of(item)])
      Monadic::Workbench::Board.reset!
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq([item["id"]])
    end

    it "refuses what is not an image, and places nothing for a Private chat" do
      expect do
        board.add_image(bytes: "not an image", epoch: epoch, origin: origin, name: "x.png", run: run_id, app_name: "x")
      end.to raise_error(Monadic::Workbench::ImageCheck::Refused)
      Monadic::Workbench::Board.reset!
      expect { add(on: board(private: true)) }.to raise_error(Monadic::Workbench::Board::Refused, /Private/)
      expect(shared_files).to be_empty
      expect(Dir.exist?(File.join(@data, "conversations"))).to be(false)
    end

    it "places nothing once the chat moved to another epoch or the reply was stopped" do
      expect do
        board.add_image(bytes: png(64, 48), epoch: epoch + 1, origin: origin, name: "x.png", run: run_id, app_name: "x")
      end.to raise_error(Monadic::Workbench::Board::Refused, /replaced/)
      expect { add(unless_closed: -> { true }) }.to raise_error(Monadic::Workbench::Board::Refused, /stopped/)
      expect(shared_files).to be_empty
      expect(board.snapshot[:items]).to be_empty
    end

    it "keeps the file and says where it is when its record cannot be settled; nothing is retried" do
      allow(ledger).to receive(:register_image).and_raise(Monadic::Workspace::Ledger::Unsettled, "x")
      allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
      expect { add }.to raise_error(Monadic::Workbench::Board::PlacedOnly) { |e|
        expect(e.path).to match(%r{\Aconversations/.+/artifacts/.+_cat\.png\z})
        expect(File.file?(File.join(@data, e.path))).to be(true)
      }
      expect(board.snapshot[:items]).to be_empty
      expect(shared_files.size).to eq(1)
    end

    it "keeps the file and its record when the board cannot be saved" do
      allow(store).to receive(:save).and_raise(Errno::ENOSPC)
      expect { add }.to raise_error(Monadic::Workbench::Board::PlacedOnly) { |e|
        expect(File.file?(File.join(@data, e.path))).to be(true)
      }
      allow(store).to receive(:save).and_call_original
      expect(board.snapshot[:items]).to be_empty
      expect(JSON.parse(File.read(ledger.path))["artifacts"].values.map { |r| r["kind"] }).to eq(["image"])
    end

    it "makes room by taking the oldest image off the board; its file stays" do
      items = (1..Monadic::Workbench::Board::ITEM_LIMIT).map { |i| add("i#{i}.png", i.to_s) }
      add("new.png", "new")
      ids = board.snapshot[:items].map { |i| i[:id] }
      expect(ids).not_to include(items.first["id"])
      expect(ids.size).to eq(Monadic::Workbench::Board::ITEM_LIMIT)
      expect(File.file?(file_of(items.first))).to be(true)
    end

    it "finishes placing even when its thread is stopped right after the board is saved" do
      saved = Queue.new
      gate = Queue.new
      allow(store).to receive(:save).and_wrap_original do |original, *args|
        original.call(*args)
        saved << true
        gate.pop
      end
      thread = Thread.new { add }
      saved.pop
      thread.kill
      gate << :go
      thread.join
      allow(store).to receive(:save).and_call_original
      in_memory = board.snapshot[:items].map { |i| i[:id] }
      Monadic::Workbench::Board.reset!
      expect(in_memory.size).to eq(1)
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq(in_memory)
    end
  end

  describe "reading an image" do
    it "gives the bytes recorded, and what it was made from" do
      first = add("a.png", "1")
      input = board.image_input(first["id"])
      expect(input).to include(artifact_id: first.dig("artifact", "id"), bytes: png(64, 48, "1"), content_type: "image/png")
      derived = add("b.png", "2", derived_from: { artifact_id: input[:artifact_id], sha256: input[:sha256] })
      expect(derived.dig("artifact", "derived_from")).to eq(input[:artifact_id])
    end

    it "stops at a file that changed, was replaced by a link, or is gone, and never reads another version" do
      item = add
      File.binwrite(file_of(item), png(64, 48, "changed"))
      expect(board.snapshot[:items].first[:status]).to eq("changed")
      expect { board.image_input(item["id"]) }.to raise_error(Monadic::Workbench::Board::Refused, /changed/)

      outside = File.join(@data, "elsewhere.png")
      File.binwrite(outside, png(64, 48))
      File.unlink(file_of(item))
      File.symlink(outside, file_of(item))
      expect { board.image_input(item["id"]) }.to raise_error(Monadic::Workbench::Board::Refused, /changed/)

      File.unlink(file_of(item))
      expect(board.snapshot[:items].first[:status]).to eq("missing")
      expect { board.image_input(item["id"]) }.to raise_error(Monadic::Workbench::Board::Refused, /no longer/)
    end

    it "stops at a file grown past its recorded size without reading it whole" do
      item = add
      File.binwrite(file_of(item), png(64, 48) + ("x" * 10_000))
      expect { artifact.read(item.dig("artifact", "id"), chat_id: chat) }.to raise_error(Monadic::Workbench::Artifact::Changed)
    end

    it "reads an image only for its own chat" do
      item = add
      other = Monadic::Workspace::Ids.generate(:chat)
      expect { artifact.read(item.dig("artifact", "id"), chat_id: other) }.to raise_error(Monadic::Workbench::Artifact::NotAllowed)
      expect { artifact.read("r_#{'a' * 16}", chat_id: chat) }.to raise_error(Monadic::Workbench::Artifact::NotAllowed)
      expect { artifact.read("../x", chat_id: chat) }.to raise_error(Monadic::Workbench::Artifact::NotAllowed)
    end
  end

  describe "removing an image" do
    it "takes it off the board only, answers a removal sent again, and refuses anything else on it" do
      item = add
      expect(remove(item).first).to eq(:accepted)
      expect(board.snapshot[:items]).to be_empty
      expect(File.file?(file_of(item))).to be(true)
      expect(remove(item).first).to eq(:same)
      expect { remove(item, "op-00000002") }.to raise_error(Monadic::Workbench::Board::Refused, /removed/)
    end

    it "refuses an id used for another operation, other bytes than the token's, or another epoch" do
      item = add
      other = add("b.png", "2")
      remove(item)
      expect { remove(other, "op-00000001") }.to raise_error(Monadic::Workbench::Board::Refused, /another operation/)
      expect do
        board.accept(item_id: other["id"], action: "remove", operation_id: "op-00000003", epoch: epoch, sha256: "f" * 64)
      end.to raise_error(Monadic::Workbench::Board::Refused, /changed/)
      expect do
        board.accept(item_id: other["id"], action: "remove", operation_id: "op-00000004", epoch: epoch + 1,
                     sha256: other.dig("artifact", "sha256"))
      end.to raise_error(Monadic::Workbench::Board::Refused, /replaced/)
      expect do
        board.accept(item_id: other["id"], action: "save", operation_id: "op-00000005", epoch: epoch,
                     sha256: other.dig("artifact", "sha256"))
      end.to raise_error(Monadic::Workbench::Board::Refused, /unknown action/)
    end
  end

  describe "approvals" do
    it "works only for the connection it was issued to, and stops when that connection or chat goes" do
      approvals = Monadic::Workbench::Approvals
      token = approvals.issue(tab: "tab-1", generation: 3, chat_id: chat, epoch: epoch, item_id: "i_x", sha256: "a" * 64)
      expect(approvals.issue(tab: "tab-1", generation: 3, chat_id: chat, epoch: epoch, item_id: "i_x", sha256: "a" * 64))
        .to eq(token)
      expect(approvals.grant(token, tab: "tab-1", generation: 3)).to have_attributes(item_id: "i_x", sha256: "a" * 64)
      expect(approvals.grant(token, tab: "tab-2", generation: 3)).to be_nil
      expect(approvals.grant(token, tab: "tab-1", generation: 4)).to be_nil
      approvals.drop_connection("tab-1", 3)
      expect(approvals.grant(token, tab: "tab-1", generation: 3)).to be_nil
    end
  end

  describe "a board after a restart" do
    def manifest
      File.join(@state, "workbench", chat, "manifest.json")
    end

    it "keeps its images, which can be removed at the chat's epoch of the new boot" do
      Monadic::Workspace::Chats.replacing!({ chat_id: chat }) # the chat was at epoch 1 before the restart
      item = add
      Monadic::Workbench::Board.reset!
      Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS.delete(chat) } # epochs start again
      expect(board.latest_image["id"]).to eq(item["id"])
      result = board.accept(item_id: item["id"], action: "remove", operation_id: "op-00000001",
                            epoch: Monadic::Workspace::Chats.epoch(chat), sha256: item.dig("artifact", "sha256"))
      expect(result.first).to eq(:accepted)
    end

    it "remembers a removal, so the removed image is not taken again" do
      item = add
      remove(item)
      Monadic::Workbench::Board.reset!
      expect(remove(item).first).to eq(:same)
    end

    it "reads a board of the earlier form as none, and leaves what that form kept" do
      FileUtils.mkdir_p(File.dirname(manifest))
      legacy = { "schema" => 1, "chat_id" => chat, "board_id" => "b", "revision" => 3,
                 "items" => { "i_1" => { "candidate" => {} } }, "operations" => {}, "artifacts" => {} }
      File.write(manifest, JSON.generate(legacy))
      kept = File.join(File.dirname(manifest), "candidates", "k_1", "image.png")
      FileUtils.mkdir_p(File.dirname(kept))
      File.binwrite(kept, png(1, 1))
      expect(board.snapshot[:items]).to be_empty
      expect(File.file?(kept)).to be(true)
    end

    it "makes nothing from a manifest it cannot read, of an unknown form, or of another chat" do
      add
      [
        "{not json",
        JSON.generate({ "schema" => 9, "chat_id" => chat, "items" => {}, "operations" => {} }),
        JSON.generate({ "schema" => 1, "chat_id" => Monadic::Workspace::Ids.generate(:chat), "items" => {}, "operations" => {} }),
        JSON.generate({ "schema" => 1, "chat_id" => chat })
      ].each do |text|
        Monadic::Workbench::Board.reset!
        File.write(manifest, text)
        expect { board }.to raise_error(Monadic::Workbench::Store::Unreadable)
      end
    end
  end

  describe "the record on the message" do
    let(:entry) do
      { "id" => "r_#{'a' * 16}", "path" => "conversations/20261106-090000_image-generator_w_#{'b' * 16}/artifacts/20261106-091233_cat.png",
        "name" => "20261106-091233_cat.png", "sha256" => "b" * 64, "content_type" => "image/png",
        "created_at" => "2026-11-06T00:12:33Z" }
    end

    it "is what the ledger records, with no token, URL or local path" do
      item = add
      record = ledger.artifact(item.dig("artifact", "id"))
      made = Monadic::Workbench::Artifact.entry(record)
      expect(Monadic::Workbench::Record.clean([made])).to eq([made])
      expect(made.keys).to match_array(%w[id path name sha256 content_type created_at])
    end

    it "keeps entries of its form only, and only their fields" do
      expect(Monadic::Workbench::Record.clean([entry])).to eq([entry])
      expect(Monadic::Workbench::Record.clean([entry.merge("token" => "x")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("path" => "conversations/../x/artifacts/#{entry['name']}")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("path" => "/abs/artifacts/#{entry['name']}")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("name" => "other.png")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("content_type" => "image/jpeg")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("id" => "r_#{'a' * 20}", "action" => "saved")])).to be_nil
      expect(Monadic::Workbench::Record.clean("x")).to be_nil
    end

    it "names the image made last, by the newest message with a record of its form" do
      second = entry.merge("id" => "r_#{'c' * 16}", "path" => entry["path"].sub("_cat.png", "_dog.png"),
                           "name" => entry["name"].sub("_cat.png", "_dog.png"))
      messages = [{ "artifacts" => [entry] }, { "artifacts" => [entry, second] }, { "text" => "later" },
                  { "artifacts" => [{ "path" => "forged.png" }] }]
      expect(Monadic::Workbench::Record.last_path(messages)).to eq(second["path"])
      expect(Monadic::Workbench::Record.last_path([{ "text" => "none" }])).to be_nil
      expect(Monadic::Workbench::Record.last_path(nil)).to be_nil
    end
  end
end
