#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-create the macOS auto-update .zip with framework symlinks preserved.
#
# Why this exists (since 2026-06-08, beta.19):
# electron-builder's mac `zip` target flattens the symlinks inside
# nested frameworks (e.g. `Electron Framework.framework/Versions/Current`
# and the top-level `Electron Framework -> Versions/Current/...`). The
# flattened bundle duplicates the framework binaries (the zip balloons
# ~2.5x) and makes `codesign --verify` report
#   "bundle format is ambiguous (could be app or framework)"
# Squirrel.Mac validates the downloaded .app with exactly that check, so
# auto-update fails with "Code signature ... did not pass validation".
# The DMG is unaffected because a filesystem image preserves symlinks.
#
# `ditto --keepParent` preserves symlinks, so re-zipping the intact .app
# restores the correct structure. Run this AFTER electron-builder and
# BEFORE scripts/patch_release_manifests.rb — the patcher then syncs the
# yml `sha512`/`size` to the corrected zip automatically.
#
# Usage: ruby scripts/repackage_mac_zip.rb [dist_dir]

require 'fileutils'
require 'shellwords'
require 'tmpdir'

dist = File.expand_path(ARGV[0] || File.join(__dir__, '..', 'dist'))
version_file = File.join(__dir__, '..', 'docker/services/ruby/lib/monadic/version.rb')
version = File.read(version_file)[/VERSION = "([^"]+)"/, 1]
abort "[repackage_mac_zip] cannot read VERSION from #{version_file}" unless version

zip = File.join(dist, "Monadic.Chat-#{version}-arm64.zip")
dmg = File.join(dist, "Monadic.Chat-#{version}-arm64.dmg")

unless File.exist?(zip)
  puts "[repackage_mac_zip] no mac zip at #{zip}; nothing to do."
  exit 0
end

# Locate the intact .app: prefer electron-builder's unpacked output, else
# mount the DMG (a filesystem image always preserves the symlinks).
app = Dir.glob(File.join(dist, 'mac-arm64', '*.app')).first ||
      Dir.glob(File.join(dist, 'mac', '*.app')).first
mount = nil
if app.nil?
  abort "[repackage_mac_zip] DMG not found: #{dmg}" unless File.exist?(dmg)
  # Note: do NOT pass -quiet — it suppresses the mount-point line we parse.
  out = `hdiutil attach -nobrowse -noverify #{dmg.shellescape} 2>&1`
  mount = out.scan(%r{/Volumes/[^\n]+}).map(&:rstrip).find { |m| Dir.exist?(m) }
  abort "[repackage_mac_zip] failed to mount DMG:\n#{out}" unless mount
  app = Dir.glob(File.join(mount, '*.app')).first
end
abort '[repackage_mac_zip] could not locate the .app to re-zip' unless app && Dir.exist?(app)

begin
  puts "[repackage_mac_zip] Re-zipping #{File.basename(app)} -> #{File.basename(zip)} (ditto, symlink-preserving)"
  FileUtils.rm_f(zip)
  FileUtils.rm_f("#{zip}.blockmap") # stale differential map, if any
  unless system('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, zip)
    abort '[repackage_mac_zip] ditto failed'
  end
ensure
  system("hdiutil detach #{mount.shellescape} -quiet >/dev/null 2>&1") if mount
end

# Sanity: the re-zipped app must pass the exact check Squirrel.Mac runs.
# Fail the build rather than ship a zip that breaks auto-update.
Dir.mktmpdir do |tmp|
  unless system('ditto', '-x', '-k', zip, tmp)
    abort '[repackage_mac_zip] could not extract verification copy'
  end
  extracted = Dir.glob(File.join(tmp, '*.app')).first
  abort '[repackage_mac_zip] verification copy has no .app' unless extracted
  unless system("codesign --verify --strict #{extracted.shellescape} >/dev/null 2>&1")
    abort '[repackage_mac_zip] codesign --verify FAILED on the re-zipped app; ' \
          'auto-update would break — aborting build'
  end
end

puts "[repackage_mac_zip] OK: #{File.basename(zip)} re-created and codesign-verified."
