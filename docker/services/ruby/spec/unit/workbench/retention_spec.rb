# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workbench/retention"

# A chat's workbench folder is kept as long as the chat is: removed with the
# chat from the history, when the user leaves a chat the history does not
# keep, and at start when idle and not kept.
RSpec.describe Monadic::Workbench::Retention do
  let(:root) { Dir.mktmpdir("workbench-retention") }
  let(:store) { Monadic::Workbench::Store.new(root) }
  let(:kept_ids) { [] }
  let(:history) { double("history").tap { |h| allow(h).to receive(:resumable?) { |id| kept_ids.include?(id) } } }

  around do |example|
    saved = ENV["MONADIC_HISTORY"]
    ENV["MONADIC_HISTORY"] = "true"
    example.run
  ensure
    saved ? ENV["MONADIC_HISTORY"] = saved : ENV.delete("MONADIC_HISTORY")
    FileUtils.rm_rf(root)
  end

  def chat_with_folder(age_days: 0)
    id = Monadic::Workspace::Ids.generate(:chat)
    dir = store.chat_dir(id, make: true)
    FileUtils.mkdir_p(File.join(dir, "pictures"))
    file = File.join(dir, "pictures", "p_#{"a" * 20}.png")
    File.write(file, "PNG")
    at = Time.now - (age_days * 86_400)
    [file, File.join(dir, "pictures"), dir].each { |f| File.utime(at, at, f) }
    id
  end

  def folder?(id) = File.directory?(store.chat_dir(id))

  it "removes a chat's folder, pictures and all, and forgets its board" do
    id = chat_with_folder
    allow(Monadic::Workbench::Board).to receive(:forget)
    expect(described_class.discard(id, store: store)).to be(true)
    expect(Monadic::Workbench::Board).to have_received(:forget).with(id)
    expect(folder?(id)).to be(false)
    expect(described_class.discard(id, store: store)).to be(false)
    expect(described_class.discard("../#{File.basename(root)}", store: store)).to be(false)
    expect(File.directory?(root)).to be(true)
  end

  it "keeps the folder of a chat left that the history keeps, and removes one it does not" do
    kept = chat_with_folder
    gone = chat_with_folder
    kept_ids << kept
    described_class.left(kept, store: store, history: history)
    described_class.left(gone, store: store, history: history)
    expect(folder?(kept)).to be(true)
    expect(folder?(gone)).to be(false)
  end

  it "removes the folder of a chat left when no history is kept" do
    ENV["MONADIC_HISTORY"] = "false"
    id = chat_with_folder
    kept_ids << id
    described_class.left(id, store: store, history: history)
    expect(folder?(id)).to be(false)
  end

  it "keeps the folder when the history cannot say whether it keeps the chat" do
    id = chat_with_folder
    failing = double("history")
    allow(failing).to receive(:resumable?).and_raise(SQLite3::Exception, "locked")
    described_class.left(id, store: store, history: failing)
    expect(folder?(id)).to be(true)
  end

  it "at start removes only the folders of chats not kept and idle for a week" do
    kept_old = chat_with_folder(age_days: 30)
    kept_ids << kept_old
    unkept_old = chat_with_folder(age_days: 8)
    unkept_recent = chat_with_folder(age_days: 6)
    other = File.join(root, "not-a-chat")
    FileUtils.mkdir_p(other)
    expect(described_class.sweep!(store: store, history: history)).to eq(1)
    expect(folder?(kept_old)).to be(true)
    expect(folder?(unkept_old)).to be(false)
    expect(folder?(unkept_recent)).to be(true)
    expect(File.directory?(other)).to be(true)
  end

  it "takes a folder written in lately as not idle, however old the folder" do
    id = chat_with_folder(age_days: 30)
    manifest = File.join(store.chat_dir(id), "manifest.json")
    File.write(manifest, "{}")
    expect(described_class.sweep!(store: store, history: history)).to eq(0)
    expect(folder?(id)).to be(true)
  end

  it "does nothing at start when there is no workbench yet" do
    expect(described_class.sweep!(store: Monadic::Workbench::Store.new(File.join(root, "none")), history: history)).to eq(0)
  end

  it "is asked when the user replaces the session's chat" do
    session = { Monadic::Workspace::Chats::SESSION_KEY => Monadic::Workspace::Ids.generate(:chat) }
    left = session[Monadic::Workspace::Chats::SESSION_KEY]
    expect(described_class).to receive(:left).with(left)
    Monadic::Workspace::Chats.begin_new!(session)
    expect(session[Monadic::Workspace::Chats::SESSION_KEY]).not_to eq(left)
  end
end
