require('dotenv').config();

exports.default = async function notarizing(context) {
    const { electronPlatformName, appOutDir } = context;   
    if (electronPlatformName !== 'darwin') {
        return;
    }

    // Dynamic import for ES Module
    const { notarize } = await import('@electron/notarize');

    const appName = context.packager.appInfo.productFilename;

    return await notarize({
        appBundleId: 'com.yohasebe.monadic',
        appPath: `${appOutDir}/${appName}.app`,
        appleId: process.env.APPLEID,
        appleIdPassword: process.env.APPLEIDPASS,
        ascProvider: process.env.ASCPROVIDER,
        teamId: process.env.TEAMID
    });
};
