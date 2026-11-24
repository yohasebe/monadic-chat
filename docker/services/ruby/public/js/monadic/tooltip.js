/**
 * MonadicTip — the Web UI's tooltips: a short text that shows when the
 * pointer rests on a control or the keyboard focuses it.
 *
 *   const tip = MonadicTip.attach(el, { placement, delay, title });
 *   tip.show(reason) / tip.hide() / tip.setText(text) / tip.dispose()
 *   MonadicTip.get(el), MonadicTip.hideAll(), MonadicTip.disposeWithin(root)
 *
 * One bubble is shared and moved to the control it describes (inside an
 * open dialog when the control is in one). The control's title moves into
 * the tooltip (so the browser's own does not show too) and comes back when
 * the tooltip is let go; a title written again later (a translation) is
 * taken in. The text is set as text, never as HTML.
 *
 * While shown, the bubble is the control's description (aria-describedby);
 * the pointer may move onto it to read it; Esc, a press anywhere, the
 * control leaving the page or scrolling out of view hide it. A delay applies
 * to the pointer and the focus coming; show() and hide() are at once.
 */
(function () {
  'use strict';

  var BUBBLE_ID = 'monadic-tip';
  var MARK = 'data-mtip';
  var GAP = 6;
  var EDGE = 8;
  var GRACE = 120; // to cross from the control to the bubble

  var handles = new WeakMap();
  var bubble = null;
  var current = null; // the handle shown
  var pending = null; // { handle, timer } waiting to show
  var hideTimer = null;
  var observer = null;

  function bubbleEl() {
    if (bubble) return bubble;
    bubble = document.createElement('div');
    bubble.id = BUBBLE_ID;
    bubble.className = 'mtip';
    bubble.setAttribute('role', 'tooltip');
    bubble.hidden = true;
    bubble.addEventListener('pointerenter', function () { clearTimeout(hideTimer); });
    bubble.addEventListener('pointerleave', function () {
      if (current) scheduleHide(current, current.opts.delay.hide);
    });
    return bubble;
  }

  // Where the bubble goes: an open dialog the control is in (its top layer),
  // else the page.
  function hostFor(el) {
    var dialog = el.closest && el.closest('dialog[open]');
    return dialog || document.body;
  }

  function describedBy(el, add) {
    var ids = (el.getAttribute('aria-describedby') || '').split(/\s+/).filter(function (id) { return id && id !== BUBBLE_ID; });
    if (add) ids.push(BUBBLE_ID);
    if (ids.length) el.setAttribute('aria-describedby', ids.join(' '));
    else el.removeAttribute('aria-describedby');
  }

  // A title written on the control after it was attached (a translation)
  // becomes the tooltip's text.
  function takeTitle(handle) {
    var title = handle.el.getAttribute('title');
    if (title !== null) {
      handle.ownsTitle = true;
      handle.text = title;
      handle.el.removeAttribute('title');
    }
  }

  function place(handle) {
    var b = bubbleEl();
    var r = handle.el.getBoundingClientRect();
    var vw = document.documentElement.clientWidth || window.innerWidth;
    var vh = document.documentElement.clientHeight || window.innerHeight;
    b.style.left = '0px';
    b.style.top = '0px';
    var w = b.offsetWidth;
    var h = b.offsetHeight;
    var above = r.top - EDGE;
    var below = vh - r.bottom - EDGE;
    var side = handle.opts.placement === 'bottom' ? 'bottom' : 'top';
    if (side === 'top' && above < h + GAP && below >= h + GAP) side = 'bottom';
    else if (side === 'bottom' && below < h + GAP && above >= h + GAP) side = 'top';
    else if (above < h + GAP && below < h + GAP) side = above > below ? 'top' : 'bottom';
    var top = side === 'top' ? r.top - GAP - h : r.bottom + GAP;
    var left = r.left + (r.width - w) / 2;
    left = Math.max(EDGE, Math.min(left, vw - EDGE - w));
    top = Math.max(EDGE, Math.min(top, vh - EDGE - h));
    b.style.left = Math.round(left) + 'px';
    b.style.top = Math.round(top) + 'px';
    b.setAttribute('data-placement', side);
  }

  function inView(el) {
    var r = el.getBoundingClientRect();
    if (!r.width && !r.height) return false;
    var vw = document.documentElement.clientWidth || window.innerWidth;
    var vh = document.documentElement.clientHeight || window.innerHeight;
    return r.bottom > 0 && r.top < vh && r.right > 0 && r.left < vw;
  }

  function onScroll() {
    if (!current) return;
    if (!current.el.isConnected || !inView(current.el)) hideCurrent();
    else place(current);
  }

  function onKey(event) {
    if (event.key !== 'Escape' || !current) return;
    // Esc closes the tooltip only; what else Esc does waits for the next one.
    event.preventDefault();
    event.stopPropagation();
    current.dismissed = true;
    hideCurrent();
  }

  function onPress(event) {
    if (!current && !pending) return;
    if (bubble && bubble.contains(event.target)) return;
    if (current) current.dismissed = true;
    if (pending) pending.handle.dismissed = true;
    hideAll();
  }

  function watch(on) {
    var method = on ? 'addEventListener' : 'removeEventListener';
    window[method]('scroll', onScroll, true);
    window[method]('resize', onScroll);
    document[method]('keydown', onKey, true);
    if (on && typeof MutationObserver === 'function') {
      // Only whether the control shown is still on the page.
      observer = new MutationObserver(function () {
        if (current && !current.el.isConnected) hideCurrent();
      });
      observer.observe(document.body, { childList: true, subtree: true });
    } else if (!on && observer) {
      observer.disconnect();
      observer = null;
    }
  }

  function display(handle) {
    clearTimeout(hideTimer);
    if (!handle.el.isConnected || !handle.text) return;
    if (current && current !== handle) describedBy(current.el, false);
    var b = bubbleEl();
    b.textContent = handle.text;
    var host = hostFor(handle.el);
    if (b.parentNode !== host) host.appendChild(b);
    describedBy(handle.el, true);
    b.hidden = false;
    var wasShown = !!current;
    current = handle;
    place(handle);
    if (!wasShown) watch(true);
  }

  function hideCurrent() {
    clearTimeout(hideTimer);
    if (!current) return;
    describedBy(current.el, false);
    current.reasons.clear();
    current = null;
    if (bubble) bubble.hidden = true;
    watch(false);
  }

  function cancelPending(handle) {
    if (pending && (!handle || pending.handle === handle)) {
      clearTimeout(pending.timer);
      pending = null;
    }
  }

  function scheduleShow(handle) {
    cancelPending();
    var wait = handle.opts.delay.show;
    if (!wait) { display(handle); return; }
    var entry = { handle: handle, timer: 0 };
    entry.timer = setTimeout(function () {
      if (pending !== entry) return; // replaced meanwhile
      pending = null;
      if (handle.reasons.size && !handle.dismissed) display(handle);
    }, wait);
    pending = entry;
  }

  function scheduleHide(handle, wait) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function () {
      if (current === handle && !handle.reasons.size) hideCurrent();
    }, Math.max(wait || 0, GRACE));
  }

  function hideAll() {
    cancelPending();
    hideCurrent();
  }

  function enter(handle, reason) {
    takeTitle(handle);
    if (handle.dismissed) return;
    handle.reasons.add(reason);
    if (current === handle) { clearTimeout(hideTimer); return; }
    scheduleShow(handle);
  }

  function leave(handle, reason) {
    handle.reasons.delete(reason);
    if (handle.reasons.size) return;
    handle.dismissed = false;
    cancelPending(handle);
    if (current === handle) scheduleHide(handle, handle.opts.delay.hide);
  }

  function attach(el, options) {
    if (!el) return null;
    var existing = handles.get(el);
    if (existing) return existing;
    var opts = options || {};
    var delay = opts.delay || {};
    var handle = {
      el: el,
      text: '',
      ownsTitle: false,
      dismissed: false,
      reasons: new Set(),
      opts: {
        placement: opts.placement === 'bottom' ? 'bottom' : 'top',
        delay: { show: Number(delay.show) || 0, hide: Number(delay.hide) || 0 }
      }
    };
    takeTitle(handle);
    if (typeof opts.title === 'string') handle.text = opts.title;

    var listeners = {
      pointerenter: function (e) { if (e.pointerType !== 'touch') enter(handle, 'hover'); },
      pointerleave: function () { leave(handle, 'hover'); },
      focusin: function () {
        // The keyboard's focus, not a click's.
        var visible = true;
        try { visible = el.matches(':focus-visible') || !!el.querySelector(':focus-visible'); } catch (_) { /* older engines */ }
        if (visible) enter(handle, 'focus');
      },
      focusout: function (e) { if (!el.contains(e.relatedTarget)) leave(handle, 'focus'); }
    };
    Object.keys(listeners).forEach(function (type) { el.addEventListener(type, listeners[type]); });

    handle.show = function (reason) {
      takeTitle(handle);
      cancelPending();
      handle.dismissed = false;
      if (reason) handle.reasons.add(reason);
      display(handle);
    };
    handle.hide = function () {
      cancelPending(handle);
      if (current === handle) hideCurrent();
      handle.reasons.clear();
    };
    handle.setText = function (text) {
      handle.text = text == null ? '' : String(text);
      if (current !== handle) return;
      if (!handle.text) { hideCurrent(); return; }
      bubbleEl().textContent = handle.text;
      place(handle);
    };
    handle.dispose = function () {
      handle.hide();
      Object.keys(listeners).forEach(function (type) { el.removeEventListener(type, listeners[type]); });
      if (handle.ownsTitle && handle.text) el.setAttribute('title', handle.text);
      el.removeAttribute(MARK);
      handles.delete(el);
    };

    el.setAttribute(MARK, '');
    handles.set(el, handle);
    return handle;
  }

  function get(el) {
    return (el && handles.get(el)) || null;
  }

  // Lets go of every tooltip of root and of what is in it.
  function disposeWithin(root) {
    if (!root) return;
    var els = [];
    if (root.hasAttribute && root.hasAttribute(MARK)) els.push(root);
    if (root.querySelectorAll) els = els.concat(Array.prototype.slice.call(root.querySelectorAll('[' + MARK + ']')));
    els.forEach(function (el) {
      var handle = handles.get(el);
      if (handle) handle.dispose();
    });
  }

  // A press anywhere hides the tooltip shown.
  document.addEventListener('pointerdown', onPress, true);

  window.MonadicTip = { attach: attach, get: get, hideAll: hideAll, disposeWithin: disposeWithin };
})();
