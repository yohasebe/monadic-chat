# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../support/test_run_dir'

# tmp/test_results grows by one directory per rspec invocation. Without a
# retention policy it reached 1,269 runs / 261 MB. prune_old_runs! keeps the
# newest N, but because it deletes directories its guard rails are the part
# that matters: only timestamp-shaped entries, never symlinks, never the
# current run, and never an exception that would take down a test run.
RSpec.describe Monadic::TestRunDir, '.prune_old_runs!' do
  # around only manages the tmpdir; stubbing must happen in before, which runs
  # inside example.run (rspec-mocks is not available in an around hook).
  around do |example|
    Dir.mktmpdir do |tmp|
      @root = File.join(tmp, 'tmp', 'test_results')
      FileUtils.mkdir_p(@root)
      example.run
    end
  end

  before do
    allow(described_class).to receive(:results_root).and_return(@root)
  end

  def make_runs(*names)
    names.each { |n| FileUtils.mkdir_p(File.join(@root, n)) }
  end

  def entries
    Dir.children(@root).sort
  end

  it 'keeps the newest N runs and deletes the rest' do
    make_runs('20260101_000001', '20260102_000001', '20260103_000001', '20260104_000001')

    removed = described_class.prune_old_runs!(keep: 2)

    expect(entries).to eq(['20260103_000001', '20260104_000001'])
    expect(removed).to contain_exactly('20260101_000001', '20260102_000001')
  end

  it 'never deletes the run passed as protect, even when it is old' do
    make_runs('20260101_000001', '20260102_000001', '20260103_000001')

    described_class.prune_old_runs!(keep: 1, protect: File.join(@root, '20260101_000001'))

    expect(entries).to include('20260101_000001')
  end

  it 'leaves entries that are not timestamp-shaped alone' do
    make_runs('20260101_000001', '20260102_000001')
    FileUtils.mkdir_p(File.join(@root, 'keep-my-notes'))
    File.write(File.join(@root, 'README.md'), 'notes')

    described_class.prune_old_runs!(keep: 1)

    expect(entries).to include('keep-my-notes', 'README.md')
  end

  it 'never deletes or follows the latest symlink' do
    make_runs('20260101_000001', '20260102_000001', '20260103_000001')
    File.symlink('20260101_000001', File.join(@root, 'latest'))

    described_class.prune_old_runs!(keep: 1)

    expect(File.symlink?(File.join(@root, 'latest'))).to be true
    # The symlink itself is not timestamp-shaped, so it survives even though
    # its target was pruned; the target going away is expected.
    expect(entries).to include('latest', '20260103_000001')
  end

  it 'does nothing when keep is zero or negative (opt-out)' do
    make_runs('20260101_000001', '20260102_000001')

    expect(described_class.prune_old_runs!(keep: 0)).to eq([])
    expect(described_class.prune_old_runs!(keep: -5)).to eq([])
    expect(entries.size).to eq(2)
  end

  it 'is a no-op when the results root does not exist' do
    FileUtils.rm_rf(@root)
    expect { described_class.prune_old_runs!(keep: 5) }.not_to raise_error
  end

  it 'warns instead of raising when deletion fails' do
    make_runs('20260101_000001', '20260102_000001')
    allow(FileUtils).to receive(:rm_rf).and_raise(Errno::EACCES)

    expect(described_class).to receive(:warn).with(/Failed to prune/)
    expect(described_class.prune_old_runs!(keep: 1)).to eq([])
  end

  describe '.configured_keep' do
    # Set the real env var and restore it, rather than stubbing ENV#[] (which
    # would break every other ENV lookup made during the example).
    def with_keep(value)
      previous = ENV['TEST_RESULTS_KEEP']
      had_key = ENV.key?('TEST_RESULTS_KEEP')
      value.nil? ? ENV.delete('TEST_RESULTS_KEEP') : ENV['TEST_RESULTS_KEEP'] = value
      yield
    ensure
      had_key ? ENV['TEST_RESULTS_KEEP'] = previous : ENV.delete('TEST_RESULTS_KEEP')
    end

    it 'defaults when TEST_RESULTS_KEEP is unset or blank' do
      with_keep(nil) { expect(described_class.configured_keep).to eq(described_class::DEFAULT_KEEP) }
      with_keep('  ') { expect(described_class.configured_keep).to eq(described_class::DEFAULT_KEEP) }
    end

    it 'honors a numeric override, including 0 to disable pruning' do
      with_keep('5') { expect(described_class.configured_keep).to eq(5) }
      with_keep('0') { expect(described_class.configured_keep).to eq(0) }
    end

    it 'falls back to the default on a non-numeric value rather than disabling pruning' do
      with_keep('lots') { expect(described_class.configured_keep).to eq(described_class::DEFAULT_KEEP) }
    end
  end
end
