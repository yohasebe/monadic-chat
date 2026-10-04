require 'spec_helper'
require 'open3'
require 'tmpdir'

# deliver-secrets hands 1Password values to the Ruby container. A container
# built before that support existed would send op:// references to providers
# as keys, so it must be told apart from one that is simply not reachable.
# monadic.sh is run with a stand-in docker first on PATH that plays the three
# cases, so no Docker is needed.
RSpec.describe 'monadic.sh deliver-secrets' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }

  def deliver(mode)
    Dir.mktmpdir('deliver') do |dir|
      fake = File.join(dir, 'docker')
      File.write(fake, <<~SH)
        #!/bin/bash
        # "exec -i" is the write step; plain "exec" is the support check.
        if [ "$1" = exec ] && [ "$2" != -i ]; then
          case "#{mode}" in
            current) exit 0 ;;
            stale) exit 42 ;;
            missing) echo "Error response from daemon: No such container" >&2; exit 1 ;;
          esac
        fi
        cat > /dev/null
        exit 0
      SH
      File.chmod(0o755, fake)
      env = { 'PATH' => "#{dir}:#{ENV['PATH']}", 'MONADIC_RUBY_CONTAINER' => 'op-test' }
      Open3.capture3(env, 'bash', File.join(root, 'docker/monadic.sh'), 'deliver-secrets', stdin_data: '{}')
    end
  end

  it 'delivers to a container that has the support' do
    _out, _err, status = deliver('current')
    expect(status.exitstatus).to eq(0)
  end

  it 'exits 3 for a container built before the support, so the app asks for a rebuild' do
    _out, err, status = deliver('stale')
    expect(status.exitstatus).to eq(3)
    expect(err).to include('predates 1Password references')
  end

  it 'does not mistake an unreachable container for an old one' do
    _out, err, status = deliver('missing')
    expect(status.exitstatus).to eq(1)
    expect(err).to include('could not reach the Ruby container')
  end
end
