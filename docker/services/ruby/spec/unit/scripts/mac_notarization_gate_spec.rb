require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# The notarize hooks skipped quietly when credentials were missing, so a build
# could succeed with a DMG that was never notarized. These examples pin the
# gate that now reads the packages themselves, and its wiring.
RSpec.describe 'the macOS notarization gate' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }
  let(:script) { File.join(root, 'scripts/verify_mac_notarization.rb') }
  let(:build_rake) { File.read(File.join(root, 'rakelib/build.rake')) }
  let(:release_rake) { File.read(File.join(root, 'rakelib/release.rake')) }

  it 'marks rake builds as release builds, so missing credentials stop them' do
    setup = build_rake[build_rake.index('def setup_build_environment')..]
    expect(setup[0, 600]).to include("ENV['MONADIC_RELEASE_BUILD'] = '1'")
    github = release_rake[release_rake.index('task :github')..]
    expect(github[0, 400]).to include("ENV['MONADIC_RELEASE_BUILD'] = '1'")
  end

  it 'runs after packaging and again before publishing' do
    expect(build_rake.scan('sh "ruby scripts/verify_mac_notarization.rb"').size).to eq(2)
    expect(release_rake).to include('system("ruby", "scripts/verify_mac_notarization.rb")')
    expect(release_rake).to include('macOS notarization verification failed; nothing was published')
  end

  it 'signs the DMG, which Gatekeeper judges by its own signature' do
    package = JSON.parse(File.read(File.join(root, 'package.json')))
    expect(package.dig('build', 'dmg', 'sign')).to be(true)
  end

  context 'on macOS', if: RUBY_PLATFORM.include?('darwin') do
    let(:version) { File.read(File.join(root, 'docker/services/ruby/lib/monadic/version.rb'))[/VERSION = "([^"]+)"/, 1] }

    # An unsigned DMG and a zip holding an unsigned .app, named like the
    # real packages: neither carries a ticket or a usable signature.
    def unsigned_packages(dist)
      Dir.mktmpdir('notarization_src') do |src|
        app = File.join(src, 'Monadic Chat.app', 'Contents', 'MacOS')
        FileUtils.mkdir_p(app)
        File.write(File.join(app, 'Monadic Chat'), "#!/bin/sh\n")
        system('hdiutil', 'create', '-quiet', '-fs', 'HFS+', '-srcfolder', src, '-volname', 'Test',
               File.join(dist, "Monadic.Chat-#{version}-arm64.dmg")) or raise 'hdiutil failed'
        system('ditto', '-c', '-k', '--keepParent', File.join(src, 'Monadic Chat.app'),
               File.join(dist, "Monadic.Chat-#{version}-arm64.zip")) or raise 'ditto failed'
      end
    end

    it 'fails on packages that are not notarized' do
      Dir.mktmpdir('notarization_dist') do |dist|
        unsigned_packages(dist)
        out, status = Open3.capture2e('ruby', script, dist)
        expect(status.exitstatus).to eq(1)
        expect(out).to include('FAIL', 'ticket stapled', 'do not publish')
      end
    end

    it 'fails when the packages are missing rather than checking nothing' do
      Dir.mktmpdir('notarization_dist') do |dist|
        out, status = Open3.capture2e('ruby', script, dist)
        expect(status.success?).to be(false)
        expect(out).to include("no Monadic.Chat-#{version}-arm64.dmg")
      end
    end
  end
end
