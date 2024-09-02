const { contextBridge, ipcRenderer } = require('electron');

// Expose specific Electron APIs to the renderer process
contextBridge.exposeInMainWorld('electronAPI', {
  onDockerDesktopStatusUpdate: (callback) => ipcRenderer.on('docker-desktop-status-update', (_event, status) => callback(status)),
  // Listen for command output from the main process
  onCommandOutput: (callback) => ipcRenderer.on('commandOutput', callback),
  // Send a command to the main process
  sendCommand: (command) => ipcRenderer.send('command', command),
  // Listen for UI control updates from the main process
  onUpdateControls: (callback) => ipcRenderer.on('updateControls', callback),
  // Listen for server ready event from the main process
  onServerReady: (callback) => ipcRenderer.on('serverReady', callback),
  // Listen for version update from the main process
  onUpdateVersion: (callback) => ipcRenderer.on('updateVersion', callback),
  // Listen for status indicator update from the main process
  onUpdateStatusIndicator: (callback) => ipcRenderer.on('updateStatusIndicator', callback),
  // Request settings from the main process
  requestSettings: () => ipcRenderer.send('request-settings'),
  // Listen for settings load event from the main process
  onLoadSettings: (callback) => ipcRenderer.on('load-settings', callback),
  // Save settings to the main process
  saveSettings: (data) => ipcRenderer.send('save-settings', data),
  // Close settings window
  closeSettings: () => ipcRenderer.send('close-settings'),
  // Check Docker Desktop status
  checkDockerDesktopStatus: () => ipcRenderer.invoke('check-docker-desktop-status'),
  // Listen for Docker Desktop status update
});
