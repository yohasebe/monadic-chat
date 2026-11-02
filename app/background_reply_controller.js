// What closing, hiding and showing the Web UI window do while answers run
// (see background_reply.js for the state it keeps). Everything that touches
// Electron is passed in, so the order of events can be tested on its own;
// main.js passes in the window, the page's channel, timers, the dialog and
// the notices, and checks who sent each message before it gets here.
//
// The page is asked before anything is decided, and each request to it
// carries an operation number its reply must name:
//   - query:   closing asks for the page's current work (a message sent a
//              moment ago counts) before the window is closed or hidden;
//   - hold:    the page stops the microphone and audio; then the window is
//              hidden;
//   - release: the page drops audio queued meanwhile; then the window is
//              unmuted. Without a reply it stays muted.
// A page that does not answer a query or a hold in time keeps the window
// shown, and the user is asked whether to close it.

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
  let query = null; // { op, generation, timer }
  let hold = null; // { op, generation, timer, sent }
  let release = null; // { op, generation }
  let closeApproved = false;

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
    const sent = hold.sent;
    hold = null;
    state.endHold(false);
    if (pageStays && sent) releasePage();
    refresh();
  }

  // pageStays: the page was told it is being closed and keeps sending
  // nothing until it is released.
  function cancelQuery({ pageStays } = { pageStays: false }) {
    if (!query) return;
    stopTimer(query);
    query = null;
    if (!hold) state.endHold(false);
    if (pageStays) releasePage();
  }

  // The page is going away (navigation, crash, the window closed, quitting):
  // nothing pending applies to it any more.
  function forgetPage() {
    cancelQuery();
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

  function closeNow(win) {
    closeApproved = true;
    win.close();
  }

  function startHold(win) {
    hold = { op: nextOp(), generation: state.generation, sent: true };
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

  return {
    // The window's close event. Returns true to let it close, false to keep
    // it (the caller then prevents the default).
    onClose({ quitting = false, updating = false } = {}) {
      if (quitting || updating || closeApproved) {
        closeApproved = false;
        forgetPage();
        return true;
      }
      if (query || hold) return false;
      // A page that is not ready has no answer to keep.
      if (state.generation === null) return true;
      const win = windowAlive();
      if (!win) return true;
      query = { op: nextOp(), generation: state.generation };
      const mine = query.op;
      query.timer = setTimer(() => {
        if (!query || query.op !== mine) return;
        cancelQuery({ pageStays: true });
        notAnswered(win);
      }, waitMs);
      // An answer that ends before the page answers is kept for a notice.
      state.startHold();
      send('background-reply:query', { op: mine });
      return false;
    },

    // The page's answer to a query: its work as of now.
    // Work that ended while the window was being closed keeps the window
    // too (whatever main knew when the close came: a report may arrive after
    // it): its end is noticed once the window is hidden.
    onState(info) {
      if (!answers(query, info)) return;
      stopTimer(query);
      query = null;
      state.report(info);
      refresh();
      const win = windowAlive();
      if (!win) return;
      const endedMeanwhile = state.endedWhileHolding() && !state.media;
      if (state.closeAction() === 'hide' || endedMeanwhile) {
        startHold(win);
      } else {
        state.endHold(false);
        closeNow(win);
      }
    },

    // Hide from the page's own link (monadic://hide-browser): as closing
    // during an answer, also when nothing runs. Not while the microphone is
    // in use, nor before the page is ready.
    hideRequested() {
      const win = windowAlive();
      if (!win || query || hold || state.hidden || state.media || state.generation === null) return;
      startHold(win);
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
      cancelQuery({ pageStays: true });
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
      closeApproved = false;
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
