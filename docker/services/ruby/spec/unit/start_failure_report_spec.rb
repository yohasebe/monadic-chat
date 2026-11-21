# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# What monadic.sh says when the server's container did not start, run as it
# is against the messages an engine gives.
RSpec.describe 'a start whose Ruby container did not start' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }

  def function(name)
    script[/^#{name}\(\) \{.*?^\}$/m] or raise "#{name} not found"
  end

  def report(messages)
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'up.txt')
      File.write(file, messages)
      out, status = Open3.capture2('bash', '-c', "#{function('report_ruby_not_started')}\nreport_ruby_not_started \"$1\"", 'bash', file)
      raise 'report failed' unless status.success?
      out
    end
  end

  it 'shows the last error the engine gave, as text' do
    out = report(<<~MESSAGES)
       Container monadic-chat-qdrant-container Started
       Container monadic-chat-ruby-container Error response from daemon: first <b>one</b>
      Error response from daemon: ports are not available: listen tcp4 127.0.0.1:3100: bind: address already in use
    MESSAGES
    expect(out).to include('The Ruby container did not start')
    expect(out).to include('<code>Error response from daemon: ports are not available: listen tcp4 127.0.0.1:3100: bind: address already in use</code>')
    expect(out).not_to include('<b>one</b>')
    expect(out).to include('press <b>Start</b> again')
  end

  it 'escapes markup in the reason' do
    expect(report("Error response from daemon: bad <script>x</script> & more\n"))
      .to include('<code>Error response from daemon: bad &lt;script&gt;x&lt;/script&gt; &amp; more</code>')
  end

  it 'says so without a reason when the engine gave none' do
    out = report(" Container monadic-chat-ruby-container Started\n")
    expect(out).to include('The Ruby container did not start')
    expect(out).not_to include('<code>')
  end

  it 'ends the start before the server is said to be started' do
    start = script[/^start_docker_compose\(\) \{.*?^\}$/m]
    check = start.index('if ! ruby_container_running; then')
    expect(check).not_to be_nil
    expect(start[check, 200]).to match(/report_ruby_not_started .*\n.*\n\s*return 1/)
    expect(script).to match(/^start\)\n\s*ensure_data_dir "" &&\n\s*start_docker_compose &&\n\s*echo "\[SERVER STARTED\]"/)
    expect(script).to match(/^restart\)\n.*\n.*\n\s*start_docker_compose &&\n\s*echo "\[SERVER STARTED\]"/)
  end
end
