# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# How monadic.sh empties the logs when it builds, run as it is on files made
# for the test.
RSpec.describe 'emptying a log file' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }
  let(:functions) do
    %w[safe_rm safe_truncate].map { |name| script[/^#{name}\(\) \{.*?^\}$/m] or raise "#{name} not found" }.join("\n")
  end

  def truncate(path)
    _out, status = Open3.capture2('bash', '-c', "#{functions}\nsafe_truncate \"$1\"", 'bash', path)
    raise 'safe_truncate failed' unless status.success?
  end

  it 'empties the file in place, so a writer that keeps it open writes to the same file' do
    Dir.mktmpdir do |dir|
      log = File.join(dir, 'extra.log')
      File.write(log, "old lines\n")
      File.open(log, 'a') do |writer|
        writer.sync = true
        truncate(log)
        writer.write("new line\n")
      end
      expect(File.read(log)).to eq("new line\n")
    end
  end

  it 'removes a link instead of emptying what it points to, and leaves a missing file missing' do
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'kept.txt')
      File.write(target, "keep me\n")
      link = File.join(dir, 'extra.log')
      File.symlink(target, link)
      truncate(link)
      expect(File.exist?(link) || File.symlink?(link)).to be(false)
      expect(File.read(target)).to eq("keep me\n")

      missing = File.join(dir, 'jupyter.log')
      truncate(missing)
      expect(File.exist?(missing)).to be(false)
    end
  end
end
