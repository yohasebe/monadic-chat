/**
 * work-screen.js
 *
 * The work screen pane shows the chat's browser as it draws, view only (the
 * server relays its screencast: lib/monadic/work_screen.rb).
 *
 * While the browser can be seen (the Work screen tab is selected, the side
 * column is shown, the browser is the item selected in the pane
 * (workbench.js), and the window is visible), the page holds a work screen
 * socket and is subscribed; when it cannot, the socket is closed. To open
 * one the page asks its chat socket for a pass (WORK_SCREEN_TOKEN) and shows
 * it first.
 *
 * Each frame is decoded off screen and then drawn, only if it still belongs
 * to the stream shown; the server is told once it is drawn (frame-consumed),
 * and sends the next. A stream that ends or waits clears the image at once.
 *
 * The page subscribes to the browser the pane shows (its instance): the
 * server relays that browser only, and a state or frame of another is not
 * taken. When the pane moves to another browser, the page subscribes again.
 *
 * When the chat's browser opens, it becomes an item of the workbench, which
 * brings it forward for the tab that opened it; the chat socket also says
 * so (browser_opened).
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
  // The browser this socket subscribed to (its instance), or null.
  var subscribed = null;
  // Bumped whenever what is shown is cleared: a frame decoded for an older
  // view is not drawn.
  var view = 0;
  // The frame drawn now: the JPEG's base64, for the browser, stream and
  // view it was drawn in (what "Show to the assistant" fixes), or null.
  var drawn = null;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

  function visible() {
    var lc = window.LayoutController;
    if (!lc || lc.selectedPane() !== 'work' || lc.isMenuHidden()) return false;
    if (window.Workbench && !window.Workbench.showsBrowser()) return false;
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
    drawn = null;
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

  function shownBrowser() {
    return window.Workbench && typeof window.Workbench.shownBrowser === 'function' ? window.Workbench.shownBrowser() : null;
  }

  // Subscribes to the browser the pane shows now.
  function subscribe() {
    var browser = shownBrowser();
    if (browser === null || !socket || socket.readyState !== WebSocket.OPEN) return;
    subscribed = browser;
    stream = null;
    drawn = null;
    send({ type: 'subscribe', browser: browser });
  }

  // Brings the socket in line with whether the pane can be seen, and with
  // the browser it shows.
  function refresh() {
    if (visible()) {
      if (!socket && !unavailable) askPass();
      else if (socket && subscribed !== shownBrowser()) {
        showEmpty();
        subscribe();
      }
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
    var conn = new WebSocket(socketUrl());
    socket = conn;
    conn.onopen = function() {
      if (conn !== socket) return;
      conn.send(JSON.stringify({ type: 'auth', token: token }));
      subscribe();
    };
    conn.onmessage = function(event) {
      if (conn !== socket) return;
      var message;
      try { message = JSON.parse(event.data); } catch (_) { return; }
      if (message.type === 'state') onState(message);
      else if (message.type === 'frame') onFrame(message);
    };
    conn.onclose = function() {
      if (conn !== socket) return;
      socket = null;
      stream = null;
      subscribed = null;
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
    var conn = socket;
    socket = null;
    stream = null;
    subscribed = null;
    drawn = null;
    if (conn) conn.close();
    showEmpty();
  }

  function onState(message) {
    // A state of a browser this socket no longer watches.
    if (typeof message.browser === 'number' && message.browser !== subscribed) return;
    if (message.state === 'live') {
      // Attached; nothing is drawn yet.
      stream = message.stream;
      showMessage('workScreenConnecting', 'Connecting to the browser…');
      return;
    }
    stream = null;
    if (message.state === 'ended' && message.reason === 'unavailable') unavailable = true;
    // The browser may have closed: the workbench says so.
    if (message.state === 'ended' && window.Workbench && typeof window.Workbench.onChanged === 'function') {
      window.Workbench.onChanged();
    }
    showEmpty();
    if (message.state !== 'ended') return;
    if (message.reason === 'connection') {
      // The chat socket reconnected: the pass this socket showed is gone.
      close();
      refresh();
    } else if (RESUBSCRIBE.indexOf(message.reason) !== -1) {
      subscribe();
    }
  }

  function onFrame(message) {
    if (message.stream !== stream || message.browser !== subscribed || typeof message.data !== 'string') return;
    var shown = view;
    var conn = socket;
    var decoded = new Image();
    decoded.src = 'data:image/jpeg;base64,' + message.data;
    decoded.decode().then(function() {
      if (conn !== socket || shown !== view || message.stream !== stream) return;
      var image = $id('work-screen-image');
      var note = $id('work-screen-empty');
      if (!image) return;
      image.src = decoded.src;
      $show(image);
      $hide(note);
      drawn = { browser: subscribed, stream: message.stream, view: shown, data: message.data };
      send({ type: 'frame-consumed', stream: message.stream, n: message.n });
    }).catch(function() {
      // An image that does not decode is not drawn; the next one is sent
      // when the server's wait for this one runs out.
    });
  }

  // A message for the work screen on the chat socket. The browser is an
  // item of the workbench, brought forward there for the tab that opened
  // it (workbench.js), which then subscribes to it; when the work screen
  // was full, the user is told.
  function onChatEvent(message) {
    if (message.event !== 'browser_opened') return;
    if (message.workbench === 'full' && window.Workbench && typeof window.Workbench.onBrowserFull === 'function') {
      window.Workbench.onBrowserFull();
    }
    refresh();
  }

  document.addEventListener('layoutchange', refresh);
  document.addEventListener('visibilitychange', refresh);

  // The frame on the screen now ({ browser, data }), or null: only the one
  // drawn in this view, for the stream and browser shown, while it can be
  // seen.
  function drawnFrame() {
    if (!drawn || drawn.view !== view || drawn.stream !== stream || drawn.browser !== subscribed || !visible()) return null;
    return { browser: drawn.browser, data: drawn.data };
  }

  window.WorkScreen = {
    drawnFrame: drawnFrame,
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
