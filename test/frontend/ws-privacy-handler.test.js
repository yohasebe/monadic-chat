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
      const modal = document.createElement('div');
      modal.id = 'privacyExportModal';
      modal.className = 'show';
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
