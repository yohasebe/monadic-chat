// Paths of the shared folder, shown by their file name. Where the page shows
// a path (the conversation, the work screen), the file name stands for it
// and the whole path is in its title; text copied from the page, and text
// the page reads out of a card (restore, textOf), carries the whole path.
// Only what the page shows changes: what was sent, kept and exported is the
// text as written. A path that holds a word the chat hides is shown whole,
// where the hidden word is marked (word-table.js).
(function () {
  'use strict';

  // A path of the shared folder, standing on its own (not the end of a URL
  // or of another path): as the conversation names it (conversations/…), or
  // as a chat's tools see it (/monadic/data/…).
  const PATH = /(?<![\w./:\\-])(?:(?:\/monadic\/data\/|\/data\/)?conversations\/[^\s/`'"<>()]+(?:\/[^\s/`'"<>()]+)+|\/monadic\/data\/[^\s`'"<>()]+)/g;
  const WHOLE = new RegExp('^(?:' + PATH.source + ')$');
  // Left as written: code blocks, what is being edited, and a hidden word's mark.
  const NOT_SHORTENED = 'pre, textarea, script, style, [contenteditable="true"], .word-table-shown';
  const CLASS = 'short-path';

  // A path in running text ends before a punctuation mark the sentence put
  // after it.
  function trimmed(path) {
    return path.replace(/[.,;:!?]+$/, '');
  }

  function segments(path) {
    return path.split('/').filter(Boolean);
  }

  function baseName(path) {
    const parts = segments(path);
    return parts[parts.length - 1] || path;
  }

  function holdsHiddenWord(path) {
    return !!(window.WordTable && typeof window.WordTable.showsWordIn === 'function' &&
      window.WordTable.showsWordIn(path));
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
    if (WHOLE.test(text) && !holdsHiddenWord(text)) mark(el, text);
  }

  // Whether the text next to a node goes on without a space (a path that
  // runs into a hidden word's mark is cut there, and is not a path alone).
  function runsOn(sibling, atEnd) {
    if (!sibling) return false;
    const text = sibling.textContent;
    return !!text && /\S/.test(atEnd ? text[0] : text[text.length - 1]);
  }

  // Paths inside running text.
  function shortenText(node) {
    const text = node.nodeValue;
    const found = [];
    PATH.lastIndex = 0;
    let m;
    while ((m = PATH.exec(text)) !== null) {
      const path = trimmed(m[0]);
      const cut = (m.index === 0 && runsOn(node.previousSibling, false)) ||
        (m.index + m[0].length === text.length && runsOn(node.nextSibling, true));
      if (!cut && !holdsHiddenWord(path)) found.push({ at: m.index, path });
    }
    if (found.length === 0) return;
    const pieces = document.createDocumentFragment();
    let at = 0;
    found.forEach(({ at: start, path }) => {
      if (start > at) pieces.appendChild(document.createTextNode(text.slice(at, start)));
      const span = document.createElement('span');
      mark(span, path);
      pieces.appendChild(span);
      at = start + path.length;
    });
    if (at < text.length) pieces.appendChild(document.createTextNode(text.slice(at)));
    node.parentNode.replaceChild(pieces, node);
  }

  // The whole path back in place of each shortened one under root (a copy
  // of what the page shows, or the page itself when a path came to hold a
  // hidden word).
  function restore(root, only) {
    root.querySelectorAll('.' + CLASS).forEach((el) => {
      const path = el.dataset.fullPath;
      if (only && !only(path)) return;
      if (el.tagName === 'SPAN' && el.parentNode) {
        el.parentNode.replaceChild(document.createTextNode(path), el);
        return;
      }
      el.classList.remove(CLASS);
      delete el.dataset.fullPath;
      el.removeAttribute('title');
      el.removeAttribute('aria-label');
      el.removeAttribute('tabindex');
      el.textContent = path;
    });
    return root;
  }

  // The text of what the page shows, with the whole paths.
  function textOf(el) {
    return restore(el.cloneNode(true)).textContent;
  }

  // Files of one name are told apart by as many folders as it takes.
  function disambiguate(root) {
    const marks = Array.from(root.querySelectorAll('.' + CLASS));
    const byName = new Map();
    marks.forEach((el) => {
      const path = el.dataset.fullPath;
      const name = baseName(path);
      if (!byName.has(name)) byName.set(name, new Set());
      byName.get(name).add(path);
    });
    const shownFor = new Map();
    byName.forEach((paths) => {
      const list = Array.from(paths);
      let depth = 1;
      const longest = Math.max(...list.map((p) => segments(p).length));
      const tail = (p, n) => segments(p).slice(-n).join('/');
      while (depth < longest && new Set(list.map((p) => tail(p, depth))).size < list.length) depth += 1;
      list.forEach((p) => shownFor.set(p, tail(p, depth)));
    });
    marks.forEach((el) => {
      const shown = shownFor.get(el.dataset.fullPath);
      if (el.textContent !== shown) el.textContent = shown;
    });
  }

  function apply(root) {
    if (!root) return;
    restore(root, holdsHiddenWord);
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

  // What is copied from the page has the whole paths back. The text is the
  // browser's own (line breaks kept); each shortened name in it, or the part
  // of one where the selection starts or ends, is put back as its path.
  function copiedText(selection) {
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    const within = (node) => {
      const el = node && (node.nodeType === 1 ? node : node.parentElement);
      return el ? el.closest('.' + CLASS) : null;
    };
    const first = within(range.startContainer);
    const last = within(range.endContainer);
    const root = range.commonAncestorContainer.nodeType === 1
      ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement;
    const marks = (first && first === last) ? [first]
      : Array.from(root.querySelectorAll('.' + CLASS)).filter((el) => range.intersectsNode(el));
    if (marks.length === 0) return null;
    const text = selection.toString();
    let out = '';
    let at = 0;
    marks.forEach((el) => {
      const shown = el.textContent;
      let from = 0;
      let to = shown.length;
      if (el === first && el.contains(range.startContainer)) from = range.startOffset;
      if (el === last && el.contains(range.endContainer)) to = range.endOffset;
      const part = shown.slice(from, to);
      const i = part ? text.indexOf(part, at) : -1;
      if (i < 0) return;
      out += text.slice(at, i) + el.dataset.fullPath;
      at = i + part.length;
    });
    return at === 0 && out === '' ? null : out + text.slice(at);
  }

  function onCopy(e) {
    if (!e.clipboardData) return;
    const text = copiedText(window.getSelection ? window.getSelection() : null);
    if (text === null) return;
    e.clipboardData.setData('text/plain', text);
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
    // The chat's hidden words changed: a path may now hold one, or no more.
    document.addEventListener('wordtable:changed', () => apply(root));
  }

  document.addEventListener('copy', onCopy);
  watch($id('discourse'));

  window.ShortPaths = { apply, restore, textOf, baseName };
  if (typeof module !== 'undefined' && module.exports) module.exports = window.ShortPaths;
})();
