# frozen_string_literal: true

require_relative '../spec_helper'
require 'yaml'

# The user's pysetup.sh and rbsetup.sh reach the image builds as build
# secrets. They must not be copied into a build context (a tracked file in a
# developer's checkout) or left in an image, where code the model runs in the
# container could read them.
RSpec.describe 'Setup scripts passed to the image builds as secrets' do
  docker_dir = File.expand_path('../../../..', __dir__)

  { 'python' => 'pysetup', 'ruby' => 'rbsetup' }.each do |service, name|
    describe "#{name}.sh in the #{service} image" do
      let(:dockerfile) { File.read(File.join(docker_dir, 'services', service, 'Dockerfile')) }
      let(:compose) { YAML.safe_load(File.read(File.join(docker_dir, 'services', service, 'compose.yml')), aliases: true) }

      it 'is run from a secret mount and never copied into the image' do
        expect(dockerfile).to include("--mount=type=secret,id=#{name},required=false")
        expect(dockerfile).not_to match(/^\s*(COPY|ADD)\b.*#{name}/)
        expect(dockerfile).to include("ARG #{name.upcase}_SHA=")
      end

      it 'is declared as a compose build secret read from the environment' do
        build = compose['services'].values.first['build']
        expect(build['secrets']).to include(name)
        expect(build['args']["#{name.upcase}_SHA"]).to include("MONADIC_#{name.upcase}_SHA")
        # compose may not read a secret file outside the build context
        expect(compose.dig('secrets', name)).to eq('environment' => "MONADIC_#{name.upcase}_CONTENT")
      end

      it 'has no placeholder file in the build context' do
        expect(File.exist?(File.join(docker_dir, 'services', service, "#{name}.sh"))).to be(false)
      end
    end
  end

  describe 'monadic.sh' do
    let(:script) { File.read(File.join(docker_dir, 'monadic.sh')) }

    it 'does not copy the setup scripts anywhere' do
      expect(script).not_to match(/cp\b[^\n]*(py|rb)setup\.sh/)
      expect(script).not_to match(/>\s*"\$\{ROOT_DIR\}[^"]*(py|rb)setup\.sh"/)
    end

    it 'passes each script to its docker build as a secret' do
      expect(script).to include('set_setup_script_build_flags pysetup')
      expect(script).to include('set_setup_script_build_flags rbsetup')
      expect(script).to include('--secret "id=$1,src=${!file_var}"')
    end

    it 'puts the contents in the environment only around each compose build' do
      exports = script.scan(/^\s*export_setup_script_contents$/).size
      unsets = script.scan(/^\s*unset_setup_script_contents$/).size
      expect(exports).to eq(3)
      expect(unsets).to eq(exports)
    end
  end

  describe 'check_environment' do
    it 'reads only the Dockerfile, not a setup script' do
      host = Class.new { include MonadicHelper }.new
      commands = []
      allow(host).to receive(:send_command) { |command:, **| commands << command; '' }
      host.check_environment
      expect(commands.join(' ')).not_to match(/setup\.sh/)
      expect(commands.join(' ')).to include('/monadic/Dockerfile')
    end
  end
end
