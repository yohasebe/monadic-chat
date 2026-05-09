#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify that every dist/latest*.yml manifest's `sha512` and `size`
# match the actual on-disk artifact bytes. Fails fast with a non-zero
# exit code if any mismatch is found, so release scripts can stop the
# pipeline before publishing a broken auto-update channel.
#
# Why this exists: electron-builder's macOS pipeline writes the manifest
# BEFORE `notarize-dmg.js` staples the DMG, so the manifest's DMG entry
# can drift from the actually-shipped bytes. `notarize-dmg.js` now
# regenerates those entries post-staple (since 2026-05-09), but this
# verifier exists as a defense-in-depth check so a future regression
# (e.g. a build path that bypasses the hook) cannot silently ship a
# broken release.
#
# Usage:
#   ruby scripts/verify_release_manifests.rb
#   ruby scripts/verify_release_manifests.rb dist/  # custom dist dir
#
# Exit codes:
#   0  all manifests match their referenced artifacts
#   1  one or more mismatches found (or no manifests at all)

require 'base64'
require 'digest'
require 'pathname'
require 'yaml'

dist = Pathname.new(ARGV[0] || File.expand_path('../dist', __dir__))
unless dist.directory?
  warn "[verify_release_manifests] dist directory not found: #{dist}"
  exit 1
end

manifests = dist.glob('latest*.yml').sort
if manifests.empty?
  warn "[verify_release_manifests] No latest*.yml manifests in #{dist}; nothing to verify."
  exit 1
end

mismatches = []

manifests.each do |yml|
  data = YAML.safe_load(yml.read, permitted_classes: [Time], aliases: false)
  files = Array(data['files'])

  files.each do |entry|
    url        = entry['url']
    declared   = entry['sha512']
    decl_size  = entry['size']
    artifact   = dist.join(url)
    rel_yml    = yml.relative_path_from(dist)

    unless artifact.exist?
      mismatches << { yml: rel_yml.to_s, url: url, reason: 'artifact missing' }
      next
    end

    actual_sha = Base64.strict_encode64(Digest::SHA512.digest(artifact.read))
    actual_size = artifact.size

    if actual_sha != declared
      mismatches << {
        yml: rel_yml.to_s,
        url: url,
        reason: 'sha512 mismatch',
        declared: declared,
        actual: actual_sha
      }
    end
    if actual_size != decl_size
      mismatches << {
        yml: rel_yml.to_s,
        url: url,
        reason: 'size mismatch',
        declared: decl_size,
        actual: actual_size
      }
    end
  end
end

if mismatches.empty?
  puts "[verify_release_manifests] OK: #{manifests.size} manifests verified, all entries match."
  exit 0
end

warn '[verify_release_manifests] FAILED:'
mismatches.each do |m|
  warn "  #{m[:yml]} -> #{m[:url]}: #{m[:reason]}"
  warn "    declared: #{m[:declared]}" if m[:declared]
  warn "    actual:   #{m[:actual]}"   if m[:actual]
end
exit 1
