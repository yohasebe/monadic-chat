# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/workspace/chat_files'
require_relative '../../../lib/monadic/shared_tools/file_operations'

# The file tools write into the chat's work folder, whatever place the model
# names, and never read, list or write another chat's folder.
RSpec.describe 'The files of a chat' do
  around do |example|
    Dir.mktmpdir('chat-files-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  let(:files) { Monadic::Workspace::ChatFiles }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:other_chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:caller_of) { ->(chat_id) { Struct.new(:chat_id, :session).new(chat_id, { parameters: { 'app_name' => 'CodingAssistantOpenAI' } }) } }
  let(:me) { caller_of.call(chat) }
  let(:tools) { Class.new { include MonadicSharedTools::FileOperations }.new }

  def work_of(chat_id)
    File.join(files.chat_dir(caller_of.call(chat_id), app_name: 'CodingAssistantOpenAI'), 'work')
  end

  def top_entries
    Dir.children(@data).sort
  end

  describe 'writing' do
    it 'puts a name at the top of the shared folder into the work folder, and says where' do
      %w[palindrome.py ./palindrome.py /monadic/data/palindrome.py].each do |given|
        result = tools.write_file_to_shared_folder(filepath: given, content: 'x', workbench: me)
        expect(result).to include(success: true, saved_as: "#{work_of(chat)}/palindrome.py", requested: given)
        expect(result[:execution_path]).to eq("/monadic/data/#{work_of(chat)}/palindrome.py")
        expect(result[:placed_in_chat_folder]).to be(given != 'work/palindrome.py')
        expect(result[:note]).to include(result[:saved_as], given)
      end
      expect(top_entries).to eq(['conversations'])
    end

    it 'takes the local path of the shared folder and keeps subfolders' do
      result = tools.write_file_to_shared_folder(filepath: File.join(@data, 'projects/src/app.py'), content: 'x', workbench: me)
      expect(result[:saved_as]).to eq("#{work_of(chat)}/projects/src/app.py")
      expect(File.read(File.join(@data, result[:saved_as]))).to eq('x')
    end

    it 'keeps a path already in the work folder, written either way, without saying it was moved' do
      first = tools.write_file_to_shared_folder(filepath: 'a.md', content: '1', workbench: me)
      again = tools.write_file_to_shared_folder(filepath: first[:saved_as], content: '2', workbench: me)
      short = tools.write_file_to_shared_folder(filepath: 'work/a.md', content: '3', mode: 'append', workbench: me)
      expect([again[:saved_as], short[:saved_as]]).to eq([first[:saved_as], first[:saved_as]])
      expect([again[:placed_in_chat_folder], short[:placed_in_chat_folder]]).to eq([false, false])
      expect(short[:action]).to eq('appended')
      expect(File.read(File.join(@data, first[:saved_as]))).to eq('23')
    end

    it 'appends to a copy of the user file named, leaving that file as it was' do
      File.write(File.join(@data, 'log.txt'), 'old ')
      result = tools.write_file_to_shared_folder(filepath: 'log.txt', content: 'new', mode: 'append', workbench: me)
      expect(result).to include(action: 'copied_and_appended', copied_from: 'log.txt', saved_as: "#{work_of(chat)}/log.txt")
      expect(File.read(File.join(@data, result[:saved_as]))).to eq('old new')
      expect(File.read(File.join(@data, 'log.txt'))).to eq('old ')
    end

    it "refuses other chats' folders in every spelling" do
      other = work_of(other_chat)
      spellings = [
        "#{other}/x.py", "/monadic/data/#{other}/x.py", File.join(@data, other, 'x.py'),
        "#{other.upcase}/x.py", " ./#{other}/x.py ", ".//#{other}//x.py",
        'conversations/x.py', 'Conversations/x.py', 'CONVERSATIONS', "conversations/../#{other}/x.py"
      ]
      spellings.each do |given|
        result = tools.write_file_to_shared_folder(filepath: given, content: 'x', workbench: me)
        expect(result[:success]).to be(false), given
      end
      expect(Dir.children(File.join(@data, other))).to be_empty
    end

    it 'refuses a decomposed spelling of conversations (NFD), as the disk would take it for the same folder' do
      decomposed = 'conversations'.unicode_normalize(:nfd) # ASCII: same; use a name with a mark
      expect(files.key(decomposed)).to eq(files.key('conversations'))
      expect(files.key("Café")).to eq(files.key("café"))
      expect { files.for_write("conversations/Café/x", caller: me, app_name: 'X') }.to raise_error(files::Refused)
    end

    it "refuses the chat's own folders other than work" do
      inputs = File.join(File.dirname(work_of(chat)), 'inputs', 'a.pdf')
      expect(tools.write_file_to_shared_folder(filepath: inputs, content: 'x', workbench: me)[:success]).to be(false)
    end

    it 'refuses ways out of the shared folder' do
      ['../etc/passwd', 'a/../../b', '/etc/passwd', '~/x', "a\u0000b", 'a\\b', "a\nb", ''].each do |given|
        expect(tools.write_file_to_shared_folder(filepath: given, content: 'x', workbench: me)[:success]).to be(false), given.inspect
      end
      expect(top_entries).to eq(['conversations'])
    end

    it 'writes nothing without a chat, and nothing at the top' do
      [nil, caller_of.call(nil), caller_of.call('not-an-id')].each do |who|
        result = tools.write_file_to_shared_folder(filepath: 'a.txt', content: 'x', workbench: who)
        expect(result).to include(success: false)
        expect(result[:error]).to include('no chat')
      end
      expect(top_entries).to eq([])
    end

    it 'writes nothing when the chat folder is gone' do
      work = work_of(chat)
      FileUtils.rm_rf(File.join(@data, File.dirname(work)))
      result = tools.write_file_to_shared_folder(filepath: 'a.txt', content: 'x', workbench: me)
      expect(result[:success]).to be(false)
      expect(top_entries).to eq(['conversations'])
      expect(Dir.children(File.join(@data, 'conversations'))).to be_empty
    end

    it 'refuses a link on the way into the work folder or in the file\'s place' do
      work = File.join(@data, work_of(chat))
      outside = File.join(@data, 'elsewhere')
      FileUtils.mkdir_p(outside)
      File.symlink(outside, File.join(work, 'linked'))
      File.symlink(File.join(outside, 'target.txt'), File.join(work, 'file.txt'))
      expect(tools.write_file_to_shared_folder(filepath: 'linked/a.txt', content: 'x', workbench: me)[:success]).to be(false)
      expect(tools.write_file_to_shared_folder(filepath: 'file.txt', content: 'x', workbench: me)[:success]).to be(false)
      expect(Dir.children(outside)).to be_empty
    end
  end

  describe 'reading' do
    before do
      File.write(File.join(@data, 'notes.md'), 'user notes')
      @mine = tools.write_file_to_shared_folder(filepath: 'notes.md', content: 'chat notes', workbench: me)[:saved_as]
      @theirs = tools.write_file_to_shared_folder(filepath: 'secret.md', content: 'THEIR-SECRET', workbench: caller_of.call(other_chat))[:saved_as]
    end

    it "reads a bare name from the chat's work folder first, and the user's own file by its full path" do
      expect(tools.read_file_from_shared_folder(filepath: 'notes.md', workbench: me)).to include(content: 'chat notes', filepath: @mine)
      expect(tools.read_file_from_shared_folder(filepath: '/monadic/data/notes.md', workbench: me)).to include(content: 'user notes', filepath: 'notes.md')
      expect(tools.read_file_from_shared_folder(filepath: @mine, workbench: me)[:content]).to eq('chat notes')
      expect(tools.read_file_from_shared_folder(filepath: 'work/notes.md', workbench: me)[:content]).to eq('chat notes')
    end

    it 'returns no bytes of a file that is not text, and says it reads text only' do
      File.binwrite(File.join(@data, 'sound.m4a'), "\x00\x00\x00\x20ftypM4A \xFF\xFE\x00".b)
      File.binwrite(File.join(@data, 'latin1.txt'), "caf\xE9".b)
      %w[sound.m4a latin1.txt].each do |name|
        result = tools.read_file_from_shared_folder(filepath: "/monadic/data/#{name}", workbench: me)
        expect(result).to include(success: false, error: 'Not a text file: this tool reads text files only'), name
        expect(result).not_to have_key(:content)
      end
    end

    it "never reads another chat's folder, however it is spelled" do
      [@theirs, "/monadic/data/#{@theirs}", @theirs.upcase, File.join(@data, @theirs)].each do |given|
        result = tools.read_file_from_shared_folder(filepath: given, workbench: me)
        expect(result[:success]).to be(false), given
        expect(result.to_s).not_to include('THEIR-SECRET')
      end
    end

    it "never reads a file that has another name elsewhere (a hard link into another chat's folder)" do
      File.link(File.join(@data, @theirs), File.join(@data, 'innocent.md'))
      result = tools.read_file_from_shared_folder(filepath: '/monadic/data/innocent.md', workbench: me)
      expect(result[:success]).to be(false)
      expect(result.to_s).not_to include('THEIR-SECRET')
      appended = tools.write_file_to_shared_folder(filepath: 'innocent.md', content: 'x', mode: 'append', workbench: me)
      expect(File.read(File.join(@data, appended[:saved_as]))).to eq('x')
    end

    it "never reads another chat's folder through a link in the user's folders" do
      File.symlink(File.join(@data, File.dirname(@theirs)), File.join(@data, 'shortcut'))
      result = tools.read_file_from_shared_folder(filepath: '/monadic/data/shortcut/secret.md', workbench: me)
      expect(result[:success]).to be(false)
      expect(result.to_s).not_to include('THEIR-SECRET')
    end
  end

  describe 'listing' do
    before do
      tools.write_file_to_shared_folder(filepath: 'a.py', content: 'x', workbench: me)
      tools.write_file_to_shared_folder(filepath: 'b.py', content: 'x', workbench: caller_of.call(other_chat))
      FileUtils.mkdir_p(File.join(@data, 'projects'))
    end

    it "lists the chat's work folder by default, and the top without what is in conversations/" do
      expect(tools.list_files_in_shared_folder(workbench: me)[:files].map { |f| f[:name] }).to eq(['a.py'])
      top = tools.list_files_in_shared_folder(directory: '/', workbench: me)
      conversations = top[:directories].find { |d| d[:name] == 'conversations' }
      expect(conversations).not_to have_key(:items)
      expect(top[:directories].map { |d| d[:name] }).to include('projects')
    end

    it "refuses conversations/ and other chats' folders" do
      ['conversations', 'Conversations/', "/monadic/data/conversations", File.dirname(work_of(other_chat))].each do |given|
        result = tools.list_files_in_shared_folder(directory: given, workbench: me)
        expect(result[:success]).to be(false), given
        expect(result.to_s).not_to include('b.py')
      end
    end
  end

  describe 'the comparison it relies on' do
    it 'would let a differently spelled other-chat path through without case folding and composition (negative control)' do
      naive = ->(relative, dir) { relative == dir || relative.start_with?("#{dir}/") }
      expect(naive.call('Conversations/x', 'conversations')).to be(false)
      expect(files.inside?('Conversations/x', 'conversations')).to be(true)
      expect(naive.call("conversations/Café", "conversations/café")).to be(false)
      expect(files.inside?("conversations/Café", "conversations/café")).to be(true)
    end
  end
end
