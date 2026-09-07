require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# The payload that ships inside the desktop app used to be assembled by copying
# `docker/` and excluding dotfiles — a deny list, which shipped whatever
# happened to be sitting in the working tree. Releases beta.21 through beta.32
# carried benchmark logs, __pycache__ and rspec state that way, each naming
# absolute paths on the build machine.
#
# These examples pin the replacement: a file ships because it is tracked or
# because it was named as a build product, and the packaged archive is checked
# against that list rather than trusted.
RSpec.describe 'the app payload allow list' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }
  let(:stager) { File.join(root, 'scripts/stage_docker_payload.rb') }
  let(:verifier) { File.join(root, 'scripts/verify_bundle_payload.rb') }

  before do
    expect(File.exist?(stager)).to be(true), "stager not found at #{stager}"
    expect(File.exist?(verifier)).to be(true), "verifier not found at #{verifier}"
  end

  describe 'what the staging step decides to ship' do
    let(:source) { File.read(stager) }

    it 'takes tracked files as the base, not the working tree' do
      # Matched in two pieces so the assertion does not itself contain an
      # interpolation sequence, which reads as a mistake in a single-quoted
      # string.
      expect(source).to include('git -C ')
      expect(source).to include('ls-files -z')
    end

    it 'names every untracked file it allows' do
      # The generated files the app cannot run without. Anything else that is
      # untracked has to be added here deliberately, which is the whole point.
      expect(source).to include("'docker/services/ruby/public/vendor/**/*'")
      expect(source).to include("'docker/services/ruby/public/js/monadic.bundle.min.js'")
      expect(source).to include("'docker/services/ruby/help_data/help_db.json'")
    end

    it 'fails when a named build product is missing' do
      # Shipping without the vendor assets or the help database would produce
      # an app that starts and then cannot render or answer.
      expect(source).to include('required build product missing')
    end
  end

  describe 'what the build actually points at' do
    let(:package_json) { JSON.parse(File.read(File.join(root, 'package.json'))) }
    let(:extra) { package_json.dig('build', 'extraResources') }

    it 'copies from the staged payload' do
      froms = extra.map { |e| e['from'] }
      expect(froms).to include('./build/app-payload/docker', './build/app-payload/bin')
    end

    it 'no longer copies the working tree' do
      # This is the defect: `from: ./docker` with a filter that only removed
      # dotfiles.
      froms = extra.map { |e| e['from'] }
      expect(froms).not_to include('./docker')
      expect(froms).not_to include('./bin')
    end
  end

  describe 'the gate that reads what shipped' do
    let(:build_rake) { File.read(File.join(root, 'rakelib/build.rake')) }
    let(:release_rake) { File.read(File.join(root, 'rakelib/release.rake')) }

    it 'stages before packaging' do
      expect(build_rake).to include('sh "ruby scripts/stage_docker_payload.rb"')
    end

    it 'checks the archives after packaging' do
      expect(build_rake).to include('sh "ruby scripts/verify_bundle_payload.rb"')
    end

    it 'checks again before publishing, and stops on failure' do
      expect(release_rake).to include('system("ruby", "scripts/verify_bundle_payload.rb")')
      expect(release_rake).to include('packaged payload verification failed')
    end
  end

  describe 'the verifier applied to an archive' do
    # Builds a miniature archive shaped like the real one and runs the real
    # verifier over it, so the comparison itself is exercised rather than
    # described.
    def with_fixture(manifest_paths, archive_paths)
      Dir.mktmpdir('payload_spec') do |dir|
        build = File.join(dir, 'build')
        FileUtils.mkdir_p(build)
        File.write(File.join(build, 'app-payload.manifest'), manifest_paths.join("\n") + "\n")
        File.write(File.join(build, 'app-payload.symlinks'), '')

        src = File.join(dir, 'src')
        archive_paths.each do |p|
          full = File.join(src, 'Monadic Chat.app/Contents/Resources/app', p)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, 'x')
        end

        dist = File.join(dir, 'dist')
        FileUtils.mkdir_p(dist)
        zip = File.join(dist, 'Monadic.Chat-1.0.0-test-arm64.zip')
        system('zip', '-q', '-r', zip, 'Monadic Chat.app', chdir: src) or raise 'zip failed'

        yield dir, dist
      end
    end

    # The verifier reads the manifest from its own repo root, so point a copy
    # of the scripts at the fixture instead.
    def run_verifier(dir, dist)
      FileUtils.mkdir_p(File.join(dir, 'scripts'))
      FileUtils.cp(verifier, File.join(dir, 'scripts'))
      Open3.capture3('ruby', File.join(dir, 'scripts/verify_bundle_payload.rb'), dist)
    end

    it 'passes when the archive matches the manifest' do
      with_fixture(%w[docker/a.rb bin/b.sh], %w[docker/a.rb bin/b.sh]) do |dir, dist|
        stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).not_to include('FAILED'), stdout
        expect(status.exitstatus).to eq(0)
      end
    end

    it 'reports a file the manifest never named' do
      # The failure this whole change is about.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb docker/tmp/benchmark.log]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('not in the staged payload')
        expect(stderr).to include('docker/tmp/benchmark.log')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a staged file that never reached the archive' do
      with_fixture(%w[docker/a.rb docker/b.rb], %w[docker/a.rb]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('did not reach the archive')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'fails when there is no archive to read' do
      # A run that checked nothing must not report success.
      Dir.mktmpdir('payload_spec') do |dir|
        FileUtils.mkdir_p(File.join(dir, 'build'))
        File.write(File.join(dir, 'build/app-payload.manifest'), "docker/a.rb\n")
        empty = File.join(dir, 'dist')
        FileUtils.mkdir_p(empty)

        _stdout, stderr, status = run_verifier(dir, empty)

        expect(stderr).to include('no packaged archive found')
        expect(status.exitstatus).not_to eq(0)
      end
    end
  end
end
