# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require_relative '../../../lib/monadic/history'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/shared_file_path'

# The history is kept in the state folder, beside the shared folder: the
# routes that serve the shared folder's files (GET /data/<name>, and the
# panel's file and text previews) reach none of its files, by name or through a link.
RSpec.describe 'The history files and the routes of the shared folder' do
  let(:marker) { "MARK#{SecureRandom.hex(16)}" }

  around do |example|
    Dir.mktmpdir('history-reach') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p([@data, @state])
      store = Monadic::History::Store.new(File.join(@state, 'history.sqlite3'))
      store.save('chat_a', { 'messages' => [{ 'role' => 'user', 'text' => marker }] })
      @history = Dir.glob(File.join(@state, 'history.sqlite3*'))
      example.run
      store.close
    end
  end

  before { allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data) }

  def served(name)
    status, _headers, body = Monadic::Utils::SharedFilePath.response(name, @data, { 'REQUEST_METHOD' => 'GET' })
    text = +''
    body.each { |chunk| text << chunk }
    body.close if body.respond_to?(:close)
    [status, text]
  end

  def preview(relative)
    io, = Monadic::Workspace::SharedFolderPreview.open_file(relative)
    text = io.read
    io.close
    text
  rescue Monadic::Workspace::SharedFolderPreview::Invalid, SystemCallError
    nil
  end

  # The text preview's route; it also refuses data that is not text, so the
  # byte-level check of the link guard is the preview above.
  def text_preview(relative)
    Monadic::Workspace::SharedFolderPreview.read_text(relative)[:text]
  rescue Monadic::Workspace::SharedFolderPreview::Invalid, Monadic::Workspace::SharedFolderPreview::NotText, SystemCallError
    nil
  end

  it 'does serve a file of the shared folder (the routes are reached at all)' do
    File.write(File.join(@data, 'note.txt'), marker)
    expect(served('note.txt')).to eq([200, marker])
    expect(preview('note.txt')).to eq(marker)
    expect(text_preview('note.txt')).to eq(marker)
  end

  it 'serves none of the history files by name, outside the shared folder or through a link' do
    expect(@history.map { |f| File.binread(f) }.join).to include(marker)
    @history.each do |file|
      base = File.basename(file)
      link = "#{base.tr('.-', '__')}.txt"
      File.symlink(file, File.join(@data, link))
      ["../state/#{base}", base, link].each do |name|
        status, text = served(name)
        expect(status).not_to eq(200), "#{name} was served"
        expect(text).not_to include(marker)
        expect(preview(name)).to be_nil, "#{name} was previewed"
        expect(text_preview(name)).to be_nil, "#{name} was shown as text"
      end
    end
  end
end
