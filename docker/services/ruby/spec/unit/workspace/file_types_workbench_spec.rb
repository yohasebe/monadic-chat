# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workspace/file_types"

# A file the user puts on the work screen: the kinds the work screen shows,
# each checked by its leading bytes as an attachment of its kind is.
RSpec.describe "The files taken for the work screen" do
  let(:types) { Monadic::Workspace::FileTypes }
  let(:preview) { Monadic::Workspace::SharedFolderPreview }

  it "are the kinds the work screen shows, and no other" do
    shown = (preview::MEDIA.keys + preview::TEXT).map { |ext| ".#{ext}" }
    expect(types.extensions("workbench")).to match_array(shown)
  end

  it "are checked by what they hold, not only by their names" do
    {
      "photo.png" => "\x89PNG\r\n\x1A\n....".b, "photo.jpg" => "\xFF\xD8\xFF\xE0..".b, "anim.gif" => "GIF89a....".b,
      "pic.webp" => "RIFF....WEBPVP8 ".b, "paper.pdf" => "%PDF-1.7\n".b, "talk.mp3" => "ID3\x04....".b,
      "clip.mp4" => "\x00\x00\x00\x18ftypmp42".b, "notes.md" => "# Notes\n".b, "run.py" => "print(1)\n".b
    }.each do |name, head|
      expect { types.check!("workbench", name, head) }.not_to raise_error, name
    end
    expect { types.check!("workbench", "photo.png", "GIF89a....".b) }.to raise_error(types::Rejected)
    expect { types.check!("workbench", "notes.md", "a\0b".b) }.to raise_error(types::Rejected)
    expect { types.check!("workbench", "tool.exe", "MZ".b) }.to raise_error(types::Rejected)
    expect { types.check!("workbench", "clip.mkv", "\x1A\x45\xDF\xA3".b) }.to raise_error(types::Rejected)
  end

  it "leave the other purposes as they were" do
    expect(types.extensions("audio")).to include(".mid", ".opus")
    expect(types.extensions("video")).to include(".mkv", ".avi")
    expect(types.extensions("document")).to include(".docx", ".csv")
  end
end
