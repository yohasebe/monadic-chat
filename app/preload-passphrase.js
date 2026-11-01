// Dedicated preload for the passphrase prompt window. Keeps
// contextIsolation: true so the small renderer cannot reach Node APIs;
// it can only call the three channels exposed here.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('passphraseAPI', {
  // Renderer subscribes once to receive { title, hint, confirmRequired, lang, labels }.
  onInit: (callback) => {
    ipcRenderer.once('passphrase-prompt:init', (_event, opts) => callback(opts));
  },
  // Renderer sends back { ok: bool, passphrase?: string }.
  submit: (result) => ipcRenderer.send('passphrase-prompt:result', result),
  // Renderer reports the height its content needs, so the window fits it.
  fit: (height) => ipcRenderer.send('passphrase-prompt:fit', height)
});
