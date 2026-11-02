/**
 * background-reply.js
 *
 * Lets an answer finish while the desktop app keeps the Web UI window hidden
 * (closed during an answer). The page tells the app:
 *   - how many answers are running (the server's "reply_state" messages),
 *     and how many were sent and not yet taken up by the server,
 *   - whether the microphone is in use or being opened,
 *   - how each answer ended ("done", "no_reply", or "lost" when the
 *     connection closed while it ran).
 * When the app holds the page in the background, the microphone is closed
 * (an open track is stopped, a Live conversation ended) and cannot be opened
 * again; audio that arrives meanwhile is dropped, not played later (the app
 * also mutes the window).
 *
 * Outside the desktop app (no window.electronAPI.backgroundReply) the page
 * only keeps the counts.
 */
(function() {
  'use strict';

  var running = new Set();
  // Sent, and not yet taken up by the server ("running") or refused: the
  // places that send a message that starts work call expectReply().
  var pending = [];
  var pendingSeq = 0;
  var held = false;
  // Asked by the app whether the window may close: nothing new starts until
  // the app holds or releases the page.
  var closing = false;
  var pendingMedia = 0;
  var streams = new Set();

  function bridge() {
    var api = window.electronAPI;
    return api && api.backgroundReply ? api.backgroundReply : null;
  }

  function mediaBusy() {
    if (pendingMedia > 0) return true;
    var busy = false;
    streams.forEach(function(stream) {
      var live = stream.getTracks().some(function(t) { return t.readyState === 'live'; });
      if (live) busy = true; else streams.delete(stream);
    });
    return busy;
  }

  function report() {
    var b = bridge();
    if (b) b.report({ running: running.size, pending: pending.length, media: mediaBusy() });
  }

  // A message that starts work (an answer, an AI User suggestion) was sent.
  // It counts until the server takes it up or refuses it, or the connection
  // closes; not for a time.
  function expectReply() {
    pendingSeq += 1;
    pending.push('sent:' + pendingSeq);
    report();
  }

  // The server answers messages in the order they came.
  function takenUp() {
    pending.shift();
  }

  function finished(requestId, outcome) {
    var b = bridge();
    if (b) b.finished({ requestId: String(requestId), outcome: outcome });
  }

  function onReplyState(data) {
    if (!data || typeof data.request_id !== 'string') return;
    if (data.state === 'running') {
      running.add(data.request_id);
      takenUp();
      report();
    } else if (data.state === 'finished' && running.delete(data.request_id)) {
      finished(data.request_id, data.outcome === 'done' ? 'done' : 'no_reply');
      report();
    }
  }

  // A message the server did not take (busy, attachments refused, a
  // voice-only model, ...): it ends without a reply.
  function onRefused() {
    var id = pending.shift();
    if (id) finished(id, 'no_reply');
    report();
  }

  function onConnectionLost() {
    var ids = Array.from(running).concat(pending);
    running.clear();
    pending = [];
    if (ids.length === 0) { report(); return; }
    ids.forEach(function(id) { finished(id, 'lost'); });
    report();
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
    closing = false;
  }

  // The work as of now, for the app deciding whether the window may close.
  // From here on nothing new starts until the app holds or releases the page.
  function stateForClosing() {
    closing = true;
    return { running: running.size, pending: pending.length, media: mediaBusy() };
  }

  function maySend() {
    return !held && !closing;
  }

  // The one way to send a message that starts work: not while the app is
  // deciding whether to close the window or keeps it in the background
  // (reported as not sent, so the text and attachments stay), and counted
  // once sent.
  function sendReply(payload, options) {
    if (!maySend()) return { sent: false, held: true };
    var result = window.safeWsSend(payload, options);
    if (result && result.sent) expectReply();
    return result;
  }

  function notAllowed() {
    return new DOMException('The window is in the background', 'NotAllowedError');
  }

  // The microphone: every request for it goes through here, so one that is
  // still being opened counts as in use, and one that opens after the page
  // was held is closed at once.
  function wrapMedia() {
    var md = navigator.mediaDevices;
    if (!md || typeof md.getUserMedia !== 'function' || md.getUserMedia.__backgroundReply) return;
    var original = md.getUserMedia.bind(md);
    var wrapped = function(constraints) {
      if (held || closing) return Promise.reject(notAllowed());
      pendingMedia += 1;
      report();
      return original(constraints).then(function(stream) {
        pendingMedia -= 1;
        if (held || closing) {
          stream.getTracks().forEach(function(t) { t.stop(); });
          report();
          throw notAllowed();
        }
        streams.add(stream);
        report();
        return stream;
      }, function(err) {
        pendingMedia -= 1;
        report();
        throw err;
      });
    };
    wrapped.__backgroundReply = true;
    md.getUserMedia = wrapped;

    // Stopping a track fires no event; report after it.
    var proto = window.MediaStreamTrack && window.MediaStreamTrack.prototype;
    if (proto && typeof proto.stop === 'function' && !proto.stop.__backgroundReply) {
      var stop = proto.stop;
      var stopped = function() {
        stop.apply(this, arguments);
        report();
      };
      stopped.__backgroundReply = true;
      proto.stop = stopped;
    }
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
    if (typeof b.onState === 'function') b.onState(stateForClosing);
  }

  window.BackgroundReply = {
    expectReply: expectReply,
    sendReply: sendReply,
    maySend: maySend,
    onReplyState: onReplyState,
    onRefused: onRefused,
    onConnectionLost: onConnectionLost,
    isHeld: function() { return held; },
    // For tests.
    _state: function() { return { running: running.size, pending: pending.length, media: mediaBusy(), held: held, closing: closing }; },
    _hold: hold,
    _release: release
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.BackgroundReply;
  }
})();
