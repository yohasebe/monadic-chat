try {
  const { contextBridge, ipcRenderer } = require('electron');

  contextBridge.exposeInMainWorld('electron', {
    receiveCommandOutput: (func) => {
      ipcRenderer.on('commandOutput', (_event, ...args) => func(...args));
    },
    sendCommand: (command) => {
      ipcRenderer.send('command', command);
    },
    updateControls: (func) => {
      ipcRenderer.on('updateControls', (_event, ...args) => func(...args));
    },
    onServerReady: (func) => {
      ipcRenderer.on('serverReady', func);
    },
    send: (channel, data) => {
      ipcRenderer.send(channel, data);
    },
    receive: (channel, func) => {
      ipcRenderer.on(channel, (_event, ...args) => func(...args));
    }
  });

  ipcRenderer.on('updateVersion', (_event, version) => {
    document.getElementById('version').textContent = version;
  });

  ipcRenderer.on('updateStatusIndicator', (_event, status) => {
    const statusElement = document.getElementById('status');
    statusElement.textContent = status;

    const isActive = status === 'Ready';
    statusElement.classList.toggle('active', isActive);
    statusElement.classList.toggle('inactive', !isActive);

    const controls = {
      folder: true,
      settings: true,
      start: status === 'Stopped',
      stop: status === 'Ready',
      restart: status === 'Ready',
      browser: status === 'Ready'
    };

    for (const [id, enabled] of Object.entries(controls)) {
      document.getElementById(id).disabled = !enabled;
    }

    if (status === 'Running') {
      statusElement.textContent = "Preparing . . .";
    }
  });
} catch (error) {
  console.error('Error in preload script:', error);
}
