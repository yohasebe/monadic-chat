// Answers that finish while the Web UI window is hidden.
//
// Closing the Web UI window while an answer is running hides it instead, so
// the page keeps its connection and receives the answer; the user is told
// when it has come. What the page reports (webview-preload.js →
// background-reply.js) is kept here and decides:
//   - what closing the window does now,
//   - which notice, if any, an answer that ended gets,
//   - whether the hidden page may be throttled.
// Each page load gets a generation; reports from any other are ignored.
// Nothing here touches Electron, so it can be tested on its own.

const NOTICES = Object.freeze({
  done: 'backgroundReplyDone',
  no_reply: 'backgroundReplyFailed',
  lost: 'backgroundReplyLost'
});

// Enough to tell a repeated end of the same answer from a new one.
const REMEMBERED_ENDS = 200;

function count(value) {
  return Number.isInteger(value) && value > 0 ? value : 0;
}

class BackgroundReplyState {
  constructor() {
    this.lastGeneration = 0;
    this.reset();
  }

  // The window is gone: nothing is kept but the generation counter.
  reset() {
    this.hidden = false;
    this.ended = new Set();
    this.endHold(false);
    this.pageGone();
  }

  // From closing the window until it is hidden or kept: an answer that
  // ends meanwhile is noticed once the window is hidden (or not at all if it
  // stays shown). Starting again while holding keeps what was kept.
  startHold() {
    if (this.holding) return;
    this.holding = true;
    this.deferred = [];
  }

  // Whether an answer ended while holding.
  endedWhileHolding() {
    return !!(this.holding && this.deferred && this.deferred.length > 0);
  }

  // The notices kept while holding, when the window was hidden.
  endHold(hidden) {
    const kept = hidden ? (this.deferred || []) : [];
    this.holding = false;
    this.deferred = [];
    if (hidden) this.hidden = true;
    return kept;
  }

  // The page is being replaced (reload, navigation) or has crashed: what it
  // reported no longer holds, and no generation is accepted until the next
  // page says it is ready. Whether the window is hidden does not change.
  pageGone() {
    this.generation = null;
    this.running = 0;
    this.pending = 0;
    this.media = false;
  }

  // A page that has loaded and says it is ready.
  newGeneration() {
    this.pageGone();
    this.lastGeneration += 1;
    this.generation = this.lastGeneration;
    return this.generation;
  }

  accepts(generation) {
    return this.generation !== null && generation === this.generation;
  }

  report({ running, pending, media }) {
    this.running = count(running);
    this.pending = count(pending);
    this.media = media === true;
  }

  // Work the page waits for: running on the server, or sent and not yet
  // taken up.
  busy() {
    return this.running > 0 || this.pending > 0;
  }

  // "hide" keeps the window (and its answer) alive out of sight; "close"
  // lets the window close as before. Quitting and installing an update
  // always close. The microphone in use, or being opened, closes too: it
  // must not stay on in a window nobody sees.
  closeAction({ quitting = false, updating = false } = {}) {
    if (quitting || updating) return 'close';
    if (this.busy() && !this.media) return 'hide';
    return 'close';
  }

  // A hidden page runs at full speed only while there is work to receive.
  throttlingAllowed() {
    return !(this.hidden && this.busy());
  }

  // The notice for an answer that ended, or null: only while the window is
  // hidden, and once for each answer.
  noticeFor({ requestId, outcome }) {
    const id = String(requestId || '');
    if (!id || this.ended.has(id)) return null;
    this.ended.add(id);
    if (this.ended.size > REMEMBERED_ENDS) {
      this.ended.delete(this.ended.values().next().value);
    }
    const notice = Object.prototype.hasOwnProperty.call(NOTICES, outcome) ? NOTICES[outcome] : NOTICES.no_reply;
    if (this.hidden) return notice;
    if (this.holding) this.deferred.push(notice);
    return null;
  }
}

module.exports = { BackgroundReplyState, NOTICES };
