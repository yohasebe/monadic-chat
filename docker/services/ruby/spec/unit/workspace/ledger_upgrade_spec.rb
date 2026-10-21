# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'rbconfig'
require 'stringio'
require_relative '../../../lib/monadic/workspace'

# A version 1 ledger (as beta.42 and beta.43 write it) is read in the current
# form without being changed. The first change keeps its bytes as they were,
# settled on disk before anything else, and then saves version 2. A failure
# before the replacement leaves the disk as it was; a failure to settle the
# replacement stops all writing to that ledger in this process.
RSpec.describe 'Upgrading the workspace ledger' do
  around do |example|
    Dir.mktmpdir('ledger-upgrade') do |dir|
      @dir = dir
      example.run
    end
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  let(:ledger_class) { Monadic::Workspace::Ledger }
  let(:disk) { Monadic::Workspace::Ledger::Disk }
  let(:ids) { Monadic::Workspace::Ids }
  let(:path) { File.join(@dir, 'ledger.json') }
  let(:ledger) { ledger_class.new(path) }
  let(:chat) { ids.generate(:chat) }
  let(:workspace) { ids.generate(:workspace) }
  let(:attachment) { ids.generate(:attachment) }

  # A version 1 ledger in the layout the earlier version writes, with a field
  # the current version does not know.
  def v1_bytes(status: 'ready')
    dir = "conversations/20261011-100000_video_#{workspace}"
    record = { 'chat_id' => chat, 'workspace_id' => workspace, 'purpose' => 'video', 'original_name' => 'v.mp4',
               'relative_path' => "#{dir}/inputs/#{attachment}__v.mp4", 'status' => status,
               'created_at' => '2026-10-11T01:00:00Z' }
    if status == 'ready'
      record['size'] = 10
      record['sha256'] = 'b' * 64
    end
    # Not the layout this version would write, so a backup made from parsed
    # data rather than from the bytes would differ.
    "#{JSON.generate(
      'schema_version' => 1,
      'chats' => { chat => { 'workspace_id' => workspace, 'created_at' => '2026-10-11T01:00:00Z' } },
      'workspaces' => { workspace => { 'chat_id' => chat, 'relative_dir' => dir, 'app_name' => 'VideoDescriberOpenAI',
                                       'created_at' => '2026-10-11T01:00:00Z', 'kept' => 'unknown field' } },
      'attachments' => { attachment => record }
    )}\n"
  end

  def write_v1(**opts)
    bytes = v1_bytes(**opts)
    File.binwrite(path, bytes)
    bytes
  end

  def change!
    ledger.update_attachment(attachment, status: 'failed', 'failure' => 'Interrupted')
  end

  def backups
    Dir.children(@dir).grep(/\.bak\z/).sort
  end

  def on_disk
    JSON.parse(File.binread(path))
  end

  it 'reads a version 1 ledger without changing the disk' do
    bytes = write_v1
    expect(ledger.attachment(attachment)[:status]).to eq('ready')
    expect(ledger.schema_version).to eq(2)
    expect(File.binread(path)).to eq(bytes)
    expect(backups).to be_empty
  end

  it 'keeps the version 1 bytes exactly on the first change, then saves version 2 (and keeps fields it does not know)' do
    bytes = write_v1
    change!
    expect(File.binread(File.join(@dir, 'ledger.json.v1.bak'))).to eq(bytes)
    expect(on_disk).to include('schema_version' => 2, 'artifacts' => {}, 'publications' => {})
    expect(on_disk['workspaces'][workspace]['kept']).to eq('unknown field')
    change!
    expect(backups).to eq(['ledger.json.v1.bak'])
  end

  it 'settles a backup of the same bytes again rather than trusting it, and keeps one of other bytes' do
    bytes = write_v1
    File.binwrite(File.join(@dir, 'ledger.json.v1.bak'), bytes)
    expect(disk).to receive(:sync_file).with(File.join(@dir, 'ledger.json.v1.bak')).and_call_original
    change!
    expect(backups).to eq(['ledger.json.v1.bak'])

    Monadic::Workspace::Ledger.clear_unsettled!
    File.binwrite(path, write_v1)
    File.binwrite(File.join(@dir, 'ledger.json.v1.bak'), 'an older backup')
    change!
    expect(File.binread(File.join(@dir, 'ledger.json.v1.bak'))).to eq('an older backup')
    other = backups - ['ledger.json.v1.bak']
    expect(other.size).to eq(1)
    expect(File.binread(File.join(@dir, other.first))).to eq(bytes)
  end

  # Faults inside the real Disk methods: the open of a new file, the fsync of
  # a file, the fsync of the folder.
  def fail_open(suffix, error)
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).with(a_string_ending_with(suffix), File::WRONLY | File::CREAT | File::EXCL, 0o600)
                                 .and_raise(error)
  end

  def fail_fsync(error)
    allow_any_instance_of(File).to receive(:fsync).and_wrap_original do |m, *args|
      yield(m.receiver.path) ? raise(error) : m.call(*args)
    end
  end

  it 'changes nothing when the backup cannot be made or settled, and leaves no part of one' do
    half_written = lambda do
      allow_any_instance_of(File).to receive(:write).and_wrap_original do |m, bytes|
        next m.call(bytes) unless m.receiver.path.end_with?('.bak')

        m.call(bytes[0, 5])
        raise Errno::ENOSPC
      end
    end
    [
      # [fault, whether a backup is left (it is when only the folder sync fails)]
      [-> { fail_open('.bak', Errno::EIO) }, false],
      [half_written, false],
      [-> { fail_fsync(Errno::ENOSPC) { |p| p.end_with?('.bak') } }, false],
      [-> { fail_fsync(Errno::EBADF) { |p| p == @dir } }, true],
      [-> { fail_fsync(Errno::EINVAL) { |p| p == @dir } }, true]
    ].each_with_index do |(fault, left), i|
      RSpec::Mocks.space.reset_all
      FileUtils.rm_f(Dir.glob(File.join(@dir, '*')))
      bytes = write_v1
      fault.call
      expect { change! }.to raise_error(ledger_class::NotUpgraded), "fault #{i}"
      RSpec::Mocks.space.reset_all
      expect(File.binread(path)).to eq(bytes)
      expect(Dir.children(@dir).grep(/\.tmp\z/)).to be_empty
      expect(backups.map { |b| File.binread(File.join(@dir, b)) }).to all(eq(bytes)), "fault #{i}"
      expect(backups.size).to eq(left ? 1 : 0), "fault #{i}"
    end
  end

  it 'does not take a backup of the same bytes as settled when it cannot be synced again' do
    bytes = write_v1
    File.binwrite(File.join(@dir, 'ledger.json.v1.bak'), bytes)
    fail_fsync(Errno::EIO) { |p| p.end_with?('.bak') }
    expect { change! }.to raise_error(ledger_class::NotUpgraded)
    RSpec::Mocks.space.reset_all
    expect(File.binread(path)).to eq(bytes)
  end

  it 'leaves a file of the same temporary name as it is (it did not make it)' do
    write_v1
    change!
    allow(SecureRandom).to receive(:hex).and_return('fixedfixed12')
    taken = "#{path}.fixedfixed12.tmp"
    File.binwrite(taken, 'someone else')
    expect { change! }.to raise_error(Errno::EEXIST)
    expect(File.binread(taken)).to eq('someone else')
  end

  it 'takes a folder that cannot be synced after the replacement as unsettled, whatever the error' do
    write_v1
    change!
    calls = 0
    fail_fsync(Errno::EBADF) { |p| p == @dir && (calls += 1) >= 1 }
    expect { change! }.to raise_error(ledger_class::Unsettled)
  end

  it 'keeps the finished file of an attachment whose ready record could not be settled' do
    data = File.join(@dir, 'data')
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data)
    FileUtils.mkdir_p(data)
    attachments = Monadic::Workspace::Attachments
    head = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b
    attachments.accept!(chat_id: chat, app_name: 'VideoDescriberOpenAI', purpose: 'video', original_name: 'first.mp4',
                        source: StringIO.new(head + ('x' * 100)), ledger: ledger)
    allow(disk).to(receive(:sync_dir).and_wrap_original { |m, d| on_disk['attachments'].values.any? { |r| r['status'] == 'ready' && r['original_name'] == 'kept.mp4' } ? raise(Errno::EIO) : m.call(d) })
    expect do
      attachments.accept!(chat_id: chat, app_name: 'VideoDescriberOpenAI', purpose: 'video', original_name: 'kept.mp4',
                          source: StringIO.new(head + ('y' * 100)), ledger: ledger)
    end.to raise_error(attachments::Unusable) { |e| expect(e.reason).to eq(:unsettled) }
    record = on_disk['attachments'].values.find { |r| r['original_name'] == 'kept.mp4' }
    expect(record['status']).to eq('ready')
    expect(File.exist?(File.join(data, record['relative_path']))).to be(true)
  end

  it 'stops writing the same ledger named in another case where the file system does not tell case apart' do
    write_v1
    change!
    other_case = File.join(@dir, 'LEDGER.JSON')
    skip 'this file system tells case apart' unless File.exist?(other_case) && File.identical?(other_case, path)

    allow(disk).to receive(:sync_dir).and_raise(Errno::EIO)
    expect { change! }.to raise_error(ledger_class::Unsettled)
    RSpec::Mocks.space.reset_all
    expect { ledger_class.new(other_case).update_attachment(attachment, status: 'failed') }
      .to raise_error(ledger_class::Unsettled)
  end

  it 'stops writing the same ledger named through a link to its folder' do
    write_v1
    change!
    link = File.join(Dir.tmpdir, "ledger-link-#{SecureRandom.hex(4)}")
    File.symlink(@dir, link)
    allow(disk).to receive(:sync_dir).and_raise(Errno::EIO)
    expect { change! }.to raise_error(ledger_class::Unsettled)
    RSpec::Mocks.space.reset_all
    through_link = ledger_class.new(File.join(link, 'ledger.json'))
    expect { through_link.update_attachment(attachment, status: 'failed') }.to raise_error(ledger_class::Unsettled)
  ensure
    File.unlink(link) if link && File.symlink?(link)
  end

  it 'leaves version 1 and its backup when the new version cannot be written or put in place' do
    [
      -> { allow(disk).to(receive(:create_exclusive).and_wrap_original { |m, p, b| p.end_with?('.tmp') ? raise(Errno::ENOSPC) : m.call(p, b) }) },
      -> { allow(disk).to receive(:replace).and_raise(Errno::EIO) }
    ].each do |fault|
      RSpec::Mocks.space.proxy_for(disk).reset
      FileUtils.rm_f(Dir.glob(File.join(@dir, '*')))
      bytes = write_v1
      fault.call
      expect { change! }.to raise_error(SystemCallError)
      expect(File.binread(path)).to eq(bytes)
      expect(backups).to eq(['ledger.json.v1.bak'])
      expect(Dir.children(@dir).grep(/\.tmp\z/)).to be_empty
    end
  end

  it 'stops writing that ledger, from any Ledger object, when the replacement cannot be settled' do
    write_v1
    calls = 0
    allow(disk).to(receive(:sync_dir).and_wrap_original { |m, d| (calls += 1) == 2 ? raise(Errno::EIO) : m.call(d) })
    expect { change! }.to raise_error(ledger_class::Unsettled)
    expect(on_disk['schema_version']).to eq(2)

    expect { change! }.to raise_error(ledger_class::Unsettled)
    expect { ledger_class.new(path).update_attachment(attachment, status: 'failed') }.to raise_error(ledger_class::Unsettled)
    expect(ledger.attachment(attachment)[:status]).to eq('failed')
  end

  it 'stops writing after an unsettled change of a version 2 ledger too' do
    write_v1
    change!
    allow(disk).to receive(:sync_dir).and_raise(Errno::EIO)
    expect { change! }.to raise_error(ledger_class::Unsettled)
  end

  it 'makes a new ledger in version 2 without a backup, and counts an existing empty one as version 1' do
    ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'Chat', relative_dir: "conversations/#{workspace}")
    expect(on_disk['schema_version']).to eq(2)
    expect(backups).to be_empty

    FileUtils.rm_f(Dir.glob(File.join(@dir, '*')))
    File.binwrite(path, '{}')
    ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'Chat', relative_dir: "conversations/#{workspace}")
    expect(File.binread(File.join(@dir, 'ledger.json.v1.bak'))).to eq('{}')
  end

  it 'keeps what reconcile finds at start in the backup as it was, and saves the change in version 2' do
    bytes = write_v1(status: 'validating')
    ledger.reconcile_interrupted!
    expect(File.binread(File.join(@dir, 'ledger.json.v1.bak'))).to eq(bytes)
    expect(on_disk['attachments'][attachment]['status']).to eq('failed')
  end

  it 'upgrades once when two Ledger objects make the first change' do
    threads = []
    write_v1
    other = ledger_class.new(path)
    threads.concat([ledger, other].map { |l| Thread.new { l.update_attachment(attachment, status: 'failed', 'failure' => 'X') } })
    expect(threads.map { |t| t.join(5) }).to all(be_truthy)
    expect(backups).to eq(['ledger.json.v1.bak'])
    expect(on_disk['schema_version']).to eq(2)
  ensure
    threads.each do |t|
      t.kill if t.alive?
      t.join(5)
    end
  end

  # The Ledger of beta.43 itself, in a process of its own: it refuses a
  # version 2 ledger for reading and for writing, and leaves it as it is.
  it 'is refused by the ledger of beta.43, which changes nothing' do
    root = File.expand_path('../../../../../..', __dir__)
    tag = 'v1.0.0-beta.43'
    files = %w[workspace/ledger.rb workspace/ids.rb utils/environment.rb]
    old = File.join(@dir, 'old', 'monadic')
    sources = files.map do |file|
      out, status = Open3.capture2('git', '-C', root, 'show', "#{tag}:docker/services/ruby/lib/monadic/#{file}")
      skip "#{tag} is not in this checkout" unless status.success?
      [file, out]
    end
    sources.each do |file, body|
      FileUtils.mkdir_p(File.dirname(File.join(old, file)))
      File.write(File.join(old, file), body)
    end
    write_v1
    change!
    bytes = File.binread(path)
    script = <<~RUBY
      require '#{File.join(old, 'workspace/ledger.rb')}'
      l = Monadic::Workspace::Ledger.new(ARGV[0])
      r = begin; l.schema_version; 'read'; rescue Monadic::Workspace::Ledger::Unreadable; 'refused'; end
      w = begin
        l.register_workspace(chat_id: Monadic::Workspace::Ids.generate(:chat), workspace_id: Monadic::Workspace::Ids.generate(:workspace),
                             app_name: 'Chat', relative_dir: 'conversations/old')
        'written'
      rescue Monadic::Workspace::Ledger::Unreadable
        'refused'
      end
      puts [r, w].join(' ')
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, '-e', script, path)
    expect(status).to be_success, err
    expect(out.strip).to eq('refused refused')
    expect(File.binread(path)).to eq(bytes)
  end
end
