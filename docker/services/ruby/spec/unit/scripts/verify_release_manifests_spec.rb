require 'spec_helper'
require 'base64'
require 'digest'
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

  before { expect(File.exist?(script_path)).to be(true), "verifier not found at #{script_path}" }

  def run_verifier(dist)
    Open3.capture3("ruby", script_path, dist.to_s)
  end

  def write_mac_manifest(dist, floor:, filename: "latest-mac.yml", files: :default)
    payload = "bytes"
    artifact = "Monadic.Chat-1.0.0-beta.32-arm64.zip"
    File.binwrite(File.join(dist, artifact), payload)

    lines = ["version: 1.0.0-beta.32"]
    lines << "minimumSystemVersion: #{floor}" if floor
    lines << "files:"
    if files == :default
      lines << "  - url: #{artifact}"
      lines << "    sha512: #{Base64.strict_encode64(Digest::SHA512.digest(payload))}"
      lines << "    size: #{payload.bytesize}"
    end
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

  context "nothing packaged to read the runtime from" do
    it "reports it instead of exiting 0 on a skipped check" do
      Dir.mktmpdir("verify_test") do |dist|
        write_mac_manifest(dist, floor: expected_floor)
        _stdout, stderr, status = run_verifier(dist)

        expect(stderr).to include('no packaged app was found')
        expect(status.exitstatus).to eq(1)
      end
    end
  end
  # The publish step attaches update manifests by name. Anything it attaches
  # that the patcher and verifier do not cover reaches the updater unchecked,
  # and electron-updater on a prerelease asks for a `beta-*` channel before
  # falling back to `latest-*` — so a stray beta manifest would be preferred
  # over the one that carries the macOS floor. This pins publish scope to
  # verified scope rather than trusting the two lists to stay aligned.
  context "what gets published against what gets verified" do
    let(:release_rake) do
      File.read(File.expand_path("../../../../../../rakelib/release.rake", __dir__))
    end

    let(:published_manifests) do
      block = release_rake[/expected_update_manifests = %w\[(.*?)\]/m, 1]
      expect(block).to be_a(String), "the publish allow list has moved or been renamed"
      block.split
    end

    it "publishes only manifests the patcher and verifier glob covers" do
      # Both scripts select `latest*.yml`; a published name outside that shape
      # is never patched and never checked.
      expect(published_manifests).to all(start_with("latest"))
      expect(published_manifests).not_to be_empty
    end

    it "still selects on that shape in both scripts" do
      # Positive control for the assertion above: if either script widened or
      # renamed its selection, "starts with latest" would stop meaning
      # "covered".
      %w[patch_release_manifests.rb verify_release_manifests.rb].each do |name|
        source = File.read(File.expand_path("../../../../../../scripts/#{name}", __dir__))
        expect(source).to include("glob('latest*.yml')"), "#{name} no longer selects latest*.yml"
      end
    end

    it "names every platform the release ships" do
      expect(published_manifests).to contain_exactly(
        "latest.yml", "latest-mac.yml", "latest-mac-arm64.yml",
        "latest-linux.yml", "latest-linux-arm64.yml"
      )
    end
  end
end
