// Closing the Web UI window during an answer hides it instead, and the answer's
// end gets one fixed notice while the window is hidden.
const { BackgroundReplyState, NOTICES } = require('../../app/background_reply');

describe('BackgroundReplyState', () => {
  let state;
  beforeEach(() => { state = new BackgroundReplyState(); });

  describe('closeAction', () => {
    test('hides the window while an answer is running', () => {
      state.report({ running: 1, media: false });
      expect(state.closeAction()).toBe('hide');
    });

    test('hides the window for a message sent and not yet taken up by the server', () => {
      state.report({ running: 0, pending: 1, media: false });
      expect(state.closeAction()).toBe('hide');
    });

    test('closes as before when nothing is running', () => {
      state.report({ running: 0, media: false });
      expect(state.closeAction()).toBe('close');
    });

    test('closes when the microphone is in use or being opened, even during an answer', () => {
      state.report({ running: 2, media: true });
      expect(state.closeAction()).toBe('close');
    });

    test('closes when quitting or installing an update, even during an answer', () => {
      state.report({ running: 1, media: false });
      expect(state.closeAction({ quitting: true })).toBe('close');
      expect(state.closeAction({ updating: true })).toBe('close');
    });

    test('takes only a whole positive count and a true media flag from a report', () => {
      state.report({ running: '3', media: 'yes' });
      expect(state.running).toBe(0);
      expect(state.media).toBe(false);
      state.report({ running: -1, media: true });
      expect(state.running).toBe(0);
      expect(state.media).toBe(true);
    });
  });

  describe('generations', () => {
    test('accepts only the current page, and none while a page is being replaced', () => {
      const first = state.newGeneration();
      expect(state.accepts(first)).toBe(true);
      state.report({ running: 1, pending: 1, media: true });
      state.hidden = true;
      state.pageGone();
      expect(state.accepts(first)).toBe(false);
      expect([state.running, state.pending, state.media, state.hidden]).toEqual([0, 0, false, true]);
      const second = state.newGeneration();
      expect(second).not.toBe(first);
      expect(state.accepts(first)).toBe(false);
      expect(state.accepts(second)).toBe(true);
    });

    test('accepts nothing before a page is ready', () => {
      expect(state.accepts(null)).toBe(false);
      expect(state.accepts(undefined)).toBe(false);
    });
  });

  describe('throttlingAllowed', () => {
    test('a hidden page runs at full speed only while there is work to receive', () => {
      expect(state.throttlingAllowed()).toBe(true);
      state.hidden = true;
      state.report({ running: 1, pending: 0, media: false });
      expect(state.throttlingAllowed()).toBe(false);
      state.report({ running: 0, pending: 0, media: false });
      expect(state.throttlingAllowed()).toBe(true);
    });
  });

  describe('noticeFor', () => {
    test('gives no notice while the window is shown', () => {
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBeNull();
    });

    test('gives the notice for each way an answer ends while hidden', () => {
      state.hidden = true;
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBe(NOTICES.done);
      expect(state.noticeFor({ requestId: 'r2', outcome: 'no_reply' })).toBe(NOTICES.no_reply);
      expect(state.noticeFor({ requestId: 'r3', outcome: 'lost' })).toBe(NOTICES.lost);
      expect(state.noticeFor({ requestId: 'r4', outcome: 'anything else' })).toBe(NOTICES.no_reply);
    });

    test('gives one notice per answer', () => {
      state.hidden = true;
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBe(NOTICES.done);
      expect(state.noticeFor({ requestId: 'r1', outcome: 'lost' })).toBeNull();
    });

    test('an answer that ended while shown gets no notice when the window is hidden later', () => {
      state.noticeFor({ requestId: 'r1', outcome: 'done' });
      state.hidden = true;
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBeNull();
    });

    test('an answer that ends while the window is being hidden is noticed once it is hidden', () => {
      state.startHold();
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBeNull();
      expect(state.endHold(true)).toEqual([NOTICES.done]);
      expect(state.hidden).toBe(true);
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBeNull();
    });

    test('and not at all when the window stays shown', () => {
      state.startHold();
      state.noticeFor({ requestId: 'r1', outcome: 'done' });
      expect(state.endHold(false)).toEqual([]);
      expect(state.hidden).toBe(false);
    });

    test('ignores an end without an id', () => {
      state.hidden = true;
      expect(state.noticeFor({ requestId: '', outcome: 'done' })).toBeNull();
    });

    test('a closed window starts from nothing', () => {
      state.hidden = true;
      state.report({ running: 1, media: true });
      state.noticeFor({ requestId: 'r1', outcome: 'done' });
      state.reset();
      expect([state.running, state.media, state.hidden, state.generation]).toEqual([0, false, false, null]);
      state.hidden = true;
      expect(state.noticeFor({ requestId: 'r1', outcome: 'done' })).toBe(NOTICES.done);
    });
  });

  test('the notice keys are the ones every app translation has', () => {
    const fs = require('fs');
    const path = require('path');
    const dir = path.join(__dirname, '../../app/translations');
    fs.readdirSync(dir).filter(f => f.endsWith('.json')).forEach((f) => {
      const t = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      Object.values(NOTICES).forEach(key => expect(typeof t.messages[key]).toBe('string'));
      ['showWebUI', 'closeWebUI'].forEach(key => expect(typeof t.menu[key]).toBe('string'));
    });
  });
});
