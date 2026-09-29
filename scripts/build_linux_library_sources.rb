#!/usr/bin/env ruby
# frozen_string_literal: true

# Assembles the corresponding source of the shared libraries the AppImage
# carries in usr/lib, as dist/monadic-chat_<version>_linux-library-sources.tar.
#
# electron-builder's AppImage tooling copies six libraries from Ubuntu 18.04
# packages into every AppImage. Two of them are GPL-3 and two LGPL, so each
# release that ships them also ships their source. The source packages are
# named, with their SHA-256, in config/linux/licenses/bundled-libraries.json;
# this fetches them from the Ubuntu archive, refuses any file whose hash
# differs, and packs them with a SHA256SUMS file and the notice that the
# AppImage carries. verify_bundle_payload.rb checks the result before release.

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'pathname'
require 'rubygems/package'
require 'stringio'
require_relative 'linux_libraries'

ROOT = Pathname.new(File.expand_path('..', __dir__))
MANIFEST = ROOT.join('config/linux/licenses/bundled-libraries.json')
NOTICE = ROOT.join('config/linux/licenses/THIRD-PARTY-LIBRARIES')
CACHE = ROOT.join('build/linux-library-sources')
DIST = Pathname.new(ARGV[0] || ROOT.join('dist'))

# Ubuntu 18.04 moves to old-releases at some point; the files do not change.
MIRRORS = %w[
  http://archive.ubuntu.com/ubuntu/
  http://old-releases.ubuntu.com/ubuntu/
].freeze

# Fixed so that the same sources always produce the same tar.
EPOCH = 1_700_000_000

def fetch(url, limit = 5)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: 15, read_timeout: 120, write_timeout: 30) do |http|
    req = Net::HTTP::Get.new(uri)
    # Net::HTTP asks for gzip and inflates it by default, which would hand
    # back something other than the .gz file the hash names.
    req['Accept-Encoding'] = 'identity'
    http.request(req)
  end
  case res
  when Net::HTTPSuccess then res.body
  when Net::HTTPRedirection
    raise "too many redirects: #{url}" if limit.zero?

    fetch(URI.join(url, res['location']).to_s, limit - 1)
  end
end

def source_file(entry)
  cached = CACHE.join(File.basename(entry['path']))
  if cached.file? && Digest::SHA256.file(cached).hexdigest == entry['sha256']
    return cached.binread
  end

  MIRRORS.each do |mirror|
    body = fetch(mirror + entry['path'])
    next unless body

    got = Digest::SHA256.hexdigest(body)
    unless got == entry['sha256']
      abort "[build_linux_library_sources] #{entry['path']} from #{mirror} has SHA-256 #{got}, " \
            "expected #{entry['sha256']}; not packing it."
    end
    FileUtils.mkdir_p(CACHE)
    cached.binwrite(body)
    return body
  end
  abort "[build_linux_library_sources] could not download #{entry['path']} from any mirror."
end

version = JSON.parse(ROOT.join('package.json').read).fetch('version')
libraries = JSON.parse(MANIFEST.read).fetch('libraries')
abort '[build_linux_library_sources] the manifest lists no libraries.' if libraries.empty?

files = {}
libraries.each do |lib|
  lib.fetch('source_files').each do |entry|
    files["#{lib.fetch('source_package')}/#{File.basename(entry['path'])}"] = source_file(entry)
  end
end
files['SHA256SUMS'] = LinuxLibraries.sha256sums(files.transform_values { |body| Digest::SHA256.hexdigest(body) })
files['THIRD-PARTY-LIBRARIES'] = NOTICE.binread

out = DIST.join("monadic-chat_#{version}_linux-library-sources.tar")
FileUtils.mkdir_p(DIST)
ENV['SOURCE_DATE_EPOCH'] = EPOCH.to_s
io = StringIO.new(+'', 'wb')
Gem::Package::TarWriter.new(io) do |tar|
  files.sort.each do |name, body|
    tar.add_file_simple(name, 0o644, body.bytesize) { |f| f.write(body) }
  end
end
out.binwrite(io.string)
puts "[build_linux_library_sources] #{files.size - 2} source files -> #{out.relative_path_from(ROOT)} (#{out.size} bytes)"
