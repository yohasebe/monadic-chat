// Paths of the shared folder, shown by their file name. Where the page shows
// a path (the conversation, the work screen), the file name stands for it
// and the whole path is in its title; text copied from the page carries the
// whole path. Only what the page shows changes: what was sent, kept and
// exported is the text as written.
(function () {
  'use strict';

  // A path of the shared folder: as the conversation names it
  // (conversations/…), or as a chat's tools see it (/monadic/data/…).
  const PATH = /(?:\/monadic\/data\/|\/data\/)?conversations\/[^\s/`'"<>()]+(?:\/[^\s/`'"<>()]+)+|\/monadic\/data\/[^\s`'"<>()]+/g;
  const WHOLE = new RegExp('^(?:' + PATH.source + ')$');
  // Left as written: code, and what is being edited.
  const NOT_SHORTENED = 'pre, textarea, script, style, [contenteditable="true"]';
  const CLASS = 'short-path';

  // A path ends with a punctuation mark the sentence put after it.
  function trimmed(path) {
    return path.replace(/[.,;:!?]+$/, '');
  }

  function baseName(path) {
    const parts = path.split('/').filter(Boolean);
    return parts[parts.length - 1] || path;
  }

  function parentAndBase(path) {
    const parts = path.split('/').filter(Boolean);
    return parts.slice(-2).join('/');
  }

  function mark(el, path) {
    el.classList.add(CLASS);
    el.dataset.fullPath = path;
    el.title = path;
    el.textContent = baseName(path);
    if (!el.closest('a, button')) {
      el.tabIndex = 0;
      el.setAttribute('aria-label', path);
    }
  }

  // An element that is the path alone (a code span, a link's text).
  function shortenWhole(el) {
    if (el.classList.contains(CLASS) || el.children.length > 0) return;
    const text = el.textContent.trim();
    if (WHOLE.test(text)) mark(el, text);
  }

  // Paths inside running text.
  function shortenText(node) {
    const text = node.nodeValue;
    PATH.lastIndex = 0;
    if (!PATH.test(text)) return;
    PATH.lastIndex = 0;
    const pieces = document.createDocumentFragment();
    let at = 0;
    let m;
    while ((m = PATH.exec(text)) !== null) {
      const path = trimmed(m[0]);
      if (m.index > at) pieces.appendChild(document.createTextNode(text.slice(at, m.index)));
      const span = document.createElement('span');
      mark(span, path);
      pieces.appendChild(span);
      at = m.index + path.length;
      PATH.lastIndex = at;
    }
    if (at < text.length) pieces.appendChild(document.createTextNode(text.slice(at)));
    node.parentNode.replaceChild(pieces, node);
  }

  // Two files of one name in the same place are told apart by their folder.
  function disambiguate(root) {
    const byName = new Map();
    root.querySelectorAll('.' + CLASS).forEach((el) => {
      const name = baseName(el.dataset.fullPath);
      if (!byName.has(name)) byName.set(name, new Set());
      byName.get(name).add(el.dataset.fullPath);
    });
    root.querySelectorAll('.' + CLASS).forEach((el) => {
      const path = el.dataset.fullPath;
      const shown = byName.get(baseName(path)).size > 1 ? parentAndBase(path) : baseName(path);
      if (el.textContent !== shown) el.textContent = shown;
    });
  }

  function apply(root) {
    if (!root) return;
    root.querySelectorAll('code, a').forEach((el) => {
      if (!el.closest(NOT_SHORTENED)) shortenWhole(el);
    });
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.parentElement &&
        node.parentElement.closest(NOT_SHORTENED + ', code, .' + CLASS)
        ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(shortenText);
    disambiguate(root);
  }

  // What is copied from the page has the whole paths back.
  function onCopy(e) {
    const selection = window.getSelection ? window.getSelection() : null;
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
    const holder = document.createElement('div');
    for (let i = 0; i < selection.rangeCount; i += 1) {
      holder.appendChild(selection.getRangeAt(i).cloneContents());
    }
    const shortened = holder.querySelectorAll('.' + CLASS);
    if (shortened.length === 0 || !e.clipboardData) return;
    shortened.forEach((el) => { el.textContent = el.dataset.fullPath; });
    e.clipboardData.setData('text/plain', holder.textContent);
    e.preventDefault();
  }

  function watch(root) {
    if (!root || typeof MutationObserver === 'undefined') return;
    apply(root);
    let timer = null;
    const observer = new MutationObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        apply(root);
        // What this changed is not a change to look at again.
        observer.takeRecords();
      }, 150);
    });
    observer.observe(root, { childList: true, subtree: true, characterData: true });
  }

  document.addEventListener('copy', onCopy);
  watch($id('discourse'));

  window.ShortPaths = { apply, baseName };
  if (typeof module !== 'undefined' && module.exports) module.exports = window.ShortPaths;
})();
