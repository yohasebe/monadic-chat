// The order of events when the Web UI window is closed (hidden) and shown:
// the controller with a fake window, page channel and timers.
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
  const ackHold = () => controller.onHeld({ generation: g, op: last('background-reply:hold')[1].op });
  // Close, and the page confirms it stopped what it had.
  const closeAndHide = () => {
    expect(controller.onClose()).toBe(false);
    ackHold();
  };
  return { controller, state, win, sent, notices, timers, g, last, fire, muted, ackHold, closeAndHide, asked };
}

describe('background reply controller', () => {
  test('closing with nothing running hides the window too: the conversation stays', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
    expect(t.last('background-reply:hold')).toBeTruthy();
    expect(t.muted()).toBe(true);
    expect(t.win.hide).not.toHaveBeenCalled();
    t.ackHold();
    expect(t.win.hide).toHaveBeenCalledTimes(1);
    expect(t.win.close).not.toHaveBeenCalled();
    expect(t.win.destroy).not.toHaveBeenCalled();
    expect(t.state.hidden).toBe(true);
    expect(t.notices).toEqual([]);
  });

  test('closing during an answer hides the window, and its end is noticed', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g, running: 1, pending: 0 });
    t.closeAndHide();
    t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome: 'done' });
    expect(t.notices).toEqual([[NOTICES.done, { generation: t.g }]]);
  });

  test.each(['done', 'no_reply', 'lost'])(
    'an answer main did not know about that ends (%s) before the page confirms the hold is noticed once hidden',
    (outcome) => {
      const t = setup();
      expect(t.controller.onClose()).toBe(false);
      t.controller.onReport({ generation: t.g, running: 1, pending: 0 });
      t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome });
      expect(t.notices).toEqual([]);
      t.ackHold();
      expect(t.notices.length).toBe(1);
    }
  );

  test('an answer that ended while the window was shown gets no notice later', () => {
    const t = setup();
    t.controller.onFinished({ generation: t.g, requestId: 'r1', outcome: 'done' });
    t.closeAndHide();
    expect(t.notices).toEqual([]);
  });

  test('closing a window that is already hidden or being hidden changes nothing', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
    const holds = t.sent.filter(([c]) => c === 'background-reply:hold').length;
    expect(t.controller.onClose()).toBe(false);
    t.ackHold();
    expect(t.controller.onClose()).toBe(false);
    expect(t.sent.filter(([c]) => c === 'background-reply:hold').length).toBe(holds);
  });

  test('a page that is not ready yet is hidden at once and held when it says it is ready', () => {
    const t = setup();
    t.controller.pageNavigating();
    expect(t.controller.onClose()).toBe(false);
    expect(t.win.hide).toHaveBeenCalledTimes(1);
    expect(t.last('background-reply:hold')).toBeUndefined();
    expect(t.controller.onReady().held).toBe(true);
  });

  test('showing the window during a hold gives the page back what it stopped, muted until it confirms', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
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
    t.closeAndHide();
    t.controller.show();
    expect(t.win.show).toHaveBeenCalled();
    expect(t.state.hidden).toBe(false);
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
    expect(t.controller.onClose()).toBe(false);
    t.fire();
    await Promise.resolve();
    expect(t.asked).toHaveBeenCalled();
    expect(t.win.destroy).not.toHaveBeenCalled();
    expect(t.win.hide).not.toHaveBeenCalled();
    expect(t.last('background-reply:release')).toBeTruthy();
  });

  test('the user may close a window whose hold was not confirmed', async () => {
    const t = setup({ askToClose: async () => true });
    expect(t.controller.onClose()).toBe(false);
    t.fire();
    await Promise.resolve();
    await Promise.resolve();
    expect(t.win.destroy).toHaveBeenCalled();
  });

  test('a page being replaced during a hold: the old confirmation does nothing', () => {
    const t = setup();
    expect(t.controller.onClose()).toBe(false);
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
    expect(t.controller.onClose()).toBe(false);
    expect(t.controller.onClose({ updating: true })).toBe(true);
    expect(t.timers.every(x => x.cleared)).toBe(true);
    expect(t.controller.onClose({ quitting: true })).toBe(true);
  });

  test('a page that crashed while hidden and waiting gets a notice for the same window', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g, running: 1, pending: 0 });
    t.closeAndHide();
    t.controller.pageCrashed();
    expect(t.notices).toEqual([['backgroundReplyLost', { generation: null }]]);
    expect(t.controller.noticeStillApplies({ generation: null })).toBe(true);
    expect(t.controller.noticeStillApplies({ generation: t.g })).toBe(false);
  });

  test('the microphone is refused while the window is hidden or being hidden', () => {
    const t = setup();
    expect(t.controller.blocksMedia()).toBe(false);
    expect(t.controller.onClose()).toBe(false);
    expect(t.controller.blocksMedia()).toBe(true);
    t.ackHold();
    expect(t.controller.blocksMedia()).toBe(true);
    t.controller.show();
    expect(t.controller.blocksMedia()).toBe(false);
  });

  test('hiding from the page link does the same as closing', () => {
    const t = setup();
    t.controller.hideRequested();
    expect(t.last('background-reply:hold')).toBeTruthy();
    expect(t.win.hide).not.toHaveBeenCalled();
    t.ackHold();
    expect(t.win.hide).toHaveBeenCalled();
  });

  test('reports from another page are ignored', () => {
    const t = setup();
    t.controller.onReport({ generation: t.g + 1, running: 3, pending: 0 });
    expect(t.state.running).toBe(0);
  });
});
