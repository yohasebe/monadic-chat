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

  function validate() {
    const v = pp.value;
    if (confirmRequired) {
      const v2 = pp2.value;
      if (v.length < 8) {
        err.textContent = 'Passphrase must be at least 8 characters.';
        ok.disabled = true;
        return false;
      }
      if (v !== v2) {
        err.textContent = 'Passphrases do not match.';
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

  // Receive initial config from main process (title, hint, confirmRequired).
  window.passphraseAPI.onInit((opts) => {
    if (opts && opts.title) titleEl.textContent = opts.title;
    if (opts && opts.hint) hintEl.textContent = opts.hint;
    if (opts && opts.confirmRequired === false) {
      confirmRequired = false;
      confirmRow.style.display = 'none';
    }
    pp.focus();
  });
})();
