require 'spec_helper'
require 'base64'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Pins the YAML structure that patch_release_manifests.rb depends on.
# The script's regex matches `- url: X\n    sha512: ...\n    size: ...`,
# so if electron-builder ever reorders these keys the patcher silently
# leaves stale hashes in the manifest. This spec is the canary.
RSpec.describe "scripts/patch_release_manifests.rb" do
  let(:script_path) do
    File.expand_path("../../../../../../scripts/patch_release_manifests.rb", __dir__)
  end

  before { expect(File.exist?(script_path)).to be(true), "patcher not found at #{script_path}" }

  def run_patcher(dist_dir)
    Open3.capture3("ruby", script_path, dist_dir.to_s)
  end

  def make_artifact(dist, filename, payload)
    artifact = File.join(dist, filename)
    File.binwrite(artifact, payload)
    artifact
  end

  def sha512_b64(bytes)
    Base64.strict_encode64(Digest::SHA512.digest(bytes))
  end

  # Mirrors the layout electron-builder writes for macOS / Linux / Windows.
  def write_manifest(dist, filename, entries:, releaseDate: "2026-05-13T00:00:00.000Z", version: "1.0.0-beta.16")
    lines = []
    lines << "version: #{version}"
    lines << "files:"
    entries.each do |e|
      lines << "  - url: #{e[:url]}"
      lines << "    sha512: #{e[:sha512]}"
      lines << "    size: #{e[:size]}"
    end
    lines << "path: #{entries.first[:url]}"
    lines << "sha512: #{entries.first[:sha512]}"
    lines << "releaseDate: '#{releaseDate}'"
    File.write(File.join(dist, filename), lines.join("\n") + "\n")
  end

  context "macOS update floor" do
    # electron-updater refuses an update when the manifest declares a
    # minimumSystemVersion above the running OS, and it compares against
    # os.release() — the Darwin version, not the macOS one. electron-builder
    # does not write the field for the mac zip/dmg targets, so the patcher
    # adds it. Without it, a machine on a macOS the new build dropped is
    # offered the update by its own installed updater.
    it "declares the floor on mac manifests" do
      Dir.mktmpdir("patch_test") do |dist|
        payload = "bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64.dmg", payload)
        write_manifest(dist, "latest-mac.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16-arm64.dmg",
          sha512: sha512_b64(payload),
          size: payload.bytesize
        }])

        _stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)

        patched = YAML.safe_load_file(File.join(dist, "latest-mac.yml"))
        expect(patched["minimumSystemVersion"]).to eq("22.0.0"),
                                                   "expected the Darwin version for macOS 13, not the macOS one"
      end
    end

    it "leaves other platforms alone" do
      # Positive control for the branch: the field is meaningless outside mac,
      # and adding it everywhere would be indistinguishable from adding it
      # correctly if only mac were ever checked.
      Dir.mktmpdir("patch_test") do |dist|
        payload = "bytes"
        make_artifact(dist, "Monadic.Chat.Setup.exe", payload)
        write_manifest(dist, "latest.yml", entries: [{
          url: "Monadic.Chat.Setup.exe",
          sha512: sha512_b64(payload),
          size: payload.bytesize
        }])

        run_patcher(dist)

        patched = YAML.safe_load_file(File.join(dist, "latest.yml"))
        expect(patched).not_to have_key("minimumSystemVersion")
      end
    end

    it "corrects a floor written in macOS numbering instead of Darwin" do
      # `13.0.0` looks like a floor for macOS 13 and survives any shape check,
      # but electron-updater compares it against os.release() — a macOS 12
      # machine reports Darwin 21.6.0, which is higher, so the update is
      # offered to the systems the floor exists to stop. Leaving an existing
      # value alone would ship that silently.
      Dir.mktmpdir("patch_test") do |dist|
        payload = "bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64.dmg", payload)
        write_manifest(dist, "latest-mac.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16-arm64.dmg",
          sha512: sha512_b64(payload),
          size: payload.bytesize
        }])
        path = File.join(dist, "latest-mac.yml")
        File.write(path, File.read(path).sub(/^version:.*\n/) { |v| "#{v}minimumSystemVersion: 13.0.0\n" })

        stdout, _stderr, status = run_patcher(dist)

        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("corrected from 13.0.0")
        expect(File.read(path)).to include("minimumSystemVersion: 22.0.0")
        expect(File.read(path).scan("minimumSystemVersion").size).to eq(1)
      end
    end

    it "does not add it twice" do
      Dir.mktmpdir("patch_test") do |dist|
        payload = "bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64.dmg", payload)
        write_manifest(dist, "latest-mac.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16-arm64.dmg",
          sha512: sha512_b64(payload),
          size: payload.bytesize
        }])

        run_patcher(dist)
        stdout, _stderr, status = run_patcher(dist)

        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("already in sync")
        expect(File.read(File.join(dist, "latest-mac.yml")).scan("minimumSystemVersion").size).to eq(1)
      end
    end
  end

  context "happy path — manifest drifted from shipped bytes" do
    it "patches sha512 and size to match the artifact" do
      Dir.mktmpdir("patch_test") do |dist|
        payload = "real shipped bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64.dmg", payload)
        write_manifest(dist, "latest-mac.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16-arm64.dmg",
          sha512: "STALE_HASH_FROM_PRE_STAPLE_DMG",
          size: 999_999
        }])

        stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)
        # Two, not one: a mac manifest also gains its minimumSystemVersion line.
        expect(stdout).to include("Patched 2 entries")
        expect(stdout).to include("minimumSystemVersion set to")

        patched = YAML.safe_load_file(File.join(dist, "latest-mac.yml"))
        entry = patched["files"].first
        expect(entry["sha512"]).to eq(sha512_b64(payload))
        expect(entry["size"]).to eq(payload.bytesize)
      end
    end
  end

  context "idempotent — manifest already matches" do
    it "leaves the manifest untouched and exits 0" do
      Dir.mktmpdir("patch_test") do |dist|
        payload = "already correct"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16.exe", payload)
        write_manifest(dist, "latest.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16.exe",
          sha512: sha512_b64(payload),
          size: payload.bytesize
        }])
        before_mtime = File.mtime(File.join(dist, "latest.yml"))

        stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("All manifests already in sync")

        expect(File.mtime(File.join(dist, "latest.yml"))).to eq(before_mtime)
      end
    end
  end

  context "structural drift — electron-builder reorders keys" do
    it "exits 1 when the url/sha512/size triplet pattern is broken" do
      Dir.mktmpdir("patch_test") do |dist|
        payload = "shipped bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-x64.AppImage", payload)
        # Same fields but in the order url/size/sha512 — pattern would no longer match.
        File.write(File.join(dist, "latest-linux.yml"), <<~YML)
          version: 1.0.0-beta.16
          files:
            - url: Monadic.Chat-1.0.0-beta.16-x64.AppImage
              size: 12345
              sha512: STALE_HASH
          path: Monadic.Chat-1.0.0-beta.16-x64.AppImage
          sha512: STALE_HASH
          releaseDate: '2026-05-13T00:00:00.000Z'
        YML

        _stdout, stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(1)
        expect(stderr).to include("pattern not found")
      end
    end
  end

  context "missing artifact" do
    it "skips entries whose artifact does not exist (no error)" do
      Dir.mktmpdir("patch_test") do |dist|
        write_manifest(dist, "latest.yml", entries: [{
          url: "Monadic.Chat-1.0.0-beta.16-missing.dmg",
          sha512: "irrelevant",
          size: 0
        }])

        stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("already in sync")
      end
    end
  end

  context "no manifests" do
    it "exits 0 with informational message" do
      Dir.mktmpdir("patch_test") do |dist|
        stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("No latest*.yml manifests")
      end
    end
  end

  context "missing dist directory" do
    it "exits 1 with diagnostic" do
      _stdout, stderr, status = run_patcher("/tmp/definitely-not-a-real-dist-#{Time.now.to_i}")
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("dist directory not found")
    end
  end

  context "multiple entries — only drifted ones get patched" do
    it "patches drifted entries and leaves matching ones alone" do
      Dir.mktmpdir("patch_test") do |dist|
        dmg = "fresh dmg bytes"
        zip = "matching zip bytes"
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64.dmg", dmg)
        make_artifact(dist, "Monadic.Chat-1.0.0-beta.16-arm64-mac.zip", zip)
        write_manifest(dist, "latest-mac.yml", entries: [
          { url: "Monadic.Chat-1.0.0-beta.16-arm64.dmg",
            sha512: "STALE", size: 1 },
          { url: "Monadic.Chat-1.0.0-beta.16-arm64-mac.zip",
            sha512: sha512_b64(zip), size: zip.bytesize }
        ])

        stdout, _stderr, status = run_patcher(dist)
        expect(status.exitstatus).to eq(0)
        # Two, not one: a mac manifest also gains its minimumSystemVersion line.
        expect(stdout).to include("Patched 2 entries")
        expect(stdout).to include("minimumSystemVersion set to")

        patched = YAML.safe_load_file(File.join(dist, "latest-mac.yml"))
        dmg_entry = patched["files"].find { |e| e["url"].end_with?(".dmg") }
        zip_entry = patched["files"].find { |e| e["url"].end_with?(".zip") }
        expect(dmg_entry["sha512"]).to eq(sha512_b64(dmg))
        expect(dmg_entry["size"]).to eq(dmg.bytesize)
        expect(zip_entry["sha512"]).to eq(sha512_b64(zip))
      end
    end
  end
end
