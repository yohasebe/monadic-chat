# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/workspace'

# The shared folder as the page lists it: what each entry is, what must not
# be removed, what a chat is using, and folder sizes counted apart from the
# listing. Read only.
RSpec.describe Monadic::Workspace::SharedFolder do
  around do |example|
    Dir.mktmpdir('shared-folder-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
  end

  let(:ids) { Monadic::Workspace::Ids }
  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }

  def write(relative, body = 'x')
    path = File.join(@data, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def item(listing, name)
    listing[:items].find { |i| i[:name] == name }
  end

  describe 'the id of the shared folder' do
    it 'is made once and kept' do
      first = described_class.root_id
      expect(first).to match(/\A[0-9a-f]{32}\z/)
      expect(described_class.root_id).to eq(first)
    end

    it 'is refused when the file is a link' do
      File.symlink('/etc/hosts', File.join(@data, described_class::ROOT_ID_FILE))
      expect { described_class.root_id }.to raise_error(described_class::Invalid)
    end
  end

  describe 'when the id cannot be made' do
    it 'still lists, and offers nothing to show on this computer' do
      write('notes.txt')
      File.chmod(0o555, @data)
      listing = described_class.list('', ledger: ledger)
      expect(listing[:root_id]).to be_nil
      expect(listing[:root_id_problem]).to be_a(String)
      expect(item(listing, 'notes.txt')[:capabilities]).to eq(reveal: false, trash: false)
    ensure
      File.chmod(0o755, @data)
    end

    it 'leaves no file of its own behind' do
      described_class.root_id
      expect(Dir.children(@data)).to eq([described_class::ROOT_ID_FILE])
    end
  end

  describe 'a folder with very many entries' do
    it 'is listed from the first ones read, and says so' do
      stub_const("#{described_class}::MAX_NAMES", 5)
      8.times { |i| write("many/f#{i}") }
      listing = described_class.list('many', ledger: ledger)
      expect(listing).to include(truncated: true, total: 5)
    end
  end

  describe 'sizes asked for without a listing' do
    it 'gives what is known, pending, or gone' do
      write('a/f', 'xyz')
      counter = described_class::Sizes.new(root_proc: -> { @data })
      counter.define_singleton_method(:enqueue) { |relative| @queue << relative unless @queue.include?(relative) }
      expect(described_class.sizes_of(['a'], sizes: counter)).to eq('a' => { size_status: 'pending' })
      counter.drain!
      expect(described_class.sizes_of(['a', 'missing', '../x'], sizes: counter))
        .to include('a' => include(bytes: 3, size_status: 'complete'), 'missing' => { size_status: 'vanished' },
                    '../x' => { size_status: 'vanished' })
    end
  end

  describe 'what may be moved to the trash' do
    let(:chat) { ids.generate(:chat) }
    let(:workspace) { ids.generate(:workspace) }
    let(:chat_dir) { "20261011-100000_chat_#{workspace}" }

    before do
      ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'ChatOpenAI',
                                relative_dir: "conversations/#{chat_dir}")
      write("conversations/#{chat_dir}/inputs/a.txt")
      write('scripts/mine.py')
      write('notes.txt')
    end

    it 'offers a plain file, but not what is protected or in a chat open in a tab' do
      expect(described_class.entry('notes.txt', ledger: ledger)[:capabilities][:trash]).to be true
      expect(described_class.entry('scripts', ledger: ledger)[:capabilities][:trash]).to be false
      expect(described_class.entry('scripts/mine.py', ledger: ledger)[:capabilities][:trash]).to be false
      expect(described_class.entry("conversations/#{chat_dir}", ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
      expect(described_class.entry("conversations/#{chat_dir}/inputs/a.txt", ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
      expect(described_class.entry("conversations/#{chat_dir}/inputs/a.txt", ledger: ledger)[:capabilities][:trash]).to be true
    end

    it 'keeps a folder that holds the folder of a chat open in a tab, and the folders kept for a purpose' do
      write('auto_forge/p/index.html')
      expect(described_class.entry('conversations', ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
      expect(described_class.entry('conversations', ledger: ledger)[:capabilities][:trash]).to be false
      expect(described_class.entry('auto_forge', ledger: ledger)[:capabilities][:trash]).to be false
      expect(described_class.entry('auto_forge/p', ledger: ledger)[:capabilities][:trash]).to be true
    end

    it 'offers nothing while the record cannot be read' do
      unreadable = double('Ledger')
      allow(unreadable).to receive(:snapshot).and_raise(Monadic::Workspace::Ledger::Unreadable)
      expect(described_class.entry('notes.txt', ledger: unreadable)[:capabilities][:trash]).to be false
    end

    it 'takes a path only as the folder spells it' do
      expect { described_class.entry('Scripts', ledger: ledger) }.to raise_error(described_class::Invalid)
      expect { described_class.entry('NOTES.txt', ledger: ledger) }.to raise_error(described_class::Invalid)
    end

    it 'refuses the shared folder itself, a missing entry and a path through a link' do
      File.symlink('/etc', File.join(@data, 'elsewhere'))
      expect { described_class.entry('', ledger: ledger) }.to raise_error(described_class::Invalid)
      expect { described_class.entry('missing.txt', ledger: ledger) }.to raise_error(described_class::Invalid)
      expect { described_class.entry('elsewhere/hosts', ledger: ledger) }.to raise_error(described_class::Invalid)
      expect(described_class.entry('elsewhere', ledger: ledger)[:capabilities][:trash]).to be false
    end
  end

  describe 'sorting, filtering and searching a folder' do
    before do
      write('small.txt', 'x')
      write('big.bin', 'x' * 500)
      write('middle.md', 'x' * 50)
      write("#{SharedFolderTestFiles.name('a')}.txt", 'x' * 10)
      File.utime(Time.at(1_700_000_000), Time.at(1_700_000_000), File.join(@data, 'big.bin'))
      File.utime(Time.at(1_800_000_000), Time.at(1_800_000_000), File.join(@data, 'small.txt'))
    end

    def names(listing)
      listing[:items].map { |i| i[:name] }.reject { |n| n.start_with?('.') }
    end

    it 'puts the largest first when sorted by size, and turns it around on request' do
      expect(names(described_class.list('', ledger: ledger, sort: 'size')).first).to eq('big.bin')
      expect(names(described_class.list('', ledger: ledger, sort: 'size', descending: true)).last).to eq('big.bin')
    end

    it 'puts the newest first when sorted by modification time' do
      listed = names(described_class.list('', ledger: ledger, sort: 'modified'))
      expect(listed.index('small.txt')).to be < listed.index('big.bin')
      expect(listed.last).to eq('big.bin')
    end

    it 'keeps the names holding the query, in any case' do
      listing = described_class.list('', ledger: ledger, query: 'MIDDLE')
      expect(names(listing)).to eq(['middle.md'])
      expect(listing[:matched]).to eq(1)
      expect(listing[:total]).to be > 1
    end

    it 'keeps the entries of the chosen kinds' do
      listing = described_class.list('', ledger: ledger, classes: ['test_file'])
      expect(names(listing)).to eq(["#{SharedFolderTestFiles.name('a')}.txt"])
    end

    it 'counts folder sizes only for the page shown when searching names or filtering by kind' do
      5.times { |n| FileUtils.mkdir_p(File.join(@data, "dir#{n}")) }
      sizes = double('Sizes')
      allow(sizes).to receive(:lookup).and_return(nil)
      described_class.list('', ledger: ledger, sizes: sizes, query: 'zzz-no-match')
      expect(sizes).not_to have_received(:lookup)
      described_class.list('', ledger: ledger, sizes: sizes, query: 'dir', classes: ['other'], per_page: 2)
      expect(sizes).to have_received(:lookup).at_most(2).times
    end

    it 'falls back to name order for an unknown sort' do
      expect(names(described_class.list('', ledger: ledger, sort: 'nonsense'))).to eq(names(described_class.list('', ledger: ledger)))
    end
  end

  describe 'listing the top of the shared folder' do
    let(:chat) { ids.generate(:chat) }

    before do
      write('scripts/mine.py')
      write('compose_user.yml')
      write('gemini3_image_1760000000.png', 'png')
      write('1760000000_abcdef12.md')
      write('notes.txt')
      write("pub_#{attachment}.mp4")
      write('pub_j_aaaaaaaaaaaaaaaa.vtt')
      FileUtils.mkdir_p(File.join(@data, 'auto_forge'))
      File.symlink('/etc', File.join(@data, 'elsewhere'))
    end

    let(:attachment) do
      workspace = ids.generate(:workspace)
      dir = "conversations/20261011-100000_video_#{workspace}"
      ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'VideoDescriberOpenAI', relative_dir: dir)
      id = ids.generate(:attachment)
      ledger.register_attachment(attachment_id: id, chat_id: chat, workspace_id: workspace, purpose: 'video',
                                 original_name: 'v.mp4', relative_path: "#{dir}/inputs/#{id}__v.mp4")
      id
    end

    let(:listing) { described_class.list('', ledger: ledger) }

    it 'protects what the app and your setup read, and says why' do
      expect(item(listing, 'scripts')).to include(classification: 'protected', protected_reason: 'user_scripts')
      expect(item(listing, 'compose_user.yml')[:protected_reason]).to be_a(String)
      expect(item(listing, described_class::ROOT_ID_FILE)[:protected_reason]).to be_a(String)
    end

    it 'says where it knows what an entry is and where it only guesses from the name' do
      expect(item(listing, "pub_#{attachment}.mp4")).to include(classification: 'public_copy', classification_source: 'ledger',
                                                                  owner_chat_id: chat)
      expect(item(listing, 'pub_j_aaaaaaaaaaaaaaaa.vtt')).to include(classification: 'public_copy', classification_source: 'name')
      expect(item(listing, 'gemini3_image_1760000000.png')).to include(classification: 'generated', classification_source: 'name')
      expect(item(listing, '1760000000_abcdef12.md')).to include(classification: 'intermediate_candidate')
      expect(item(listing, 'notes.txt')).to include(classification: 'other', classification_source: 'none')
      expect(item(listing, 'auto_forge')).to include(classification: 'projects', kind: 'folder')
    end

    it 'marks what tests made for certain, and what only looks like an old test leftover' do
      write("#{SharedFolderTestFiles.name('notebook')}.ipynb")
      write('.test_tmp/x.md')
      write('test_selenium_1760000000.txt')
      write('test_image.png', 'png')
      write("auto_forge/#{SharedFolderTestFiles.name('TestApp_1')}/index.html")
      write('auto_forge/TestApp_1760000000/index.html')
      write('auto_forge/MyProject_1760000000/index.html')
      write('pdf2text_0123456789abcdef.pdf')
      top = described_class.list('', ledger: ledger)
      expect(item(top, "#{SharedFolderTestFiles.name('notebook')}.ipynb")).to include(classification: 'test_file')
      expect(item(top, '.test_tmp')).to include(classification: 'test_file')
      expect(item(top, 'test_selenium_1760000000.txt')).to include(classification: 'test_candidate', classification_source: 'name')
      expect(item(top, 'test_image.png')).to include(classification: 'generated')
      expect(item(top, 'pdf2text_0123456789abcdef.pdf')).to include(classification: 'intermediate_candidate')
      projects = described_class.list('auto_forge', ledger: ledger)
      expect(item(projects, SharedFolderTestFiles.name('TestApp_1'))).to include(classification: 'test_file')
      expect(item(projects, 'TestApp_1760000000')).to include(classification: 'test_candidate')
      expect(item(projects, 'MyProject_1760000000')).to include(classification: 'projects')
    end

    it 'lists a link as a link, without following it or offering to open it' do
      link = item(listing, 'elsewhere')
      expect(link).to include(kind: 'link', size_status: 'none')
      expect(link[:capabilities]).to eq(reveal: false, trash: false)
    end

    it 'gives files their size and leaves folders to the count' do
      expect(item(listing, 'notes.txt')).to include(bytes: 1, size_status: 'complete')
      expect(item(listing, 'auto_forge')).to include(size_status: 'pending')
      expect(item(listing, 'auto_forge')).not_to have_key(:bytes)
    end

    it 'pages through the entries' do
      first = described_class.list('', ledger: ledger, per_page: 3)
      second = described_class.list('', ledger: ledger, per_page: 3, page: 2)
      expect(first[:total]).to eq(second[:total])
      expect(first[:items].map { |i| i[:name] } & second[:items].map { |i| i[:name] }).to be_empty
    end
  end

  describe 'listing the chat folders' do
    it 'ties a folder to its chat by the ledger only, and marks one open in a tab' do
      open_chat = ids.generate(:chat)
      other_chat = ids.generate(:chat)
      [open_chat, other_chat].each_with_index do |chat, i|
        workspace = ids.generate(:workspace)
        relative = "conversations/2026101#{i}-100000_chat_#{workspace}"
        FileUtils.mkdir_p(File.join(@data, relative))
        ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'ChatOpenAI', relative_dir: relative)
      end
      FileUtils.mkdir_p(File.join(@data, 'conversations', '20261012-100000_chat_w_unknownunknown1'))

      listing = described_class.list('conversations', ledger: ledger, live_chat_ids: [open_chat])
      by_owner = listing[:items].group_by { |i| i[:owner_chat_id] }
      expect(by_owner[open_chat].first).to include(classification_source: 'ledger', app_name: 'ChatOpenAI',
                                                   busy_reason: 'open_in_tab')
      expect(by_owner[other_chat].first).not_to have_key(:busy_reason)
      expect(by_owner[nil].first).to include(classification: 'chat_folder', classification_source: 'none')
    end

    it 'protects everything inside a protected folder' do
      write('apps/my_app/my_app.mdsl')
      expect(described_class.list('apps', ledger: ledger)[:items].first[:protected_reason]).to be_a(String)
    end
  end

  describe 'the path asked for' do
    it 'is refused when it could leave the shared folder or goes through a link' do
      File.symlink('/etc', File.join(@data, 'elsewhere'))
      ['/etc', '..', 'a/../..', 'a//b', 'a\\b', "a\0b", 'elsewhere', 'missing'].each do |path|
        expect { described_class.list(path, ledger: ledger) }.to raise_error(described_class::Invalid), path.inspect
      end
    end
  end

  describe Monadic::Workspace::SharedFolder::Sizes do
    let(:time) { [0.0] }

    def sizes(**options)
      clock = time
      described_class.new(root_proc: -> { @data }, clock: -> { clock[0] }, **options).tap do |s|
        # counted in the test's own thread
        s.define_singleton_method(:enqueue) { |relative| @queue << relative unless @queue.include?(relative) }
      end
    end

    it 'counts a folder in the background and reports it when asked again' do
      write('auto_forge/p/index.html', '12345')
      write('auto_forge/p/README.md', '123')
      File.symlink('/etc', File.join(@data, 'auto_forge', 'p', 'link'))
      counter = sizes
      expect(counter.lookup('auto_forge')).to be_nil
      counter.drain!
      expect(counter.lookup('auto_forge')).to include(bytes: 8, files: 2, status: 'complete')
    end

    it 'tells what is known without queueing a count (for choosing all)' do
      write('auto_forge/p/index.html', '12345')
      counter = sizes
      expect(counter.peek('auto_forge')).to be_nil
      counter.drain!
      expect(counter.peek('auto_forge')).to be_nil # nothing was queued
      counter.lookup('auto_forge')
      counter.drain!
      expect(counter.peek('auto_forge')).to include(bytes: 5, files: 1, status: 'complete')
    end

    it 'gives every entry for all, in name order too' do
      3.times { |i| write("f#{i}.txt") }
      listing = Monadic::Workspace::SharedFolder.list('', page: 1, per_page: 1, all: true, ledger: Monadic::Workspace::Ledger.new(File.join(@data, '..', 'l.json')))
      expect(listing[:items].map { |i| i[:name] }.grep(/\Af/)).to eq(%w[f0.txt f1.txt f2.txt]) # past the page size of 1
    end

    it 'says a count was cut short, with what it counted' do
      10.times { |i| write("big/f#{i}.txt", 'x') }
      counter = sizes(max_entries: 3)
      counter.lookup('big')
      counter.drain!
      result = counter.lookup('big')
      expect(result[:status]).to eq('partial')
      expect(result[:files]).to be < 10
    end

    it 'shares one budget among the folders of one run' do
      5.times { |i| write("a/f#{i}", 'x') }
      5.times { |i| write("b/f#{i}", 'x') }
      counter = sizes(max_entries: 6)
      counter.lookup('a')
      counter.lookup('b')
      counter.drain!
      expect([counter.lookup('a')[:status], counter.lookup('b')[:status]]).to include('partial')
    end

    it 'does not follow a folder replaced by a link while it waited' do
      write('parent/child/f', 'x')
      outside = Dir.mktmpdir('outside')
      File.write(File.join(outside, 'big'), 'x' * 10)
      counter = sizes
      counter.lookup('parent/child')
      FileUtils.mv(File.join(@data, 'parent'), File.join(@data, 'moved'))
      FileUtils.mkdir_p(File.join(outside, 'child'))
      File.write(File.join(outside, 'child', 'big'), 'x' * 10)
      File.symlink(outside, File.join(@data, 'parent'))
      counter.drain!
      expect(counter.lookup('parent/child')).to include(bytes: 0, status: 'changed')
    ensure
      FileUtils.rm_rf(outside) if outside
    end

    it 'reports a folder it may not enter, and goes on with the next' do
      write('closed/inner/f', 'x')
      write('open/f', 'xy')
      File.chmod(0o000, File.join(@data, 'closed'))
      counter = sizes
      counter.lookup('closed/inner')
      counter.lookup('open')
      counter.drain!
      expect(counter.lookup('closed/inner')[:status]).to eq('permission_denied')
      expect(counter.lookup('open')).to include(bytes: 2, status: 'complete')
    ensure
      File.chmod(0o755, File.join(@data, 'closed'))
    end

    it 'does not count a folder again while it is being counted' do
      write('busy/f', 'xyz')
      counter = nil
      asked = []
      counter = described_class.new(root_proc: lambda {
        asked << counter.lookup('busy') if asked.empty? # asked again mid-count
        @data
      })
      counter.define_singleton_method(:enqueue) do |relative|
        @queue << relative unless @queue.include?(relative) || @running == relative
      end
      counter.lookup('busy')
      counter.drain!
      expect(counter.instance_variable_get(:@queue)).to be_empty
      expect(counter.lookup('busy')).to include(bytes: 3, status: 'complete')
    end

    # The real worker: a folder asked for just as the worker finds nothing
    # more to do is still counted.
    it 'counts a folder queued as the worker finishes' do
      write('a/f', 'x')
      write('b/f', 'xy')
      gate = Queue.new
      release = Queue.new
      counter = described_class.new(root_proc: -> { @data })
      original = counter.method(:store)
      counter.define_singleton_method(:store) do |relative, result|
        original.call(relative, result)
        if relative == 'a'
          gate << :stored
          release.pop
        end
      end
      counter.lookup('a')
      gate.pop
      counter.lookup('b') # queued while the worker is about to look for more
      release << :go
      deadline = Time.now + 5
      sleep 0.01 until counter.lookup('b') || Time.now > deadline
      expect(counter.lookup('b')).to include(bytes: 2, status: 'complete')
    end

    # A worker that has given up its place finishes after a new worker has
    # started: it leaves the new one's folder marked as being counted.
    it "lets a finished worker leave the next worker's state alone" do
      counter = described_class.new(root_proc: -> { @data })
      successor = Thread.new { sleep 5 }
      counter.instance_variable_set(:@worker, successor)
      counter.instance_variable_set(:@running, 'b')
      counter.drain! # this thread is not the worker: the queue is empty, it ends
      expect(counter.instance_variable_get(:@running)).to eq('b')
      expect(counter.instance_variable_get(:@worker)).to equal(successor)
      expect(counter.lookup('b')).to be_nil
      expect(counter.instance_variable_get(:@queue)).to be_empty # not queued again
    ensure
      successor&.kill
    end

    it 'keeps a full count over a recount cut short' do
      5.times { |i| write("d/f#{i}", 'x') }
      counter = sizes
      counter.lookup('d')
      counter.drain!
      counter.instance_variable_set(:@max_entries, 1)
      time[0] += described_class::FRESH_FOR + 1
      counter.lookup('d')
      counter.drain!
      expect(counter.lookup('d')).to include(bytes: 5, status: 'complete')
    end

    it 'counts again once a count is old' do
      write('c/f', 'x')
      counter = sizes
      counter.lookup('c')
      counter.drain!
      write('c/g', 'xx')
      time[0] += described_class::FRESH_FOR + 1
      expect(counter.lookup('c')[:bytes]).to eq(1) # the old count, while the new one runs
      counter.drain!
      expect(counter.lookup('c')[:bytes]).to eq(3)
    end
  end
end
