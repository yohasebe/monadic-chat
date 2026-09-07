#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that the packaged archives carry exactly the payload that
# stage_docker_payload.rb assembled — no more, no less.
#
# Staging alone is not a guarantee: electron-builder could be pointed back at
# the working tree, a filter could be widened, or a stale staging directory
# could be packaged. This reads the archives that actually ship and compares
# them against the manifest the staging step wrote.
#
# An extra file is the failure this exists to catch: releases beta.21 through
# beta.32 carried benchmark logs, __pycache__ and rspec state, each naming
# absolute paths on the build machine.

require 'pathname'
require 'set'

ROOT = Pathname.new(File.expand_path('..', __dir__))
DIST = Pathname.new(ARGV[0] || ROOT.join('dist'))
MANIFEST = ROOT.join('build/app-payload.manifest')

unless MANIFEST.file?
  abort "[verify_bundle_payload] no manifest at #{MANIFEST.relative_path_from(ROOT)}; run stage_docker_payload.rb first."
end

expected = MANIFEST.read.split("\n").reject(&:empty?).to_set

# A symlink to a directory survives as a link in the mac zip but is copied out
# as its contents on Windows, which cannot store links. Both carry the same
# payload, so the dereferenced form is an accepted alternative: it widens what
# may appear without widening what must appear.
SYMLINK_LIST = ROOT.join('build/app-payload.symlinks')
symlinks = {}
if SYMLINK_LIST.file?
  SYMLINK_LIST.read.split("\n").reject(&:empty?).each do |line|
    link, target = line.split("\t", 2)
    next unless link && target

    symlinks[link] = Pathname.new(File.dirname(link)).join(target).cleanpath.to_s
  end
end

dereferenced = Set.new
symlinks.each do |link, resolved|
  expected.each do |e|
    dereferenced << e.sub(%r{\A#{Regexp.escape(resolved)}/}, "#{link}/") if e.start_with?("#{resolved}/")
  end
end
allowed = expected | dereferenced

# Archive -> the prefix under which the payload sits inside it.
def archives(dist)
  found = []
  dist.glob('Monadic*-arm64.zip').each { |z| found << [z, %r{\AMonadic Chat\.app/Contents/Resources/app/}] }
  dist.glob('Monadic.Chat.Setup.*.zip').each { |z| found << [z, %r{\Aresources/app/}] }
  found.sort_by { |z, _| z.basename.to_s }
end

def entries(zip)
  out = `unzip -Z1 "#{zip}" 2>/dev/null`
  abort "[verify_bundle_payload] could not read #{zip}" unless $?.success?

  out.split("\n")
end

targets = archives(DIST)
if targets.empty?
  abort "[verify_bundle_payload] no packaged archive found in #{DIST}; nothing was checked."
end

failures = []

targets.each do |zip, prefix|
  rel = zip.relative_path_from(DIST).to_s
  # Skip directory entries and the resource forks the mac zip carries.
  payload = entries(zip)
            .reject { |e| e.end_with?('/') }
            .reject { |e| e.start_with?('__MACOSX/') }
            .grep(prefix)
            .map { |e| e.sub(prefix, '') }
            .reject { |e| e.split('/').last.to_s.start_with?('._') }
            .select { |e| e.start_with?('docker/', 'bin/') }
            .to_set

  extra = (payload - allowed).to_a.sort
  # A symlink the archive stored as its contents instead is still present.
  satisfied = symlinks.keys.select { |link| payload.any? { |e| e.start_with?("#{link}/") } }.to_set
  missing = (expected - payload - satisfied).to_a.sort

  unless extra.empty?
    failures << "#{rel}: #{extra.size} file(s) not in the staged payload"
    extra.first(15).each { |e| failures << "    + #{e}" }
    failures << "    … and #{extra.size - 15} more" if extra.size > 15
  end

  unless missing.empty?
    failures << "#{rel}: #{missing.size} staged file(s) did not reach the archive"
    missing.first(10).each { |e| failures << "    - #{e}" }
  end

  puts "[verify_bundle_payload] #{rel}: #{payload.size} payload files" if extra.empty? && missing.empty?
end

if failures.empty?
  puts "[verify_bundle_payload] OK: #{targets.size} archive(s) match the staged payload (#{expected.size} files)."
  exit 0
end

warn '[verify_bundle_payload] FAILED:'
failures.each { |f| warn "  #{f}" }
exit 1
