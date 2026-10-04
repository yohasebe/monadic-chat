#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that the macOS packages about to ship are notarized and stapled.
#
# The notarize hooks used to skip quietly when credentials were missing, and
# nothing downstream looked: a build could end "successfully" with a DMG that
# Gatekeeper rejects. This asks Apple's own tools about the files themselves,
# the DMG and the .app inside the update zip, rather than trusting the build
# log.
#
# Usage: ruby scripts/verify_mac_notarization.rb [dist_dir]

require 'open3'
require 'pathname'
require 'tmpdir'

ROOT = Pathname.new(File.expand_path('..', __dir__))
DIST = Pathname.new(ARGV[0] || ROOT.join('dist'))

abort '[verify_mac_notarization] needs macOS (xcrun stapler, spctl)' unless RUBY_PLATFORM.include?('darwin')

version = ROOT.join('docker/services/ruby/lib/monadic/version.rb').read[/VERSION = "([^"]+)"/, 1]
abort '[verify_mac_notarization] cannot read the version from version.rb' unless version

dmgs = DIST.glob("Monadic.Chat-#{version}-arm64.dmg")
zips = DIST.glob("Monadic.Chat-#{version}-arm64.zip")
abort "[verify_mac_notarization] no Monadic.Chat-#{version}-arm64.dmg in #{DIST}" if dmgs.empty?
abort "[verify_mac_notarization] no Monadic.Chat-#{version}-arm64.zip in #{DIST}" if zips.empty?

# [passed, first line of output]
def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.lines.map(&:strip).reject(&:empty?).first.to_s]
end

failures = []
check = lambda do |label, *cmd|
  ok, line = run(*cmd)
  puts "[verify_mac_notarization] #{ok ? 'ok  ' : 'FAIL'} #{label}#{ok ? '' : " — #{line}"}"
  failures << label unless ok
end

dmgs.each do |dmg|
  check.call("#{dmg.basename}: ticket stapled", 'xcrun', 'stapler', 'validate', dmg.to_s)
  check.call("#{dmg.basename}: Gatekeeper accepts it", 'spctl', '-a', '-t', 'open',
             '--context', 'context:primary-signature', dmg.to_s)
end

zips.each do |zip|
  Dir.mktmpdir('verify_notarization') do |tmp|
    unless system('ditto', '-x', '-k', zip.to_s, tmp, out: File::NULL, err: File::NULL)
      failures << "#{zip.basename}: could not be unpacked"
      next
    end
    apps = Dir.glob(File.join(tmp, '*.app'))
    if apps.size != 1
      failures << "#{zip.basename}: expected one .app, found #{apps.size}"
      next
    end
    app = apps.first
    check.call("#{zip.basename} → #{File.basename(app)}: ticket stapled", 'xcrun', 'stapler', 'validate', app)
    check.call("#{zip.basename} → #{File.basename(app)}: Gatekeeper accepts it", 'spctl', '-a', '-t', 'exec', app)
  end
end

if failures.empty?
  puts "[verify_mac_notarization] OK: #{dmgs.size} DMG and #{zips.size} zip are notarized and stapled."
  exit 0
end

warn "[verify_mac_notarization] FAILED (#{failures.size}): do not publish."
exit 1
