# frozen_string_literal: true

# Which auto-update manifests a release may attach.
#
# The publish step used to take `dist/*.yml` minus electron-builder's debug
# dump. Only `latest-*` manifests are patched (sha512/size, and the macOS
# floor) and verified, so anything else reached the updater unchecked — and
# electron-updater running on a prerelease asks for a `beta-*` channel before
# falling back to `latest-*`, so a stray beta manifest would be preferred over
# the one carrying the floor.
#
# Selection lives here rather than inside the rake task so it can be exercised
# against real directories.
module ReleaseManifestSet
  # One per platform/arch the release ships. Order is the order they are
  # attached, which only affects the log.
  EXPECTED = %w[
    latest.yml
    latest-mac.yml
    latest-mac-arm64.yml
    latest-linux.yml
    latest-linux-arm64.yml
  ].freeze

  # electron-builder's debug dump. Not an update manifest and never attached.
  IGNORED = %w[builder-debug.yml].freeze

  # Returns [paths, error]. `error` is a message when the directory does not
  # hold exactly the expected set: an extra manifest is a build-configuration
  # change that nothing has checked, and a missing one leaves that platform
  # without an update path while the release still looks complete.
  def self.select(dist)
    found = Dir.glob(File.join(dist, '*.yml')).map { |f| File.basename(f) } - IGNORED

    unexpected = found - EXPECTED
    unless unexpected.empty?
      return [[], "unexpected update manifest(s) in #{dist}: #{unexpected.sort.join(', ')}. " \
                  'These are neither patched nor verified. Remove them, or extend ' \
                  'scripts/release_manifest_set.rb and the patch/verify scripts together.']
    end

    missing = EXPECTED - found
    unless missing.empty?
      return [[], "missing update manifest(s) in #{dist}: #{missing.sort.join(', ')}. " \
                  'Rebuild rather than publishing a release that leaves those platforms ' \
                  'without an update path.']
    end

    [EXPECTED.map { |name| File.join(dist, name) }, nil]
  end
end
