/**
 * Tests for the macOS floor that keeps unsupported systems off the update.
 *
 * Electron 44 drops macOS 12, so an update offered to a macOS 12 machine
 * installs a runtime that cannot launch — and the decision to offer it is
 * made by the OLD app, which is already in users' hands. The guard is a
 * `minimumSystemVersion` field written into the mac update manifests.
 *
 * Two numbering systems meet here and are easy to swap:
 *   - the manifest is compared against `os.release()`, which is the DARWIN
 *     version (macOS 13 = Darwin 22)
 *   - `build.mac.minimumSystemVersion` in package.json is the MACOS version
 *     that goes into LSMinimumSystemVersion (13.0)
 * Both are asserted below so a future edit cannot quietly write one where
 * the other belongs.
 *
 * The comparison itself is not reimplemented here: these examples call
 * electron-updater's own `checkIfUpdateSupported`, so the test tracks
 * whatever the shipped updater actually does.
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const yaml = require(path.join(__dirname, '../../node_modules/js-yaml'));

const ROOT = path.join(__dirname, '../..');

const { AppUpdater } = require(path.join(ROOT, 'node_modules/electron-updater/out/AppUpdater.js'));
const checkIfUpdateSupported = AppUpdater.prototype.checkIfUpdateSupported;

// The floor the release patcher writes, read from the script rather than
// duplicated, so the two cannot drift apart.
const patcherSource = fs.readFileSync(path.join(ROOT, 'scripts/patch_release_manifests.rb'), 'utf8');
const darwinFloor = (patcherSource.match(/MAC_MINIMUM_DARWIN_VERSION\s*=\s*'([^']+)'/) || [])[1];

const packageJson = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
const macFloor = packageJson.build?.mac?.minimumSystemVersion;

describe('the release patcher and the app bundle agree on which macOS is the floor', () => {
  it('writes a Darwin version into the manifest', () => {
    expect(darwinFloor).toBe('22.0.0');
  });

  it('declares the matching macOS version in the app bundle', () => {
    // Darwin 22 is macOS 13. Writing "13.0" into the manifest, or "22.0.0"
    // into the bundle, would leave the guard comparing unrelated numbers.
    expect(macFloor).toBe('13.0');
  });
});

describe('electron-updater applied to the manifest the patcher produces', () => {
  const realRelease = os.release;
  const logger = { info: () => {}, warn: () => {}, error: () => {} };

  const supported = (darwinVersion, updateInfo) => {
    os.release = () => darwinVersion;
    return checkIfUpdateSupported.call({ _logger: logger }, updateInfo);
  };

  const withFloor = { version: '1.0.0-beta.32', minimumSystemVersion: darwinFloor };
  const withoutFloor = { version: '1.0.0-beta.32' };

  afterEach(() => {
    os.release = realRelease;
  });

  it('refuses the update on macOS 12, where the new runtime cannot launch', () => {
    expect(supported('21.6.0', withFloor)).toBe(false);
  });

  it('offers it on macOS 13, the first supported release', () => {
    expect(supported('22.6.0', withFloor)).toBe(true);
  });

  it('offers it on a current macOS', () => {
    expect(supported('24.6.0', withFloor)).toBe(true);
  });

  it('offers it to macOS 12 when the field is absent', () => {
    // Positive control: this is the shape beta.31 published, and the reason
    // the field has to be added rather than assumed. Without it the three
    // examples above would pass on a guard that does nothing.
    expect(supported('21.6.0', withoutFloor)).toBe(true);
  });
});

describe('the manifest the release patcher actually produces', () => {
  // The examples above build updateInfo in JS from the patcher's constant, so
  // they would keep passing if the insertion itself were removed. These run
  // the real script over a manifest shaped the way electron-builder writes
  // one, then hand its output to the real updater — the two halves of the
  // guard meeting where they meet in a release.
  const patcher = path.join(ROOT, 'scripts/patch_release_manifests.rb');
  const realRelease = os.release;
  const logger = { info: () => {}, warn: () => {}, error: () => {} };

  const supported = (darwinVersion, updateInfo) => {
    os.release = () => darwinVersion;
    return checkIfUpdateSupported.call({ _logger: logger }, updateInfo);
  };

  const patchedManifest = (existingFloor) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'update-floor-'));
    try {
      const artifact = 'Monadic.Chat-1.0.0-beta.32-arm64.zip';
      const payload = Buffer.from('bytes');
      fs.writeFileSync(path.join(dir, artifact), payload);

      const lines = ['version: 1.0.0-beta.32'];
      if (existingFloor) lines.push(`minimumSystemVersion: ${existingFloor}`);
      lines.push('files:');
      lines.push(`  - url: ${artifact}`);
      lines.push('    sha512: placeholder');
      lines.push('    size: 0');
      lines.push("releaseDate: '2026-09-07T00:00:00.000Z'");
      fs.writeFileSync(path.join(dir, 'latest-mac.yml'), lines.join('\n') + '\n');

      execFileSync('ruby', [patcher, dir], { stdio: 'pipe' });
      return yaml.load(fs.readFileSync(path.join(dir, 'latest-mac.yml'), 'utf8'));
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  };

  afterEach(() => {
    os.release = realRelease;
  });

  it('carries a floor the updater reads', () => {
    // Positive control: electron-builder does not write this field for the
    // mac targets, so without the patcher step the manifest arrives bare.
    expect(patchedManifest(null).minimumSystemVersion).toBe(darwinFloor);
  });

  it('refuses the update on macOS 12', () => {
    expect(supported('21.6.0', patchedManifest(null))).toBe(false);
  });

  it('offers it exactly at the boundary, Darwin 22.0.0', () => {
    expect(supported('22.0.0', patchedManifest(null))).toBe(true);
  });

  it('still refuses macOS 12 when the manifest arrived with a wrong floor', () => {
    // A floor in macOS numbering compares as lower than a macOS 12 machine's
    // Darwin version, so passing it through unchanged would disable the guard.
    expect(supported('21.6.0', patchedManifest('13.0.0'))).toBe(false);
  });
});
