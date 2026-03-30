/**
 * DOM Helper Utilities
 *
 * Lightweight helper functions for common DOM operations.
 * Replaces verbose getElementById + null-check patterns with concise calls.
 *
 * Usage:
 *   $id("model")                  // document.getElementById("model") (returns element or null)
 *   $show(el)                     // el.style.display = ""
 *   $hide(el)                     // el.style.display = "none"
 *   $toggle(el, visible)          // show or hide based on boolean
 *   $on(el, event, fn)            // el.addEventListener(event, fn)
 *   $dispatch(el, eventName)      // el.dispatchEvent(new Event(eventName, {bubbles: true}))
 */
(function(window) {
  'use strict';

  /** Get element by ID (null if not found) */
  function $id(id) {
    return document.getElementById(id);
  }

  /** Show element (clear inline display) */
  function $show(el) {
    if (el) el.style.display = "";
  }

  /** Hide element */
  function $hide(el) {
    if (el) el.style.display = "none";
  }

  /** Toggle element visibility */
  function $toggle(el, visible) {
    if (el) el.style.display = visible ? "" : "none";
  }

  /** Add event listener with null safety */
  function $on(el, event, fn, options) {
    if (el) el.addEventListener(event, fn, options);
  }

  /** Dispatch bubbling event */
  function $dispatch(el, eventName) {
    if (el) el.dispatchEvent(new Event(eventName, { bubbles: true }));
  }

  // Export
  window.$id = $id;
  window.$show = $show;
  window.$hide = $hide;
  window.$toggle = $toggle;
  window.$on = $on;
  window.$dispatch = $dispatch;

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { $id, $show, $hide, $toggle, $on, $dispatch };
  }
})(typeof window !== 'undefined' ? window : global);
