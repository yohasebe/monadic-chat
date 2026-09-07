require 'spec_helper'
require 'base64'
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# The verifier is the last gate before manifests are published, so what it
# lets through is what ships. These examples pin the checks that were found
# to pass on a broken release: a macOS floor written in the wrong numbering
# system, a manifest listing no files at all, and a run that had no packaged
# app to read the Electron version from and still exited 0.
#
# Assertions read the reported reasons rather than the exit status: the
# script also compares the packaged Electron against `node_modules/electron`,
# which is absent wherever the Ruby suite runs without a JS install, so the
# status is not a signal here.
RSpec.describe "scripts/verify_release_manifests.rb" do
  let(:script_path) do
    File.expand_path("../../../../../../scripts/verify_release_manifests.rb", __dir__)
  end

  # The floor the patcher writes, read from the same place the verifier reads
  # it, so this spec cannot pin a value the release no longer uses.
  let(:expected_floor) do
    patcher = File.expand_path("../../../../../../scripts/patch_release_manifests.rb", __dir__)
    File.read(patcher)[/MAC_MINIMUM_DARWIN_VERSION\s*=\s*'([^']+)'/, 1]
  end

  # The release this checkout builds. Written into the fixtures so they stay
  # valid across version bumps.
  let(:release_version) do
    path = File.expand_path("../../../lib/monadic/version.rb", __dir__)
    File.read(path)[/VERSION = "([^"]+)"/, 1]
  end

  before { expect(File.exist?(script_path)).to be(true), "verifier not found at #{script_path}" }

  def run_verifier(dist)
    Open3.capture3("ruby", script_path, dist.to_s)
  end

  def write_mac_manifest(dist, floor:, filename: "latest-mac.yml", files: :default,
                         version: release_version, artifact_version: nil)
    payload = "bytes"
    artifact = "Monadic.Chat-#{artifact_version || version}-arm64.dmg"
    File.binwrite(File.join(dist, artifact), payload)

    digest = Base64.strict_encode64(Digest::SHA512.digest(payload))

    lines = ["version: #{version}"]
    lines << "minimumSystemVersion: #{floor}" if floor
    lines << "files:"
    if files == :default
      lines << "  - url: #{artifact}"
      lines << "    sha512: #{digest}"
      lines << "    size: #{payload.bytesize}"
    end
    # electron-builder also writes this legacy pair, naming the first entry.
    lines << "path: #{artifact}"
    lines << "sha512: #{digest}"
    lines << "releaseDate: '2026-09-07T00:00:00.000Z'"
    File.write(File.join(dist, filename), lines.join("\n") + "\n")
  end

  FLOOR_REASON = 'minimumSystemVersion is not the Darwin version this release requires'

  context "the macOS update floor" do
    it "accepts the Darwin version the patcher writes" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        _stdout, stderr, = run_verifier(dist)

        expect(stderr).not_to include(FLOOR_REASON)
      end
    end

    it "rejects the macOS number written where the Darwin number belongs" do
      # 13.0.0 reads as a plausible floor and passes a shape check, but a
      # macOS 12 machine reports Darwin 21.6.0, which compares as higher — so
      # the guard would admit exactly the systems it exists to stop.
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: "13.0.0")
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include(FLOOR_REASON)
        expect(stderr).to include('13.0.0')
        expect(status.exitstatus).to eq(1)
      end
    end

    it "rejects a mac manifest with no floor at all" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: nil)
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include(FLOOR_REASON)
        expect(status.exitstatus).to eq(1)
      end
    end

    it "leaves non-mac manifests out of the floor check" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: nil, filename: "latest.yml")
        _stdout, stderr, = run_verifier(dist)

        expect(stderr).not_to include(FLOOR_REASON)
      end
    end
  end

  context "the legacy top-level pair" do
    it "is reported when it no longer matches the artifact it names" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        path = File.join(dist, "latest-mac.yml")
        File.write(path, File.read(path).sub(/^sha512: .+$/, "sha512: staleHashFromBeforeRepackaging=="))

        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('the legacy top-level sha512 does not match')
        expect(status.exitstatus).to eq(1)
      end
    end

    it "is accepted when it matches" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        _stdout, stderr, = run_verifier(dist)

        expect(stderr).not_to include('the legacy top-level sha512')
      end
    end
  end

  context "a manifest that lists nothing" do
    it "is reported rather than passing every per-entry check vacuously" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor, files: :none)
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('no files entries')
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  context "nothing shipped to read the runtime from" do
    it "reports it instead of exiting 0 on a skipped check" do
      # The build deletes the unpacked app before verifying, so the zip is the
      # only place left that states which runtime ships. A run with mac
      # manifests but no zip has checked nothing.
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('the shipped zip is missing')
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  # Reading the plists needs PlistBuddy, which exists only on macOS. Release
  # builds happen on macOS, so these run where the check matters; elsewhere the
  # antecedent is genuinely absent rather than the assertions being skipped for
  # convenience.
  context "what the shipped zip declares", if: File.exist?("/usr/libexec/PlistBuddy") do
    def write_zip(dist, artifact_name, electron:, os_floor:)
      Dir.mktmpdir("zip_src") do |src|
        fw = File.join(src, "Monadic Chat.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources")
        app = File.join(src, "Monadic Chat.app/Contents")
        FileUtils.mkdir_p(fw)
        FileUtils.mkdir_p(app)
        File.write(File.join(fw, "Info.plist"), plist("CFBundleVersion" => electron))
        File.write(File.join(app, "Info.plist"), plist("LSMinimumSystemVersion" => os_floor))

        zip = File.join(dist, artifact_name)
        ok = system("zip", "-q", "-r", zip, "Monadic Chat.app", chdir: src)
        raise "could not build the fixture zip" unless ok
      end
    end

    def plist(pairs)
      body = pairs.map { |k, v| "  <key>#{k}</key>\n  <string>#{v}</string>" }.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        #{body}
        </dict>
        </plist>
      XML
    end

    let(:installed_electron) do
      path = File.expand_path("../../../../../../node_modules/electron/package.json", __dir__)
      File.exist?(path) ? JSON.parse(File.read(path))["version"] : nil
    end

    let(:bundle_floor) do
      path = File.expand_path("../../../../../../package.json", __dir__)
      JSON.parse(File.read(path)).dig("build", "mac", "minimumSystemVersion")
    end

    it "accepts a zip carrying the installed runtime and the configured floor" do
      skip "electron is not installed" unless installed_electron

      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        write_zip(dist, "Monadic.Chat-#{release_version}-arm64.zip",
                  electron: installed_electron, os_floor: bundle_floor)
        _stdout, stderr, = run_verifier(dist)

        expect(stderr).not_to include('the shipped runtime differs')
        expect(stderr).not_to include('different macOS floor')
      end
    end

    it "reports a zip built on the previous Electron" do
      # This is the failure that shipped beta.31: the dependency had been
      # raised while the build kept producing the old runtime.
      skip "electron is not installed" unless installed_electron

      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        write_zip(dist, "Monadic.Chat-#{release_version}-arm64.zip",
                  electron: "39.2.7", os_floor: bundle_floor)
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('the shipped runtime differs')
        expect(stderr).to include('39.2.7')
        expect(status.exitstatus).to eq(1)
      end
    end

    it "reports a bundle declaring a macOS floor the build config does not" do
      skip "electron is not installed" unless installed_electron

      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        write_zip(dist, "Monadic.Chat-#{release_version}-arm64.zip",
                  electron: installed_electron, os_floor: "12.0")
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('different macOS floor')
        expect(status.exitstatus).to eq(1)
      end
    end
  end
  # sha512 and size only prove a manifest matches a file that is present, and
  # dist keeps the previous release's artifacts. A manifest a failed build left
  # behind therefore points at real files with correct hashes — and its macOS
  # floor is correct too, since the previous release wrote one. Without a
  # version check every gate here passes on the wrong release.
  context "which release the manifest describes" do
    VERSION_REASON = 'manifest is not for this release'
    ARTIFACT_REASON = 'referenced artifact is not from this release'

    it "accepts a manifest for the version being built" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        _stdout, stderr, = run_verifier(dist)

        expect(stderr).not_to include(VERSION_REASON)
        expect(stderr).not_to include(ARTIFACT_REASON)
      end
    end

    it "rejects one left behind by the previous release" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor, version: "1.0.0-beta.1")
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include(VERSION_REASON)
        expect(status.exitstatus).to eq(1)
      end
    end

    it "rejects one pointing at the previous release's artifacts" do
      # The header can be rewritten while the entries still name old files.
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor, artifact_version: "1.0.0-beta.1")
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include(ARTIFACT_REASON)
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  # The publish step attaches update manifests by name. Anything it attaches
  # that the patcher and verifier do not cover reaches the updater unchecked,
  # and electron-updater on a prerelease asks for a `beta-*` channel before
  # falling back to `latest-*` — so a stray beta manifest would be preferred
  # over the one that carries the macOS floor.
  #
  # These run the selection the release task uses, over real directories. The
  # expected names are written out here rather than read from the module, so
  # the two cannot be wrong together.
  context "choosing what to publish" do
    let(:selector) do
      path = File.expand_path("../../../../../../scripts/release_manifest_set.rb", __dir__)
      expect(File.exist?(path)).to be(true), "release_manifest_set.rb not found at #{path}"
      require path
      ReleaseManifestSet
    end

    let(:full_set) do
      %w[latest.yml latest-mac.yml latest-mac-arm64.yml latest-linux.yml latest-linux-arm64.yml]
    end

    def dist_with(names)
      dir = Dir.mktmpdir("release_set")
      names.each { |n| File.write(File.join(dir, n), "version: 1.0.0-beta.32\n") }
      yield dir
    ensure
      FileUtils.remove_entry(dir) if dir
    end

    it "returns every manifest the release ships" do
      dist_with(full_set) do |dist|
        paths, error = selector.select(dist)

        expect(error).to be_nil
        expect(paths.map { |p| File.basename(p) }).to match_array(full_set)
      end
    end

    it "ignores electron-builder's debug dump" do
      dist_with(full_set + %w[builder-debug.yml]) do |dist|
        paths, error = selector.select(dist)

        expect(error).to be_nil
        expect(paths.map { |p| File.basename(p) }).not_to include("builder-debug.yml")
      end
    end

    it "refuses a channel manifest nothing patched or verified" do
      # electron-updater on a prerelease asks for this one first, and it would
      # carry no macOS floor.
      dist_with(full_set + %w[beta-mac.yml]) do |dist|
        paths, error = selector.select(dist)

        expect(error).to include("beta-mac.yml")
        expect(paths).to be_empty
      end
    end

    it "refuses a set that is missing a platform" do
      # Publishing the rest would look complete while leaving that platform
      # with no update path.
      dist_with(full_set - %w[latest-mac.yml]) do |dist|
        paths, error = selector.select(dist)

        expect(error).to include("latest-mac.yml")
        expect(paths).to be_empty
      end
    end
  end

  # The selection above is only half of the guarantee: the task must also run
  # the verifier over the files it is about to attach. `rake release:github`
  # skips the build when the packages already exist, so without this a stale
  # dist would be published unchecked.
  context "the release task" do
    let(:release_rake) do
      File.read(File.expand_path("../../../../../../rakelib/release.rake", __dir__))
    end

    it "selects through the module rather than a glob" do
      expect(release_rake).to include("ReleaseManifestSet.select")
      expect(release_rake).not_to include('Dir.glob("dist/*.yml")')
    end

    it "stops when verification fails" do
      expect(release_rake).to include('system("ruby", "scripts/verify_release_manifests.rb")')
      expect(release_rake).to match(/verification failed; nothing was published/)
    end
  end
end
