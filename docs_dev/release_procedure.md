# Release Procedure (Internal)

Authoritative, reproducible steps for cutting a Monadic Chat release. This
replaces the ad-hoc notes that previously lived only in a maintainer's head /
personal memory. It has been followed without incident for beta.24–beta.27.

> Audience: maintainers with push access and a configured macOS signing +
> notarization environment. Not user-facing.

## 0. Prerequisites

- macOS on Apple Silicon (the only supported build host for the mac artifact).
- `gh` CLI installed and authenticated (`gh auth status`).
- Apple notarization credentials configured (see `docs_dev/notarize-dmg-fix-2026-04.md`).
- Windows Authenticode signing runs automatically during `rake build` via a
  Parallels Windows VM (electron-builder's `win.signtoolOptions` points at the
  cert in the VM's store; a VM window opens on its own while signing). The mac
  host drives mac + linux + the VM-signed win artifacts — no separate manual
  Windows step. Verify after building (see §8). See `docs_dev/electron-build.md`.
- A clean working tree on the branch you intend to release from (usually `dev`).

## 1. Bump the version (single source of truth)

Version lives in **`docker/services/ruby/lib/monadic/version.rb`** (`VERSION = "..."`)
and must be mirrored in **`package.json`**, **`package-lock.json`** (root
`version` and `packages[""].version`), and **`CITATION.cff`** (`version` +
`date-released`). `docker/monadic.sh` reads `version.rb` at runtime, so no
manual edit there.

`rake update_version[<old>,<new>]` bumps `version.rb` + `package.json`, but be
aware of two caveats and prefer editing by hand when they apply:
- It does NOT touch `package-lock.json` or `CITATION.cff` — update those
  manually.
- Its CHANGELOG step *relabels* the current-month top entry rather than adding
  a new one. If the top entry is an already-published release, do not use it —
  add a fresh CHANGELOG section by hand (see step 2).

Verify all agree:

```bash
grep 'VERSION = ' docker/services/ruby/lib/monadic/version.rb
node -e "console.log(require('./package.json').version)"
node -e "const p=require('./package-lock.json'); console.log(p.version, p.packages[''].version)"
ruby -ryaml -e "puts YAML.load_file('CITATION.cff')['version']"
```

## 2. CHANGELOG entry

Add the new release's entry to `CHANGELOG.md` in the established
`- [Month, Year] <version>` heading shape (the release task extracts the
section by this exact heading — a bare version mention elsewhere will not be
picked up). Draft material is accumulated in the `pending-changelog-entries`
maintainer memory during the dev cycle; transcribe and then clear it.

## 3. Create the release commit on `main`

`main` must have the **same tree** as the released `dev` tip so the built
artifacts match what is tagged. Use `commit-tree` to guarantee tree identity
rather than a merge (which can introduce drift):

```bash
git commit-tree origin/dev^{tree} -p origin/main -m "Release v<version>"
# → prints a new commit SHA; fast-forward main to it:
git push origin <new-sha>:main
git tag v<version> <new-sha>
git push origin v<version>
```

## 4. Build all platform packages

Run from the project root, **in the foreground** (the build must go through
`setup_build_environment`, which also rebuilds the help database from docs):

```bash
rake build            # builds linux-x64, linux-arm64, win, mac-arm64
```

Notes:
- Each `electron-builder` invocation is passed `--publish never
  -c.generateUpdatesFilesForAllChannels=true`. The channel flag makes a
  prerelease build ALSO emit `latest-*.yml` (not just `beta-*.yml`), which is
  load-bearing for the updater — see §7.
- The task then runs `scripts/repackage_mac_zip.rb` **before** patching
  manifests. This preserves framework symlinks in the mac zip; a flattened
  zip was the beta.19 auto-update breaker. See
  `docs_dev/macos-zip-symlink-autoupdate-bug` (maintainer memory).
- `latest-mac.yml` is mirrored to `latest-mac-arm64.yml` if the arch-specific
  file is absent.

## 5. Notarize + staple (macOS) and patch manifests

After signing/notarization completes, the stapled DMG/zip bytes differ from
what the just-built `latest-*.yml` recorded. Re-sync the manifests, then
validate:

```bash
ruby scripts/patch_release_manifests.rb    # re-computes sha512/size in dist/latest*.yml
ruby scripts/verify_release_manifests.rb   # asserts every yml matches its artifact bytes
xcrun stapler validate "dist/Monadic Chat-<version>-arm64.dmg"
```

Do not skip `verify_release_manifests.rb`: a manifest whose sha512/size does
not match the artifact will make auto-update fail the integrity check on the
user's machine, and that failure is not self-healing (see
`docs_dev/auto-updater-selfheal-lesson`). Note: a notarization log that says
"skipped" is a stapler quirk, not a failure — see
`docs_dev/mac_notarize_skipped_misread` (memory).

