const { contextBridge, ipcRenderer } = require('electron');

// Add event listener to disable Cmd/Ctrl+A in the main window
window.addEventListener('DOMContentLoaded', () => {
  // Disable Cmd/Ctrl+A only in the main index.html window
  const pathname = window.location && window.location.pathname;
  if (pathname && pathname.endsWith('index.html')) {
    document.addEventListener('keydown', (event) => {
      // Check if Cmd (macOS) or Ctrl (Windows/Linux) is pressed with A
      if ((event.metaKey || event.ctrlKey) && event.key === 'a') {
        // Prevent the default select all behavior
        event.preventDefault();
        event.stopPropagation();
      }
    }, true); // Use capture phase to ensure this runs before other handlers
  }
});

contextBridge.exposeInMainWorld('electronAPI', {
  // Listen for temporal UI disable event from the main process 
  onDisableUI: (callback) => ipcRenderer.on('disable-ui', callback),

  // Listen for command output from the main process
  onCommandOutput: (callback) => ipcRenderer.on('command-output', callback),
  
  // Listen for clear messages command
  onClearMessages: (callback) => ipcRenderer.on('clear-messages', callback),

  // Send a command to the main process
  sendCommand: (command) => ipcRenderer.send('command', command),

  // Listen for UI control updates from the main process
  onUpdateControls: (callback) => ipcRenderer.on('update-controls', callback),

  // Listen for server ready event from the main process
  onServerReady: (callback) => ipcRenderer.on('server-ready', callback),

  // Listen for version update from the main process
  onUpdateVersion: (callback) => ipcRenderer.on('update-version', callback),

  // Listen for monadic chat status indicator update from the main process
  onUpdateStatusIndicator: (callback) => ipcRenderer.on('update-status-indicator', callback),

  // Listen for docker status indicator update from the main process
  onUpdateDockerStatusIndicator: (callback) => ipcRenderer.on('docker-desktop-status-update', callback),
  
  // Get the current distributed mode setting
  getDistributedMode: () => {
    // This is a synchronous function that returns the mode from a cookie
    const cookies = document.cookie.split('; ');
    for (const cookie of cookies) {
      if (cookie.startsWith('distributed-mode=')) {
        return cookie.split('=')[1];
      }
    }
    return 'off'; // Default to standalone mode
  },
  
  // Get an updated distributed mode setting (sent from main process)
  onUpdateDistributedMode: (callback) => ipcRenderer.on('update-distributed-mode', callback),
  
  // Listen for network URL display command
  onDisplayNetworkUrl: (callback) => ipcRenderer.on('display-network-url', callback),
  
  // Listen for update message from the auto-updater
  onUpdateMessage: (callback) => ipcRenderer.on('update-message', callback),
  
  // Listen for update progress from the auto-updater (for progress window)
  onUpdateProgress: (callback) => {
    ipcRenderer.on('update-progress', (event, progressObj) => {
      // Ensure we have valid progress data before forwarding
      const sanitizedProgress = progressObj || { percent: 0 };
      
      // Debug log for progress updates
      console.log('Progress update received:', JSON.stringify(sanitizedProgress));
      
      // Also forward via postMessage as a fallback
      window.postMessage({ type: 'update-progress', progress: sanitizedProgress }, '*');
      
      // Call callback if provided
      if (callback) callback(event, sanitizedProgress);
    });
  },

  // Cancel update download
  cancelUpdate: () => ipcRenderer.send('cancel-update'),

  // Request settings from the main process
  requestSettings: () => ipcRenderer.send('request-settings'),

  // Listen for settings load event from the main process
  onLoadSettings: (callback) => ipcRenderer.on('load-settings', callback),

  // Save settings to the main process
  saveSettings: (data) => ipcRenderer.send('save-settings', data),

  // Close settings window
  closeSettings: () => ipcRenderer.send('close-settings'),
  // Attempt-close notifications and confirmations
  onAttemptCloseSettings: (callback) => ipcRenderer.on('attempt-close-settings', callback),
  confirmCloseSettings: () => ipcRenderer.send('confirm-close-settings'),
  
  // Change UI language immediately
  changeUILanguage: (language) => ipcRenderer.send('change-ui-language', language),
  
  // Restart application after settings change
  restartApp: () => ipcRenderer.send('restart-app'),
  
  // Select TTS dictionary file
  selectTTSDict: () => ipcRenderer.invoke('select-tts-dict'),
  
  // Clear messages area when mode changes
  clearMessages: () => ipcRenderer.send('clear-messages'),
  // Focus main window (invoked by internal browser)
  focusMainWindow: () => ipcRenderer.send('focus-main-window'),
  // Zoom controls for internal browser window
  zoomIn: () => ipcRenderer.send('zoom-in'),
  zoomOut: () => ipcRenderer.send('zoom-out'),
  // Listen for reset display command
  onResetDisplay: (callback) => ipcRenderer.on('reset-display-to-initial', callback),
  
  // Listen for UI language change
  onUILanguageChanged: (callback) => ipcRenderer.on('ui-language-changed', callback),

  // Translations loader for renderer (Install Options, etc.)
  getTranslations: (lang) => ipcRenderer.invoke('get-translations', lang)
});

// Install Options API (isolated renderer access)
contextBridge.exposeInMainWorld('installOptionsAPI', {
  get: () => ipcRenderer.invoke('get-install-options'),
  save: (options) => ipcRenderer.invoke('save-install-options', options)
});

// Install Options window close flow
contextBridge.exposeInMainWorld('installOptionsWindowAPI', {
  onAttemptClose: (callback) => ipcRenderer.on('attempt-close-install-options', callback),
  confirmClose: () => ipcRenderer.send('confirm-close-install-options')
});

// (removed) experimental captureAPI
