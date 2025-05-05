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
      console.log('Requesting media permissions...');
      // Request with more detailed options and constraints for better compatibility
      const constraints = {
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      };
      
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      // Clean up the stream after permissions are granted
      if (stream) {
        console.log('Stream obtained successfully:', stream.id);
        const audioTracks = stream.getAudioTracks();
        console.log('Audio tracks:', audioTracks.length, audioTracks.map(t => t.label));
        
        // Keep the stream active slightly longer to ensure permission is properly registered
        setTimeout(() => {
          stream.getTracks().forEach(track => {
            console.log('Stopping track:', track.label);
            track.stop();
          });
        }, 500);
      }
      console.log('Media permissions granted!');
      return true;
    } catch (err) {
      console.error('Failed to get media permissions:', err.name, err.message);
      return false;
    }
  }
});
// Intercept link clicks in the loaded page and open external links in the default browser
// Setup proper audio cleanup for macOS
const isMac = /Mac/.test(navigator.platform);
if (isMac) {
  // Add handler to clean up audio resources on page unload
  window.addEventListener('beforeunload', () => {
    // Find and clean up any AudioContext instances
    if (window.audioCtx && typeof window.audioCtx.close === 'function') {
      window.audioCtx.close().catch(err => console.warn('Error closing AudioContext:', err));
    }
    
    // If ttsStop function exists, call it to properly clean up audio resources
    if (typeof window.ttsStop === 'function') {
      window.ttsStop();
    }
    
    // Stop all media streams
    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      // Attempt to enumerate and stop any active tracks
      navigator.mediaDevices.enumerateDevices()
        .then(devices => {
          // Just logging that we attempted cleanup
          console.log('Cleaning up media devices before unload');
        })
        .catch(err => {
          console.warn('Error cleaning up media devices:', err);
        });
    }
  });
}

window.addEventListener('DOMContentLoaded', () => {
  // Track last search term
  let lastSearchTerm = '';
  // Create in-page Find overlay UI (styled to match Monadic Chat)
  const findOverlay = document.createElement('div');
  findOverlay.style.cssText = 
    'position:fixed;top:10px;right:10px;display:flex;align-items:center;'
    + 'background:#fff;border:1px solid #ccc;border-radius:4px;'
    + 'padding:4px 6px;box-shadow:0 2px 6px rgba(0,0,0,0.2);'
    + 'z-index:2147483647;display:none;';
  findOverlay.className = 'search-overlay';

  const findInput = document.createElement('input');
  findInput.type = 'text';
  findInput.placeholder = 'Search';
  findInput.className = 'search-input';
  findInput.style.cssText = 'min-width:120px;border:none;outline:none;'
    + 'padding:4px;font-size:14px;';

  const prevBtn = document.createElement('button');
  prevBtn.textContent = '◀';
  prevBtn.title = 'Previous';
  prevBtn.className = 'search-button prev-button';
  prevBtn.style.cssText = 'border:none;background:transparent;color:#333;'
    + 'font-size:16px;cursor:pointer;margin:0 4px;';

  const nextBtn = document.createElement('button');
  nextBtn.textContent = '▶';
  nextBtn.title = 'Next';
  nextBtn.className = 'search-button next-button';
  nextBtn.style.cssText = 'border:none;background:transparent;color:#333;'
    + 'font-size:16px;cursor:pointer;margin:0 4px;';

  const closeBtn = document.createElement('button');
  closeBtn.textContent = '×';
  closeBtn.title = 'Close';
  closeBtn.className = 'search-button close-button';
  closeBtn.style.cssText = 'border:none;background:transparent;color:#333;'
    + 'font-size:16px;cursor:pointer;margin-left:4px;';

  findOverlay.append(prevBtn, findInput, nextBtn, closeBtn);
  document.body.appendChild(findOverlay);

  const showOverlay = () => { findOverlay.style.display = 'flex'; findInput.value = ''; findInput.focus(); };
  const hideOverlay = () => { findOverlay.style.display = 'none'; ipcRenderer.send('stop-find-in-page'); };
  closeBtn.addEventListener('click', hideOverlay);
  // Prev/Next navigation
  prevBtn.addEventListener('click', () => {
    if (lastSearchTerm) ipcRenderer.send('find-in-page-nav', { term: lastSearchTerm, forward: false });
  });
  nextBtn.addEventListener('click', () => {
    if (lastSearchTerm) ipcRenderer.send('find-in-page-nav', { term: lastSearchTerm, forward: true });
  });
  // Prevent search dialog from closing when clicking inside it
  findOverlay.addEventListener('mousedown', (e) => {
    // Prevent event propagation when clicking inside the search overlay
    e.stopPropagation();
  });

  // Capture document-wide clicks to close the search dialog when clicking outside
  document.addEventListener('mousedown', (e) => {
    // Close search dialog when clicking outside of it
    if (findOverlay.style.display !== 'none') {
      // Check if the click is outside the search dialog
      if (!findOverlay.contains(e.target)) {
        hideOverlay();
      }
    }
  });

  // Capture key events (Ctrl/Cmd+F to open, Enter/Shift+Enter to navigate, Esc to close)
  document.addEventListener('keydown', (event) => {
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const cmdOrCtrl = isMac ? event.metaKey : event.ctrlKey;
    // Open search
    if (cmdOrCtrl && event.key === 'f') {
      event.preventDefault();
      event.stopImmediatePropagation();
      showOverlay();
    // Navigate matches when overlay visible
    } else if (findOverlay.style.display !== 'none' && event.key === 'Enter') {
      event.preventDefault();
      event.stopImmediatePropagation();
      const term = findInput.value;
      if (!term) return;
      const firstSearch = (lastSearchTerm !== term);
      lastSearchTerm = term;
      if (event.shiftKey) {
        ipcRenderer.send('find-in-page-nav', { term, forward: false });
      } else if (firstSearch) {
        ipcRenderer.send('find-in-page', term);
      } else {
        ipcRenderer.send('find-in-page-nav', { term, forward: true });
      }
    // Close search
    } else if (event.key === 'Escape' && findOverlay.style.display !== 'none') {
      event.preventDefault();
      event.stopImmediatePropagation();
      hideOverlay();
    }
  }, true);
  // IME composition flag: distinguish actual Enter from IME commit
  let isComposing = false;
  findInput.addEventListener('compositionstart', () => { isComposing = true; });
  findInput.addEventListener('compositionend', () => { isComposing = false; });
  // Handle Enter/Shift+Enter navigation and Escape to close (on keyup)
  findInput.addEventListener('keyup', (e) => {
    // If IME is composing, skip
    if (isComposing) return;
    const term = findInput.value;
    // Escape: hide overlay
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopImmediatePropagation();
      hideOverlay();
      return;
    }
    // Enter/Shift+Enter: navigate matches
    if (e.key === 'Enter') {
      e.preventDefault();
      e.stopImmediatePropagation();
      if (!term) return;
      const firstSearch = (lastSearchTerm !== term);
      lastSearchTerm = term;
      if (e.shiftKey) {
        // Shift+Enter: previous match
        ipcRenderer.send('find-in-page-nav', { term, forward: false });
      } else if (firstSearch) {
        // First search invocation for this term
        ipcRenderer.send('find-in-page', term);
      } else {
        // Subsequent Enter: next match
        ipcRenderer.send('find-in-page-nav', { term, forward: true });
      }
    }
  });
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
      } else if (event.key === 'Escape') {
        // Clear search highlights
        event.preventDefault();
        try {
          ipcRenderer.send('stop-find-in-page');
        } catch (err) {
          console.error('Failed to send stop-find-in-page:', err);
        }
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
