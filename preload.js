const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electron', {
  receiveCommandOutput: (callback) => {
    ipcRenderer.on('commandOutput', (_event, ...args) => callback(...args));
  },
  sendCommand: (command) => {
    ipcRenderer.send('command', command);
  },
  updateControls: (callback) => {
    ipcRenderer.on('updateControls', (_event, ...args) => callback(...args));
  },
  onServerReady: (callback) => {
    ipcRenderer.on('serverReady', () => callback());
  },
  requestSettings: () => {
    ipcRenderer.send('request-settings');
  },
  onLoadSettings: (callback) => {
    ipcRenderer.on('load-settings', (_event, settings) => callback(settings));
  },
  saveSettings: (data) => {
    ipcRenderer.send('save-settings', data);
  },
  closeSettings: () => {
    ipcRenderer.send('close-settings');
  }
});

// Version update listener
ipcRenderer.on('updateVersion', (_event, version) => {
  document.getElementById('version').textContent = version;
});

// Status update listener
ipcRenderer.on('updateStatusIndicator', (_event, status) => {
  const statusElement = document.getElementById('status');
  statusElement.textContent = status;

  const buttons = {
    start: document.getElementById('start'),
    stop: document.getElementById('stop'),
    restart: document.getElementById('restart'),
    browser: document.getElementById('browser'),
    folder: document.getElementById('folder'),
    settings: document.getElementById('settings')
  };

  // Enable/disable buttons based on status
  if (status === 'Port in use' || status === 'Starting' || status === 'Stopping') {
    Object.values(buttons).forEach(button => button.disabled = true);
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Running') {
    statusElement.textContent = "Preparing . . .";
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    buttons.browser.disabled = true;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Ready') {
    statusElement.textContent = "Ready";
    statusElement.classList.remove('inactive');
    statusElement.classList.add('active');
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    buttons.browser.disabled = false;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Stopped') {
    statusElement.classList.remove('active');
    statusElement.classList.add('inactive');
    buttons.start.disabled = false;
    buttons.stop.disabled = true;
    buttons.restart.disabled = true;
    buttons.browser.disabled = true;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else {
    Object.values(buttons).forEach(button => button.disabled = true);
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  }
});
