// The order of events when the Web UI window is closed, hidden and shown
// while answers run: the controller with a fake window, page channel and
// timers.
const { BackgroundReplyState, NOTICES } = require('../../app/background_reply');
const { createBackgroundReplyController } = require('../../app/background_reply_controller');

function setup({ askToClose = async () => false } = {}) {
  const sent = [];
  const notices = [];
  const applied = [];
  const timers = [];
  const win = {
    destroyed: false,
    hidden: false,
    isDestroyed() { return this.destroyed; },
    isMinimized() { return false; },
    restore: jest.fn(),
    hide: jest.fn(function() { this.hidden = true; }),
    show: jest.fn(function() { this.hidden = false; }),
    focus: jest.fn(),
    destroy: jest.fn(function() { this.destroyed = true; }),
    close: jest.fn()
  };
  const state = new BackgroundReplyState();
  const asked = jest.fn(askToClose);
  const controller = createBackgroundReplyController({
    state,
    getWindow: () => (win.destroyed ? null : win),
    send: (channel, payload) => sent.push([channel, payload]),
    apply: (a) => applied.push(a),
    setTimer: (fn) => { const t = { fn, cleared: false }; timers.push(t); return t; },
    clearTimer: (t) => { t.cleared = true; },
    askToClose: asked,
    notify: (key, binding) => notices.push([key, binding]),
    closeNotices: jest.fn(),
    menuChanged: jest.fn()
  });
  const hello = controller.onReady();
  const g = hello.generation;
  const last = (channel) => [...sent].reverse().find(([c]) => c === channel);
  const fire = () => timers.filter(t => !t.cleared).forEach((t) => { t.cleared = true; t.fn(); });
  const muted = () => applied[applied.length - 1].muted;
  // Close, and the page answers the query with its work as of now.
  const closeWith = (work) => {
    const allowed = controller.onClose();
    if (allowed) return 'closed';
    const [, { op }] = last('background-reply:query');
    controller.onState(Object.assign({ generation: g, op }, work));
    return 'asked';
  };
  const ackHold = () => controller.onHeld({ generation: g, op: last('background-reply:hold')[1].op });
  return { controller, state, win, sent, notices, timers, g, last, fire, muted, closeWith, ackHold, asked };
}

