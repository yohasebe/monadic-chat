# frozen_string_literal: true

# The shared libraries electron-builder copies into the AppImage's usr/lib,
# pinned in config/linux/licenses/bundled-libraries.json together with the
# source release that has to accompany them. Used by
# verify_bundle_payload.rb; kept apart so the checks can be exercised alone.

require 'digest'
require 'json'
require 'rubygems/package'

module LinuxLibraries
  MANIFEST = 'config/linux/licenses/bundled-libraries.json'
  NOTICE = 'config/linux/licenses/THIRD-PARTY-LIBRARIES'
  EXTRA_MEMBERS = %w[SHA256SUMS THIRD-PARTY-LIBRARIES].freeze

  module_function

  def libraries(root)
    JSON.parse(File.read(File.join(root, MANIFEST))).fetch('libraries')
  end

  # {"libXss.so.1.0.0" => "<sha256>", ...} for one architecture ("x64" or "arm64").
  def library_hashes(libraries, arch)
    libraries.flat_map { |l| l.fetch('files').map { |name, sums| [name, sums.fetch(arch)] } }.to_h
  end

  # {"libxss/libxss_1.2.2-1.dsc" => "<sha256>", ...}: the members of the source release.
  def source_members(libraries)
    libraries.flat_map do |l|
      l.fetch('source_files').map { |f| ["#{l.fetch('source_package')}/#{File.basename(f.fetch('path'))}", f.fetch('sha256')] }
    end.to_h
  end

  def sha256sums(members)
    members.sort.map { |name, sha| "#{sha}  #{name}\n" }.join
  end

  # Problems with a source release tar: it must hold exactly the pinned
  # files, a SHA256SUMS that agrees with them, and the notice as committed.
  def source_problems(tar_path, libraries, notice)
    entries = {}
    File.open(tar_path, 'rb') do |io|
      Gem::Package::TarReader.new(io).each { |e| entries[e.full_name] = e.read.to_s if e.file? }
    end
    expected = source_members(libraries)
    problems = []
    (expected.keys - entries.keys).each { |n| problems << "source release lacks #{n}" }
    (entries.keys - expected.keys - EXTRA_MEMBERS).each { |n| problems << "source release holds #{n}, which is not pinned" }
    (expected.keys & entries.keys).each do |n|
      problems << "source release #{n} differs from its pinned SHA-256" unless Digest::SHA256.hexdigest(entries[n]) == expected[n]
    end
    problems << 'source release SHA256SUMS does not match the pinned files' unless entries['SHA256SUMS'] == sha256sums(expected)
    problems << 'source release THIRD-PARTY-LIBRARIES differs from the committed notice' unless entries['THIRD-PARTY-LIBRARIES'] == notice
    problems
  end
end
