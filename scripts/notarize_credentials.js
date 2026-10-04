'use strict';

// Notarization credentials for scripts/notarize.js (.app, afterSign) and
// scripts/notarize-dmg.js (DMG, afterAllArtifactBuild).
//
// NOTARY_PROFILE names a profile saved once with
// `xcrun notarytool store-credentials <name>` (the same variable and profile
// other projects on the build machine use). notarytool reads the password
// from the keychain, so it never appears in this process, its environment or
// a command line. A release build (`rake build`, which sets
// MONADIC_RELEASE_BUILD=1) requires it and stops without it: skipping there
// used to produce a DMG that was not notarized while the build reported
// success.
//
// Other builds may still use APPLEID / APPLEIDPASS / TEAMID, as before. That
// path hands the password to notarytool as a command-line argument
// (@electron/notarize does), so a release build does not accept it.

const REFERENCE = /^op:\/\//;

function isReleaseBuild(env = process.env) {
  return env.MONADIC_RELEASE_BUILD === '1';
}

// Options for @electron/notarize, or { missing: reason }. The reason names
// variables only, never a value.
function notarizeCredentials(env = process.env) {
  if (env.NOTARY_PROFILE) return { keychainProfile: env.NOTARY_PROFILE };
  if (isReleaseBuild(env)) {
    return { missing: 'a release build needs NOTARY_PROFILE (xcrun notarytool store-credentials)' };
  }
  const { APPLEID, APPLEIDPASS, TEAMID } = env;
  if (!APPLEID || !APPLEIDPASS || !TEAMID) {
    return { missing: 'set NOTARY_PROFILE, or APPLEID, APPLEIDPASS and TEAMID' };
  }
  // A 1Password reference is not the password. Passing it on would submit
  // the reference text to Apple.
  if (REFERENCE.test(APPLEIDPASS)) {
    return { missing: 'APPLEIDPASS is a 1Password reference, which is not read here; use NOTARY_PROFILE' };
  }
  return { appleId: APPLEID, appleIdPassword: APPLEIDPASS, teamId: TEAMID };
}

// The credentials, or null after a warning; throws in a release build.
function credentialsOrSkip(label, env = process.env, warn = console.warn) {
  const creds = notarizeCredentials(env);
  if (!creds.missing) return creds;
  if (isReleaseBuild(env)) {
    throw new Error(`[${label}] release build stopped: notarization credentials are not available (${creds.missing}).`);
  }
  warn(`[${label}] ${creds.missing}; skipping notarization (not a release build).`);
  return null;
}

module.exports = { isReleaseBuild, notarizeCredentials, credentialsOrSkip };
