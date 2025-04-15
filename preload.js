const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Listen for temporal UI disable event from the main process 
  onDisableUI: (callback) => ipcRenderer.on('disable-ui', callback),

  // Listen for command output from the main process
  onCommandOutput: (callback) => ipcRenderer.on('command-output', callback),

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
      // Forward the progress info to the renderer via postMessage
      window.postMessage({ type: 'update-progress', progress: progressObj }, '*');
      if (callback) callback(event, progressObj);
    });
  },

  // Request settings from the main process
  requestSettings: () => ipcRenderer.send('request-settings'),

  // Listen for settings load event from the main process
  onLoadSettings: (callback) => ipcRenderer.on('load-settings', callback),

  // Save settings to the main process
  saveSettings: (data) => ipcRenderer.send('save-settings', data),

  // Close settings window
  closeSettings: () => ipcRenderer.send('close-settings'),
  
  // Restart application after settings change
  restartApp: () => ipcRenderer.send('restart-app'),
  
  // Select TTS dictionary file
  selectTTSDict: () => ipcRenderer.invoke('select-tts-dict'),
  
  // Clear messages area when mode changes
  clearMessages: () => ipcRenderer.send('clear-messages'),
});
