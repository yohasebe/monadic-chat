const { contextBridge, ipcRenderer } = require('electron');

// Expose API to focus the main Electron window from the webview
contextBridge.exposeInMainWorld('electronAPI', {
  focusMainWindow: () => ipcRenderer.send('focus-main-window'),
  // Zoom controls
  zoomIn: () => ipcRenderer.send('zoom-in'),
  zoomOut: () => ipcRenderer.send('zoom-out'),
  // Reset web UI session
  resetWebUI: () => ipcRenderer.send('reset-web-ui'),
  // Notify page of zoom changes so overlay can adjust
  onZoomChanged: (callback) => ipcRenderer.on('zoom-changed', callback)
});
// Intercept link clicks in the loaded page and open external links in the default browser
window.addEventListener('DOMContentLoaded', () => {
  // Ensure standard keyboard shortcuts work in webviews
  // This adds web-standard keyboard event listeners for basic editing operations
  document.addEventListener('keydown', (event) => {
    // Let all key events propagate naturally - no need to intercept them here
    // The main process has been modified to not interfere with standard editing shortcuts
  });

  // Capture clicks in the capture phase to override page handlers
  document.addEventListener('click', (event) => {
    let el = event.target;
    // Traverse up to catch clicks on child elements inside links
    while (el && el !== document.documentElement) {
      if (el.tagName === 'A' && el.hasAttribute('href')) {
        const rawHref = el.getAttribute('href');
        // Only treat absolute http(s) links as external
        if (rawHref.startsWith('http://') || rawHref.startsWith('https://')) {
          event.preventDefault();
          ipcRenderer.send('open-external', rawHref);
        }
        // Stop walking once an <a> is handled
        break;
      }
      el = el.parentElement;
    }
  }, true);
  // Make clicking the nav logo trigger the same behavior as clicking #menu #reset
  // Wire clicking the site logo (navbar-brand) to trigger reset
  const logoLink = document.querySelector('#main-nav .navbar-brand');
  const resetBtn = document.querySelector('#menu #reset');
  if (logoLink && resetBtn) {
    logoLink.style.cursor = 'pointer';
    logoLink.addEventListener('click', (e) => {
      e.preventDefault();
      resetBtn.click();
    });
  }
});
