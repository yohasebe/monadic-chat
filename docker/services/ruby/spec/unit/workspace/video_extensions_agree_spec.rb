# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/workspace/file_types"

# The page offers videos to attach by extension (select_image.js); the server
# accepts them by its own table. A type the page offers but the server
# refuses can only fail after the upload, so the two lists must agree.
RSpec.describe "Attachment extensions offered by the page" do
  { "VIDEO_EXTENSIONS" => "video", "AUDIO_EXTENSIONS" => "audio" }.each do |constant, purpose|
    it "are exactly the ones the server accepts as #{purpose} attachments" do
      source = File.read(File.expand_path("../../../public/js/monadic/select_image.js", __dir__))
      listed = source[/const #{constant} = \[([^\]]*)\]/, 1]
      expect(listed).not_to be_nil
      offered = listed.scan(/'([^']+)'/).flatten
      expect(offered).not_to be_empty
      expect(offered.sort).to eq(Monadic::Workspace::FileTypes::PURPOSES.fetch(purpose).keys.sort)
    end
  end
end
