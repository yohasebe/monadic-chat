const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electron', {
  receiveCommandOutput: (func) => {
    ipcRenderer.on('commandOutput', (_event, ...args) => func(...args));
  },
  sendCommand: (command) => {
    ipcRenderer.send('command', command);
  }
});

ipcRenderer.on('updateStatusIndicator', (_event, status) => {
  const statusElement = document.getElementById('status');
  statusElement.textContent = status;

  if (status === 'Running') {
    statusElement.classList.remove('stopped');
    statusElement.classList.add('running');
  } else if (status === 'Stopped') {
    statusElement.classList.remove('running');
    statusElement.classList.add('stopped');
  }
});


