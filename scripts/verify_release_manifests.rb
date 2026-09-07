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

require 'digest'
require 'pathname'
require 'yaml'
require 'json'

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

# The Electron the packaged app actually contains, read from the framework
# rather than inferred. Chromium versions and user-agent strings move with
# Electron but are not the same number: Electron 39 ships Chromium 142 and
# Electron 44 ships Chromium 152, so reading the browser version and mapping
# it back is how a release went out on Electron 39 while its build had been
# updated to 44.
def packaged_electron_version(app_dir)
  plist = app_dir.join('Contents/Frameworks/Electron Framework.framework/Resources/Info.plist')
  return nil unless plist.exist?

  out = `/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "#{plist}" 2>/dev/null`.strip
  out.empty? ? nil : out
end

# The version npm resolved for this checkout, which is what the build should
# have used. Compared against the framework above, not against the semver
# range in package.json.
def installed_electron_version(root)
  pkg = root.join('node_modules/electron/package.json')
  return nil unless pkg.exist?

  JSON.parse(pkg.read)['version']
end

mismatches = []

manifests.each do |yml|
  data = YAML.safe_load(yml.read, permitted_classes: [Time], aliases: false)
  files = Array(data['files'])

  # Every check below is per entry, so an empty list would assert nothing and
  # still exit 0 — a manifest the updater cannot download from.
  if files.empty?
    mismatches << { yml: yml.relative_path_from(dist).to_s, url: '(manifest)',
                    reason: 'no files entries', declared: '-', actual: '-' }
  end

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

    actual_sha = [Digest::SHA512.digest(artifact.read)].pack('m0')
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

# The macOS update floor. electron-updater reads this from the manifest and
# refuses the update on an older OS, and the check runs on the version the
# user already has — so a build that drops OS support must announce it here,
# not only in the new app's Info.plist.
# Read the expected floor from the script that writes it, so the value is
# stated once. Checking only the shape (three integers) would accept `13.0.0`
# — the macOS number written where the Darwin number belongs — and that
# compares as lower than a macOS 12 machine's `21.6.0`, which is the exact
# failure the floor exists to prevent.
patcher_source = Pathname.new(File.expand_path('patch_release_manifests.rb', __dir__)).read
expected_floor = patcher_source[/MAC_MINIMUM_DARWIN_VERSION\s*=\s*'([^']+)'/, 1]

if expected_floor.nil?
  mismatches << { yml: '(scripts)', url: 'patch_release_manifests.rb',
                  reason: 'could not read MAC_MINIMUM_DARWIN_VERSION',
                  declared: '-', actual: '-' }
end

mac_manifests = manifests.select { |m| m.basename.to_s.start_with?('latest-mac') }
mac_manifests.each do |yml|
  data = YAML.safe_load(yml.read, permitted_classes: [Time], aliases: false)
  next if expected_floor && data['minimumSystemVersion'].to_s == expected_floor

  mismatches << {
    yml: yml.relative_path_from(dist).to_s,
    url: '(manifest)',
    reason: 'minimumSystemVersion is not the Darwin version this release requires',
    declared: data['minimumSystemVersion'].inspect,
    actual: "expected #{expected_floor.inspect}"
  }
end

# The packaged Electron, compared against what npm resolved. A build config
# that pins an old version, or a stale node_modules, silently ships the wrong
# runtime; this is what let an Electron 39 build go out after the dependency
# had been raised to 44.
root = Pathname.new(File.expand_path('..', __dir__))
expected_electron = installed_electron_version(root)
app_dirs = dist.glob('mac*/*.app')

# The two conditions below are independent facts about the run: what npm
# resolved, and what the build produced. Reporting them in one if/elsif chain
# meant a missing node_modules hid a missing app, so a run could be told about
# one problem while silently not checking for the other.
if expected_electron.nil?
  mismatches << { yml: '(node_modules)', url: 'electron',
                  reason: 'electron is not installed; cannot verify what was packaged',
                  declared: '-', actual: '-' }
end

if app_dirs.empty?
  # Skipping used to leave a clean exit 0 on a run that checked no runtime at
  # all. When mac manifests are being published, the packaged app is the only
  # place the shipped Electron can be read from, so its absence is a failure.
  if mac_manifests.empty?
    puts "[verify_release_manifests] note: no packaged .app in #{dist} and no mac manifests; skipped the Electron check."
  else
    mismatches << { yml: '(dist)', url: 'mac*/*.app',
                    reason: 'mac manifests are present but no packaged app was found to read the Electron version from',
                    declared: expected_electron, actual: 'none' }
  end
elsif expected_electron
  app_dirs.each do |app|
    packaged = packaged_electron_version(app)
    rel = app.relative_path_from(dist).to_s

    if packaged.nil?
      mismatches << { yml: rel, url: 'Electron Framework',
                      reason: 'could not read the framework version',
                      declared: expected_electron, actual: '-' }
    elsif packaged != expected_electron
      mismatches << { yml: rel, url: 'Electron Framework',
                      reason: 'packaged Electron differs from the installed one',
                      declared: expected_electron, actual: packaged }
    end
  end
end

if mismatches.empty?
  puts "[verify_release_manifests] OK: #{manifests.size} manifests verified, all entries match."
  puts "[verify_release_manifests] Electron #{expected_electron} in #{app_dirs.size} packaged app(s); macOS floor declared in #{mac_manifests.size} manifest(s)."
  exit 0
end

warn '[verify_release_manifests] FAILED:'
mismatches.each do |m|
  warn "  #{m[:yml]} -> #{m[:url]}: #{m[:reason]}"
  warn "    declared: #{m[:declared]}" if m[:declared]
  warn "    actual:   #{m[:actual]}"   if m[:actual]
end
exit 1
