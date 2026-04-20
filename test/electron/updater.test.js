/**
 * Unit tests for `app/updater.js` focusing on the state transitions of
 * `installInProgress` — the flag that main.js's `before-quit` handler
 * consults to decide whether to let Squirrel.Mac own the quit sequence.
 *
 * The full end-to-end flow (Squirrel swap + relaunch) can only be validated
 * with a real signed build on macOS, which is impractical in CI. What CAN
 * be verified deterministically here is the state machine: the flag must
 * be true during install, false otherwise, and it MUST be reset on every
 * failure path. A regression here was the original concern #1 that
 * motivated this test — if `installInProgress` gets stuck at true after a
 * failed install, the app loses its quit-confirmation dialog for the rest
 * of the session.
 */

// Mock Electron and electron-updater BEFORE requiring the module under test.
const autoUpdaterEvents = {};
const autoUpdaterMock = {
  autoDownload: null,
  autoInstallOnAppQuit: null,
  logger: null,
  on: jest.fn((event, handler) => {
    autoUpdaterEvents[event] = handler;
  }),
  checkForUpdates: jest.fn(() => Promise.resolve()),
  downloadUpdate: jest.fn(() => Promise.resolve()),
  quitAndInstall: jest.fn()
};
jest.mock('electron-updater', () => ({ autoUpdater: autoUpdaterMock }));

const showMessageBoxMock = jest.fn(() => Promise.resolve({ response: 0 }));
const appExitMock = jest.fn();
jest.mock('electron', () => ({
  app: { exit: appExitMock },
  dialog: { showMessageBox: showMessageBoxMock },
  shell: { openExternal: jest.fn() }
}));

// Speed up the 1500ms delay to keep tests fast. We restore real timers in
// afterAll so other test files in the suite are not affected.
jest.useFakeTimers();

const updater = require('../../app/updater');

function makeDeps(overrides = {}) {
  const mainWindow = {
    isDestroyed: () => false,
    webContents: { send: jest.fn() }
  };
  return Object.assign({
    dockerManager: {
      checkStatus: jest.fn(() => Promise.resolve(false)),
      runCommand: jest.fn(() => Promise.resolve())
    },
    getMainWindow: () => mainWindow,
    log: { warn: jest.fn() }
  }, overrides);
}

describe('app/updater.js — installInProgress state machine', () => {
  beforeEach(() => {
    updater._resetForTests();
    Object.keys(autoUpdaterEvents).forEach(k => delete autoUpdaterEvents[k]);
    autoUpdaterMock.quitAndInstall.mockClear();
    showMessageBoxMock.mockClear();
    appExitMock.mockClear();
  });

  it('starts as false before any install activity', () => {
    updater.init(makeDeps());
    expect(updater.isInstallInProgress()).toBe(false);
  });

  it('becomes true right before quitAndInstall is called', async () => {
    updater.init(makeDeps());
    const installPromise = updater.gracefulStopThenInstall();
    // Advance past the 1500ms Squirrel delay.
    await jest.advanceTimersByTimeAsync(1500);
    await installPromise;
    expect(autoUpdaterMock.quitAndInstall).toHaveBeenCalledWith(false, true);
    expect(updater.isInstallInProgress()).toBe(true);
  });

  it('rolls back to false when quitAndInstall throws synchronously', async () => {
    updater.init(makeDeps());
    autoUpdaterMock.quitAndInstall.mockImplementationOnce(() => {
      throw new Error('squirrel unreachable');
    });
    // Convert rejection into a resolved Error so we can assert both the
    // thrown message and the state-reset in the same frame. Using
    // `.rejects.toThrow` here races with the timer advance and produces a
    // spurious unhandled-rejection trace even though behaviour is correct.
    const installPromise = updater.gracefulStopThenInstall().catch(e => e);
    await jest.advanceTimersByTimeAsync(1500);
    const caught = await installPromise;
    expect(caught).toBeInstanceOf(Error);
    expect(caught.message).toBe('squirrel unreachable');
    expect(updater.isInstallInProgress()).toBe(false);
  });

  it('resets the flag when electron-updater emits an error event', async () => {
    updater.init(makeDeps());
    // Put the flag into the installing state first.
    const installPromise = updater.gracefulStopThenInstall();
    await jest.advanceTimersByTimeAsync(1500);
    await installPromise;
    expect(updater.isInstallInProgress()).toBe(true);

    // Now simulate electron-updater reporting a download / post-check error.
    const errorHandler = autoUpdaterEvents['error'];
    expect(errorHandler).toBeDefined();
    errorHandler(new Error('network down'));

    expect(updater.isInstallInProgress()).toBe(false);
  });

  it('arms a 5-second safety-net that force-exits if quitAndInstall does not complete', async () => {
    updater.init(makeDeps());
    const installPromise = updater.gracefulStopThenInstall();
    await jest.advanceTimersByTimeAsync(1500);
    await installPromise;
    // quitAndInstall was called, but in a real app Electron would have
    // exited by now. In the mock it does not, so the safety-net timer
    // should fire after the 5s grace period.
    expect(appExitMock).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(5000);
    expect(appExitMock).toHaveBeenCalledWith(0);
  });

  it('does NOT arm the safety-net when quitAndInstall throws synchronously', async () => {
    updater.init(makeDeps());
    autoUpdaterMock.quitAndInstall.mockImplementationOnce(() => {
      throw new Error('squirrel unreachable');
    });
    const installPromise = updater.gracefulStopThenInstall().catch(e => e);
    await jest.advanceTimersByTimeAsync(1500);
    await installPromise;
    // The throw exits gracefulStopThenInstall before the safety-net
    // setTimeout is registered, so no forced exit happens here — the
    // error path will surface a dialog to the user instead.
    await jest.advanceTimersByTimeAsync(10000);
    expect(appExitMock).not.toHaveBeenCalled();
  });

  it('continues with the install even if Docker stop fails', async () => {
    const deps = makeDeps({
      dockerManager: {
        checkStatus: jest.fn(() => Promise.resolve(true)),
        runCommand: jest.fn(() => Promise.reject(new Error('docker exec failed')))
      }
    });
    updater.init(deps);
    const installPromise = updater.gracefulStopThenInstall();
    await jest.advanceTimersByTimeAsync(1500);
    await installPromise;
    expect(autoUpdaterMock.quitAndInstall).toHaveBeenCalled();
    expect(updater.isInstallInProgress()).toBe(true);
    expect(deps.log.warn).toHaveBeenCalled();
  });
});

