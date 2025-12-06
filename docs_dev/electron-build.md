# Electron Build Guide

This document covers the build process for the Monadic Chat Electron application across all platforms.

## Build Commands

```bash
# Build for specific platforms
npm run build:mac-arm64   # Mac ARM64 (Apple Silicon)
npm run build:mac-x64     # Mac Intel
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
- `afterSign`: Notarization script (`scripts/notarize.js`)

Required environment variables (in `~/.zshrc` or `.env`):
- `APPLEID`: Apple ID email
- `APPLEIDPASS`: App-specific password
- `TEAMID`: Apple Developer Team ID

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
