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

    // Structured event for any future progress-bar UI.
    mainWindow.webContents.send('update-download-progress', {
      percent: Math.round(progress.percent),
      bytesPerSecond: progress.bytesPerSecond,
      transferred: progress.transferred,
      total: progress.total
    });

    // Human-readable line in the existing command-output panel so users
    // can see the download is alive without extra UI work.
    const percent = Math.round(progress.percent);
    const mbps = (progress.bytesPerSecond / 1024 / 1024).toFixed(1);
    mainWindow.webContents.send('command-output',
      `[HTML]: <p>Downloading update: ${percent}% (${mbps} MB/s)</p>`);
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

  // isSilent = false (let user see the installer on Windows),
  // isForceRunAfter = true (relaunch the new version)
  autoUpdater.quitAndInstall(false, true);
}

module.exports = { init, downloadUpdate, gracefulStopThenInstall };
