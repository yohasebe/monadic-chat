/**
 * work-screen.js
 *
 * The work screen pane shows the chat's browser as it draws, view only (the
 * server relays its screencast: lib/monadic/work_screen.rb).
 *
 * While the pane can be seen (the Work screen tab is selected, the side
 * column is shown, and the window is visible), the page holds a work screen
 * socket and is subscribed; when it cannot, the socket is closed. To open
 * one the page asks its chat socket for a pass (WORK_SCREEN_TOKEN) and shows
 * it first.
 *
 * Each frame is decoded off screen and then drawn, only if it still belongs
 * to the stream shown; the server is told once it is drawn (frame-consumed),
 * and sends the next. A stream that ends or waits clears the image at once.
 *
 * When the chat's browser opens, the chat socket says so (browser_opened)
 * and the side column switches to this pane.
 */
(function() {
  'use strict';

  var REOPEN_DELAY = 1000;
  // Ends after which the same socket subscribes again: the tab is now in
  // another chat, or the chat was replaced (Reset), and that chat may have
  // its own browser.
  var RESUBSCRIBE = ['chat', 'replaced', 'slow'];

  var socket = null;
  var asking = false;
  var reopenTimer = null;
  var unavailable = false;
  var stream = null;
  // Bumped whenever what is shown is cleared: a frame decoded for an older
  // view is not drawn.
  var view = 0;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

  function visible() {
    var lc = window.LayoutController;
    if (!lc || lc.selectedPane() !== 'work' || lc.isMenuHidden()) return false;
    if (document.visibilityState === 'hidden') return false;
    var br = window.BackgroundReply;
    return !(br && typeof br.isHeld === 'function' && br.isHeld());
  }

  // The work screen socket's address: the chat socket's host and port.
  function socketUrl() {
    var base = typeof window.monadicSocketBase === 'function' ? window.monadicSocketBase() : 'ws://localhost:4567';
    return base + '/work-screen';
  }

  // Shows a message in place of the image (key under ui.sidePane).
  function showMessage(key, fallback) {
    view += 1;
    var image = $id('work-screen-image');
    if (image) {
      image.removeAttribute('src');
      $hide(image);
    }
    var note = $id('work-screen-empty');
    if (note) {
      note.setAttribute('data-i18n', 'ui.sidePane.' + key);
      note.textContent = t('ui.sidePane.' + key, fallback);
      $show(note);
    }
  }

  function showEmpty() {
    if (unavailable) {
      showMessage('workScreenUnavailable', 'The work screen is not available in this mode.');
    } else {
      showMessage('workScreenEmpty', 'No work screen is currently available.');
    }
  }

  function send(message) {
    if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }

  // Brings the socket in line with whether the pane can be seen.
  function refresh() {
    if (visible()) {
      if (!socket && !unavailable) askPass();
    } else {
      close();
    }
  }

  function askPass() {
    if (asking || reopenTimer || typeof window.safeWsSend !== 'function') return;
    asking = true;
    window.safeWsSend({ message: 'WORK_SCREEN_TOKEN' }, { silentDrop: true });
  }

  // The chat socket's answer to WORK_SCREEN_TOKEN.
  function onPass(token) {
    asking = false;
    if (socket || !visible() || typeof token !== 'string') return;
    var ws = new WebSocket(socketUrl());
    socket = ws;
    ws.onopen = function() {
      ws.send(JSON.stringify({ type: 'auth', token: token }));
      ws.send(JSON.stringify({ type: 'subscribe' }));
    };
    ws.onmessage = function(event) {
      if (ws !== socket) return;
      var message;
      try { message = JSON.parse(event.data); } catch (_) { return; }
      if (message.type === 'state') onState(message);
      else if (message.type === 'frame') onFrame(message);
    };
    ws.onclose = function() {
      if (ws !== socket) return;
      socket = null;
      stream = null;
      showEmpty();
      if (visible() && !unavailable) reopenLater();
    };
  }

  function reopenLater() {
    if (reopenTimer) return;
    reopenTimer = setTimeout(function() {
      reopenTimer = null;
      refresh();
    }, REOPEN_DELAY);
  }

  function close() {
    if (reopenTimer) {
      clearTimeout(reopenTimer);
      reopenTimer = null;
    }
    var ws = socket;
    socket = null;
    stream = null;
    if (ws) ws.close();
    showEmpty();
  }

  function onState(message) {
    if (message.state === 'live') {
      // Attached; nothing is drawn yet.
      stream = message.stream;
      showMessage('workScreenConnecting', 'Connecting to the browser…');
      return;
    }
    stream = null;
    if (message.state === 'ended' && message.reason === 'unavailable') unavailable = true;
    showEmpty();
    if (message.state !== 'ended') return;
    if (message.reason === 'connection') {
      // The chat socket reconnected: the pass this socket showed is gone.
      close();
      refresh();
    } else if (RESUBSCRIBE.indexOf(message.reason) !== -1) {
      send({ type: 'subscribe' });
    }
  }

  function onFrame(message) {
    if (message.stream !== stream || typeof message.data !== 'string') return;
    var shown = view;
    var ws = socket;
    var decoded = new Image();
    decoded.src = 'data:image/jpeg;base64,' + message.data;
    decoded.decode().then(function() {
      if (ws !== socket || shown !== view || message.stream !== stream) return;
      var image = $id('work-screen-image');
      var note = $id('work-screen-empty');
      if (!image) return;
      image.src = decoded.src;
      $show(image);
      $hide(note);
      send({ type: 'frame-consumed', stream: message.stream, n: message.n });
    }).catch(function() {
      // An image that does not decode is not drawn; the next one is sent
      // when the server's wait for this one runs out.
    });
  }

  // A message for the work screen on the chat socket.
  function onChatEvent(message) {
    if (message.event !== 'browser_opened') return;
    var lc = window.LayoutController;
    if (lc && lc.selectedPane() !== 'work') {
      lc.setPane('work'); // the layout change refreshes
    } else {
      send({ type: 'subscribe' });
      refresh();
    }
  }

  document.addEventListener('layoutchange', refresh);
  document.addEventListener('visibilitychange', refresh);

  window.WorkScreen = {
    refresh: refresh,
    onPass: onPass,
    onChatEvent: onChatEvent,
    // The chat socket (re)opened: a pass asked on the one before is not answered.
    onChatSocketOpen: function() {
      asking = false;
      refresh();
    }
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WorkScreen;
  }
})();
