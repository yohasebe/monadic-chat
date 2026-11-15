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
