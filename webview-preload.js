const { contextBridge, ipcRenderer } = require('electron');

// Expose API to focus the main Electron window from the webview
contextBridge.exposeInMainWorld('electronAPI', {
  focusMainWindow: () => ipcRenderer.send('focus-main-window'),
  // Zoom controls
  zoomIn: () => ipcRenderer.send('zoom-in'),
  zoomOut: () => ipcRenderer.send('zoom-out'),
  resetZoom: () => ipcRenderer.send('zoom-reset'),
  // Notify page of zoom changes so overlay can adjust
  onZoomChanged: (callback) => ipcRenderer.on('zoom-changed', callback)
});