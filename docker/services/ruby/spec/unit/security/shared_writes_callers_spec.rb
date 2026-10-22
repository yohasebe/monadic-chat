# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/public_copy"
require_relative "../../../lib/monadic/utils/tool_image_utils"
require_relative "../../../lib/monadic/workspace"

# The places that write into the shared folder for the server leave a file
# outside it unchanged when a link is put where they write: the public
# copies, the run folders, the image a video is made from, the chat folders.
RSpec.describe "Writes into the shared folder" do
  around do |example|
    Dir.mktmpdir("shared-writes") do |dir|
      @root = File.join(dir, "data")
      @state = File.join(dir, "state")
      @outside = File.join(dir, "outside")
      FileUtils.mkdir_p([@root, @outside])
      @secret = File.join(@outside, "report.txt")
      File.write(@secret, "SECRET")
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  def outside_unchanged
    expect(File.read(@secret)).to eq("SECRET")
    expect(Dir.children(@outside)).to eq(["report.txt"])
  end

  describe Monadic::Utils::PublicCopy do
    it "makes no copy through a link at the public name, and copies nothing from behind a link" do
      File.write(File.join(@root, "clip.vtt"), "WEBVTT")
      File.symlink(@secret, File.join(@root, "pub_x.vtt"))
      expect(described_class.publish(File.join(@root, "clip.vtt"), "pub_x.vtt")).to be_nil
      File.symlink(@secret, File.join(@root, "linked.vtt"))
      expect(described_class.publish(File.join(@root, "linked.vtt"), "pub_y.vtt")).to be_nil
      expect(File.exist?(File.join(@root, "pub_y.vtt"))).to be(false)
      outside_unchanged
    end

    it "copies a plain file" do
      File.write(File.join(@root, "clip.vtt"), "WEBVTT")
      expect(described_class.publish(File.join(@root, "clip.vtt"), "pub_z.vtt")).to eq("/data/pub_z.vtt")
      expect(File.read(File.join(@root, "pub_z.vtt"))).to eq("WEBVTT")
    end
  end

  describe "the image a video is made from" do
    let(:utils) { Monadic::Utils::ToolImageUtils }

    it "removes only the file it wrote, never a name the model gave" do
      FileUtils.mkdir_p(File.join(@root, "video_gen_temp_x"))
      expect(utils.discard_materialized("video_gen_temp_x/../../outside/report.txt")).to be(false)
      outside_unchanged
      name = utils.write_data_url_to_shared("data:image/png;base64,#{Base64.strict_encode64('PNG')}", "image/png")
      expect(File.exist?(File.join(@root, name))).to be(true)
      expect(utils.discard_materialized(name)).to be(true)
      expect(File.exist?(File.join(@root, name))).to be(false)
    end
  end

  describe "chat folders" do
    let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, "ledger.json")) }

    it "are not made through a link at conversations/" do
      File.symlink(@outside, File.join(@root, "conversations"))
      chat = Monadic::Workspace::Ids.generate(:chat)
      expect { Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: "Chat", ledger: ledger) }
        .to raise_error(Monadic::Workspace::Folders::Unavailable)
      outside_unchanged
    end

    it "are not made through a link at conversations/ to a folder inside the shared folder either" do
      FileUtils.mkdir_p(File.join(@root, "ordinary"))
      File.symlink(File.join(@root, "ordinary"), File.join(@root, "conversations"))
      chat = Monadic::Workspace::Ids.generate(:chat)
      expect { Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: "Chat", ledger: ledger) }
        .to raise_error(Monadic::Workspace::Folders::Unavailable)
      expect(Dir.children(File.join(@root, "ordinary"))).to be_empty
      expect(ledger.workspace_for_chat(chat)).to be_nil
    end

    it "keep a run's subtitles out of a file a link points at" do
      chat = Monadic::Workspace::Ids.generate(:chat)
      workspace = Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: "Chat", ledger: ledger)
      job = Monadic::Workspace::Jobs.create!(workspace[:workspace_id], ledger: ledger)
      File.symlink(@secret, File.join(job[:path], "transcript.vtt"))
      expect { Monadic::Utils::SharedPathGuard.write_file!(File.join(job[:path], "transcript.vtt"), "WEBVTT") }
        .to raise_error(Monadic::Utils::SharedPathGuard::InvalidPath)
      outside_unchanged
    end
  end
end
