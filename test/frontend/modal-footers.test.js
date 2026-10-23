/**
 * @jest-environment jsdom
 */
// Modal footers follow one rule set: confirm and input dialogs end with a grey
// Cancel and the action on the right; a delete is a red outline. And while a
// dialog is open, the chat's Easy Submit keys leave the keyboard to it.
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
  const CANCEL = '<button type="button" class="btn btn-sm btn-secondary" data-bs-dismiss="modal" data-i18n="ui.cancel">Cancel</button>';

  test.each(['loadModal', 'fileModal', 'docModal', 'audioUploadModal', 'urlModal', 'pdfDeleteConfirmation'])(
    '%s has a Cancel that only closes it, before the action', (id) => {
      const footer = footerOf(id);
      expect(footer).toContain(CANCEL);
      expect(footer.indexOf(CANCEL)).toBeLessThan(footer.lastIndexOf('<button'));
      expect(footer).not.toMatch(/<div class="modal-footer">\s*<div><\/div>/);
    });

  test('deleting is a red outline, never yellow or blue', () => {
    expect(footerOf('deleteConfirmation')).not.toContain('btn-warning');
    expect(footerOf('deleteConfirmation').match(/btn-outline-danger/g)).toHaveLength(2);
    expect(footerOf('pdfDeleteConfirmation')).toMatch(/id="pdfDeleteConfirmed" class="btn btn-sm btn-outline-danger"/);
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
      <div class="modal" id="dialog"><button id="cancel">Cancel</button></div>`;
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
    document.getElementById('dialog').classList.add('show');
    const enter = press('Enter');
    press('ArrowRight');
    expect(sent).not.toHaveBeenCalled();
    expect(voiced).not.toHaveBeenCalled();
    expect(enter.defaultPrevented).toBe(false);
  });

  test('without a dialog, Enter outside the message box still sends the draft', () => {
    document.getElementById('dialog').classList.remove('show');
    press('Enter');
    expect(sent).toHaveBeenCalledTimes(1);
  });
});
