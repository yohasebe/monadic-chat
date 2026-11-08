/**
 * background-reply.js
 *
 * The desktop app hides the Web UI window when it is closed, so the
 * conversation stays and an answer still running comes in. The page tells
 * the app:
 *   - how many answers are running (the server's "reply_state" messages),
 *     and how many were sent and not yet taken up by the server,
 *   - how each answer ended ("done", "no_reply", or "lost" when the
 *     connection closed while it ran).
 * When the app holds the page in the background, the microphone is closed
 * (an open track is stopped, a Live conversation ended) and cannot be opened
 * again; audio that arrives meanwhile is dropped, not played later (the app
 * also mutes the window).
 *
 * Outside the desktop app (no window.electronAPI.backgroundReply) the page
 * only keeps the counts.
 *
 * It also keeps the token the server gives for stopping the answer running
 * now ("reply_cancel"): while the server waits for that answer it reads the
 * Cancel sent on the connection only after it, so Cancel first asks for the
 * stop at /reply/cancel/<token>. The token is good for the socket it came on
 * and the answer it names only, and goes when the answer finished, was
 * cancelled or reset, or the connection closed.
 *
 * Speech made for an answer names it ("reply_speech"). The page takes it
 * only for an answer sent since the user last pressed Cancel: Cancel revokes
 * all before it, also one the server takes up only after it, so what still
 * comes for such an answer (audio, Web Speech, its progress and end) is
 * dropped, while speech for an answer sent after it and manual playback
 * (named for no answer) are taken.
 */
