// Renderer for the passphrase prompt window. Communicates with main via the
// dedicated preload (window.passphraseAPI) so contextIsolation stays on.

(function () {
  'use strict';

  const pp = document.getElementById('pp');
  const pp2 = document.getElementById('pp2');
  const err = document.getElementById('err');
  const ok = document.getElementById('ok');
  const cancel = document.getElementById('cancel');
  const titleEl = document.getElementById('title');
  const hintEl = document.getElementById('hint');
  const confirmRow = document.getElementById('confirm-row');

  let confirmRequired = true;
  // English until main sends the app's language with the init message.
  let messages = {
    tooShort: 'Passphrase must be at least 8 characters.',
    mismatch: 'Passphrases do not match.'
  };

  function validate() {
    const v = pp.value;
    if (confirmRequired) {
      const v2 = pp2.value;
      if (v.length < 8) {
        err.textContent = messages.tooShort;
        ok.disabled = true;
        return false;
      }
      if (v !== v2) {
        err.textContent = messages.mismatch;
        ok.disabled = true;
        return false;
      }
    } else {
      if (v.length < 1) {
        err.textContent = '';
        ok.disabled = true;
        return false;
      }
    }
    err.textContent = '';
    ok.disabled = false;
    return true;
  }

  pp.addEventListener('input', validate);
  pp2.addEventListener('input', validate);

  ok.addEventListener('click', () => {
    if (validate()) {
      window.passphraseAPI.submit({ ok: true, passphrase: pp.value });
    }
  });

  cancel.addEventListener('click', () => {
    window.passphraseAPI.submit({ ok: false });
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      window.passphraseAPI.submit({ ok: false });
    }
    if (e.key === 'Enter' && !ok.disabled) {
      ok.click();
    }
  });

  // Receive initial config from main process (title, hint, confirmRequired,
  // and the window's own words in the app's language).
  window.passphraseAPI.onInit((opts) => {
    const labels = (opts && opts.labels) || {};
    if (opts && opts.lang) document.documentElement.lang = opts.lang;
    if (labels.windowTitle) document.title = labels.windowTitle;
    if (labels.label) document.getElementById('label-pp').textContent = labels.label;
    if (labels.confirmLabel) document.getElementById('label-pp2').textContent = labels.confirmLabel;
    if (labels.cancel) cancel.textContent = labels.cancel;
    if (labels.ok) ok.textContent = labels.ok;
    messages = {
      tooShort: labels.tooShort || messages.tooShort,
      mismatch: labels.mismatch || messages.mismatch
    };
    if (opts && opts.title) titleEl.textContent = opts.title;
    if (opts && opts.hint) hintEl.textContent = opts.hint;
    if (opts && opts.confirmRequired === false) {
      confirmRequired = false;
      confirmRow.style.display = 'none';
    }
    pp.focus();
    // Long titles and hints (translations) wrap; measure once the font is in.
    document.fonts.ready.then(() => {
      window.passphraseAPI.fit(Math.ceil(document.body.getBoundingClientRect().height));
    });
  });
})();
