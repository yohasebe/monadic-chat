const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {

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

  // Request settings from the main process
  requestSettings: () => ipcRenderer.send('request-settings'),

  // Listen for settings load event from the main process
  onLoadSettings: (callback) => ipcRenderer.on('load-settings', callback),

  // Save settings to the main process
  saveSettings: (data) => ipcRenderer.send('save-settings', data),

  // Close settings window
  closeSettings: () => ipcRenderer.send('close-settings'),
});