describe('background reply controller', () => {
  test('closing with nothing running asks the page first, then closes the window as before', () => {
    const t = setup();
    t.closeWith({ running: 0, pending: 0, media: false });
    expect(t.win.close).toHaveBeenCalledTimes(1);
    // The close that follows goes through.
    expect(t.controller.onClose()).toBe(true);
  });

  test('a message sent a moment ago keeps the window: the page counts it when asked', () => {
    const t = setup();
    // The page's last report said nothing runs; the send was just now.
    t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: false });
    t.closeWith({ running: 0, pending: 1, media: false });
    expect(t.win.close).not.toHaveBeenCalled();
    expect(t.last('background-reply:hold')).toBeTruthy();
    expect(t.muted()).toBe(true);
    t.ackHold();
    expect(t.win.hide).toHaveBeenCalled();
    expect(t.state.hidden).toBe(true);
  });

  test('an answer running when the window was closed and ending before the page answers keeps the window', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g, running: 1, pending: 0, media: false });
    expect(t.controller.onClose()).toBe(false);
    const [, { op }] = t.last('background-reply:query');
    t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome: 'done' });
    t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: false });
    t.controller.onState({ generation: t.g, op, running: 0, pending: 0, media: false });
    expect(t.win.close).not.toHaveBeenCalled();
    expect(t.last('background-reply:hold')).toBeTruthy();
    t.ackHold();
    expect(t.notices).toEqual([[NOTICES.done, { generation: t.g }]]);
  });

  test.each(['done', 'no_reply', 'lost'])(
    'work reported only after the close that ends (%s) before the page answers keeps the window',
    (outcome) => {
      const t = setup();
      // main still has the page as idle when the close comes.
      expect(t.controller.onClose()).toBe(false);
      const [, { op }] = t.last('background-reply:query');
      t.controller.onReport({ generation: t.g, running: 0, pending: 1, media: false });
      t.controller.onReport({ generation: t.g, running: 1, pending: 0, media: false });
      t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome });
      t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: false });
      t.controller.onState({ generation: t.g, op, running: 0, pending: 0, media: false });
      expect(t.win.close).not.toHaveBeenCalled();
      t.ackHold();
      expect(t.notices.length).toBe(1);
    }
  );

  test('a close with no work and nothing ending meanwhile still closes', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
    const [, { op }] = t.last('background-reply:query');
    t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: false });
    t.controller.onState({ generation: t.g, op, running: 0, pending: 0, media: false });
    expect(t.win.close).toHaveBeenCalledTimes(1);
    expect(t.notices).toEqual([]);
  });

  test('showing the window while the page is asked gives the page back its sending', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
    t.controller.show();
    expect(t.last('background-reply:release')).toBeTruthy();
    const [, { op }] = t.last('background-reply:query');
    t.controller.onState({ generation: t.g, op, running: 0, pending: 0, media: false });
    expect(t.win.close).not.toHaveBeenCalled();
  });

  test('the microphone in use closes the window even during an answer', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: true });
    expect(t.win.close).toHaveBeenCalled();
    expect(t.last('background-reply:hold')).toBeUndefined();
  });

  test('an answer that ends before the page confirms the hold is noticed once hidden', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome: 'done' });
    expect(t.notices).toEqual([]);
    t.ackHold();
    expect(t.notices).toEqual([[NOTICES.done, { generation: t.g }]]);
  });

  test('showing the window during a hold gives the page back what it stopped, muted until it confirms', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    const holdOp = t.last('background-reply:hold')[1].op;
    t.controller.show();
    const release = t.last('background-reply:release');
    expect(release).toBeTruthy();
    expect(release[1].op).not.toBe(holdOp);
    expect(t.muted()).toBe(true);
    // The late confirmation of the hold no longer hides anything.
    t.controller.onHeld({ generation: t.g, op: holdOp });
    expect(t.win.hide).not.toHaveBeenCalled();
    t.controller.onReleased({ generation: t.g, op: release[1].op });
    expect(t.muted()).toBe(false);
  });

  test('a hidden window shown again stays muted, however long, until the page confirms', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    t.ackHold();
    t.controller.show();
    t.fire();
    expect(t.muted()).toBe(true);
    const release = t.last('background-reply:release');
    t.controller.onReleased({ generation: t.g, op: release[1].op - 1 });
    expect(t.muted()).toBe(true);
    t.controller.onReleased({ generation: t.g, op: release[1].op });
    expect(t.muted()).toBe(false);
  });

  test('a hold not confirmed in time keeps the window shown, gives the page back, and asks', async () => {
    const t = setup({ askToClose: async () => false });
    t.closeWith({ running: 1, pending: 0, media: false });
    t.fire();
    await Promise.resolve();
    expect(t.asked).toHaveBeenCalled();
    expect(t.win.destroy).not.toHaveBeenCalled();
    expect(t.win.hide).not.toHaveBeenCalled();
    expect(t.last('background-reply:release')).toBeTruthy();
  });

  test('the user may close a window whose hold was not confirmed', async () => {
    const t = setup({ askToClose: async () => true });
    t.closeWith({ running: 1, pending: 0, media: false });
    t.fire();
    await Promise.resolve();
    await Promise.resolve();
    expect(t.win.destroy).toHaveBeenCalled();
  });

  test('a query not answered in time keeps the window, gives the page back its sending, and asks', async () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
    t.fire();
    await Promise.resolve();
    expect(t.asked).toHaveBeenCalled();
    expect(t.win.close).not.toHaveBeenCalled();
    expect(t.last('background-reply:release')).toBeTruthy();
  });

  test('a page being replaced during a hold: the old confirmation does nothing', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    const holdOp = t.last('background-reply:hold')[1].op;
    t.controller.pageNavigating();
    const next = t.controller.onReady().generation;
    t.controller.onHeld({ generation: t.g, op: holdOp });
    t.controller.onHeld({ generation: next, op: holdOp });
    expect(t.win.hide).not.toHaveBeenCalled();
    expect(t.timers.every(x => x.cleared)).toBe(true);
  });

  test('quitting or installing an update closes, also during a hold', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    expect(t.controller.onClose({ updating: true })).toBe(true);
    expect(t.timers.every(x => x.cleared)).toBe(true);
  });

  test('a page that crashed while hidden and waiting gets a notice for the same window', () => {
    const t = setup();
    t.closeWith({ running: 1, pending: 0, media: false });
    t.ackHold();
    t.controller.pageCrashed();
    expect(t.notices).toEqual([['backgroundReplyLost', { generation: null }]]);
    expect(t.controller.noticeStillApplies({ generation: null })).toBe(true);
    expect(t.controller.noticeStillApplies({ generation: t.g })).toBe(false);
  });

  test('the microphone is refused while the window is hidden or being hidden', () => {
    const t = setup();
    expect(t.controller.blocksMedia()).toBe(false);
    t.closeWith({ running: 1, pending: 0, media: false });
    expect(t.controller.blocksMedia()).toBe(true);
    t.ackHold();
    expect(t.controller.blocksMedia()).toBe(true);
  });

  test('hiding from the page link waits for the page too, and not while the microphone is in use', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: true });
    t.controller.hideRequested();
    expect(t.last('background-reply:hold')).toBeUndefined();
    t.controller.onReport({ generation: t.g, running: 0, pending: 0, media: false });
    t.controller.hideRequested();
    expect(t.last('background-reply:hold')).toBeTruthy();
    expect(t.win.hide).not.toHaveBeenCalled();
    t.ackHold();
    expect(t.win.hide).toHaveBeenCalled();
  });

  test('reports from another page are ignored', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g + 1, running: 3, pending: 0, media: false });
    expect(t.state.running).toBe(0);
  });
});
