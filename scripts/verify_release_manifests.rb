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
require 'tempfile'
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
# Read a value out of a plist held inside the shipped zip. The unpacked
# `dist/mac-arm64/*.app` the build produced is deleted before this runs, and it
# was never the thing users receive: the zip is what the updater downloads and
# what the dmg is built from, so it is the archive to open.
def plist_value_from_zip(zip, inner_path, key)
  raw = `unzip -p "#{zip}" "#{inner_path}" 2>/dev/null`
  return nil if raw.empty?

  Tempfile.create(['plist', '.plist']) do |f|
    f.binmode
    f.write(raw)
    f.flush
    out = `/usr/libexec/PlistBuddy -c "Print :#{key}" "#{f.path}" 2>/dev/null`.strip
    return out.empty? ? nil : out
  end
end

APP_IN_ZIP = 'Monadic Chat.app'
FRAMEWORK_PLIST = "#{APP_IN_ZIP}/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist"
APP_PLIST = "#{APP_IN_ZIP}/Contents/Info.plist"

def shipped_electron_version(zip)
  plist_value_from_zip(zip, FRAMEWORK_PLIST, 'CFBundleVersion')
end

def shipped_minimum_system_version(zip)
  plist_value_from_zip(zip, APP_PLIST, 'LSMinimumSystemVersion')
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

  # The legacy top-level pair names the same artifact as the first files entry.
  # Current updaters ignore it while `files` is populated, but it ships in the
  # manifest, and a stale hash there is indistinguishable from a real mismatch
  # to anyone auditing the release.
  legacy_path = data['path']
  if legacy_path
    legacy_artifact = dist.join(legacy_path.to_s)
    if legacy_artifact.exist?
      actual = [Digest::SHA512.digest(legacy_artifact.read)].pack('m0')
      if data['sha512'].to_s != actual
        mismatches << { yml: yml.relative_path_from(dist).to_s, url: "#{legacy_path} (top level)",
                        reason: 'the legacy top-level sha512 does not match the artifact it names',
                        declared: data['sha512'].to_s[0, 16], actual: actual[0, 16] }
      end
    end
  end

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
# Every manifest must describe this release. sha512/size only prove a manifest
# matches *some* file that is present, and a dist directory keeps the previous
# release's artifacts, so a stale manifest left behind by a failed build points
# at real files with correct hashes and passes every check below.
version_rb = Pathname.new(File.expand_path('../docker/services/ruby/lib/monadic/version.rb', __dir__))
expected_version = version_rb.exist? ? version_rb.read[/VERSION = "([^"]+)"/, 1] : nil

if expected_version.nil?
  mismatches << { yml: '(version.rb)', url: 'VERSION',
                  reason: 'could not read the release version',
                  declared: '-', actual: '-' }
else
  manifests.each do |yml|
    data = YAML.safe_load(yml.read, permitted_classes: [Time], aliases: false)
    rel = yml.relative_path_from(dist).to_s

    if data['version'].to_s != expected_version
      mismatches << { yml: rel, url: '(manifest)', reason: 'manifest is not for this release',
                      declared: expected_version, actual: data['version'].inspect }
    end

    Array(data['files']).each do |entry|
      next if entry['url'].to_s.include?(expected_version)

      mismatches << { yml: rel, url: entry['url'].to_s,
                      reason: 'referenced artifact is not from this release',
                      declared: expected_version, actual: entry['url'].to_s }
    end
  end
end

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
mac_zips = dist.glob('Monadic*-arm64.zip').sort

# The macOS version the bundle itself declares. It uses macOS numbering while
# the manifest floor uses Darwin numbering, so each is read from its own source
# and compared against its own expectation, never against the other.
expected_bundle_floor = begin
  JSON.parse(root.join('package.json').read).dig('build', 'mac', 'minimumSystemVersion')
rescue StandardError
  nil
end

if expected_electron.nil?
  mismatches << { yml: '(node_modules)', url: 'electron',
                  reason: 'electron is not installed; cannot verify what was packaged',
                  declared: '-', actual: '-' }
end

if mac_zips.empty?
  if mac_manifests.empty?
    puts "[verify_release_manifests] note: no mac zip in #{dist} and no mac manifests; skipped the runtime check."
  else
    mismatches << { yml: '(dist)', url: 'Monadic*-arm64.zip',
                    reason: 'mac manifests are present but the shipped zip is missing, so nothing states what runtime ships',
                    declared: expected_electron, actual: 'none' }
  end
else
  mac_zips.each do |zip|
    rel = zip.relative_path_from(dist).to_s
    shipped = shipped_electron_version(zip)
    floor = shipped_minimum_system_version(zip)

    if shipped.nil?
      mismatches << { yml: rel, url: 'Electron Framework',
                      reason: 'could not read the framework version out of the shipped zip',
                      declared: expected_electron, actual: '-' }
    elsif expected_electron && shipped != expected_electron
      mismatches << { yml: rel, url: 'Electron Framework',
                      reason: 'the shipped runtime differs from the installed one',
                      declared: expected_electron, actual: shipped }
    end

    if expected_bundle_floor.nil?
      mismatches << { yml: '(package.json)', url: 'build.mac.minimumSystemVersion',
                      reason: 'could not read the macOS version the bundle should declare',
                      declared: '-', actual: '-' }
    elsif floor != expected_bundle_floor
      mismatches << { yml: rel, url: 'LSMinimumSystemVersion',
                      reason: 'the shipped app declares a different macOS floor than the build config',
                      declared: expected_bundle_floor, actual: floor.inspect }
    end
  end
end

if mismatches.empty?
  puts "[verify_release_manifests] OK: #{manifests.size} manifests verified, all entries match."
  puts "[verify_release_manifests] Electron #{expected_electron} in #{mac_zips.size} shipped zip(s); macOS floor declared in #{mac_manifests.size} manifest(s)."
  exit 0
end

warn '[verify_release_manifests] FAILED:'
mismatches.each do |m|
  warn "  #{m[:yml]} -> #{m[:url]}: #{m[:reason]}"
  warn "    declared: #{m[:declared]}" if m[:declared]
  warn "    actual:   #{m[:actual]}"   if m[:actual]
end
exit 1
