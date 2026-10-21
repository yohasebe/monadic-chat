# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'timeout'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/shell'

# One server writes the state folder. A second one does not start, and a mark
# left behind is followed by a new one only when its server is known to have
# stopped. A server acting on what it saw earlier never takes the folder from
# the server that holds it.
RSpec.describe Monadic::Workspace::ServerOwner do
  around do |example|
    Dir.mktmpdir('server-owner') do |dir|
      @state = dir
      example.run
    end
  end

  after { described_class.reset! }

  def owner(mode: 'container', host_id: 'c1', pid: 100, alive: [], running: nil, instance: nil)
    described_class.new(state_path: @state, mode: mode, host_id: host_id, pid: pid, instance: instance,
                        pid_alive: ->(id) { alive.include?(id) }, container_running: -> { running })
  end

  def refused?(server)
    server.acquire!
    false
  rescue described_class::Refused
    true
  end

  def marks
    Dir.children(File.join(@state, 'server.owner')).sort
  end

  def write_mark(number, data)
    dir = File.join(@state, 'server.owner', "g#{number}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'owner.json'), data.is_a?(String) ? data : JSON.generate(data))
  end

  def valid_mark(**over)
    { 'owner_id' => 'ab' * 8, 'mode' => 'host', 'host_id' => 'mac', 'pid' => 200, 'instance' => nil }
      .merge(over.transform_keys(&:to_s))
  end

  it 'lets one server hold the folder, and the next follow once the first has stopped' do
    first = owner(pid: 100).acquire!
    expect(refused?(owner(pid: 101, alive: [100]))).to be(true)
    expect { first.check_held! }.not_to raise_error

    first.release!
    expect { first.check_held! }.to raise_error(described_class::Refused)
    second = owner(pid: 101, alive: [100]).acquire!
    expect(second.generation).to eq(2)
    expect(marks).to eq(['g2'])
    expect(Dir.children(@state)).to eq(['server.owner'])
  end

  it 'follows a mark only from a server known to have stopped' do
    restart1 = "#{'0' * 36}:1"
    restart2 = "#{'0' * 36}:2"
    cases = [
      # [mark left by, seen by, followed?]
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'container', host_id: 'c2', alive: [100] }, true],
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'container', host_id: 'c1', alive: [] }, true],
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'container', host_id: 'c1', alive: [100] }, false],
      # A restarted container keeps its name and may give its server the same process id.
      [{ mode: 'container', host_id: 'c1', pid: 7, instance: restart1 },
       { mode: 'container', host_id: 'c1', alive: [7], instance: restart2 }, true],
      [{ mode: 'container', host_id: 'c1', pid: 7, instance: restart1 },
       { mode: 'container', host_id: 'c1', alive: [7], instance: restart1 }, false],
      [{ mode: 'container', host_id: 'c1', pid: 999 }, { mode: 'container', host_id: 'c1', alive: [999] }, true],
      [{ mode: 'host', host_id: 'mac', pid: 200 }, { mode: 'host', host_id: 'mac', alive: [] }, true],
      [{ mode: 'host', host_id: 'mac', pid: 999 }, { mode: 'host', host_id: 'mac', alive: [999] }, true],
      [{ mode: 'host', host_id: 'mac', pid: 200 }, { mode: 'host', host_id: 'mac', alive: [200] }, false],
      [{ mode: 'host', host_id: 'mac', pid: 200 }, { mode: 'host', host_id: 'other', alive: [] }, false],
      # From the host, only docker saying the container has stopped counts.
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'host', host_id: 'mac', running: false }, true],
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'host', host_id: 'mac', running: true }, false],
      [{ mode: 'container', host_id: 'c1', pid: 100 }, { mode: 'host', host_id: 'mac', running: nil }, false],
      [{ mode: 'host', host_id: 'mac', pid: 200 }, { mode: 'container', host_id: 'c1', alive: [] }, false]
    ]
    cases.each do |left, seen, followed|
      FileUtils.rm_rf(File.join(@state, 'server.owner'))
      owner(**left).acquire!
      expect(refused?(owner(pid: 999, **seen))).to eq(!followed), "#{left} seen by #{seen}"
    end
  end

  it 'tells a server in the container how to go on when a server from the host left the mark' do
    owner(mode: 'host', host_id: 'mac', pid: 200).acquire!
    expect { owner(mode: 'container').acquire! }
      .to raise_error(described_class::Refused, /run from the host.*server\.owner/)
  end

  it 'takes no mark that is not whole and well formed as a stopped server' do
    bad = ['{', valid_mark.except('pid'), valid_mark(pid: '200'), valid_mark(pid: 0),
           valid_mark(owner_id: 'x'), valid_mark(mode: 'vm'), valid_mark(host_id: ''),
           valid_mark(instance: 'boot:'), [1, 2]]
    bad.each do |data|
      FileUtils.rm_rf(File.join(@state, 'server.owner'))
      write_mark(1, data)
      expect(refused?(owner(mode: 'host', host_id: 'mac', pid: 300))).to be(true), data.inspect
    end
    FileUtils.rm_rf(File.join(@state, 'server.owner'))
    write_mark(1, valid_mark)
    expect(refused?(owner(mode: 'host', host_id: 'mac', pid: 300))).to be(false)
  end

  it 'never lets a server acting on an earlier look take the folder from the one that holds it' do
    host = { mode: 'host', host_id: 'mac' }
    stale = owner(**host, pid: 100).acquire!
    stale_record = stale.send(:read, 1)
    # The late server has looked at generation 1 and judged its server
    # stopped; before it goes on, another server follows that generation.
    late = owner(**host, pid: 400, alive: [300])
    looked = false
    allow(late).to(receive(:generations).and_wrap_original { |m| looked ? m.call : (looked = true) && [1] })
    allow(late).to(receive(:read).and_wrap_original { |m, n| n == 1 ? stale_record : m.call(n) })
    holder = owner(**host, pid: 300, alive: [400]).acquire!
    expect(holder.generation).to eq(2)

    expect(late).to receive(:place).with(2).and_call_original
    expect(refused?(late)).to be(true)
    expect { holder.check_held! }.not_to raise_error
    expect(marks).to eq(['g2'])

    # A server that makes a number the holder has cleared already (below its
    # own) finds the higher one and gives way.
    later = owner(**host, pid: 600, alive: [300])
    calls = 0
    allow(later).to(receive(:generations).and_wrap_original { |m| (calls += 1) == 1 ? [] : m.call })
    expect(later).to receive(:place).with(1).and_call_original
    expect(refused?(later)).to be(true)
    expect(marks).to eq(['g2'])
    expect { holder.check_held! }.not_to raise_error
  end

  it 'sees a generation in place whichever error the system gives for it (ENOTEMPTY on macOS, also EEXIST on Linux)' do
    owner(pid: 100).acquire!
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(a_string_including('draft-'), File.join(@state, 'server.owner', 'g2'))
                                   .and_raise(Errno::EEXIST)
    expect(refused?(owner(pid: 101, alive: []))).to be(true)
    expect(marks).to eq(['g1'])
  end

  it 'asks docker whether the Ruby container runs, and counts only a clear answer' do
    ok = instance_double(Process::Status, success?: true)
    failed = instance_double(Process::Status, success?: false)
    answers = { ["true\n", ok] => true, ["false\n", ok] => false, ['', failed] => nil, ["maybe\n", ok] => nil }
    answers.each do |(out, status), expected|
      allow(Monadic::Shell).to receive(:capture).and_return([out, '', status])
      expect(described_class.ruby_container_running?).to eq(expected)
    end
    [Errno::ENOENT, Errno::EACCES, Monadic::Shell::TimedOut].each do |error|
      allow(Monadic::Shell).to receive(:capture).and_raise(error)
      expect(described_class.ruby_container_running?).to be_nil
    end
  end

  it 'reads the start of the container where it runs, and nothing elsewhere' do
    expect(described_class.container_instance).to be_nil.or match(/\A[0-9a-f-]{36}:\d+\z/)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/proc/sys/kernel/random/boot_id').and_return("#{'1' * 36}\n")
    allow(File).to receive(:read).with('/proc/1/stat')
                                 .and_return('1 (my (odd) name) S 0 1 1 0 -1 4194560 1 2 3 4 5 6 7 8 20 0 1 0 4242 1 2')
    expect(described_class.container_instance).to eq("#{'1' * 36}:4242")
    allow(File).to receive(:read).with('/proc/1/stat').and_return('1 (short) S 0')
    expect(described_class.container_instance).to be_nil
  end

  it 'stops the whole server only when its parent is Falcon' do
    allow(Process).to receive(:kill)
    allow(described_class).to receive(:falcon_process?).and_return(false)
    described_class.stop_server!
    expect(Process).not_to have_received(:kill)
    allow(described_class).to receive(:falcon_process?).and_return(true)
    described_class.stop_server!
    expect(Process).to have_received(:kill).with('TERM', Process.ppid)
  end

  it 'is taken by the server only (config.ru), before the ledger is touched or requests are served' do
    root = File.expand_path('../../..', __dir__)
    config = File.read(File.join(root, 'config.ru'))
    take = config.index('ServerOwner.acquire!')
    expect(take).not_to be_nil
    expect(take).to be < config.index('reconcile_interrupted!')
    expect(take).to be < config.index('use MCPServerStarter')
    expect(File.read(File.join(root, 'lib/monadic.rb'))).not_to include('ServerOwner.acquire!')
  end

  describe 'the ledger' do
    let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
    let(:chat) { Monadic::Workspace::Ids.generate(:chat) }

    def register(id = Monadic::Workspace::Ids.generate(:workspace))
      ledger.register_workspace(chat_id: chat, workspace_id: id, app_name: 'Chat', relative_dir: "conversations/#{id}")
    end

    it 'is written by the server that holds the folder, and not once it has stopped or another has followed' do
      held = described_class.acquire!(state_path: @state, mode: 'container', host_id: 'c1', pid: 100,
                                      instance: nil, pid_alive: ->(_) { false }, container_running: -> { nil })
      expect { register }.not_to raise_error

      held.release!
      expect { register }.to raise_error(described_class::Refused, /stopping/)
      owner(host_id: 'c2', pid: 101).acquire!
      expect { register }.to raise_error(described_class::Refused)
    end

    it 'is not written by a server whose generation another has followed' do
      described_class.acquire!(state_path: @state, mode: 'container', host_id: 'c1', pid: 100,
                               instance: nil, pid_alive: ->(_) { true }, container_running: -> { nil })
      write_mark(2, valid_mark(mode: 'container', host_id: 'c9', pid: 300))
      expect { register }.to raise_error(described_class::Refused, /another server has taken it/)
    end

    it 'lets a change under way finish before the server notes that it has stopped, and starts none after' do
      held = described_class.acquire!(state_path: @state, mode: 'host', host_id: 'mac', pid: 100,
                                      instance: nil, pid_alive: ->(_) { true }, container_running: -> { nil })
      inside = Queue.new
      go_on = Queue.new
      writer = Thread.new do
        Thread.current.report_on_exception = false
        ledger.send(:write) do |data|
          inside << true
          go_on.pop
          data['chats']['written'] = true
        end
      end
      Timeout.timeout(5) { inside.pop }
      releasing = Thread.new { held.release! }
      sleep 0.05
      expect(releasing).to be_alive
      # The next server sees no note yet and the process alive: it does not follow.
      expect(refused?(owner(mode: 'host', host_id: 'mac', pid: 200, alive: [100]))).to be(true)

      go_on << true
      expect(writer.join(2)).to be_truthy
      expect(releasing.join(2)).to be_truthy
      expect(JSON.parse(File.read(File.join(@state, 'ledger.json')))['chats']['written']).to be(true)
      expect { Timeout.timeout(2) { register } }.to raise_error(described_class::Refused, /stopping/)
      expect(refused?(owner(mode: 'host', host_id: 'mac', pid: 200, alive: [100]))).to be(false)
    end

    it 'notes nothing when a change under way does not finish in time' do
      held = described_class.acquire!(state_path: @state, mode: 'host', host_id: 'mac', pid: 100,
                                      instance: nil, pid_alive: ->(_) { true }, container_running: -> { nil })
      inside = Queue.new
      go_on = Queue.new
      writer = Thread.new { ledger.send(:write) { |_| inside << true; go_on.pop } }
      Timeout.timeout(5) { inside.pop }
      held.release!(wait: 0.05)
      expect(Dir.children(File.join(@state, 'server.owner', 'g1'))).to eq(['owner.json'])
      expect(refused?(owner(mode: 'host', host_id: 'mac', pid: 200, alive: [100]))).to be(true)
    ensure
      go_on << true
      writer&.join(2)
    end

    it 'is written as before where no server took the folder (programs and tests)' do
      expect(described_class.current).to be_nil
      expect { register }.not_to raise_error
    end
  end
end
