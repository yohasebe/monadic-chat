/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-privacy-handler.js: the export dialog.
 */

require('../../docker/services/ruby/public/js/monadic/ws-privacy-handler');

describe('WsPrivacyHandler.resetExportDialog — content default', () => {
  function buildDialog() {
    document.body.innerHTML = `
      <input type="checkbox" id="export-encrypt-toggle" />
      <input type="radio" name="privacyExportContent" id="privacyExportContentRestored" value="restored" checked />
      <input type="radio" name="privacyExportContent" id="privacyExportContentMasked" value="masked" />
      <input type="text" id="privacy-export-passphrase" />
      <input type="text" id="privacy-export-passphrase-confirm" />
      <div id="privacy-export-content-section" style="display:none;"></div>
      <div id="privacy-export-status"></div>
      <div id="privacy-export-pass-section"></div>
      <div id="privacy-export-restored-warning"></div>
      <button id="privacy-export-continue"></button>
      <div class="privacy-strength-bar"></div>
      <div id="privacy-strength-label"></div>
    `;
  }

  function chatHidesWords(hides) {
    window.WordTable = { hidesWords: () => hides };
  }

  afterEach(() => { document.body.innerHTML = ''; delete window.WordTable; });

  it('defaults to "masked" when the chat hides words', () => {
    buildDialog();
    chatHidesWords(true);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(true);
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(false);
  });

  it('defaults to "restored" when the chat hides no words', () => {
    buildDialog();
    chatHidesWords(false);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(true);
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(false);
  });

  describe('while the dialog is open', () => {
    function openDialog(chat) {
      buildDialog();
      const modal = document.createElement('dialog');
      modal.id = 'privacyExportModal';
      modal.setAttribute('open', '');
      document.body.appendChild(modal);
      window.WordTable = { hidesWords: () => false, chat: () => chat };
      window.WsPrivacyHandler.resetExportDialog();
    }
    const tableNow = (hides, chat) => {
      window.WordTable = { hidesWords: () => hides, chat: () => chat };
      document.dispatchEvent(new CustomEvent('wordtable:changed'));
    };
    const byId = (id) => document.getElementById(id);

    it('offers "masked" when the table arrives after it was opened', () => {
      openDialog(null);
      tableNow(true, 'chat-1');
      expect(byId('privacyExportContentMasked').checked).toBe(true);
      expect(byId('privacy-export-content-section').style.display).toBe('');
    });

    it('keeps what the user picked when the words change', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentRestored').checked = true;
      byId('privacyExportContentRestored').dispatchEvent(new Event('change', { bubbles: true }));
      tableNow(true, 'chat-1');
      expect(byId('privacyExportContentRestored').checked).toBe(true);
    });

    it('does not keep "masked" when no word is hidden any more', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentMasked').dispatchEvent(new Event('change', { bubbles: true }));
      tableNow(false, 'chat-1');
      expect(byId('privacyExportContentRestored').checked).toBe(true);
      expect(byId('privacy-export-content-section').style.display).toBe('none');
    });

    it('starts over for another chat, whatever was picked', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentRestored').checked = true;
      byId('privacyExportContentRestored').dispatchEvent(new Event('change', { bubbles: true }));
      byId('privacy-export-passphrase').value = 'typed for the other chat';
      tableNow(true, 'chat-2');
      expect(byId('privacyExportContentMasked').checked).toBe(true);
      expect(byId('privacy-export-passphrase').value).toBe('');
    });
  });

  it('hides the content section when the chat hides no words', () => {
    buildDialog();
    chatHidesWords(false);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacy-export-content-section').style.display).toBe('none');
  });
});

