// What closing, hiding and showing the Web UI window do (see
// background_reply.js for the state it keeps). Everything that touches
// Electron is passed in, so the order of events can be tested on its own;
// main.js passes in the window, the page's channel, timers, the dialog and
// the notices, and checks who sent each message before it gets here.
//
// Closing the window hides it, whatever the page is doing: the conversation
// stays until the user resets it, closes the Web UI from the tray, or quits.
// Each request to the page carries an operation number its reply must name:
//   - hold:    the page stops the microphone, Live and audio; then the
//              window is hidden;
//   - release: the page drops audio queued meanwhile; then the window is
//              unmuted. Without a reply it stays muted.
// A page that does not confirm a hold in time keeps the window shown, and
// the user is asked whether to close it.

const WAIT_MS = 2000;

function createBackgroundReplyController(deps) {
  const {
    state, // BackgroundReplyState
    getWindow, // () => the Web UI window, or null
    send, // (channel, payload) => to the page
    apply, // ({ muted, throttle }) => sound and throttling of the window
    setTimer = setTimeout,
    clearTimer = clearTimeout,
    askToClose, // (win) => Promise<boolean>: close the window now?
    notify, // (noticeKey, binding) => show a notice
    closeNotices, // () => close the notices shown
    menuChanged = () => {}
  } = deps;
  const waitMs = deps.waitMs || WAIT_MS;

  let op = 0;
  let hold = null; // { op, generation, timer }
  let release = null; // { op, generation }

  function windowAlive() {
    const win = getWindow();
    return win && !win.isDestroyed() ? win : null;
  }

  function refresh() {
    if (!windowAlive()) return;
    apply({ muted: state.hidden || !!hold || !!release, throttle: state.throttlingAllowed() });
  }

  function nextOp() {
    op += 1;
    return op;
  }

  function stopTimer(pending) {
    if (pending && pending.timer) clearTimer(pending.timer);
  }

  // The page stays (it is shown again, or the user keeps it): what a hold
  // may have stopped is given back, under a new operation.
  function releasePage() {
    const win = windowAlive();
    if (!win) return;
    release = { op: nextOp(), generation: state.generation };
    refresh();
    send('background-reply:release', { op: release.op });
  }

  function cancelHold({ pageStays }) {
    if (!hold) return;
    stopTimer(hold);
    hold = null;
    state.endHold(false);
    if (pageStays) releasePage();
    refresh();
  }

  // The page is going away (navigation, crash, the window closed, quitting):
  // nothing pending applies to it any more.
  function forgetPage() {
    cancelHold({ pageStays: false });
    release = null;
  }

  function answers(pending, info) {
    return !!(pending && info && info.op === pending.op && info.generation === pending.generation &&
      state.accepts(info.generation));
  }

  async function notAnswered(win) {
    if (win.isDestroyed()) return;
    const close = await askToClose(win);
    if (close && !win.isDestroyed()) win.destroy();
  }

  function startHold(win) {
    hold = { op: nextOp(), generation: state.generation };
    const mine = hold.op;
    hold.timer = setTimer(() => {
      if (!hold || hold.op !== mine) return;
      cancelHold({ pageStays: true });
      notAnswered(win);
    }, waitMs);
    state.startHold();
    refresh();
    send('background-reply:hold', { op: mine });
  }

  function hideWindow() {
    const win = windowAlive();
    if (!win || hold || state.hidden) return;
    // A page that is not ready yet has nothing open to stop; it is held when
    // it says it is ready.
    if (state.generation === null) {
      state.hidden = true;
      refresh();
      win.hide();
      menuChanged();
      return;
    }
    startHold(win);
  }

  return {
    // The window's close event. Returns true to let it close, false to keep
    // it (the caller then prevents the default).
    onClose({ quitting = false, updating = false } = {}) {
      if (quitting || updating) {
        forgetPage();
        return true;
      }
      if (!windowAlive()) return true;
      hideWindow();
      return false;
    },

    // Hide from the page's own link (monadic://hide-browser): the same as
    // closing.
    hideRequested() {
      if (windowAlive()) hideWindow();
    },

    onHeld(info) {
      if (!answers(hold, info)) return;
      stopTimer(hold);
      const generation = hold.generation;
      hold = null;
      const kept = state.endHold(true);
      refresh();
      const win = windowAlive();
      if (win) win.hide();
      menuChanged();
      kept.forEach(notice => notify(notice, { generation }));
    },

    onReleased(info) {
      if (!answers(release, info)) return;
      release = null;
      refresh();
    },

    // From the tray, a notice, or opening the Web UI again.
    show() {
      const win = windowAlive();
      if (!win) return;
      closeNotices();
      cancelHold({ pageStays: true });
      if (state.hidden) {
        state.hidden = false;
        releasePage();
        menuChanged();
      }
      if (win.isMinimized()) win.restore();
      win.show();
      win.focus();
    },

    onReady() {
      const generation = state.newGeneration();
      refresh();
      return { generation, held: state.hidden };
    },

    onReport(info) {
      if (!info || !state.accepts(info.generation)) return;
      state.report(info);
      refresh();
    },

    onFinished(info) {
      if (!info || !state.accepts(info.generation)) return;
      const notice = state.noticeFor(info);
      if (notice) notify(notice, { generation: state.generation });
    },

    pageNavigating() {
      forgetPage();
      state.pageGone();
      closeNotices();
      refresh();
    },

    pageCrashed() {
      const wasWaiting = state.hidden && state.busy();
      forgetPage();
      state.pageGone();
      refresh();
      // Not tied to a page: it shows the same window, whatever it holds now.
      if (wasWaiting) notify('backgroundReplyLost', { generation: null });
    },

    windowClosed() {
      forgetPage();
      state.reset();
      closeNotices();
      menuChanged();
    },

    // Whether a notice made for `binding` may show the window now.
    noticeStillApplies(binding) {
      return !!binding && (binding.generation === null || binding.generation === state.generation);
    },

    blocksMedia() {
      return state.hidden || !!hold;
    }
  };
}

module.exports = { createBackgroundReplyController, WAIT_MS };
