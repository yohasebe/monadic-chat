const { contextBridge, ipcRenderer, clipboard } = require('electron');

// Expose API to focus the main Electron window from the webview
contextBridge.exposeInMainWorld('electronAPI', {
  focusMainWindow: () => ipcRenderer.send('focus-main-window'),
  // Zoom controls
  zoomIn: () => ipcRenderer.send('zoom-in'),
  zoomOut: () => ipcRenderer.send('zoom-out'),
  // Reset web UI session
  resetWebUI: () => ipcRenderer.send('reset-web-ui'),
  // Notify page of zoom changes so overlay can adjust
  onZoomChanged: (callback) => ipcRenderer.on('zoom-changed', callback),
  // Clipboard access
  readClipboard: () => clipboard.readText(),
  writeClipboard: (text) => clipboard.writeText(text),
  // Media permissions helper
  requestMediaPermissions: async () => {
    // This helps trigger the permission request explicitly for the webview
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      return true;
    } catch (err) {
      console.error('Failed to get media permissions:', err);
      return false;
    }
  }
});
// Intercept link clicks in the loaded page and open external links in the default browser
window.addEventListener('DOMContentLoaded', () => {
  // Explicitly enable standard keyboard shortcuts for common operations
  document.addEventListener('keydown', (event) => {
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const cmdOrCtrl = isMac ? event.metaKey : event.ctrlKey;
    
    if (cmdOrCtrl) {
      // Handle standard edit operations
      if (event.key === 'c') {
        // Copy
        const selection = window.getSelection().toString();
        if (selection) {
          window.electronAPI.writeClipboard(selection);
        }
      } else if (event.key === 'v') {
        // Paste
        const clipText = window.electronAPI.readClipboard();
        if (clipText && document.activeElement) {
          // For input fields and textareas
          if (document.activeElement.tagName === 'INPUT' || 
              document.activeElement.tagName === 'TEXTAREA' ||
              document.activeElement.isContentEditable) {
            
            // Use execCommand for standard elements
            document.execCommand('insertText', false, clipText);
          }
        }
      } else if (event.key === 'x') {
        // Cut
        const selection = window.getSelection().toString();
        if (selection && document.activeElement) {
          window.electronAPI.writeClipboard(selection);
          // If in editable area, delete selection
          if (document.activeElement.tagName === 'INPUT' || 
              document.activeElement.tagName === 'TEXTAREA' ||
              document.activeElement.isContentEditable) {
            document.execCommand('delete');
          }
        }
      } else if (event.key === 'a') {
        // Select all
        if (document.activeElement) {
          if (document.activeElement.tagName === 'INPUT' || 
              document.activeElement.tagName === 'TEXTAREA') {
            document.activeElement.select();
          } else {
            // Select all in the current editable element or document body
            try {
              // Try to select within the current editable element
              if (document.activeElement.isContentEditable) {
                const range = document.createRange();
                range.selectNodeContents(document.activeElement);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
              } else {
                // Default to document.body for normal text
                document.execCommand('selectAll');
              }
            } catch (e) {
              // Fallback if the above doesn't work
              document.execCommand('selectAll');
            }
          }
        }
      } else if (event.key === 'z') {
        // Undo
        if (!event.shiftKey) {
          document.execCommand('undo');
        } else {
          // Redo (Shift+Cmd/Ctrl+Z)
          document.execCommand('redo');
        }
      } else if (event.key === 'y') {
        // Redo alternative (Ctrl+Y)
        document.execCommand('redo');
      }
    }
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
