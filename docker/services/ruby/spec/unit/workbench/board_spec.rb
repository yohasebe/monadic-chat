# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/board"
require_relative "../../../lib/monadic/workbench/approvals"
require_relative "../../../lib/monadic/workbench/saver"
require_relative "../../../lib/monadic/workbench/record"

RSpec.describe "the workbench (board, approvals, saver, record)" do
  # A PNG header of the given size: what the check reads.
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  let(:state) { Dir.mktmpdir }
  let(:shared) { Dir.mktmpdir }
  let(:store) { Monadic::Workbench::Store.new(File.join(state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:epoch) { Monadic::Workspace::Chats.epoch(chat) }
  let(:origin) { { actor: :agent, source: :tool, request_id: "q1", tab_id: "tab-1" } }
  let(:recorded) { [] }
  let(:recorder) do
    lambda do |board:, operation:, artifact:|
      recorded << [operation["mid"], artifact[:id]] unless recorded.any? { |r| r[1] == artifact[:id] }
      true
    end
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
  end

  after do
    FileUtils.rm_rf(state)
    FileUtils.rm_rf(shared)
  end

  def board(private: false)
    Monadic::Workbench::Board.for(chat, private: private, store: store)
  end

  def candidate(name = "cat.png", salt = "", derived_from: nil)
    board.add_candidate(bytes: png(64, 48, salt), epoch: epoch, origin: origin, name: name, derived_from: derived_from)
  end

  def operate(item, action, operation_id = "op-00000001", on: board)
    on.accept(item_id: item["id"], action: action, operation_id: operation_id, epoch: epoch,
              sha256: item.dig("candidate", "sha256"))
  end

  def save(item, operation_id = "op-00000001")
    operate(item, "save", operation_id)
  end

  def run(operation_id = "op-00000001")
    Monadic::Workbench::Saver.run(board, operation_id, recorder: recorder, shared_root: shared)
  end

  describe "images" do
    it "keeps a checked image in the order they came; the snapshot has no path" do
      first = candidate("a.png", "1")
      second = candidate("b.png", "2")
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq([first["id"], second["id"]])
      expect(board.snapshot.to_s).not_to include("candidates/")
      expect(board.latest_image["id"]).to eq(second["id"])
      expect(File.binread(board.path(second.dig("candidate", "path")))).to eq(png(64, 48, "2"))
    end

    it "refuses what is not an image, and keeps nothing for a Private chat" do
      expect { board.add_candidate(bytes: "<svg/>", epoch: epoch, origin: origin, name: "x.png") }
        .to raise_error(Monadic::Workbench::ImageCheck::Refused)
      Monadic::Workbench::Board.reset!
      private_board = board(private: true)
      expect { private_board.add_candidate(bytes: png(1, 1), epoch: epoch, origin: origin, name: "x.png") }
        .to raise_error(Monadic::Workbench::Board::Refused)
      expect(Dir.exist?(File.join(state, "workbench", chat))).to be(false)
    end

    it "keeps what an image was made from as it was read, also once that image is gone" do
      first = candidate("a.png", "1")
      input = board.candidate_input(first["id"])
      expect(input).to include(id: first["id"], bytes: png(64, 48, "1"))
      operate(first, "remove")
      second = candidate("b.png", "2", derived_from: { id: input[:id], sha256: input[:sha256] })
      expect(second.dig("candidate", "derived_from")).to eq("id" => first["id"], "sha256" => input[:sha256])
    end

    it "does not hand out bytes that changed, nor those of an image that is gone" do
      item = candidate
      path = board.path(item.dig("candidate", "path"))
      File.chmod(0o600, path)
      File.binwrite(path, png(64, 48, "x"))
      expect { board.candidate_input(item["id"]) }.to raise_error(Monadic::Workbench::Board::Refused)
      expect { board.candidate_input("i_none") }.to raise_error(Monadic::Workbench::Board::Refused)
    end

    it "makes room by putting away a saved image first, then the oldest; never the latest nor one being saved" do
      candidate("kept.png", "0")
      run_save = lambda do |item, id|
        save(item, id)
        run(id)
      end
      saved = candidate("saved.png", "1")
      run_save.call(saved, "op-saved01")
      saving = candidate("saving.png", "2")
      save(saving, "op-saving1")
      5.times { |n| candidate("n#{n}.png", "n#{n}") }
      expect(board.snapshot[:items].size).to eq(8)
      candidate("next.png", "next")
      names = board.snapshot[:items].map { |i| i[:name] }
      expect(names).not_to include("saved.png")
      expect(names).to include("kept.png", "saving.png")
      candidate("again.png", "again")
      names = board.snapshot[:items].map { |i| i[:name] }
      expect(names).not_to include("kept.png")
      expect(names).to include("saving.png", "again.png")
      expect(File.exist?(File.join(shared, "saved.png"))).to be(true)
    end

    it "refuses a new image rather than put away the latest when every other is being saved" do
      7.times do |n|
        item = candidate("s#{n}.png", "s#{n}")
        save(item, "op-saving-#{n}")
      end
      latest = candidate("latest.png", "latest")
      expect { candidate("new.png", "new") }.to raise_error(Monadic::Workbench::Board::Refused, /full/)
      expect(board.latest_image["id"]).to eq(latest["id"])
    end
  end

  describe "operations" do
    it "saves an image once: another operation on it is told of the first" do
      item = candidate
      expect(save(item).first).to eq(:accepted)
      status, operation = save(item, "op-00000002")
      expect(status).to eq(:taken)
      expect(operation["id"]).to eq("op-00000001")
    end

    it "gives the same answer again for the same operation, and refuses its id for another" do
      item = candidate
      save(item)
      expect(save(item).first).to eq(:same)
      expect { board.accept(item_id: item["id"], action: "save", operation_id: "op-00000001", epoch: epoch, sha256: "0" * 64) }
        .to raise_error(Monadic::Workbench::Board::Refused)
      other = candidate("b.png", "2")
      expect { operate(other, "save") }.to raise_error(Monadic::Workbench::Board::Refused)
      expect { operate(item, "remove") }.to raise_error(Monadic::Workbench::Board::Refused)
    end

    it "removes an image with its bytes, answers a removal sent again, and refuses anything else on it" do
      item = candidate
      bytes_dir = File.dirname(board.path(item.dig("candidate", "path")))
      expect(operate(item, "remove").first).to eq(:accepted)
      expect(board.item(item["id"])).to be_nil
      expect(Dir.exist?(bytes_dir)).to be(false)
      expect(operate(item, "remove").first).to eq(:same)
      expect { operate(item, "save", "op-00000002") }.to raise_error(Monadic::Workbench::Board::Refused, /removed/)
    end

    it "keeps an image while it is being saved, and lets it go once saved, keeping what the save made" do
      item = candidate
      save(item)
      expect { operate(item, "remove", "op-00000002") }.to raise_error(Monadic::Workbench::Board::Refused, /being saved/)
      run
      expect(operate(item, "remove", "op-00000002").first).to eq(:accepted)
      expect(File.binread(File.join(shared, "cat.png"))).to eq(png(64, 48))
      expect(board.recorded_operations.map { |o| o["id"] }).to eq(["op-00000001"])
    end

    it "refuses an operation for other bytes than the token's, or once the chat moved to another epoch" do
      item = candidate
      expect { board.accept(item_id: item["id"], action: "save", operation_id: "op-00000001", epoch: epoch, sha256: "0" * 64) }
        .to raise_error(Monadic::Workbench::Board::Refused, /changed/)
      Monadic::Workspace::Chats.replacing!({ chat_id: chat })
      expect { save(item) }.to raise_error(Monadic::Workbench::Board::Refused)
    end

    it "takes an operation whatever time has passed, while the binding holds" do
      item = candidate
      allow(Time).to receive(:now).and_return(Time.now + (365 * 24 * 3600))
      expect(save(item).first).to eq(:accepted)
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

  describe "saving" do
    it "keeps the original, copies it under its name, records it once, and leaves no temporary file" do
      item = candidate
      save(item)
      operation = run
      expect(operation["state"]).to eq("recorded")
      expect(File.binread(File.join(shared, "cat.png"))).to eq(png(64, 48))
      expect(File.binread(board.path(operation["original"]))).to eq(png(64, 48))
      expect(recorded.size).to eq(1)
      expect(Dir.children(shared)).to eq(["cat.png"])
    end

    it "never overwrites a file it did not make: a taken name gets another" do
      File.write(File.join(shared, "cat.png"), "the user's own file")
      item = candidate
      save(item)
      operation = run
      expect(File.read(File.join(shared, "cat.png"))).to eq("the user's own file")
      expect(operation["final_name"]).to eq("cat-2.png")
      expect(File.binread(File.join(shared, "cat-2.png"))).to eq(png(64, 48))
    end

    it "leaves alone a file that has its temporary name, and uses another" do
      item = candidate
      _, operation = save(item)
      File.write(File.join(shared, operation["temp_name"]), "someone else's")
      saved = run
      expect(saved["state"]).to eq("recorded")
      expect(File.read(File.join(shared, operation["temp_name"]))).to eq("someone else's")
      expect(File.binread(File.join(shared, "cat.png"))).to eq(png(64, 48))
      expect(Dir.children(shared).sort).to eq(["cat.png", operation["temp_name"]].sort)
    end

    it "keeps two chats' operations of the same page id apart in the shared folder" do
      other_chat = Monadic::Workspace::Ids.generate(:chat)
      other = Monadic::Workbench::Board.for(other_chat, store: store)
      first = candidate("a.png", "1")
      second = other.add_candidate(bytes: png(64, 48, "2"), epoch: Monadic::Workspace::Chats.epoch(other_chat),
                                   origin: origin, name: "b.png")
      _, op_a = save(first, "op-shared01")
      _, op_b = other.accept(item_id: second["id"], action: "save", operation_id: "op-shared01",
                             epoch: Monadic::Workspace::Chats.epoch(other_chat), sha256: second.dig("candidate", "sha256"))
      expect(op_a["temp_name"]).not_to eq(op_b["temp_name"])
      run("op-shared01")
      Monadic::Workbench::Saver.run(other, "op-shared01", recorder: recorder, shared_root: shared)
      expect(File.binread(File.join(shared, "a.png"))).to eq(png(64, 48, "1"))
      expect(File.binread(File.join(shared, "b.png"))).to eq(png(64, 48, "2"))
      expect(Dir.children(shared).sort).to eq(%w[a.png b.png])
    end

    # A crash right after a step's work and before it is written down: run
    # again, the operation finds its own work and makes nothing twice.
    [
      ["the original is kept", "original_kept"],
      ["the shared copy is linked", "shared_copied"],
      ["the message is recorded", "recorded"]
    ].each do |what, step|
      it "takes up an operation cut off after #{what} without making anything twice" do
        item = candidate
        save(item)
        real = board.method(:advance)
        crashed = false
        allow(board).to receive(:advance) do |id, to, **fields|
          if to == step && !crashed
            crashed = true
            raise "crash"
          end
          real.call(id, to, **fields)
        end
        expect { run }.to raise_error(RuntimeError, "crash")
        operation = run
        expect(operation["state"]).to eq("recorded")
        expect(Dir.children(shared)).to eq(["cat.png"])
        expect(recorded.size).to eq(1)
        artifacts = Dir.children(File.join(state, "workbench", chat, "artifacts"))
        expect(artifacts.size).to eq(1)
      end
    end

    it "takes up an unfinished operation after a restart (a new board from the manifest)" do
      item = candidate
      save(item)
      allow(Monadic::Workbench::Saver).to receive(:record).and_raise("crash")
      expect { run }.to raise_error(RuntimeError, "crash")
      allow(Monadic::Workbench::Saver).to receive(:record).and_call_original
      Monadic::Workbench::Board.reset!
      restored = board
      expect(restored.unfinished_operations.map { |o| o["id"] }).to eq(["op-00000001"])
      expect(run["state"]).to eq("recorded")
      expect(Dir.children(shared)).to eq(["cat.png"])
    end

    it "waits at shared_copied while the chat is not open, and records when it is" do
      item = candidate
      save(item)
      closed = ->(**) { false }
      operation = Monadic::Workbench::Saver.run(board, "op-00000001", recorder: closed, shared_root: shared)
      expect(operation["state"]).to eq("shared_copied")
      expect(run["state"]).to eq("recorded")
    end
  end

  describe "a board after a restart" do
    it "keeps its images, which can be saved at the chat's epoch of the new boot" do
      Monadic::Workspace::Chats.replacing!({ chat_id: chat }) # the chat was at epoch 1 before the restart
      item = board.add_candidate(bytes: png(64, 48), epoch: Monadic::Workspace::Chats.epoch(chat), origin: origin, name: "cat.png")
      Monadic::Workbench::Board.reset!
      Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS.delete(chat) } # epochs start again
      restored = board
      expect(restored.latest_image["id"]).to eq(item["id"])
      expect(save(item).first).to eq(:accepted)
    end

    it "remembers a removal, so the removed image is not taken again" do
      item = candidate
      operate(item, "remove")
      Monadic::Workbench::Board.reset!
      expect(operate(item, "remove").first).to eq(:same)
      expect { save(item, "op-00000002") }.to raise_error(Monadic::Workbench::Board::Refused, /removed/)
    end

    it "finishes a change even when its thread is stopped right after the manifest is saved" do
      saved = Queue.new
      gate = Queue.new
      allow(store).to receive(:save).and_wrap_original do |original, *args|
        original.call(*args)
        saved << true
        gate.pop
      end
      thread = Thread.new { candidate }
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

    it "makes nothing from a manifest it cannot read" do
      candidate
      Monadic::Workbench::Board.reset!
      File.write(File.join(state, "workbench", chat, "manifest.json"), "{not json")
      expect { board }.to raise_error(Monadic::Workbench::Store::Unreadable)
    end
  end

  describe "the record on the message" do
    let(:entry) do
      Monadic::Workbench::Record.entry(artifact_id: "r_#{'a' * 20}", name: "cat.png", sha256: "b" * 64,
                                       content_type: "image/png", derived_from: nil, saved_at: "2026-11-05T00:00:00Z")
    end

    it "keeps entries of its form only, and only their fields" do
      expect(Monadic::Workbench::Record.clean([entry])).to eq([entry])
      expect(Monadic::Workbench::Record.clean([entry.merge("token" => "x")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("name" => "../x.png")])).to be_nil
      expect(Monadic::Workbench::Record.clean([entry.merge("by" => "model")])).to be_nil
      expect(Monadic::Workbench::Record.clean("x")).to be_nil
    end

    it "records the same save once" do
      message = {}
      2.times { Monadic::Workbench::Record.add!(message, entry) }
      expect(message["artifacts"].size).to eq(1)
    end

    it "names the image saved last, by the newest message with a record of its form" do
      second = entry.merge("id" => "r_#{'c' * 20}", "name" => "dog.png")
      messages = [{ "artifacts" => [entry] }, { "artifacts" => [entry, second] }, { "text" => "later" },
                  { "artifacts" => [{ "name" => "forged.png" }] }]
      expect(Monadic::Workbench::Record.last_saved_name(messages)).to eq("dog.png")
      expect(Monadic::Workbench::Record.last_saved_name([{ "text" => "none" }])).to be_nil
      expect(Monadic::Workbench::Record.last_saved_name(nil)).to be_nil
    end
  end
end