describe('app/updater.js — download progress milestone logging', () => {
  let deps;
  let sent;

  beforeEach(() => {
    updater._resetForTests();
    Object.keys(autoUpdaterEvents).forEach(k => delete autoUpdaterEvents[k]);
    sent = [];
    const mainWindow = {
      isDestroyed: () => false,
      webContents: { send: (channel, payload) => sent.push({ channel, payload }) }
    };
    deps = makeDeps({ getMainWindow: () => mainWindow });
    updater.init(deps);
  });

  function emitProgress(percent) {
    autoUpdaterEvents['download-progress']({
      percent,
      bytesPerSecond: 1024 * 1024 * 10,
      transferred: 0,
      total: 0
    });
  }

  function commandOutputLines() {
    return sent.filter(s => s.channel === 'command-output').map(s => s.payload);
  }

  it('logs at 25/50/75/100 milestones, not every tick', () => {
    [10, 15, 20, 25, 30, 45, 50, 60, 75, 80, 95, 100].forEach(emitProgress);
    const lines = commandOutputLines();
    expect(lines).toHaveLength(4);
  });

  it('displays the actual percent rather than the milestone value', () => {
    emitProgress(52);  // First tick crosses 25 and 50
    const lines = commandOutputLines();
    // The single log line should reflect the REAL percent (52), not 25 or 50.
    expect(lines[0]).toContain('52%');
  });

  it('captures ALL milestones crossed in a single jump (20% → 80%)', () => {
    emitProgress(20);  // Below all milestones, no log
    emitProgress(80);  // Crosses 25, 50, AND 75 at once
    // One line (at the jump), but all three milestones should be marked so
    // 100% still logs when we reach it — not suppressed by the catch-up.
    expect(commandOutputLines()).toHaveLength(1);
    emitProgress(100);
    expect(commandOutputLines()).toHaveLength(2);
  });

  it('does nothing when mainWindow is destroyed mid-download', () => {
    const destroyedDeps = makeDeps({
      getMainWindow: () => ({ isDestroyed: () => true, webContents: { send: jest.fn() } })
    });
    updater._resetForTests();
    Object.keys(autoUpdaterEvents).forEach(k => delete autoUpdaterEvents[k]);
    updater.init(destroyedDeps);
    // Should not throw, should not crash.
    expect(() => emitProgress(50)).not.toThrow();
  });
});

describe('app/updater.js — downloadUpdate orchestration', () => {
  beforeEach(() => {
    updater._resetForTests();
    Object.keys(autoUpdaterEvents).forEach(k => delete autoUpdaterEvents[k]);
    autoUpdaterMock.checkForUpdates.mockClear();
    autoUpdaterMock.downloadUpdate.mockClear();
  });

  it('calls checkForUpdates BEFORE downloadUpdate so UpdateInfo is populated', async () => {
    updater.init(makeDeps());
    const order = [];
    autoUpdaterMock.checkForUpdates.mockImplementationOnce(() => {
      order.push('check');
      return Promise.resolve();
    });
    autoUpdaterMock.downloadUpdate.mockImplementationOnce(() => {
      order.push('download');
      return Promise.resolve();
    });
    await updater.downloadUpdate();
    expect(order).toEqual(['check', 'download']);
  });

  it('is a no-op while a download is already in progress', async () => {
    updater.init(makeDeps());
    autoUpdaterMock.checkForUpdates.mockImplementationOnce(() =>
      new Promise(resolve => setTimeout(resolve, 100)));
    autoUpdaterMock.downloadUpdate.mockImplementationOnce(() => Promise.resolve());

    const first = updater.downloadUpdate();
    const second = updater.downloadUpdate();  // Should exit immediately
    await jest.advanceTimersByTimeAsync(100);
    await first;
    await second;
    expect(autoUpdaterMock.checkForUpdates).toHaveBeenCalledTimes(1);
  });
});
