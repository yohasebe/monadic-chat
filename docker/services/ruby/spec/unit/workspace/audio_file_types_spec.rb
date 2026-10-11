# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workspace/file_types"

# Audio attachments: the leading bytes of files ffmpeg wrote (sine tone, one
# second each) are accepted under their own extension, and a file of another
# kind under that name is not.
RSpec.describe "Audio attachments by extension and leading bytes" do
  HEADS = {
    "a.aac" => "fff15040213ffcde02004c61", "a.flac" => "664c61430000002212001200",
    "a.m4a" => "0000001c667479704d344120", "a.mp3" => "494433040000000000235453",
    "b.mp3" => "fffb50c400000a2c432e5594", # no ID3 tag: the first MPEG frame
    "a.ogg" => "4f6767530002000000000000", "a.opus" => "4f6767530002000000000000",
    "a.wav" => "52494646ce58010057415645", "a.webm" => "1a45dfa39f4286810142f781"
  }.freeze

  def check(name, hex)
    Monadic::Workspace::FileTypes.check!("audio", name, [hex].pack("H*"))
  end

  it "accepts each kind under its own extension" do
    HEADS.each { |name, hex| expect { check(name, hex) }.not_to raise_error, name }
  end

  it "refuses a file whose contents are another kind" do
    expect { check("song.mp3", HEADS["a.wav"]) }.to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:content) }
    expect { check("song.flac", HEADS["a.ogg"]) }.to raise_error(Monadic::Workspace::FileTypes::Rejected)
    expect { check("notes.mp3", "4c6f72656d20697073756d") }.to raise_error(Monadic::Workspace::FileTypes::Rejected)
  end

  it "refuses an extension it does not take as audio" do
    expect { check("clip.mp4", HEADS["a.m4a"]) }.to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:extension) }
  end
end
