# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/shared_tools/scratch_browser"
require_relative "../../../lib/monadic/adapters/selenium_helper"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_tools"
require_relative "../../../apps/drawio_grapher/drawio_grapher_tools"

# A diagram preview's browser session: its own, closed when it is done.
RSpec.describe MonadicSharedTools::ScratchBrowser do
  let(:owner) { MonadicSharedTools::BrowserOwner }
  let(:commands) { [] }
  # What Selenium reports, as web_navigator.py --action status prints it.
  let(:status) { { sessions: [], max: 3 } }
  let(:stop_reply) { '{"success": true}' }

  before do
    owner.reset!
    allow(owner).to receive(:observe) { status.dup }
    owner.runner = lambda do |args, _|
      commands << args
      next stop_reply if args.include?('stop')

      status[:sessions] += ['wd-job'] if args.include?('start')
      '{"success": true, "session_id": "wd-job"}'
    end
  end

  it 'runs the job on its own session and closes it' do
    described_class.with_session('file:///monadic/data/x.html') { |run, _| run.call(%w[--action full_screenshot]) }
    expect(commands.size).to eq(3)
    expect(commands[0]).to include('start', '--managed', 'file:///monadic/data/x.html')
    expect(commands[1]).to eq(%w[--action full_screenshot --managed --session-id wd-job])
    expect(commands[2]).to eq(%w[--action stop --managed --session-id wd-job])
  end

  it 'closes the session when the job raises' do
    expect { described_class.with_session('u') { raise 'boom' } }.to raise_error('boom')
    expect(commands.last).to include('stop')
  end

  it 'names its session, so it is not counted twice while it runs' do
    described_class.with_session('u') do
      expect(owner.snapshot[:job_sessions]).to eq(['wd-job'])
      owner.with_job { nil } # 1 job + its session, not 2
    end
  end

  context 'when the session does not close' do
    let(:stop_reply) { '{"success": false}' }

    it 'keeps its slot, through what Selenium reports, after the job' do
      described_class.with_session('u') { nil }
      expect(owner.snapshot[:jobs]).to eq(0)
      status[:sessions] += %w[chat-1 chat-2] # two more of Selenium's slots in use
      expect { owner.with_job { nil } }.to raise_error(MonadicSharedTools::BrowserOwner::Full)
    end
  end

  it 'refuses at once when every slot is taken' do
    owner.with_job do
      owner.with_job do
        owner.with_job do
          expect { described_class.with_session('u') { nil } }.to raise_error(MonadicSharedTools::BrowserOwner::Full)
        end
      end
    end
    expect(commands).to be_empty
  end
end

RSpec.describe "Diagram preview pages" do
  let(:shared) { Dir.mktmpdir }
  let(:tools) { Class.new.include(MermaidGrapherTools).new }

  before do
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
  end

  after { FileUtils.rm_rf(shared) }

  it "removes its own page and leaves another preview's page alone" do
    mine = File.join(shared, 'mermaid_live_1_aaaa.html')
    other = File.join(shared, 'mermaid_live_1_bbbb.html')
    [mine, other].each { |f| File.write(f, 'x') }
    tools.send(:remove_preview_page, File.basename(mine))
    tools.send(:cleanup_old_mermaid_files)
    expect(File.exist?(mine)).to be(false)
    expect(File.exist?(other)).to be(true)
  end

  it 'goes on when another preview removes its page while the old ones are swept' do
    gone = File.join(shared, 'mermaid_live_1_dddd.html')
    left = File.join(shared, 'mermaid_live_1_eeee.html')
    old = Time.now - MermaidGrapherTools::PREVIEW_IMAGE_MAX_AGE - 1
    [gone, left].each { |f| File.write(f, 'x'); File.utime(old, old, f) }
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(gone).and_raise(Errno::ENOENT)
    expect { tools.send(:cleanup_old_mermaid_files) }.not_to raise_error
    expect(File.exist?(left)).to be(false)
  end

  it 'removes pages that earlier runs left' do
    left = File.join(shared, 'mermaid_test_1_cccc.html')
    File.write(left, 'x')
    old = Time.now - MermaidGrapherTools::PREVIEW_IMAGE_MAX_AGE - 1
    File.utime(old, old, left)
    tools.send(:cleanup_old_mermaid_files)
    expect(File.exist?(left)).to be(false)
  end
end
