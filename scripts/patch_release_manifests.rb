#!/usr/bin/env ruby
# frozen_string_literal: true

# Sync every `dist/latest*.yml` entry's `sha512` and `size` to the bytes
# of the actually-shipped artifact on disk. Idempotent: entries that
# already match are left untouched.
#
# Why this exists (since 2026-05-12):
# electron-builder writes `latest-mac.yml` at some point during the
# macOS pipeline. `notarize-dmg.js` (afterAllArtifactBuild hook) is
# supposed to recompute the DMG entry after stapling, but empirically
# the yml does not contain the dmg entry at the moment that hook fires
# on certain electron-builder versions — the hook emits its
# "no entry matched" warning, the yml is then finalised by
# electron-builder with the pre-staple hash, and the manifest ships
# stale. Patching from outside electron-builder, after the npm
# subprocess has fully exited, sidesteps the timing race entirely.
#
# Usage:
#   ruby scripts/patch_release_manifests.rb
#   ruby scripts/patch_release_manifests.rb dist/
#
# Exit codes:
#   0 — all manifests now match shipped bytes (whether patched or not)
#   1 — a yml entry's expected pattern could not be located (unsafe to
#       silently leave a known-broken manifest)

require 'digest'
require 'pathname'
require 'yaml'

dist = Pathname.new(ARGV[0] || File.expand_path('../dist', __dir__))
unless dist.directory?
  warn "[patch_release_manifests] dist directory not found: #{dist}"
  exit 1
end

manifests = dist.glob('latest*.yml').sort
if manifests.empty?
  puts "[patch_release_manifests] No latest*.yml manifests in #{dist}; nothing to patch."
  exit 0
end

# Regex anchors on the YAML structure electron-builder emits:
#   - url: <name>
#     sha512: <base64>
#     size: <integer>
# Indentation is consistent (4 spaces after the dash line). We avoid a
# full YAML round-trip so quoting / key order / comments survive.
def patch_entry(content, url, sha512, size)
  pattern = /(- url: #{Regexp.escape(url)}\n\s+sha512: )[^\n]+(\n\s+size: )\d+/
  return nil unless content.match?(pattern)
  content.sub(pattern, "\\1#{sha512}\\2#{size}")
end

# The macOS floor, as electron-updater compares it. `checkIfUpdateSupported`
# reads `minimumSystemVersion` from the update manifest and compares it with
# `os.release()`, which reports the Darwin version — macOS 13 is Darwin 22.
# That is a different numbering from the app's own LSMinimumSystemVersion
# (`13.0`, set from build.mac.minimumSystemVersion), so the two are written
# separately and must not be copied from each other.
#
# electron-builder does not emit this field for the mac zip/dmg targets even
# though builder-util-runtime's UpdateInfo declares it, so it is added here.
# Without it, a machine running a macOS the new build no longer supports is
# offered the update by its own installed updater — the check runs on the OLD
# side, so shipping a corrected app is too late.
MAC_MINIMUM_DARWIN_VERSION = '22.0.0' # macOS 13 Ventura

# Returns [content, failure, change]. An existing value is corrected rather
# than trusted: a floor written in macOS numbering (`13.0`) instead of Darwin
# numbering compares as *lower* than a macOS 12 machine's `21.6.0`, so the
# guard reads as satisfied and the update goes out to the systems it was
# meant to stop. Leaving whatever is already there would ship that silently.
def ensure_minimum_system_version(content, basename)
  return [content, nil, nil] unless basename.start_with?('latest-mac')

  existing = content[/^minimumSystemVersion:[ \t]*(\S+)/, 1]

  if existing
    return [content, nil, nil] if existing == MAC_MINIMUM_DARWIN_VERSION

    patched = content.sub(/^minimumSystemVersion:.*\n/,
                          "minimumSystemVersion: #{MAC_MINIMUM_DARWIN_VERSION}\n")
    if patched == content
      return [content, "#{basename}: could not replace minimumSystemVersion #{existing}", nil]
    end

    return [patched, nil,
            "#{basename}: minimumSystemVersion corrected from #{existing} to " \
            "#{MAC_MINIMUM_DARWIN_VERSION} (Darwin; macOS 13)"]
  end

  # Place it next to `version:` so the file stays readable.
  patched = content.sub(/^(version:.*\n)/) do
    "#{Regexp.last_match(1)}minimumSystemVersion: #{MAC_MINIMUM_DARWIN_VERSION}\n"
  end
  return [content, "#{basename}: could not place minimumSystemVersion", nil] if patched == content

  [patched, nil,
   "#{basename}: minimumSystemVersion set to #{MAC_MINIMUM_DARWIN_VERSION} (Darwin; macOS 13)"]
end

changes = []
failures = []

manifests.each do |yml|
  content = yml.read
  begin
    data = YAML.safe_load(content, permitted_classes: [Time], aliases: false)
  rescue Psych::SyntaxError => e
    failures << "#{yml.basename}: cannot parse YAML (#{e.message})"
    next
  end

  Array(data['files']).each do |entry|
    url      = entry['url']
    artifact = dist.join(url)
    next unless artifact.exist?

    actual_sha  = [Digest::SHA512.digest(artifact.read)].pack('m0')
    actual_size = artifact.size

    next if entry['sha512'] == actual_sha && entry['size'] == actual_size

    patched = patch_entry(content, url, actual_sha, actual_size)
    if patched
      content = patched
      changes << "#{yml.basename}: #{url} → sha512+size synced to shipped bytes (size #{entry['size']} → #{actual_size})"
    else
      failures << "#{yml.basename}: pattern not found for #{url} (yml structure changed?)"
    end
  end

  content, mac_failure, mac_change = ensure_minimum_system_version(content, yml.basename.to_s)
  failures << mac_failure if mac_failure
  changes << mac_change if mac_change

  yml.write(content) if content != yml.read
end

if changes.empty? && failures.empty?
  puts "[patch_release_manifests] All manifests already in sync; nothing to patch."
elsif failures.empty?
  puts "[patch_release_manifests] Patched #{changes.size} entries:"
  changes.each { |c| puts "  #{c}" }
end

unless failures.empty?
  warn "[patch_release_manifests] FAILED:"
  failures.each { |f| warn "  #{f}" }
  exit 1
end