## 6. Publish the GitHub release

The 11 expected assets are: 6 binaries (mac dmg + zip, win exe + zip, linux
x64 + arm64 AppImage) and the auto-update manifests
(`latest-mac.yml`, `latest-mac-arm64.yml`, `latest.yml`, `latest-linux.yml`,
`latest-linux-arm64.yml`). The `builder-debug.yml` electron-builder emits is
NOT an asset — exclude it.

```bash
gh release create v<version> <assets...> \
  --title "Monadic Chat <version>" \
  --notes-file <changelog-section>.md \
  [--prerelease]        # SEE §7 — this flag's presence is a release-type decision, not a default
```

`rake release:github[<version>,<prerelease?>,<target>]` automates asset
discovery (exactly the 11 assets — `builder-debug.yml` is excluded) +
`gh release create`, reading the CHANGELOG section for notes. Pass the third
arg `<target>` (a commit SHA) so the tag is created at the exact release
commit instead of the remote default-branch HEAD. Read §7 before choosing the
prerelease argument.

```bash
# Move main to the release tree, then release the same commit:
NEW=$(git commit-tree origin/dev^{tree} -p origin/main -m "Release v<version>")
git push origin "$NEW:main"
rake "release:github[<version>,true,$NEW]"     # true = prerelease (betas); OMIT for v1.0 stable — see §7
```

Ordering note: pushing the new `version.rb` to `main` makes the in-app update
check (which reads `version.rb` from `main`) advertise the new version. If the
GitHub release is not yet published, a user who checks in that window is
offered a download that 404s. Keep the `push main` → `release:github` steps
back-to-back (seconds apart). For a higher-traffic release (v1.0), prefer
publishing the release first (create+push the tag at `$NEW`, run
`release:github`), then fast-forward `main` to `$NEW`.

## 7. Release channel / prerelease flag — READ BEFORE PUBLISHING

**This is the single most consequential decision at publish time, and it has
never been exercised for a stable release.** Every beta (beta.18–beta.27) was
published with `--prerelease`. v1.0.0 must NOT be.

### How the updater actually resolves "latest"

Update detection and download are two separate mechanisms:

1. **Detection** — `app/main.js:checkForUpdatesManual()` fetches `version.rb`
   from the `main` branch (`raw.githubusercontent.com`) and semver-compares it
   to the running app version. This is channel-agnostic: it works for every
   user regardless of prerelease flags. It only decides whether to *offer* an
   update.

2. **Download** — `app/updater.js` calls electron-updater's
   `autoUpdater.checkForUpdates()` + `downloadUpdate()`. electron-updater
   (6.8.9) **auto-derives `allowPrerelease` from the running app's version**
   (`AppUpdater.js`: `this.allowPrerelease = hasPrereleaseComponents(currentVersion)`).
   There is no explicit `allowPrerelease`/`channel` config in this repo — the
   running version alone decides the channel.

That auto-derivation splits users into two paths:

- **On a prerelease version** (e.g. `1.0.0-beta.27`) → `allowPrerelease = true`.
  electron-updater reads the GitHub **atom feed** (which includes prereleases)
  and channel-matches. A beta-channel user WILL accept a newer stable release
  from the feed (verified against `GitHubProvider.getLatestVersion`).
  → **beta.27 → v1.0.0 works whether or not v1.0.0 is flagged prerelease.**

