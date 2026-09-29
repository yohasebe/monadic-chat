require 'spec_helper'
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rubygems/package'
require 'stringio'
require 'tmpdir'

# The AppImage carries six libraries from Ubuntu packages, two of them GPL-3
# and two LGPL. Each release therefore ships their notices inside the AppImage
# and their source beside it. These examples pin the pieces to one another:
# the manifest, the notices, the packaging settings, and the source release.
RSpec.describe 'the libraries bundled in the AppImage' do
  root = File.expand_path('../../../../../..', __dir__)
  require File.join(root, 'scripts/linux_libraries')

  let(:root) { root }
  let(:licenses) { File.join(root, 'config/linux/licenses') }
  let(:libraries) { LinuxLibraries.libraries(root) }
  let(:notice) { File.read(File.join(licenses, 'THIRD-PARTY-LIBRARIES')) }
  let(:extra_files) do
    JSON.parse(File.read(File.join(root, 'package.json'))).dig('build', 'linux', 'extraFiles')
  end

  describe 'the manifest and the notices' do
    it 'pins every library for both architectures that ship' do
      expect(libraries).not_to be_empty
      libraries.each do |lib|
        lib.fetch('files').each_value do |sums|
          expect(sums.keys).to contain_exactly('x64', 'arm64')
          expect(sums.values).to all(match(/\A\h{64}\z/))
        end
        expect(lib.fetch('source_files')).not_to be_empty
        expect(lib.fetch('source_files').map { |f| f['sha256'] }).to all(match(/\A\h{64}\z/))
      end
    end

    it 'has the copyright file of every package, and ships it' do
      libraries.each do |lib|
        pkg = lib.fetch('binary_package')
        expect(File.file?(File.join(licenses, 'copyright', pkg))).to be(true), pkg
        expect(extra_files).to include(
          'from' => "config/linux/licenses/copyright/#{pkg}", 'to' => "usr/share/doc/#{pkg}/copyright"
        )
      end
    end

    it 'ships the full text of every license the copyright files refer to' do
      referred = Dir[File.join(licenses, 'copyright', '*')].flat_map do |f|
        File.read(f).scan(%r{/usr/share/common-licenses/([A-Za-z0-9.\-]+[0-9])})
      end.flatten.uniq
      expect(referred).not_to be_empty
      referred.each do |name|
        expect(File.file?(File.join(licenses, 'common-licenses', name))).to be(true), name
        expect(extra_files).to include(
          'from' => "config/linux/licenses/common-licenses/#{name}", 'to' => "usr/share/common-licenses/#{name}"
        )
      end
    end

    it 'names every package, version and source in the notice, and ships the notice' do
      libraries.each do |lib|
        expect(notice).to include("#{lib['binary_package']} #{lib['version']}")
        expect(notice).to match(/^\s+#{Regexp.escape(lib['source_package'])}\s+#{Regexp.escape(lib['version'])}$/)
        lib.fetch('files').each_key { |so| expect(notice).to include(so) }
      end
      expect(extra_files).to include(
        'from' => 'config/linux/licenses/THIRD-PARTY-LIBRARIES', 'to' => 'usr/share/doc/monadic-chat/THIRD-PARTY-LIBRARIES'
      )
    end
  end

  describe 'checking a source release' do
    let(:fake_libraries) do
      [{ 'binary_package' => 'libfoo1', 'source_package' => 'foo',
         'files' => { 'libfoo.so.1' => { 'x64' => 'a' * 64, 'arm64' => 'b' * 64 } },
         'source_files' => [
           { 'path' => 'pool/main/f/foo/foo_1.0.orig.tar.gz', 'sha256' => Digest::SHA256.hexdigest('orig') },
           { 'path' => 'pool/main/f/foo/foo_1.0-1.dsc', 'sha256' => Digest::SHA256.hexdigest('dsc') }
         ] }]
    end
    let(:good_members) { { 'foo/foo_1.0.orig.tar.gz' => 'orig', 'foo/foo_1.0-1.dsc' => 'dsc' } }

    def write_tar(path, members)
      io = StringIO.new(+'', 'wb')
      Gem::Package::TarWriter.new(io) do |tar|
        members.each { |name, body| tar.add_file_simple(name, 0o644, body.bytesize) { |f| f.write(body) } }
      end
      File.binwrite(path, io.string)
    end

    def problems_for(members)
      Dir.mktmpdir('sources_spec') do |dir|
        path = File.join(dir, 'x_linux-library-sources.tar')
        write_tar(path, members)
        LinuxLibraries.source_problems(path, fake_libraries, 'NOTICE')
      end
    end

    def complete(members)
      sums = LinuxLibraries.sha256sums(members.transform_values { |b| Digest::SHA256.hexdigest(b) })
      members.merge('SHA256SUMS' => sums, 'THIRD-PARTY-LIBRARIES' => 'NOTICE')
    end

    it 'accepts the pinned files with matching sums and notice' do
      expect(problems_for(complete(good_members))).to eq([])
    end

    it 'reports a file whose contents differ from the pin' do
      members = complete(good_members).merge('foo/foo_1.0-1.dsc' => 'changed')
      expect(problems_for(members)).to include('source release foo/foo_1.0-1.dsc differs from its pinned SHA-256')
    end

    it 'reports a missing file' do
      members = complete(good_members).reject { |n, _| n == 'foo/foo_1.0-1.dsc' }
      expect(problems_for(members)).to include('source release lacks foo/foo_1.0-1.dsc')
    end

    it 'reports a file that is not pinned' do
      members = complete(good_members).merge('notes.txt' => 'x')
      expect(problems_for(members)).to include('source release holds notes.txt, which is not pinned')
    end

    it 'reports a notice that differs from the committed one' do
      members = complete(good_members).merge('THIRD-PARTY-LIBRARIES' => 'old notice')
      expect(problems_for(members)).to include('source release THIRD-PARTY-LIBRARIES differs from the committed notice')
    end
  end

  describe 'building the source release' do
    it 'packs the pinned files from its cache into a release the check accepts, the same bytes each time' do
      # The cache stands in for the Ubuntu archive, so nothing is downloaded.
      Dir.mktmpdir('build_sources_spec') do |dir|
        FileUtils.mkdir_p(File.join(dir, 'scripts'))
        %w[build_linux_library_sources.rb linux_libraries.rb].each do |f|
          FileUtils.cp(File.join(root, 'scripts', f), File.join(dir, 'scripts'))
        end
        FileUtils.mkdir_p(File.join(dir, 'config/linux/licenses'))
        File.write(File.join(dir, 'package.json'), '{"version":"9.9.9"}')
        File.write(File.join(dir, LinuxLibraries::NOTICE), 'NOTICE')
        bodies = { 'foo_1.0.orig.tar.gz' => 'orig', 'foo_1.0-1.dsc' => 'dsc' }
        libs = [{ 'binary_package' => 'libfoo1', 'source_package' => 'foo', 'files' => {},
                  'source_files' => bodies.map { |n, b| { 'path' => "pool/main/f/foo/#{n}", 'sha256' => Digest::SHA256.hexdigest(b) } } }]
        File.write(File.join(dir, LinuxLibraries::MANIFEST), JSON.generate('libraries' => libs))
        cache = File.join(dir, 'build/linux-library-sources')
        FileUtils.mkdir_p(cache)
        bodies.each { |n, b| File.write(File.join(cache, n), b) }

        outputs = 2.times.map do
          _out, err, status = Open3.capture3('ruby', File.join(dir, 'scripts/build_linux_library_sources.rb'))
          expect(status.exitstatus).to eq(0), err
          File.binread(File.join(dir, 'dist/monadic-chat_9.9.9_linux-library-sources.tar'))
        end
        expect(outputs.uniq.size).to eq(1)
        tar = File.join(dir, 'dist/monadic-chat_9.9.9_linux-library-sources.tar')
        expect(LinuxLibraries.source_problems(tar, libs, 'NOTICE')).to eq([])
      end
    end
  end
end
