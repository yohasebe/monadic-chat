// Marking words for the Privacy Filter in the message box: the selection is
// wrapped as ⟦word⟧ (a person) or ⟦word|type⟧. The server takes the marks
// out, keeps the words for the chat and masks them wherever they occur. The
// button shows only while the Privacy Filter is on for the chat.
(function () {
  'use strict';

  const OPEN = '⟦';
  const CLOSE = '⟧';
  // The type words the server reads (Privacy::Marks), in English so they are
  // read the same whatever the page's language. The type is always written,
  // a person too: a "|" in the selected words is then never taken for the
  // separator of a type.
  const TYPE_WORDS = {
    PERSON: 'person',
    ORGANIZATION: 'organization',
    LOCATION: 'location',
    EMAIL_ADDRESS: 'email',
    PHONE_NUMBER: 'phone',
    URL: 'url',
    DATE_TIME: 'date'
  };

  // The text with the range [start, end) marked, or an error.
  function markRange(text, start, end, type) {
    const word = text.slice(start, end);
    if (!word.trim()) return { error: 'empty' };
    if (/[\r\n]/.test(word)) return { error: 'line' };
    if (word.includes(OPEN) || word.includes(CLOSE)) return { error: 'nested' };
    const typeWord = TYPE_WORDS[type];
    const marked = OPEN + word + '|' + typeWord + CLOSE;
    return { text: text.slice(0, start) + marked + text.slice(end), caret: start + marked.length };
  }

  function t(key, fallback) {
    try {
      if (typeof webUIi18n !== 'undefined') {
        const v = webUIi18n.t('ui.privacyMark.' + key);
        if (v && v !== 'ui.privacyMark.' + key) return v;
      }
    } catch (_) { /* fall back */ }
    return fallback;
  }

  function markSelection(type) {
    const box = $id('message');
    if (!box) return;
    const result = markRange(box.value, box.selectionStart, box.selectionEnd, type || 'PERSON');
    if (result.error) {
      const messages = {
        empty: t('selectFirst', 'Select the words to mask first.'),
        line: t('oneLine', 'A mark cannot span more than one line.'),
        nested: t('nested', 'The selection already contains a mark.')
      };
      if (typeof setAlert === 'function') setAlert(messages[result.error], 'warning');
      return;
    }
    box.value = result.text;
    box.focus();
    box.setSelectionRange(result.caret, result.caret);
    box.dispatchEvent(new Event('input', { bubbles: true }));
  }

  // On for the chat: checked, and either still editable or locked because
  // the chat has begun (the toggle is locked after the first message, which
  // is when marking matters most). Disabled without the lock means the app
  // has no Privacy Filter.
  function privacyOn() {
    const toggle = $id('check-privacy-session');
    return !!(toggle && toggle.checked && (!toggle.disabled || window.privacyToggleLocked));
  }

  function refresh() {
    const group = $id('privacy-mark-group');
    if (group) group.style.display = privacyOn() ? '' : 'none';
  }

  function init() {
    // The buttons and the type menu do not take the focus from the message
    // box, so the selected words stay selected (and shown) while the menu
    // is open.
    const group = $id('privacy-mark-group');
    $on(group, 'mousedown', function (e) { e.preventDefault(); });
    $on($id('privacy-mark'), 'click', function () { markSelection('PERSON'); });
    document.querySelectorAll('[data-privacy-mark-type]').forEach(function (item) {
      $on(item, 'click', function (e) {
        e.preventDefault();
        markSelection(item.getAttribute('data-privacy-mark-type'));
      });
    });
    // Ctrl/Cmd + Shift + K in the message box marks the selection.
    $on($id('message'), 'keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && !e.altKey && (e.key === 'K' || e.key === 'k') && privacyOn()) {
        e.preventDefault();
        markSelection('PERSON');
      }
    });
    $on($id('check-privacy-session'), 'change', refresh);
    document.addEventListener('privacy:state-changed', refresh);
    refresh();
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { markRange: markRange, TYPE_WORDS: TYPE_WORDS };
  }
  if (typeof window !== 'undefined') window.PrivacyMark = { markSelection: markSelection, refresh: refresh };
})();
