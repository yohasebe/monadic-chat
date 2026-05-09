// electron-builder afterAllArtifactBuild hook.
//
// scripts/notarize.js (wired as afterSign) already notarizes the .app before
// electron-builder wraps it into a .dmg. However, Gatekeeper also checks the
// DMG itself when the user first opens it — and without a notarization
// ticket stapled to the DMG, macOS shows an "unidentified developer" warning
// and, on stricter configurations, refuses to mount the volume until the
// user explicitly overrides in System Settings → Privacy & Security.
//
// This hook runs once per platform build after all artifacts for that
// platform are generated. For macOS builds, it locates the produced .dmg(s),
// submits each to Apple's notary service (notarytool), then staples the
// ticket so offline launches succeed without contacting Apple's servers.
//
// On non-macOS builds (Linux/Windows), the hook is a no-op.
//
// CRITICAL post-staple step (since 2026-05-09):
// Stapling the DMG modifies the file (the ticket is embedded in the DMG
// itself), which changes both its byte length and sha512. electron-builder
// has already written `latest-mac.yml` (and any companion arch-specific
// files) at this point with the *pre-staple* hash and size, so without
// regenerating those entries the published manifest no longer matches the
// shipped DMG. electron-updater then refuses the download with a hash
// mismatch error. After stapling, this hook recomputes the DMG hash + size
// and patches every matching `latest-mac*.yml` it finds in dist/.

require('dotenv').config();
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function shaB64(file) {
  const buf = fs.readFileSync(file);
  return crypto.createHash('sha512').update(buf).digest('base64');
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Patch the DMG entry's `sha512:` and `size:` fields in `ymlPath` to match
// the actually-shipped (post-staple) bytes. Returns true if the file was
// modified.
function patchDmgEntry(ymlPath, dmgBasename, sha512, size) {
  if (!fs.existsSync(ymlPath)) return false;
  let content = fs.readFileSync(ymlPath, 'utf8');
  const pattern = new RegExp(
    `(- url: ${escapeRegex(dmgBasename)}\\s*\\n\\s*sha512: )[^\\n]+(\\s*\\n\\s*size: )\\d+`
  );
  if (!pattern.test(content)) return false;
  content = content.replace(pattern, `$1${sha512}$2${size}`);
  fs.writeFileSync(ymlPath, content);
  return true;
}

exports.default = async function afterAllArtifactBuild(context) {
  const { artifactPaths } = context;
  if (!Array.isArray(artifactPaths) || artifactPaths.length === 0) return;

  const dmgs = artifactPaths.filter((p) => typeof p === 'string' && p.endsWith('.dmg'));
  if (dmgs.length === 0) return;

  if (!process.env.APPLEID || !process.env.APPLEIDPASS || !process.env.TEAMID) {
    console.warn('[notarize-dmg] APPLEID / APPLEIDPASS / TEAMID not set; skipping DMG notarization.');
    return;
  }

  const { notarize } = await import('@electron/notarize');

  for (const dmgPath of dmgs) {
    const name = path.basename(dmgPath);
    console.log(`[notarize-dmg] Submitting ${name} to Apple notary service . . .`);

    await notarize({
      tool: 'notarytool',
      appBundleId: 'com.yohasebe.monadic',
      appPath: dmgPath,
      appleId: process.env.APPLEID,
      appleIdPassword: process.env.APPLEIDPASS,
      teamId: process.env.TEAMID
    });

    console.log(`[notarize-dmg] Stapling ticket to ${name} . . .`);
    execSync(`xcrun stapler staple "${dmgPath}"`, { stdio: 'inherit' });
    console.log(`[notarize-dmg] ${name}: notarized and stapled.`);

    // Patch every `latest-mac*.yml` in the same directory so the
    // manifest's DMG entry matches the post-staple bytes. If we omit
    // this, electron-updater rejects the DMG with a hash mismatch.
    const distDir = path.dirname(dmgPath);
    const stat = fs.statSync(dmgPath);
    const sha512 = shaB64(dmgPath);
    const ymls = fs.readdirSync(distDir).filter((f) => /^latest-mac.*\.yml$/.test(f));
    let patchedAny = false;
    for (const ymlName of ymls) {
      const ymlPath = path.join(distDir, ymlName);
      if (patchDmgEntry(ymlPath, name, sha512, stat.size)) {
        console.log(`[notarize-dmg] Patched ${ymlName}: ${name} sha512+size now match shipped bytes.`);
        patchedAny = true;
      }
    }
    if (!patchedAny) {
      console.warn(
        `[notarize-dmg] WARNING: no latest-mac*.yml entry matched ${name}. ` +
        `Auto-update may use a stale hash for this DMG.`
      );
    }
  }
};
