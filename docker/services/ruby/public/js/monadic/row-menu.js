/**
 * row-menu.js
 *
 * The small menu of a row or a band in the side column ("⋯" in the Files
 * and History tabs) and the panel of a button (the filters): one at a time,
 * in the look of Bootstrap's dropdown menu. It is put on the body and
 * placed by its button (fixed), not inside the column: the column scrolls
 * and is its own layer (overflow, transform), which would cut it off.
 *
 *   RowMenu.open(button, items, opts): items are { label, icon, action,
 *     disabled, title, danger } (or 'divider'). ↑ and ↓ move between them,
 *     Enter or Space runs one, Esc or Tab closes. opts.restore: where the
 *     focus goes back when the button is gone (its list was drawn anew).
 *   RowMenu.openPanel(button, node): node (a form) is shown as it is; Esc
 *     closes. Changes in it act at once (no Apply).
 *   RowMenu.close()
 *
 * It closes on a click outside, on Esc or Tab, when the page or a column
 * scrolls, and when the window is resized. When the focus was in it, it
 * goes back to its button (or to opts.restore when the button is gone); a
 * click elsewhere keeps the focus where it went.
 */
(function () {
  'use strict';

  let current = null; // { box, button, onClose }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  // Under the button, its right edges aligned; above it when there is no
  // room below; always inside the window.
  function place(box, button) {
    const r = button.getBoundingClientRect();
    const w = box.offsetWidth;
    const h = box.offsetHeight;
    const margin = 4;
    let left = Math.min(r.right - w, window.innerWidth - w - margin);
    left = Math.max(margin, left);
    let top = r.bottom + 2;
    if (top + h > window.innerHeight - margin && r.top - h - 2 >= margin) top = r.top - h - 2;
    top = Math.max(margin, Math.min(top, window.innerHeight - h - margin));
    box.style.left = `${Math.round(left)}px`;
    box.style.top = `${Math.round(top)}px`;
  }

  function items() {
    return current ? Array.from(current.box.querySelectorAll('.dropdown-item:not(:disabled)')) : [];
  }

  function onKey(e) {
    if (!current) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      close(true);
      return;
    }
    if (!current.list) return;
    const list = items();
    const at = list.indexOf(document.activeElement);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (!list.length) return;
      const next = at < 0 ? 0 : (at + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length;
      list[next].focus();
    } else if (e.key === 'Tab') {
      // The menu is at the end of the page: the focus goes back to its
      // button rather than past everything.
      e.preventDefault();
      close(true);
    }
  }

  function onOutside(e) {
    if (!current) return;
    if (current.box.contains(e.target) || current.button.contains(e.target)) return;
    close(false);
  }

  function onMove(e) {
    if (!current) return;
    if (e && e.type === 'scroll' && current.box.contains(e.target)) return;
    close(false);
  }

  function show(button, box, list, onClose, restore) {
    close(false);
    box.classList.add('row-menu', 'dropdown-menu', 'show');
    box.style.position = 'fixed';
    box.style.margin = '0';
    box.style.maxHeight = 'calc(100vh - 8px)';
    box.style.overflowY = 'auto';
    document.body.appendChild(box);
    current = { box: box, button: button, list: list, onClose: onClose, restore: restore };
    button.setAttribute('aria-expanded', 'true');
    place(box, button);
    document.addEventListener('keydown', onKey, true);
    document.addEventListener('mousedown', onOutside, true);
    window.addEventListener('resize', onMove);
    document.addEventListener('scroll', onMove, true);
  }

  // back: the focus returns to the button (Esc, or after an item ran); it
  // does also when it was in the menu (a scroll or a resize closed it).
  function close(back) {
    if (!current) return;
    const { box, button, onClose, restore } = current;
    const focusWasIn = box.contains(document.activeElement);
    current = null;
    document.removeEventListener('keydown', onKey, true);
    document.removeEventListener('mousedown', onOutside, true);
    window.removeEventListener('resize', onMove);
    document.removeEventListener('scroll', onMove, true);
    box.remove();
    button.setAttribute('aria-expanded', 'false');
    if (back || focusWasIn) {
      if (button.isConnected && typeof button.focus === 'function') button.focus({ preventScroll: true });
      else if (typeof restore === 'function') restore();
    }
    if (typeof onClose === 'function') onClose();
  }

  function open(button, entries, opts) {
    if (current && current.button === button) { close(true); return; }
    const box = element('div');
    box.setAttribute('role', 'menu');
    (entries || []).forEach(function (entry) {
      if (entry === 'divider') {
        box.appendChild(element('hr', 'dropdown-divider'));
        return;
      }
      const item = element('button', `dropdown-item${entry.danger ? ' text-danger' : ''}`);
      item.type = 'button';
      item.setAttribute('role', 'menuitem');
      if (entry.icon) {
        const i = element('i', `${entry.icon} me-2`);
        i.setAttribute('aria-hidden', 'true');
        item.appendChild(i);
      }
      item.appendChild(document.createTextNode(entry.label));
      if (entry.title) item.title = entry.title;
      item.disabled = !!entry.disabled;
      item.addEventListener('click', function () {
        close(true);
        if (typeof entry.action === 'function') entry.action();
      });
      box.appendChild(item);
    });
    show(button, box, true, null, opts && opts.restore);
    const first = items()[0];
    if (first) first.focus({ preventScroll: true });
  }

  function openPanel(button, node, onClose) {
    if (current && current.button === button) { close(true); return; }
    const box = element('div', 'row-menu-panel');
    box.appendChild(node);
    show(button, box, false, onClose);
    const first = box.querySelector('select, input, button');
    if (first) first.focus({ preventScroll: true });
  }

  function isOpen() {
    return !!current;
  }

  const api = { open: open, openPanel: openPanel, close: close, isOpen: isOpen };
  window.RowMenu = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