describe('WsPrivacyHandler — the export request and its answer', () => {
  function buildDialog() {
    document.body.innerHTML = `
      <input type="checkbox" id="export-encrypt-toggle" />
      <input type="radio" name="privacyExportContent" id="privacyExportContentRestored" value="restored" checked />
      <input type="text" id="privacy-export-passphrase" />
      <input type="text" id="privacy-export-passphrase-confirm" />
      <div id="privacy-export-status"></div>
      <div id="privacy-export-pass-section"></div>
      <div id="privacy-export-restored-warning"></div>
      <button id="privacy-export-continue"></button>
      <div class="privacy-strength-bar"></div>
      <div id="privacy-strength-label"></div>
    `;
    window.WordTable = { hidesWords: () => false };
    window.WsPrivacyHandler.resetExportDialog();
  }

  const status = () => document.getElementById('privacy-export-status').textContent;
  const button = () => document.getElementById('privacy-export-continue');
  let sent;

  beforeEach(() => {
    sent = [];
    window.safeWsSend = (payload) => { sent.push(payload); return { sent: true }; };
    global.URL.createObjectURL = jest.fn(() => 'blob:x');
    global.URL.revokeObjectURL = jest.fn();
    buildDialog();
  });
  afterEach(() => { document.body.innerHTML = ''; delete window.WordTable; delete window.safeWsSend; });

  it('asks once, with an id, and waits with the button off', () => {
    button().click();
    button().click();
    expect(sent).toHaveLength(1);
    expect(sent[0].request_id).toMatch(/^exp-/);
    expect(button().disabled).toBe(true);
  });

  it('says the export was not sent, and lets the user try again, when it could not be sent', () => {
    window.safeWsSend = () => ({ sent: false, queued: false });
    button().click();
    expect(status()).toContain('could not be sent');
    expect(button().disabled).toBe(false);
  });

  it('takes only the answer to the request it is waiting for, and says the download started', () => {
    button().click();
    const id = sent[0].request_id;
    window.WsPrivacyHandler.handleExportData({ request_id: 'exp-earlier', content_base64: btoa('{}'), filename: 'old.json' });
    expect(status()).not.toContain('old.json');
    window.WsPrivacyHandler.handleExportData({ request_id: id, content_base64: btoa('{}'), filename: 'chat.json' });
    expect(status()).toContain('chat.json');
    expect(status()).not.toMatch(/Downloaded/);
    expect(button().disabled).toBe(false);
  });

  it('shows a translated reason, never the server detail, for an error', () => {
    button().click();
    window.WsPrivacyHandler.handleExportError({ request_id: sent[0].request_id, error: 'export_failed', detail: 'Internal stack' });
    expect(status()).not.toContain('Internal stack');
    expect(button().disabled).toBe(false);
  });

  it('says how many images sent in the chat the file could not hold', () => {
    button().click();
    window.WsPrivacyHandler.handleExportData({ request_id: sent[0].request_id, content_base64: btoa('{}'), filename: 'chat.json',
      sent_images_missing: 2 });
    expect(status()).toContain('chat.json');
    expect(status()).toContain('2 images');
  });

  it('says the images were too large to export, and about how large', () => {
    button().click();
    window.WsPrivacyHandler.handleExportError({ request_id: sent[0].request_id, error: 'too_large', image_bytes: 3 * 1024 * 1024 });
    expect(status()).toContain('too large');
    expect(status()).toContain('3 MB');
    expect(button().disabled).toBe(false);
  });

  it('says how much the images sent take in the file, warning when it is near the limit', () => {
    window.WsPrivacyHandler.handleExportEstimate({ image_bytes: 5 * 1024 * 1024, near: false });
    expect(status()).toContain('5 MB');
    window.WsPrivacyHandler.handleExportEstimate({ image_bytes: 120 * 1024 * 1024, near: true });
    expect(status()).toContain('120 MB');
    expect(status()).toContain('close to');
    window.WsPrivacyHandler.handleExportEstimate({ image_bytes: 0, near: false });
    expect(status()).toContain('120 MB');
  });

  it('ignores an answer that arrives after the dialog was opened again', () => {
    button().click();
    const id = sent[0].request_id;
    window.WsPrivacyHandler.resetExportDialog();
    window.WsPrivacyHandler.handleExportData({ request_id: id, content_base64: btoa('{}'), filename: 'late.json' });
    expect(status()).toBe('');
  });
});
