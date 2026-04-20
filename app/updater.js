// electron-updater wiring for Monadic Chat
//
// Design notes:
// - autoDownload is disabled; downloads are explicitly initiated by the user
//   from the "Download & Install" dialog button.
// - autoInstallOnAppQuit is disabled; we drive quitAndInstall ourselves so
//   Docker containers can be stopped gracefully before the Electron process
//   exits. Without this, the new Electron process may start before the old
//   Ruby / PGVector containers finish shutting down, causing port conflicts
//   on reboot.
// - Progress is forwarded to the renderer so the UI can show a progress bar.
//
// IMPORTANT: This module is a thin wrapper. Update detection continues to
// run through checkForUpdatesManual() in main.js (which reads version.rb
// from main branch). This module takes over once the user chooses to
// download, and handles the download + Docker stop + restart sequence.

const { autoUpdater } = require('electron-updater');
const { dialog, shell } = require('electron');

let deps = null;
let downloadInProgress = false;
// Set to true once gracefulStopThenInstall enters the quitAndInstall path.
// main.js's `before-quit` handler checks this via isInstallInProgress() and
// skips its quit-confirmation/force-exit flow; letting Squirrel.Mac own the
// full quit-swap-relaunch sequence is the only way the new version actually
// launches on macOS. When the interception was active, Squirrel's helper
// saw our forced `app.exit(0)` instead of a normal Electron quit and its
// relaunch step picked up the pre-swap binary.
let installInProgress = false;
// Progress-line throttling: we only append a human-readable line to the
// command-output panel at 25/50/75/100% milestones so the UI doesn't fill
// with a dozen near-identical rows. The structured `update-download-progress`
// event still fires on every tick for any future progress-bar widget.
const PROGRESS_MILESTONES = [25, 50, 75, 100];
let loggedMilestones = new Set();

function init(injected) {
  deps = injected; // { dockerManager, getMainWindow, log, i18n }

  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = false;

  if (deps && deps.log) {
    autoUpdater.logger = deps.log;
  }

  autoUpdater.on('download-progress', (progress) => {
    const mainWindow = deps.getMainWindow();
    if (!mainWindow || mainWindow.isDestroyed()) return;

    // Structured event (every tick) — any future progress-bar widget can
    // subscribe to this.
    mainWindow.webContents.send('update-download-progress', {
      percent: Math.round(progress.percent),
      bytesPerSecond: progress.bytesPerSecond,
      transferred: progress.transferred,
      total: progress.total
    });

    // Command-output line — throttled to milestone percentages so the log
    // reads cleanly: 25%, 50%, 75%, done. Otherwise users saw ~20 lines of
    // "Downloading update: X%" noise.
    const percent = Math.round(progress.percent);
    const milestone = PROGRESS_MILESTONES.find(m => percent >= m && !loggedMilestones.has(m));
    if (milestone !== undefined) {
      loggedMilestones.add(milestone);
      const mbps = (progress.bytesPerSecond / 1024 / 1024).toFixed(1);
      mainWindow.webContents.send('command-output',
        `[HTML]: <p>Downloading update: ${milestone}% (${mbps} MB/s)</p>`);
    }
  });

  autoUpdater.on('update-downloaded', async (info) => {
    downloadInProgress = false;
    const mainWindow = deps.getMainWindow();

    const result = await dialog.showMessageBox(mainWindow, {
      type: 'info',
      buttons: ['Restart Now', 'Later'],
      defaultId: 0,
      cancelId: 1,
      title: 'Update Ready',
      message: `Monadic Chat ${info.version} is ready to install.`,
      detail: 'The app will stop Docker containers gracefully, then restart to apply the update. Any in-progress conversation will be lost — please finish or save first.'
    });

    if (result.response !== 0) {
      return;
    }

    await gracefulStopThenInstall();
  });

  autoUpdater.on('error', (err) => {
    downloadInProgress = false;
    const mainWindow = deps.getMainWindow();
    const message = err && err.message ? err.message : String(err);

    dialog.showMessageBox(mainWindow, {
      type: 'error',
      buttons: ['Open Releases Page', 'Close'],
      defaultId: 0,
      title: 'Update Error',
      message: 'Automatic update failed',
      detail: `${message}\n\nYou can download the latest version manually from the releases page.`
    }).then((result) => {
      if (result.response === 0) {
        shell.openExternal('https://github.com/yohasebe/monadic-chat/releases');
      }
    });
  });
}

// Start downloading the available update. Returns a promise that resolves
// when the download completes; the update-downloaded handler then prompts
// the user to restart.
//
// NOTE: electron-updater throws "Please check update first" if you call
// downloadUpdate() without first populating its internal UpdateInfo state.
// Our primary version check goes through checkForUpdatesManual() in
// main.js (raw.githubusercontent.com → version.rb compare) and never
// touches electron-updater's state, so we must re-check via the updater
// here before kicking off the download. The call is cheap — a single
// YAML fetch from the GitHub release — and returns the UpdateCheckResult
// we then feed into downloadUpdate().
async function downloadUpdate() {
  if (downloadInProgress) {
    return;
  }
  downloadInProgress = true;
  loggedMilestones = new Set();  // Fresh progress log per download attempt
  try {
    await autoUpdater.checkForUpdates();
    await autoUpdater.downloadUpdate();
  } catch (err) {
    downloadInProgress = false;
    throw err;
  }
}

// Stop Docker containers (waits for completion) before invoking
// quitAndInstall. Called from the "Restart Now" dialog path above, and also
// exposed so callers can trigger the same sequence if they initiated the
// download flow out-of-band.
async function gracefulStopThenInstall() {
  const mainWindow = deps.getMainWindow();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('command-output',
      '[HTML]: <p>Stopping Docker containers before restart . . .</p>');
  }

  try {
    const dockerStatus = await deps.dockerManager.checkStatus();
    if (dockerStatus) {
      // Await the stop so the new process does not start while containers
      // are still shutting down. runCommand returns a promise that resolves
      // once the 'Stopped' status is emitted.
      await deps.dockerManager.runCommand(
        'stop',
        '[HTML]: <p>Stopping Docker containers before restart . . .</p>',
        'Stopping',
        'Stopped'
      );
    }
  } catch (err) {
    // If the stop fails, still proceed with the install — the new process
    // has its own recovery path for leftover containers.
    if (deps.log) {
      deps.log.warn('Docker stop failed before quitAndInstall:', err);
    }
  }

  // macOS-specific reliability: Squirrel.Mac's helper process (which
  // actually swaps the binary and relaunches the app) is spawned right
  // before the Electron main process exits. Our graceful Docker stop
  // leaves transient timers/promises in the event loop that can delay
  // quit just long enough to miss the helper's relaunch window —
  // observed symptom: app quits but does NOT restart. A short delay
  // before quitAndInstall lets Squirrel set up cleanly.
  await new Promise(resolve => setTimeout(resolve, 1500));

  // Signal to main.js's `before-quit` handler that it must let the
  // internal `app.quit()` (called by quitAndInstall) complete normally,
  // rather than intercepting it with the usual confirmation / force-exit
  // flow. Without this, Squirrel.Mac sees `app.exit(0)` instead of a
  // clean quit, and its relaunch step ends up launching the pre-swap
  // binary (the old version).
  installInProgress = true;

  // isSilent = false (let user see the installer on Windows),
  // isForceRunAfter = true (relaunch the new version)
  autoUpdater.quitAndInstall(false, true);
}

function isInstallInProgress() {
  return installInProgress;
}

module.exports = { init, downloadUpdate, gracefulStopThenInstall, isInstallInProgress };
