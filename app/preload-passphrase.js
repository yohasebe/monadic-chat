// Dedicated preload for the passphrase prompt window. Keeps
// contextIsolation: true so the small renderer cannot reach Node APIs;
// it can only call the two channels exposed here.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('passphraseAPI', {
  // Renderer subscribes once to receive { title, hint, confirmRequired }.
  onInit: (callback) => {
    ipcRenderer.once('passphrase-prompt:init', (_event, opts) => callback(opts));
  },
  // Renderer sends back { ok: bool, passphrase?: string }.
  submit: (result) => ipcRenderer.send('passphrase-prompt:result', result)
});
