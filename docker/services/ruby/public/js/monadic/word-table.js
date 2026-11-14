// The words a chat hides from what it sends. The button asks the server to
// find names in the message; the user decides here what to hide, and the
// server keeps the decisions (the chat's word table). What is found stays on
// this page until it is decided.
(function () {
  'use strict';

  const TYPES = {
    PERSON: 'person',
    ORGANIZATION: 'organization',
    LOCATION: 'location',
    EMAIL_ADDRESS: 'email',
    PHONE_NUMBER: 'phone',
    URL: 'url',
    DATE_TIME: 'date'
  };
  const MAX_WORD_CHARS = 200;

  const state = {
    chat: null, marked: false, unavailable: false, active: [], kept: [],
    drafts: [], leave: [], open: false, finding: null, findFailed: false,
    waiting: null, queue: [], resume: null, seq: 0, noticed: false
  };

  function t(key, fallback) {
    try {
      if (typeof webUIi18n !== 'undefined') {
        const v = webUIi18n.t(key);
        if (v && v !== key) return v;
      }
    } catch (_) { /* fall back */ }
    return fallback;
  }

  function typeName(type) {
    const name = TYPES[type];
    return name ? t('ui.privacyMark.' + name, type) : type;
  }

  // The text in order, each piece { text } or, for a word to hide,
  // { text, word }. The longest word is taken where several start together.
  function splitByWords(text, words) {
    const list = Array.from(new Set(words)).filter(Boolean).sort((a, b) => b.length - a.length);
    if (list.length === 0) return text ? [{ text: text }] : [];
    const pattern = new RegExp(list.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'g');
    const parts = [];
    let at = 0;
    text.replace(pattern, (match, offset) => {
      if (offset > at) parts.push({ text: text.slice(at, offset) });
      parts.push({ text: match, word: match });
      at = offset + match.length;
      return match;
    });
    if (at < text.length) parts.push({ text: text.slice(at) });
    return parts;
  }

  // Why the selection cannot be a word to hide, or null.
  function selectionProblem(word) {
    if (!word.trim()) return 'selectFirst';
    if (/[\r\n]/.test(word)) return 'oneLine';
    if (word.includes('<<') || word.includes('>>') || word.length > MAX_WORD_CHARS) return 'cannotHide';
    return null;
  }

  function hiddenWords() {
    return state.active.map((e) => e.word).concat(state.drafts.map((e) => e.word));
  }

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function offButton(word, label, onClick) {
    const button = element('button', 'word-table-off');
    button.appendChild(element('i', 'fa-solid fa-xmark'));
    button.type = 'button';
    button.title = label;
    button.setAttribute('aria-label', label + ': ' + word);
    $on(button, 'click', onClick);
    return button;
  }

  function takeOff(word) {
    const draft = state.drafts.findIndex((e) => e.word === word);
    if (draft >= 0) {
      state.drafts.splice(draft, 1);
      if (!state.leave.includes(word)) state.leave.push(word);
      render();
    } else {
      change({ keep: [word] });
    }
  }

  function renderPreview() {
    const box = $id('word-table-preview');
    if (!box) return;
    const message = $id('message');
    box.textContent = '';
    splitByWords(message ? message.value : '', hiddenWords()).forEach((part) => {
      if (!part.word) {
        box.appendChild(document.createTextNode(part.text));
        return;
      }
      const entry = state.active.concat(state.drafts).find((e) => e.word === part.word);
      const mark = element('mark', 'word-table-hidden');
      mark.appendChild(element('span', 'word-table-type', typeName(entry.type)));
      mark.appendChild(document.createTextNode(part.text));
      mark.appendChild(offButton(part.word, t('ui.wordTable.off', 'Do not hide'), () => takeOff(part.word)));
      box.appendChild(mark);
    });
  }

  function typeSelect(current, onChange) {
    const select = element('select', 'form-select word-table-type-select');
    Object.keys(TYPES).concat(TYPES[current] ? [] : [current]).forEach((type) => {
      const option = element('option', '', typeName(type));
      option.value = type;
      select.appendChild(option);
    });
    select.value = current;
    $on(select, 'change', () => onChange(select.value));
    return select;
  }

  function renderList() {
    const list = $id('word-table-list');
    if (list) {
      list.textContent = '';
      state.active.concat(state.drafts).forEach((entry) => {
        const isDraft = state.drafts.includes(entry);
        const row = element('span', 'word-table-word' + (isDraft ? ' word-table-draft' : ''));
        row.appendChild(element('span', 'word-table-text', entry.word));
        row.appendChild(typeSelect(entry.type, (type) => {
          if (isDraft) { entry.type = type; render(); } else { change({ hide: [{ word: entry.word, type: type }] }); }
        }));
        row.appendChild(offButton(entry.word, t('ui.wordTable.off', 'Do not hide'), () => takeOff(entry.word)));
        list.appendChild(row);
      });
    }
    const kept = $id('word-table-kept');
    if (!kept) return;
    kept.textContent = '';
    const shownAsIs = state.kept.concat(state.leave.filter((w) => !state.kept.includes(w)));
    if (shownAsIs.length === 0) return;
    kept.appendChild(element('span', 'word-table-kept-label', t('ui.wordTable.notHidden', 'Not hidden:')));
    shownAsIs.forEach((word) => {
      const button = element('button', 'word-table-putback', word);
      button.type = 'button';
      button.title = t('ui.wordTable.putBack', 'Offer this word again');
      $on(button, 'click', () => {
        if (state.leave.includes(word)) {
          state.leave = state.leave.filter((w) => w !== word);
          render();
        } else {
          change({ show: [word] });
        }
      });
      kept.appendChild(button);
    });
  }

  function renderStatus() {
    const status = $id('word-table-status');
    if (!status) return;
    status.style.display = state.marked ? '' : 'none';
    status.classList.toggle('word-table-unavailable', state.unavailable);
    status.textContent = state.unavailable
      ? t('ui.wordTable.unavailable', 'Word table not available: nothing is sent')
      : t('ui.wordTable.status', 'Hidden: {n}').replace('{n}', String(state.active.length));
  }

  function render() {
    const panel = $id('word-table-panel');
    if (panel) panel.style.display = state.open ? '' : 'none';
    renderStatus();
    if (!state.open) return;
    renderPreview();
    renderList();
  }

  function showError(code, detail) {
    const box = $id('word-table-error');
    if (!box) return;
    box.textContent = code ? (detail || t('ui.wordTable.errors.' + code, code)) : '';
    box.style.display = code ? '' : 'none';
  }

  function dropChanges() {
    state.waiting = null;
    state.queue = [];
    state.resume = null;
  }

  // One change at a time: each answer belongs to the change it was sent for.
  function sendNextChange() {
    if (state.waiting || state.queue.length === 0) return;
    const next = state.queue.shift();
    const request = ++state.seq;
    state.waiting = { request: request, then: next.then };
    const result = window.safeWsSend(Object.assign({ message: 'WORDS_CHANGE', chat: state.chat, request: request }, next.ops));
    if (!result || !result.sent) dropChanges();
  }

  function change(ops, then) {
    state.queue.push({ ops: ops, then: then || null });
    showError(null);
    sendNextChange();
  }

  function decided() {
    return state.drafts.length > 0 || state.leave.length > 0;
  }

  // Only what this change carries is settled when it is taken: what was
  // added or altered meanwhile stays undecided.
  function apply() {
    const hide = state.drafts.map((e) => ({ word: e.word, type: e.type }));
    const keep = state.leave.slice();
    change({ hide: hide, keep: keep }, () => {
      state.drafts = state.drafts.filter((e) => !hide.some((h) => h.word === e.word && h.type === e.type));
      state.leave = state.leave.filter((w) => !keep.includes(w));
      if (!decided() && state.finding === null && !state.findFailed) state.open = false;
      render();
    });
  }

  function open() {
    state.open = true;
    showError(state.unavailable ? 'table_unavailable' : null);
    render();
  }

  // Closing gives up a search still running: its answer is ignored.
  function close() {
    state.open = false;
    state.finding = null;
    state.findFailed = false;
    showError(null);
    render();
  }

  function fail(code, detail) {
    open();
    showError(code, detail);
  }

  function find() {
    open();
    state.findFailed = false;
    const message = $id('message');
    const text = message ? message.value : '';
    if (!text.trim()) return;
    state.finding = ++state.seq;
    const result = window.safeWsSend({ message: 'WORDS_FIND', text: text, request: state.finding });
    if (!result || !result.sent) {
      state.finding = null;
      state.findFailed = true;
    }
  }

  // The words selected in the text of the panel, or null.
  function selectedWord() {
    const selection = window.getSelection ? window.getSelection() : null;
    const box = $id('word-table-preview');
    if (!selection || selection.isCollapsed || !box) return null;
    if (!box.contains(selection.anchorNode) || !box.contains(selection.focusNode)) return null;
    return selection.toString();
  }

  function hideAddMenu() {
    const menu = $id('word-table-add');
    if (menu) menu.style.display = 'none';
  }

  function hideAs(word, type) {
    state.leave = state.leave.filter((w) => w !== word);
    if (!hiddenWords().includes(word)) state.drafts.push({ word: word, type: type });
    state.findFailed = false;
    showError(null);
    hideAddMenu();
    render();
  }

  // Under the selection, as far left as it fits in the panel.
  function placeAddMenu(menu) {
    const wrap = menu.parentElement;
    const selection = window.getSelection();
    if (!wrap || !selection || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0).getBoundingClientRect();
    const area = wrap.getBoundingClientRect();
    menu.style.top = (range.bottom - area.top + 6) + 'px';
    menu.style.left = Math.max(0, Math.min(range.left - area.left, area.width - menu.offsetWidth)) + 'px';
  }

  // Words selected in the text are offered to be hidden, by type, beside
  // the selection.
  function offerSelection() {
    const menu = $id('word-table-add');
    if (!menu) return;
    const word = selectedWord();
    if (word === null) {
      hideAddMenu();
      return;
    }
    menu.textContent = '';
    const problem = selectionProblem(word);
    if (problem) {
      menu.appendChild(element('span', 'word-table-add-problem', t('ui.wordTable.errors.' + problem, problem)));
    } else {
      menu.appendChild(element('span', 'word-table-add-label', t('ui.wordTable.addAs', 'Hide as')));
      Object.keys(TYPES).forEach((type) => {
        const button = element('button', 'btn btn-outline-primary word-table-add-type', typeName(type));
        button.type = 'button';
        // The button does not take the focus: the selected words stay selected.
        $on(button, 'mousedown', (e) => e.preventDefault());
        $on(button, 'click', () => hideAs(word, type));
        menu.appendChild(button);
      });
    }
    menu.style.display = '';
    placeAddMenu(menu);
  }

  // The chat's hidden words where the conversation shows them: each is marked,
  // and says what the chat sent in its place.
  const NOT_MARKED = 'code, pre, textarea, script, style, [contenteditable="true"]';
  let shownObserver = null;
  let shownTimer = null;

  function unwrapShown(root) {
    root.querySelectorAll('.word-table-shown').forEach((span) => {
      const parent = span.parentNode;
      parent.replaceChild(document.createTextNode(span.textContent), span);
      parent.normalize();
    });
  }

  function markShown() {
    const root = $id('discourse');
    if (!root) return;
    unwrapShown(root);
    const byWord = new Map(state.active.map((entry) => [entry.word, entry]));
    if (byWord.size > 0) {
      root.querySelectorAll('.card-text').forEach((cardText) => {
        const walker = document.createTreeWalker(cardText, NodeFilter.SHOW_TEXT, {
          acceptNode: (node) => (node.parentElement && node.parentElement.closest(NOT_MARKED)
            ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
        });
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        nodes.forEach((node) => {
          const parts = splitByWords(node.nodeValue, Array.from(byWord.keys()));
          if (!parts.some((part) => part.word)) return;
          const pieces = document.createDocumentFragment();
          parts.forEach((part) => {
            if (!part.word) {
              pieces.appendChild(document.createTextNode(part.text));
              return;
            }
            const entry = byWord.get(part.word);
            const span = element('span', 'word-table-shown', part.text);
            span.title = t('ui.wordTable.shownTitle', 'Sent as {placeholder}')
              .replace('{placeholder}', entry.placeholder || typeName(entry.type));
            pieces.appendChild(span);
          });
          node.parentNode.replaceChild(pieces, node);
        });
      });
    }
    // What this changed is not a change to mark again.
    if (shownObserver) shownObserver.takeRecords();
  }

  // A placeholder as a file holds it (what a model wrote, kept as written).
  const PLACEHOLDER = /<<[\s?]*([A-Z][A-Z_]*_\d+)[\s?]*>>/g;

  // In root (text drawn from a file of the chat, such as its state notes),
  // each placeholder of a word the chat hides is shown as the word; its
  // title says how the file holds it. Only what is drawn changes: the file
  // and what is sent keep the placeholder. Done again when the table
  // changes: what was shown before is put back first.
  function showWordsIn(root) {
    if (!root) return;
    root.querySelectorAll('.word-table-shown[data-placeholder]').forEach((span) => {
      const parent = span.parentNode;
      parent.replaceChild(document.createTextNode(span.dataset.placeholder), span);
      parent.normalize();
    });
    const byId = new Map(state.active.map((entry) => [String(entry.placeholder || '').slice(2, -2), entry]));
    if (byId.size === 0) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.parentElement && node.parentElement.closest(NOT_MARKED)
        ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach((node) => {
      const text = node.nodeValue;
      const pieces = document.createDocumentFragment();
      let at = 0;
      let found = false;
      text.replace(PLACEHOLDER, (match, id, offset) => {
        const entry = byId.get(id);
        if (!entry) return match;
        found = true;
        if (offset > at) pieces.appendChild(document.createTextNode(text.slice(at, offset)));
        const span = element('span', 'word-table-shown', entry.word);
        span.dataset.placeholder = match;
        span.title = t('ui.wordTable.writtenTitle', 'Written in the file as {placeholder}')
          .replace('{placeholder}', entry.placeholder);
        pieces.appendChild(span);
        at = offset + match.length;
        return match;
      });
      if (!found) return;
      if (at < text.length) pieces.appendChild(document.createTextNode(text.slice(at)));
      node.parentNode.replaceChild(pieces, node);
    });
  }

  // The Markdown the work screen has drawn, shown again with the table as
  // it is now.
  function showWordsOnWorkScreen() {
    document.querySelectorAll('.workbench-markdown').forEach(showWordsIn);
  }

  function markShownSoon() {
    clearTimeout(shownTimer);
    shownTimer = setTimeout(markShown, 150);
  }

  function watchShown() {
    const root = $id('discourse');
    if (!root || typeof MutationObserver === 'undefined') return;
    shownObserver = new MutationObserver(markShownSoon);
    shownObserver.observe(root, { childList: true, subtree: true, characterData: true });
  }

  function handleTable(data) {
    if (data.chat !== state.chat) {
      state.drafts = [];
      state.leave = [];
      state.open = false;
      state.finding = null;
      state.findFailed = false;
      dropChanges();
      state.noticed = false;
      state.chat = data.chat;
    }
    state.marked = !!data.marked;
    state.unavailable = !!data.unavailable;
    state.active = Array.isArray(data.active) ? data.active : [];
    state.kept = Array.isArray(data.kept) ? data.kept : [];
    render();
    markShown();
    showWordsOnWorkScreen();
    document.dispatchEvent(new CustomEvent('wordtable:changed'));
  }

  function handleFound(data) {
    if (data.request !== state.finding) return;
    state.finding = null;
    if (data.chat !== state.chat) return;
    if (data.error) {
      state.findFailed = true;
      fail(data.error, data.detail);
      return;
    }
    (data.candidates || []).forEach((candidate) => {
      if (!hiddenWords().includes(candidate.word) && !state.leave.includes(candidate.word)) {
        state.drafts.push({ word: candidate.word, type: candidate.type });
      }
    });
    render();
  }

  function handleChanged(data) {
    const waiting = state.waiting;
    if (!waiting || data.request !== waiting.request) return;
    state.waiting = null;
    if (data.success) {
      if (waiting.then) waiting.then();
    } else {
      state.resume = null;
      fail(data.error, data.detail);
    }
    sendNextChange();
    if (state.waiting || !state.resume) return;
    const resend = state.resume;
    state.resume = null;
    resend();
  }

  // Nothing more comes for what was asked before the connection closed.
  function connectionLost() {
    const searching = state.finding !== null;
    const changing = !!state.waiting;
    state.finding = null;
    dropChanges();
    if (searching) {
      state.findFailed = true;
      fail('words_find_failed');
    } else if (changing) {
      fail('words_refused');
    }
  }

  // A search still running, or one that failed, stops what would go out
  // until the user has seen the result or closed the panel.
  function searchHolds() {
    if (state.finding !== null) {
      showError('stillFinding');
      return true;
    }
    if (state.findFailed) {
      showError('closeToSend');
      return true;
    }
    return false;
  }

  // Whether a request carrying the chat's text has to wait. true: resend
  // repeats it once what was decided here has been taken, and is asked
  // again then.
  function holdSend(resend) {
    if (searchHolds()) return true;
    if (state.waiting) {
      state.resume = resend;
      return true;
    }
    if (!decided()) return false;
    state.resume = resend;
    apply();
    return true;
  }

  // Reading aloud decides nothing: it waits until the words shown here are
  // decided by the user.
  function holdSpeech() {
    if (searchHolds()) return true;
    if (!decided()) return false;
    open();
    showError('decideFirst');
    return true;
  }

  // Once for a chat: what is not hidden is said before it goes.
  function noticeNotHidden() {
    if (!state.marked || state.noticed) return;
    state.noticed = true;
    if (typeof setAlert === 'function') {
      setAlert(t('ui.wordTable.notHiddenNotice', 'Images and voice are sent as they are: their words are not hidden.'), 'info');
    }
  }

  // A file of an earlier version: its words are hidden here from now on,
  // and the panel shows which, for the user to check.
  function noticeOlderFile(count) {
    state.open = true;
    render();
    const box = $id('word-table-error');
    if (!box) return;
    box.textContent = t('ui.wordTable.olderFile', 'The {n} words this file hides are hidden in this chat. Check them here.').replace('{n}', String(count));
    box.style.display = '';
  }

  function init() {
    $on($id('anonymize'), 'click', find);
    $on($id('word-table-status'), 'click', () => {
      if (state.open) close(); else open();
    });
    $on($id('word-table-close'), 'click', close);
    $on($id('word-table-apply'), 'click', () => {
      if (decided()) apply();
      else if (!searchHolds()) close();
    });
    const preview = $id('word-table-preview');
    $on(preview, 'mouseup', () => setTimeout(offerSelection, 0));
    $on(preview, 'keyup', () => setTimeout(offerSelection, 0));
    document.addEventListener('selectionchange', () => { if (selectedWord() === null) hideAddMenu(); });
    $on($id('word-table-help'), 'click', function () {
      const how = $id('word-table-how');
      if (!how) return;
      const showing = how.style.display === 'none';
      how.style.display = showing ? '' : 'none';
      this.setAttribute('aria-expanded', String(showing));
    });
    $on($id('message'), 'input', () => { if (state.open) renderPreview(); });
    $on($id('voice'), 'click', noticeNotHidden);
    $on($id('image-file'), 'click', noticeNotHidden);
    watchShown();
    render();
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  const api = {
    handleTable: handleTable, handleFound: handleFound, handleChanged: handleChanged,
    holdSend: holdSend, holdSpeech: holdSpeech, noticeOlderFile: noticeOlderFile, connectionLost: connectionLost, find: find,
    showWordsIn: showWordsIn,
    isMarked: () => state.marked, hidesWords: () => state.active.length > 0, chat: () => state.chat,
    // Whether text holds a word the conversation marks as hidden.
    showsWordIn: (text) => splitByWords(String(text), state.active.map((e) => e.word)).some((part) => part.word)
  };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = Object.assign({ splitByWords: splitByWords, selectionProblem: selectionProblem, offerSelection: offerSelection, markShown: markShown, _state: state, init: init }, api);
  }
  if (typeof window !== 'undefined') window.WordTable = api;
})();