(function() {
  'use strict';

  var running = new Set();
  // Sent, and not yet taken up by the server ("running") or refused: the
  // places that send a message that starts work call expectReply(). Each
  // holds whether its speech is to be taken: not once Cancel was pressed
  // after it was sent, even if the server takes it up only after that.
  var pending = [];
  var pendingSeq = 0;
  var held = false;
  var streams = new Set();
  var stopToken = null;
  // The answers whose speech is taken: those sent since the last Cancel (or
  // taken up with nothing sent from this page), the latest few; speech for
  // one older than that is dropped too.
  var speechFor = [];
  var SPEECH_KEPT = 16;

  function bridge() {
    var api = window.electronAPI;
    return api && api.backgroundReply ? api.backgroundReply : null;
  }

  function report() {
    var b = bridge();
    if (b) b.report({ running: running.size, pending: pending.length });
  }

  // A message that starts work (an answer, an AI User suggestion) was sent.
  // It counts until the server takes it up or refuses it, or the connection
  // closes; not for a time.
  function expectReply() {
    pendingSeq += 1;
    pending.push({ id: 'sent:' + pendingSeq, speech: true });
    report();
  }

  // The server answers messages in the order they came: the one taken up
  // is the first sent. Returns whether its speech is to be taken.
  function takenUp() {
    var sent = pending.shift();
    return !sent || sent.speech;
  }

  function finished(requestId, outcome) {
    var b = bridge();
    if (b) b.finished({ requestId: String(requestId), outcome: outcome });
  }

  function onReplyState(data) {
    if (!data || typeof data.request_id !== 'string') return;
    if (data.state === 'running') {
      running.add(data.request_id);
      if (takenUp() && speechFor.indexOf(data.request_id) === -1) speechFor.push(data.request_id);
      if (speechFor.length > SPEECH_KEPT) speechFor = speechFor.slice(-SPEECH_KEPT);
      report();
    } else if (data.state === 'finished' && running.delete(data.request_id)) {
      if (stopToken && stopToken.requestId === data.request_id) stopToken = null;
      finished(data.request_id, data.outcome === 'done' ? 'done' : 'no_reply');
      report();
    }
  }

  // A message the server did not take (busy, attachments refused, a
  // voice-only model, ...): it ends without a reply.
  function onRefused() {
    var sent = pending.shift();
    if (sent) finished(sent.id, 'no_reply');
    report();
  }

  // The token for stopping an answer, from the socket it came on (one that
  // has already finished is not taken).
  function onReplyToken(socket, data) {
    if (!data || typeof data.request_id !== 'string' || typeof data.token !== 'string') return;
    if (!running.has(data.request_id)) return;
    stopToken = { socket: socket, requestId: data.request_id, token: data.token };
  }

  // Asks the server to stop the answer running now, by HTTP, when its token
  // came on the socket the page uses now. What comes of it is not waited
  // for: the Cancel sent on the connection follows anyway.
  function stopAnswer(socket) {
    speechFor = [];
    pending.forEach(function(sent) { sent.speech = false; });
    var given = stopToken;
    stopToken = null;
    if (!given || given.socket !== socket || typeof fetch !== 'function') return false;
    fetch('/reply/cancel/' + encodeURIComponent(given.token), {
      method: 'POST', credentials: 'same-origin', cache: 'no-store', keepalive: true
    }).catch(function() { /* the Cancel on the connection still stops it */ });
    return true;
  }

  // Whether a message is speech for an answer whose speech is not taken.
  function refusesSpeech(data) {
    return !!data && typeof data.reply_speech === 'string' && speechFor.indexOf(data.reply_speech) === -1;
  }

  // The answer was stopped another way (the server said it was cancelled,
  // or the chat was reset): its token goes.
  function forgetStopToken() {
    stopToken = null;
  }

  // Returns how many answers ended with the connection.
  function onConnectionLost() {
    stopToken = null;
    var ids = Array.from(running).concat(pending.map(function(sent) { return sent.id; }));
    running.clear();
    pending = [];
    ids.forEach(function(id) { finished(id, 'lost'); });
    report();
    return ids.length;
  }

  function stopAudio() {
    if (typeof window.ttsStop === 'function') {
      window.ttsStop();
    } else if (window.speechSynthesis) {
      try { window.speechSynthesis.cancel(); } catch (_) { /* nothing to stop */ }
    }
  }

  function stopMicrophone() {
    streams.forEach(function(stream) {
      stream.getTracks().forEach(function(t) {
        try { t.stop(); } catch (_) { /* already stopped */ }
      });
    });
    streams.clear();
    var lc = window.LiveConversation;
    if (lc && typeof lc.isActive === 'function' && lc.isActive() && typeof lc.stopConversation === 'function') {
      try { lc.stopConversation(); } catch (_) { /* its own teardown */ }
    }
  }

  function hold() {
    held = true;
    stopMicrophone();
    stopAudio();
    report();
  }

  function release() {
    // What arrived while held is not played now (the app keeps the window
    // muted until this is done).
    stopAudio();
    held = false;
  }

  function maySend() {
    return !held;
  }

  // The one way to send a message that starts work: not while the app keeps
  // the page in the background (reported as not sent, so the text and
  // attachments stay), and counted once sent.
  function sendReply(payload, options) {
    if (!maySend()) return { sent: false, held: true };
    var result = window.safeWsSend(payload, options);
    if (result && result.sent) expectReply();
    return result;
  }

  function notAllowed() {
    return new DOMException('The window is in the background', 'NotAllowedError');
  }

  // The microphone: every request for it goes through here, so the page
  // knows what to stop when it is held, and one that opens after the page was
  // held is closed at once.
  function wrapMedia() {
    var md = navigator.mediaDevices;
    if (!md || typeof md.getUserMedia !== 'function' || md.getUserMedia.__backgroundReply) return;
    var original = md.getUserMedia.bind(md);
    var wrapped = function(constraints) {
      if (held) return Promise.reject(notAllowed());
      return original(constraints).then(function(stream) {
        if (held) {
          stream.getTracks().forEach(function(t) { t.stop(); });
          throw notAllowed();
        }
        // Streams whose tracks have all stopped are not kept.
        streams.forEach(function(s) {
          if (!s.getTracks().some(function(t) { return t.readyState === 'live'; })) streams.delete(s);
        });
        streams.add(stream);
        return stream;
      });
    };
    wrapped.__backgroundReply = true;
    md.getUserMedia = wrapped;
  }

  // Speech the browser speaks itself (Web Speech) is not started while held.
  function wrapSpeech() {
    var synth = window.speechSynthesis;
    if (!synth || typeof synth.speak !== 'function' || synth.speak.__backgroundReply) return;
    var speak = synth.speak.bind(synth);
    var gated = function(utterance) {
      if (held) return;
      speak(utterance);
    };
    gated.__backgroundReply = true;
    synth.speak = gated;
  }

  wrapMedia();
  wrapSpeech();

  var b = bridge();
  if (b) {
    b.onHold(hold);
    b.onRelease(release);
  }

  window.BackgroundReply = {
    expectReply: expectReply,
    sendReply: sendReply,
    maySend: maySend,
    onReplyState: onReplyState,
    onReplyToken: onReplyToken,
    stopAnswer: stopAnswer,
    forgetStopToken: forgetStopToken,
    refusesSpeech: refusesSpeech,
    onRefused: onRefused,
    onConnectionLost: onConnectionLost,
    isHeld: function() { return held; },
    // For tests.
    _state: function() { return { running: running.size, pending: pending.length, held: held }; },
    _hold: hold,
    _release: release
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.BackgroundReply;
  }
})();
