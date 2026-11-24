/**
 * MonadicDialog — the Web UI's modal dialogs, on the browser's <dialog>.
 *
 *   const d = MonadicDialog.of(el);   // el: <dialog class="mdialog">
 *   d.open(opener?)                    // shown modal; the page behind waits
 *   d.close(reason?) -> Promise<bool>  // true when it closed
 *   d.isOpen
 *
 * Events on the dialog (not bubbling): mdialog:shown once it can be used
 * (its first control focused), mdialog:hide before it closes (cancelable:
 * the dialog stays), mdialog:hidden once it has closed. Every way of
 * closing — a [data-dialog-close] button, Esc, a press on the backdrop,
 * close() — goes the same way and ends once.
 *
 * data-dialog-static: Esc and the backdrop do not close it (its buttons do).
 * [data-dialog-initial] (or [autofocus]) is focused when it opens; else its
 * first field, else its first control after the close (×) button. When it
 * closes, the focus goes back to what opened it if that is still there.
 *
 * While a dialog is open the page's root has data-dialog-open (Easy Submit
 * leaves the keyboard to the dialog; the page does not scroll behind it).
 * It closes at once (no fade out), so it is never half closed.
 */
(function () {
  'use strict';

  var dialogs = new WeakMap();
  var openCount = 0;

  function markOpen(delta) {
    openCount = Math.max(0, openCount + delta);
    if (openCount) document.documentElement.setAttribute('data-dialog-open', '');
    else document.documentElement.removeAttribute('data-dialog-open');
  }

  function shownControl(el) {
    return el && el.isConnected && !el.disabled && el.getClientRects().length > 0;
  }

  function firstFocus(el) {
    var chosen = el.querySelector('[data-dialog-initial], [autofocus]');
    if (shownControl(chosen)) return chosen;
    var field = Array.prototype.find.call(el.querySelectorAll('input:not([type="hidden"]), select, textarea'), shownControl);
    if (field) return field;
    return Array.prototype.find.call(el.querySelectorAll('button, [href], [tabindex]:not([tabindex="-1"])'), function (c) {
      return shownControl(c) && !c.classList.contains('btn-close');
    }) || null;
  }

  // The visible panel (the backdrop is the dialog's area outside it).
  function panelOf(el) {
    return el.querySelector('.modal-content') || el;
  }

  function outside(el, x, y) {
    var r = panelOf(el).getBoundingClientRect();
    return x < r.left || x > r.right || y < r.top || y > r.bottom;
  }

  function fire(el, type, cancelable, detail) {
    var event = new CustomEvent(type, { bubbles: false, cancelable: !!cancelable, detail: detail || {} });
    return el.dispatchEvent(event);
  }

  function make(el) {
    var state = { opener: null, closing: null, pendingOpen: null, press: null };

    function finishClose() {
      var done = state.closing;
      state.closing = null;
      markOpen(-1);
      // Back to what opened it, when the focus is not already somewhere else.
      var active = document.activeElement;
      var opener = state.opener;
      state.opener = null;
      if ((!active || active === document.body || el.contains(active)) && shownControl(opener)) {
        try { opener.focus({ preventScroll: true }); } catch (_) { opener.focus(); }
      }
      fire(el, 'mdialog:hidden', false, { reason: done ? done.reason : 'close' });
      if (done) done.resolve(true);
      if (state.pendingOpen) {
        var next = state.pendingOpen;
        state.pendingOpen = null;
        api.open(next.opener);
      }
    }

    el.addEventListener('close', function () {
      if (!state.closing) state.closing = { reason: 'close', resolve: function () {} };
      finishClose();
    });

    // Esc: the same way as the other closings (and refused when static).
    el.addEventListener('cancel', function (event) {
      event.preventDefault();
      api.close('esc');
    });

    // The backdrop: a press that starts and ends outside the panel, the
    // same pointer, closes it; a drag from inside out (or out in) does not.
    el.addEventListener('pointerdown', function (event) {
      state.press = (event.target === el && outside(el, event.clientX, event.clientY))
        ? event.pointerId : null;
    });
    el.addEventListener('pointercancel', function () { state.press = null; });
    el.addEventListener('pointerup', function (event) {
      var started = state.press;
      state.press = null;
      if (started === null || started !== event.pointerId) return;
      if (event.target === el && outside(el, event.clientX, event.clientY)) {
        event.preventDefault();
        api.close('backdrop');
      }
    });

    el.addEventListener('click', function (event) {
      var button = event.target && event.target.closest && event.target.closest('[data-dialog-close]');
      if (button && el.contains(button)) api.close('button');
    });

    var api = {
      get isOpen() { return el.open && !state.closing; },
      open: function (opener) {
        if (!el.isConnected) return false;
        if (state.closing) { state.pendingOpen = { opener: opener }; return true; }
        if (el.open) return true;
        state.opener = opener || (document.activeElement !== document.body ? document.activeElement : null);
        markOpen(1);
        try {
          el.showModal();
        } catch (_) {
          markOpen(-1);
          state.opener = null;
          return false;
        }
        var first = firstFocus(el);
        if (first) {
          try { first.focus({ preventScroll: true }); } catch (_) { first.focus(); }
        }
        fire(el, 'mdialog:shown');
        return true;
      },
      close: function (reason) {
        reason = reason || 'close';
        if (!el.open) return Promise.resolve(false);
        if (state.closing) return state.closing.promise;
        if ((reason === 'esc' || reason === 'backdrop') && el.hasAttribute('data-dialog-static')) {
          return Promise.resolve(false);
        }
        if (!fire(el, 'mdialog:hide', true, { reason: reason })) return Promise.resolve(false);
        var resolve;
        var promise = new Promise(function (r) { resolve = r; });
        state.closing = { reason: reason, resolve: resolve, promise: promise };
        el.close();
        return promise;
      }
    };
    return api;
  }

  function of(el) {
    if (!el) return null;
    var d = dialogs.get(el);
    if (!d) { d = make(el); dialogs.set(el, d); }
    return d;
  }

  window.MonadicDialog = {
    of: of,
    // Whether a dialog of this kind is open (Easy Submit asks).
    anyOpen: function () { return openCount > 0; }
  };
})();
