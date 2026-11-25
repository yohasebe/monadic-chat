# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/music_features"

RSpec.describe Monadic::Utils::MusicFeatures do
  let(:app) do
    Class.new do
      include Monadic::Utils::MusicFeatures
      attr_reader :commands

      def send_command(command:, container:)
        (@commands ||= []) << [command, container]
        'Done. {"success": true, "tempo": {"bpm": 120}} bye'
      end
    end.new
  end
  let(:shown) { [] }

  around do |example|
    Dir.mktmpdir("music-features") do |dir|
      @data = File.realpath(dir)
      example.run
    end
  end

  before do
    stub_const("CONFIG", { "PYOPT_LIBROSA" => "true" })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Workbench::ChatOutput).to receive(:show) { |path, workbench| shown << [path, workbench] }
    FileUtils.mkdir_p(File.join(@data, "sub"))
    File.write(File.join(@data, "song.mp3"), "ID3")
    File.write(File.join(@data, "sub", "piece.mid"), "MThd")
  end

  describe "#music_file" do
    let(:attachment_id) { Monadic::Workspace::Ids.generate(:attachment) }
    let(:record) { { relative_path: "conversations/c1/attachments/song.mp3", path: "/somewhere/song.mp3", purpose: "audio" } }

    before do
      found = record
      app.define_singleton_method(:resolve_audio_attachment) do |id, session|
        (@asked ||= []) << [id, session]
        found
      end
      app.singleton_class.send(:attr_reader, :asked)
    end

    it "finds a file attached to the chat by its id, also when the id is given as the path" do
      expect(app.music_file(attachment_id: attachment_id, session: :s))
        .to eq(relative: "conversations/c1/attachments/song.mp3", absolute: "/somewhere/song.mp3")
      expect(app.music_file(file_path: attachment_id, session: :s)).to include(relative: "conversations/c1/attachments/song.mp3")
      expect(app.asked).to eq([[attachment_id, :s], [attachment_id, :s]])
    end

    it "finds a file on the work screen by its item: one put there as its attachment, one opened there by its path" do
      allow(Monadic::Workbench::MediaItem).to receive(:resolve).with(:wb, "i_put", kinds: %w[audio midi])
                                                               .and_return(record: record)
      allow(Monadic::Workbench::MediaItem).to receive(:resolve).with(:wb, "i_opened", kinds: %w[audio midi])
                                                               .and_return(path: "sub/piece.mid")
      expect(app.music_file(item: "i_put", workbench: :wb))
        .to eq(relative: "conversations/c1/attachments/song.mp3", absolute: "/somewhere/song.mp3")
      expect(shown).to eq([["conversations/c1/attachments/song.mp3", :wb]])
      expect(app.music_file(item: "i_opened", workbench: :wb)).to eq(relative: "sub/piece.mid", absolute: File.join(@data, "sub", "piece.mid"))
      allow(Monadic::Workbench::MediaItem).to receive(:resolve).and_raise(Monadic::Workbench::MediaItem::Refused, "that item is not audio or midi")
      expect(app.music_file(item: "i_text", workbench: :wb)).to eq(error: "that item is not audio or midi")
      expect(app.asked).to be_nil
    end

    it "finds a file of the shared folder by its path, with or without the folder in front" do
      expect(app.music_file(file_path: "sub/piece.mid")).to eq(relative: "sub/piece.mid", absolute: File.join(@data, "sub", "piece.mid"))
      expect(app.music_file(file_path: "/monadic/data/song.mp3")).to eq(relative: "song.mp3", absolute: File.join(@data, "song.mp3"))
      expect(app.asked).to be_nil
    end

    it "takes no path that leaves the shared folder, by its name or through a link" do
      Dir.mktmpdir("outside") do |outside|
        File.write(File.join(outside, "secret.mp3"), "ID3")
        File.symlink(File.join(outside, "secret.mp3"), File.join(@data, "link.mp3"))
        ["", "  ", "/etc/passwd", "../song.mp3", "sub/../../song.mp3", "/monadic/data/../config/env", "link.mp3"].each do |path|
          expect(app.music_file(file_path: path)).to include(:error), path
        end
      end
      expect(app.music_file).to include(:error)
      expect(shown).to be_empty
    end

    it "shows audio on the work screen of the reply, and not MIDI" do
      app.music_file(attachment_id: attachment_id, workbench: :w)
      app.music_file(file_path: "sub/piece.mid", workbench: :w)
      expect(shown).to eq([["conversations/c1/attachments/song.mp3", :w]])
    end

    it "says why an attached file cannot be used" do
      app.define_singleton_method(:resolve_audio_attachment) do |_id, _session|
        raise Monadic::Workspace::Attachments::Unusable.new(:not_in_request, "This file was not attached to a message of this chat.")
      end
      expect(app.music_file(attachment_id: attachment_id)).to eq(error: "This file was not attached to a message of this chat.")
    end
  end

  describe "#measure_music_features" do
    it "runs the analyzer once in the Python container, on the file as that container sees it" do
      expect(app.measure_music_features(app.music_file(file_path: "song.mp3"))).to eq("success" => true, "tempo" => { "bpm" => 120 })
      expect(app.commands.size).to eq(1)
      command, container = app.commands.first
      expect(container).to eq("python")
      expect(command).to include("music_analyzer.py analyze", "/monadic/data/song.mp3")
      expect(command).not_to include(@data)
    end

    it "asks for the Music Analysis package for audio, and still reads MIDI without it" do
      stub_const("CONFIG", { "PYOPT_LIBROSA" => "false" })
      expect(app.measure_music_features({ relative: "song.MP3" }))
        .to include("success" => false, "package_needed" => true, "error" => a_string_including("Music Analysis package"))
      expect(app.commands).to be_nil
      expect(app.measure_music_features({ relative: "sub/piece.mid" })).to include("success" => true)
    end
  end

  describe ".parse" do
    it "says there is no result for output with no JSON object, or one that cannot be read" do
      expect(described_class.parse(nil)).to include("success" => false)
      expect(described_class.parse("no result")).to include("success" => false)
      expect(described_class.parse("{not json}")).to include("success" => false, "error" => a_string_including("could not be read"))
    end
  end
end
