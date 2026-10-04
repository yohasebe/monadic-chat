require('dotenv').config();
const { execSync } = require('child_process');
const { credentialsOrSkip } = require('./notarize_credentials');

exports.default = async function notarizing(context) {
    const { electronPlatformName, appOutDir } = context;
    if (electronPlatformName !== 'darwin') {
        return;
    }

    // Stops a release build when no credentials are usable; skips otherwise.
    const credentials = credentialsOrSkip('notarize');
    if (!credentials) return;

    const { notarize } = await import('@electron/notarize');
    const appName = context.packager.appInfo.productFilename;
    const appPath = `${appOutDir}/${appName}.app`;

    console.log(`[notarize] Submitting ${appName}.app to Apple notary service . . .`);
    await notarize({
        tool: 'notarytool',
        appBundleId: 'com.yohasebe.monadic',
        appPath,
        ...credentials
    });

    // @electron/notarize with tool: 'notarytool' may or may not staple
    // depending on version. Always run staple explicitly to guarantee the
    // ticket is embedded so offline Gatekeeper checks succeed.
    console.log(`[notarize] Stapling ticket to ${appName}.app . . .`);
    execSync(`xcrun stapler staple "${appPath}"`, { stdio: 'inherit' });
    console.log(`[notarize] ${appName}.app: notarized and stapled.`);
};