- **On a stable version** (e.g. `1.0.0`) → `allowPrerelease = false`.
  electron-updater resolves via the GitHub API `**/releases/latest**`, which
  returns only the newest **non-prerelease** release.
  → **A stable user only ever sees non-prerelease releases.**

### The consequence for v1.0.0

- **Publish v1.0.0 WITHOUT `--prerelease`.** Then `/releases/latest` returns
  `v1.0.0` and every future stable user resolves updates correctly.
- **If v1.0.0 is mistakenly flagged prerelease**, `/releases/latest` keeps
  returning the current newest non-prerelease release — today that is
  **`v1.0.0-beta.17`** (betas 9–17 were published non-prerelease; 18–27 were
  prerelease). A fresh v1.0.0 install would then have its updater pointed at a
  *downgrade*, which is incoherent and `allowDowngrade` (default false) will
  reject. This breaks the update path for every new stable user and is not
  self-healing.

### After v1.0.0

- Future **stable** releases: publish non-prerelease (so `/releases/latest`
  advances).
- Future **betas** (e.g. `1.0.1-beta.1`): publish with `--prerelease`. Stable
  users won't see them (correct channel separation); beta testers on a beta
  version will (their auto-derived `allowPrerelease = true`).

### First-stable checklist

- [ ] `gh release create` run **without** `--prerelease`
- [ ] `gh api repos/yohasebe/monadic-chat/releases/latest --jq .tag_name`
      returns `v1.0.0` after publishing
- [ ] Real-machine auto-update test from an installed **beta.27** → v1.0.0
      (the beta→stable path) BEFORE announcing — auto-update bugs are not
      self-healing.

## 8. Verify the build before publishing

Run these on the mac host after `rake build`:

```bash
ruby scripts/verify_release_manifests.rb                       # sha512/size match, all one version
xcrun stapler validate "dist/Monadic.Chat-<version>-arm64.dmg" # notarized + stapled
zipinfo "dist/Monadic.Chat-<version>-arm64.zip" | grep -c '^l' # framework symlinks preserved (>0; beta.19 guard)
```

Note: use `zipinfo` (or `ditto`), NOT `unzip -l | grep '->'`, to detect zip
symlinks — `unzip -l` does not show the arrow notation and will read as 0.

Verify Windows signing on the mac host (no `osslsigncode`/`signtool` needed —
parse the PE certificate table; a non-empty Security directory = signed):

```bash
python3 - "dist/Monadic.Chat.Setup.<version>.exe" <<'PY'
import sys,struct
d=open(sys.argv[1],'rb').read(); pe=struct.unpack_from('<I',d,0x3C)[0]
opt=pe+24; p=struct.unpack_from('<H',d,opt)[0]==0x20b; dd=opt+(112 if p else 96)
off,size=struct.unpack_from('<II',d,dd+32)
print("SIGNED" if size>0 and b'Yoichiro Hasebe' in d[off:off+size] else "NOT SIGNED", "cert bytes:", size)
PY
```

## 9. Post-publish verification

- Real-machine smoke test of the packaged build: launch → containers start →
  one round-trip chat per provider → quit → all containers stop (the standard
  3-point smoke, see `release-packaged-smoke-checklist` memory).
- Confirm the 11 assets are attached and manifests validate against them.
- `ghcr` service images are pulled as `:latest` and are unchanged across most
  releases, so no separate publish is needed unless a service Dockerfile
  changed.

## Related references

- `docs_dev/electron-build.md` — build environment, Windows signing on Parallels
- `docs_dev/notarize-dmg-fix-2026-04.md` — notarization setup
- `docs_dev/docker-build-caching.md` — container build/caching behavior
- Maintainer memories: `release-beta27-2026-07-10`, `macos-zip-symlink-autoupdate-bug`,
  `auto-updater-selfheal-lesson`, `release-manifest-drift`, `mac_notarize_skipped_misread`
