# Electron Build Guide

This document covers the build process for the Monadic Chat Electron application across all platforms.

## Build Commands

```bash
# Build for specific platforms
npm run build:mac-arm64   # Mac ARM64 (Apple Silicon) - Intel Mac not supported
npm run build:win         # Windows x64
npm run build:linux-arm64 # Linux ARM64
npm run build:linux-x64   # Linux x64

# Build all platforms (via Rake)
rake build                # All platforms
rake build:mac_arm64      # Mac ARM64 only
rake build:win            # Windows only
```

## Windows Build on ARM64 Mac (Parallels)

When building Windows packages from an ARM64 Mac using Parallels Desktop, you may encounter a signtool.exe path error:

```
Exit code: 2. Command failed: prlctl exec ... arm64\signtool.exe
```

### Cause

electron-builder determines the signtool.exe path based on the **host** CPU architecture (ARM64), but the winCodeSign package only includes `x64` and `ia32` versions of signtool.exe, not `arm64`.

### Solution

Create a copy of the `x64` folder as `arm64` in the winCodeSign cache:

```bash
cd ~/Library/Caches/electron-builder/winCodeSign/winCodeSign-2.6.0/windows-10
cp -r x64 arm64
```

**Important Notes:**
- A **symlink** (`ln -s x64 arm64`) does NOT work because Parallels VM accesses files via `\\Mac\Host\...` network path, which doesn't resolve symlinks correctly.
- This is a one-time setup per development machine.
- If the winCodeSign cache is deleted (e.g., during troubleshooting), you need to recreate the `arm64` folder after the next build attempt downloads winCodeSign again.

### Verification

After creating the `arm64` folder, verify the structure:

```bash
ls -la ~/Library/Caches/electron-builder/winCodeSign/winCodeSign-2.6.0/windows-10/
# Should show: arm64, ia32, x64 (all directories)
```

## Code Signing

### macOS

macOS code signing is configured via:
- `build.mac.hardenedRuntime`: true
- `build.mac.entitlements`: Entitlements plist file
- `afterSign`: Notarization script for the `.app` (`scripts/notarize.js`)
- `afterAllArtifactBuild`: Notarization script for the DMG (`scripts/notarize-dmg.js`)
- `build.dmg.sign`: true — the DMG is signed too; Gatekeeper judges a disk image by its own signature (`spctl --context context:primary-signature`)


Notarization credentials, read by both scripts through `scripts/notarize_credentials.js`:
- **`NOTARY_PROFILE`** (in `~/.zshrc`): the name of a notarytool keychain profile. Create it once with `xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>` and enter the app-specific password at its prompt; notarytool then reads the password from the keychain, so it never passes through the build's environment or a command line. The same variable and profile can be shared with other projects on the build machine. **When the app-specific password is regenerated, run `store-credentials` again**, or notarization fails (and a release build stops).
- `APPLEID`, `APPLEIDPASS`, `TEAMID`: accepted only for builds that are not release builds, for compatibility. `@electron/notarize` passes the password to notarytool as a command-line argument, visible to other processes of the same user while it runs. A value of `APPLEIDPASS` that is a 1Password reference (`op://…`) is not read and counts as missing.

`rake build`, `rake build:*` and `rake release:github` set `MONADIC_RELEASE_BUILD=1`. A release build requires `NOTARY_PROFILE` and stops without it; other builds (e.g. `npx electron-builder` run directly) warn and skip notarization. After packaging and again before publishing, `scripts/verify_mac_notarization.rb` checks the DMG (`xcrun stapler validate`, `spctl -a -t open --context context:primary-signature`) and the `.app` in the update zip (`xcrun stapler validate`, `spctl -a -t exec`), and stops the build or the release on any failure.

### Windows

Windows code signing uses a certificate from the Windows Certificate Store (accessed via Parallels):
- `certificateSubjectName`: Certificate subject name
- `certificateSha1`: Certificate thumbprint

The certificate must be installed in the Windows VM's certificate store.

## Troubleshooting

### Build Hangs or Fails Silently

1. Check Docker Desktop is running
2. Verify Parallels VM is running (for Windows builds)
3. Check Parallels "Share folders" is set to "All Disks"

### Windows Signing Fails with Exit Code 2

1. Ensure the `arm64` folder exists (see above)
2. Verify the certificate is installed in the Windows VM
3. Check Parallels VM connectivity

### macOS Notarization Fails

1. Verify Apple credentials are correct
2. Check the app bundle is properly signed
3. Review notarization logs for specific errors
