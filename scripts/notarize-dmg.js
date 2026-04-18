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

require('dotenv').config();
const { execSync } = require('child_process');
const path = require('path');

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
  }
};
