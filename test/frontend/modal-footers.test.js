/**
 * @jest-environment jsdom
 */
// Modal footers follow one rule set: confirm and input dialogs end with a grey
// Cancel and the action on the right; a delete is one red button. And while
// a dialog is open, the chat's Easy Submit keys leave the keyboard to it.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const erb = fs.readFileSync(path.join(ROOT, 'docker/services/ruby/views/index.erb'), 'utf8');

function footerOf(id) {
  const at = erb.indexOf(`id="${id}"`);
  const start = erb.indexOf('<div class="modal-footer', at);
  return erb.slice(start, erb.indexOf('</div>\n', erb.indexOf('<button', start) + 1) + 400);
}

describe('modal footers', () => {
  // The footer's buttons in order, by meaning: a grey Cancel only closes the
  // dialog (whatever other classes the shared buttons give it).
  const buttonsOf = (footer) => Array.from(footer.matchAll(/<button\b[^>]*>/g), (m) => {
    const tag = m[0];
    const cls = (tag.match(/class="([^"]*)"/) || [, ''])[1].split(/\s+/);
    return {
      cancel: /data-dialog-close/.test(tag) && /data-i18n="ui\.cancel"/.test(tag) && cls.includes('btn-secondary'),
      meaning: ['btn-primary', 'btn-secondary', 'btn-danger', 'btn-warning'].find((k) => cls.includes(k)) || null,
      kinds: cls.filter((c) => /^btn-(warning|outline-)/.test(c))
    };
  });

  test.each(['loadModal', 'docModal', 'audioUploadModal', 'urlModal'])(
    '%s has a Cancel that only closes it, before the action', (id) => {
      const footer = footerOf(id);
      const buttons = buttonsOf(footer);
      const cancel = buttons.findIndex((b) => b.cancel);
      expect(cancel).toBeGreaterThan(-1);
      expect(cancel).toBeLessThan(buttons.length - 1);
      expect(footer).not.toMatch(/<div class="modal-footer">\s*<div><\/div>/);
    });

  test('deleting ends with a grey Cancel and one red Delete, what goes chosen above them', () => {
    const buttons = buttonsOf(footerOf('deleteConfirmation'));
    const cancel = buttons.findIndex((b) => b.cancel);
    const reds = buttons.map((b, i) => (b.meaning === 'btn-danger' ? i : -1)).filter((i) => i >= 0);
    expect(cancel).toBeGreaterThan(-1);
    expect(reds).toHaveLength(1);
    expect(cancel).toBeLessThan(reds[0]);
    expect(buttons.flatMap((b) => b.kinds)).toEqual([]);
    const body = erb.slice(erb.indexOf('id="deleteConfirmation"'), erb.indexOf('<div class="modal-footer', erb.indexOf('id="deleteConfirmation"')));
    expect([...body.matchAll(/name="deleteScope" id="[^"]+" value="([a-z]+)"/g)].map((m) => m[1])).toEqual(['message', 'turn', 'below']);
  });
});

describe('Easy Submit keys while a dialog is open', () => {
  // The handler is a document listener; load it once and change only the
  // dialog's state between tests.
  let sent; let voiced;
  beforeAll(() => {
    document.body.innerHTML = `
      <input type="checkbox" id="check-easy-submit" checked>
      <textarea id="message">a draft</textarea>
      <button id="send"></button>
      <button id="voice"></button>
      <div id="main-panel"></div>
      <dialog id="dialog"><button id="cancel">Cancel</button></dialog>`;
    global.$id = (id) => document.getElementById(id);
    sent = jest.fn(); voiced = jest.fn();
    document.getElementById('send').addEventListener('click', sent);
    document.getElementById('voice').addEventListener('click', voiced);
    require('../../docker/services/ruby/public/js/monadic/ws-input-handler.js');
  });
  beforeEach(() => { sent.mockClear(); voiced.mockClear(); document.getElementById('cancel').focus(); });
  const press = (key) => {
    const e = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
    document.getElementById('cancel').dispatchEvent(e);
    return e;
  };

  test('Enter and the right arrow belong to the dialog', () => {
    // MonadicDialog marks the page's root while a dialog is open.
    document.documentElement.setAttribute('data-dialog-open', '');
    const enter = press('Enter');
    press('ArrowRight');
    expect(sent).not.toHaveBeenCalled();
    expect(voiced).not.toHaveBeenCalled();
    expect(enter.defaultPrevented).toBe(false);
  });

  test('without a dialog, Enter outside the message box still sends the draft', () => {
    document.documentElement.removeAttribute('data-dialog-open');
    press('Enter');
    expect(sent).toHaveBeenCalledTimes(1);
  });
});
