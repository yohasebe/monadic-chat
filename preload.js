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

  if (status === 'Port in use') {
    statusElement.classList.remove('running');
    statusElement.classList.add('stopped');
    document.getElementById('start').disabled = true;
    document.getElementById('stop').disabled = true;
    document.getElementById('restart').disabled = true;
    document.getElementById('browser').disabled = true;
  } else if (status === 'Running') {
    statusElement.classList.remove('stopped');
    statusElement.classList.add('running');
    document.getElementById('start').disabled = true;
    document.getElementById('stop').disabled = false;
    document.getElementById('restart').disabled = false;
    document.getElementById('browser').disabled = false;
  } else if (status === 'Stopped') {
    statusElement.classList.remove('running');
    statusElement.classList.add('stopped');
    document.getElementById('start').disabled = false;
    document.getElementById('stop').disabled = true;
    document.getElementById('restart').disabled = true;
    document.getElementById('browser').disabled = true;
  } else {
    statusElement.classList.remove('running');
    statusElement.classList.add('stopped');
    document.getElementById('start').disabled = true;
    document.getElementById('stop').disabled = true;
    document.getElementById('restart').disabled = true;
    document.getElementById('browser').disabled = true;
  }
});
