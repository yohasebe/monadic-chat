# frozen_string_literal: true

require "spec_helper"
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

  before { stub_const("CONFIG", { "PYOPT_LIBROSA" => "true" }) }

  describe ".path_in_shared_folder" do
    it "takes a path in the shared folder, with or without the folder in front" do
      expect(described_class.path_in_shared_folder("song.mp3")).to eq("/monadic/data/song.mp3")
      expect(described_class.path_in_shared_folder("conversations/c1/song.mid")).to eq("/monadic/data/conversations/c1/song.mid")
      expect(described_class.path_in_shared_folder("/monadic/data/sub/song.mp3")).to eq("/monadic/data/sub/song.mp3")
    end

    it "takes no path that leaves the shared folder" do
      ["", "  ", "/etc/passwd", "../song.mp3", "sub/../../song.mp3", "/monadic/data/../config/env"].each do |path|
        expect(described_class.path_in_shared_folder(path)).to be_nil
      end
    end
  end

  describe "#music_file" do
    let(:attachment_id) { Monadic::Workspace::Ids.generate(:attachment) }
    let(:record) { { relative_path: "conversations/c1/attachments/song.mp3", path: "/somewhere/song.mp3", purpose: "audio" } }
    let(:shown) { [] }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/data")
      allow(Monadic::Workbench::ChatOutput).to receive(:show) { |path, workbench| shown << [path, workbench] }
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

    it "finds a file of the shared folder by its path" do
      expect(app.music_file(file_path: "sub/piece.mid")).to eq(relative: "sub/piece.mid", absolute: "/data/sub/piece.mid")
      expect(app.asked).to be_nil
    end

    it "shows audio on the work screen of the reply, and not MIDI" do
      app.music_file(attachment_id: attachment_id, workbench: :w)
      app.music_file(file_path: "piece.mid", workbench: :w)
      expect(shown).to eq([["conversations/c1/attachments/song.mp3", :w]])
    end

    it "says why a file cannot be used" do
      expect(app.music_file(file_path: "../song.mp3")).to include(:error)
      expect(app.music_file).to include(:error)
      app.define_singleton_method(:resolve_audio_attachment) do |_id, _session|
        raise Monadic::Workspace::Attachments::Unusable.new(:not_in_request, "This file was not attached to a message of this chat.")
      end
      expect(app.music_file(attachment_id: attachment_id)).to eq(error: "This file was not attached to a message of this chat.")
      expect(shown).to be_empty
    end
  end

  describe "#measure_music_features" do
    it "runs the analyzer once in the Python container and gives its result" do
      expect(app.measure_music_features("song.mp3")).to eq("success" => true, "tempo" => { "bpm" => 120 })
      expect(app.commands.size).to eq(1)
      command, container = app.commands.first
      expect(container).to eq("python")
      expect(command).to include("music_analyzer.py analyze", "/monadic/data/song.mp3")
    end

    it "runs nothing for a path outside the shared folder" do
      expect(app.measure_music_features("../song.mp3")).to include("success" => false)
      expect(app.commands).to be_nil
    end

    it "asks for the Music Analysis package for audio, and still reads MIDI without it" do
      stub_const("CONFIG", { "PYOPT_LIBROSA" => "false" })
      expect(app.measure_music_features("song.MP3")).to include("success" => false, "package_needed" => true,
                                                                "error" => a_string_including("Music Analysis package"))
      expect(app.commands).to be_nil
      expect(app.measure_music_features("song.mid")).to include("success" => true)
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
