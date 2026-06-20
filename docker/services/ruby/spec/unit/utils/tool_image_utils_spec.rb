# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/utils/tool_image_utils'

# materialize_session_image bridges the gap between an uploaded image (stored in
# the session as a data URL) and the file-on-shared-volume that the video CLI
# generators require. Shared by the Veo and Grok image-to-video paths.
RSpec.describe Monadic::Utils::ToolImageUtils do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(tmpdir)
  end

  # 1x1 red PNG
  let(:png_b64) { 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' }
  let(:data_url) { "data:image/png;base64,#{png_b64}" }

  def session_with_image(data:, type: nil, title: 'photo.png')
    img = { 'data' => data, 'title' => title }
    img['type'] = type if type
    { messages: [{ 'role' => 'user', 'text' => 'animate this', 'images' => [img] }] }
  end

  describe '.materialize_session_image' do
    it 'writes an uploaded data URL to a temp file on the shared volume and returns the filename' do
      session = session_with_image(data: data_url)
      filename = described_class.materialize_session_image(session)

      expect(filename).to match(/\Avideo_gen_temp_\d+_\d+\.png\z/)
      saved = File.join(tmpdir, filename)
      expect(File.exist?(saved)).to be true
      expect(File.binread(saved)).to eq(Base64.decode64(png_b64))
    end

    it 'derives the extension from a JPEG data URL' do
      session = session_with_image(data: "data:image/jpeg;base64,#{png_b64}")
      filename = described_class.materialize_session_image(session)
      expect(filename).to end_with('.jpg')
    end

    it 'ignores the literal "image_path" placeholder and still resolves the upload' do
      session = session_with_image(data: data_url)
      filename = described_class.materialize_session_image(session, image_path: 'image_path')
      # Upload takes precedence (image_path is only consulted when nil), and the
      # placeholder is never treated as a real filename.
      expect(filename).to match(/\Avideo_gen_temp_/)
    end

    it 'uses an explicit filename when no upload is present (and not the placeholder)' do
      expect(described_class.materialize_session_image({ messages: [] }, image_path: 'cat.jpg')).to eq('cat.jpg')
      expect(described_class.materialize_session_image({ messages: [] }, image_path: 'image_path')).to be_nil
    end

    it 'falls back to last_image_key when no upload and no explicit path' do
      session = { messages: [], grok_last_video_image: 'prev.png' }
      result = described_class.materialize_session_image(session, last_image_key: :grok_last_video_image)
      expect(result).to eq('prev.png')
    end

    it 'returns nil when there is nothing to resolve' do
      expect(described_class.materialize_session_image({ messages: [] })).to be_nil
    end

    it 'rejects an oversize image (returns nil)' do
      huge = 'A' * (21 * 1024 * 1024)
      session = session_with_image(data: "data:image/png;base64,#{Base64.strict_encode64(huge)}")
      expect(described_class.materialize_session_image(session)).to be_nil
    end
  end
end
