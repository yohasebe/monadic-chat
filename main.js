const { app, dialog, Menu, Tray, BrowserWindow, ipcMain } = require('electron')
const { exec, execSync, spawn} = require('child_process');
const extendedContextMenu = require('electron-context-menu');
const path = require('path')
const os = require('os');
const https = require('https');

let tray = null;
let currentStatus = 'Stopped';
let isQuitting = false;
const iconDir = path.isPackaged ? path.join(process.resourcesPath, 'menu_icons') : path.join(__dirname, 'menu_icons');

let contextMenu = null;

checkDockerInstallation()
  .then(initializeApp)
  .catch((error) => {
    dialog.showErrorBox('Error', error);
    console.error(error);
    app.quit();
  });

function compareVersions(version1, version2) {
  const parts1 = version1.split('.');
  const parts2 = version2.split('.');

  for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
    const part1 = parseInt(parts1[i] || 0, 10);
    const part2 = parseInt(parts2[i] || 0, 10);

    if (part1 < part2) {
      return -1;
    } else if (part1 > part2) {
      return 1;
    }
  }

  return 0;
}

function checkForUpdates() {
  const url = 'https://raw.githubusercontent.com/yohasebe/monadic-chat/main/lib/monadic/version.rb';

  https.get(url, (res) => {
    let data = '';

    res.on('data', (chunk) => {
      data += chunk;
    });

    res.on('end', () => {
      const versionRegex = /VERSION = "(.*?)"/;
      const match = data.match(versionRegex);

      if (match && match[1]) {
        const latestVersion = match[1];
        const currentVersion = app.getVersion();

        if (compareVersions(latestVersion, currentVersion) > 0) {
          dialog.showMessageBox({
            type: 'info',
            buttons: ['OK'],
            title: 'Update Available',
            message: 'A new version of the app is available. Please update to the latest version.',
          });
        } else {
          dialog.showMessageBox({
            type: 'info',
            buttons: ['OK'],
            title: 'Up to Date',
            message: 'You are already using the latest version of the app.',
          });
        }
      } else {
        dialog.showErrorBox('Error', 'Failed to retrieve the latest version number.');
      }
    });
  }).on('error', (err) => {
    dialog.showErrorBox('Error', err.message);
  });
}

function checkDockerInstallation() {
  return new Promise((resolve, reject) => {
    if (os.platform() === 'win32') {
      exec('docker -v', function (_err, _stdout, _stderr) {
        if (_err) {
          reject("Docker is not installed. Please install Docker Desktop for Windows.");
        } else {
          exec('wsl -l -v', function (_err, _stdout, _stderr) {
            if (_err) {
              reject("WSL 2 is not installed. Please install WSL 2 and set it as the default version for your WSL distributions.");
            } else {
              resolve();
            }
          });
        }
      });
    } else if (os.platform() === 'darwin') {
      exec('/usr/local/bin/docker -v', function (_err, stdout, _stderr) {
        if (stdout.includes('docker') || stdout.includes('Docker')) {
          resolve();
        } else {
          reject("Docker is not installed. Please install Docker Desktop for Mac.");
        }
      });
    } else if (os.platform() === 'linux') {
      exec('docker -v', function (_err, stdout, _stderr) {
        if (stdout.includes('docker') || stdout.includes('Docker')) {
          resolve();
        } else {
          reject("Docker is not installed. Please install Docker for Linux.");
        }
      });
    } else {
      reject('Unsupported platform');
    }
  });
}

function quitApp() {
  const options = {
    type: 'question',
    buttons: ['Cancel', 'Quit'],
    defaultId: 1,
    title: 'Confirm Quit',
    message: 'Do you want to quit Monadic Chat?',
    checkboxLabel: 'Shut down Docker Desktop (if possible)',
    checkboxChecked: false,
    icon: path.join(iconDir, 'monadic-chat.png')
  };

  dialog.showMessageBox(null, options).then((result) => {
    setTimeout(() => {
      if (result.response === 1) {
        runCommand('stop', 'Monadic Chat is stopping...', 'Stopped', true);
        if (result.checkboxChecked) {
          shutdownDocker();
        }
        isQuitting = true;
        app.quit();
      } else {
        return false;
        ;
      }
    }, 500);
  })

}

let mainWindow = null;

function openMainWindow() {
  if (mainWindow) {
    mainWindow.show();
    mainWindow.focus();
  } else {
    createMainWindow();
  }
}

let statusMenuItem = {
  label: 'Stopped',
  enabled: false
};

const menuItems = [
  statusMenuItem,
  { type: 'separator' },
  {
    label: 'Build',
    click: () => {
      openMainWindow();
      runCommand('build', 'Building Monadic Chat...', 'stopped');
    }
  },
  { type: 'separator' },
  {
    label: 'Start',
    click: () => {
      openMainWindow();
      runCommand('start', 'Monadic Chat starting...', 'Running');
    }
  },
  {
    label: 'Stop',
    click: () => {
      openMainWindow();
      runCommand('stop', 'Monadic Chat is stopping...', 'Stopped');
    }
  },
  {
    label: 'Restart',
    click: () => {
      openMainWindow();
      runCommand('restart', 'Monadic Chat is restarting...', 'Running');
    }
  },
  { type: 'separator' },
  {
    label: 'Open Browser',
    click: openBrowser
  },
  {
    label: 'Open Console',
    click: () => {
      openMainWindow();
    }
  },
  { type: 'separator' },
  {
    label: 'Check for Updates',
    click: () => {
      openMainWindow();
      checkForUpdates();
    }
  },
  { type: 'separator' },
  {
    label: 'Exit',
    click: () => {
      openMainWindow();
      quitApp();
    }
  }
]

function initializeApp() {
  app.whenReady().then(() => {
    tray = new Tray(path.join(iconDir, 'Stop.png'))
    tray.setToolTip('Monadic Chat')
    tray.setContextMenu(contextMenu)

    extendedContextMenu({});

    updateStatus();
    createMainWindow();
    contextMenu = Menu.buildFromTemplate(menuItems);

    ipcMain.on('command', (_event, command) => {
      switch (command) {
        case 'start':
          runCommand('start', 'Monadic Chat starting...', 'Running');
          break;
        case 'stop':
          runCommand('stop', 'Monadic Chat is stopping...', 'Stopped');
          break;
        case 'restart':
          runCommand('restart', 'Monadic Chat is restarting...', 'Running');
          break;
        case 'browser':
          openBrowser();
          break;
        case 'exit':
          quitApp();
          break;
      }
    });

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createMainWindow();
      }
    });

    if (mainWindow) {
      mainWindow.show();
    }

    writeToScreen(`Monadic Chat ${app.getVersion()}\n`);
  })
}


function toUnixPath(p) {
  return p.replace(/\\/g, '/').replace(/^([a-zA-Z]):/, '/mnt/$1').toLowerCase();
}

function shutdownDocker() {
  const command = "shutdown"
  const monadicScriptPath = path.isPackaged ? path.join(process.resourcesPath, 'monadic.sh') : path.join(__dirname, 'monadic.sh');
  const cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;

  exec(cmd, (err, stdout, _stderr) => {
    if (err) {
      dialog.showErrorBox('Error', err.message);
      console.error(err);
      return;
    }
    console.log(stdout);
    if (mainWindow) {
      mainWindow.webContents.send('commandOutput', stdout);
    }
  });
}

function runCommand(command, message, statusAfterCommand, sync = false) {
  writeToScreen(message);
  tray.setImage(path.join(iconDir, `${capitalizeFirstLetter(command)}.png`));
  statusMenuItem.label = `${capitalizeFirstLetter(command)}`;

  const monadicScriptPath = path.isPackaged ? path.join(process.resourcesPath, 'monadic.sh') : path.join(__dirname, 'monadic.sh');
  const cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;

  if (sync) {
    execSync(cmd, (err, stdout, _stderr) => {
      if (err) {
        dialog.showErrorBox('Error', err.message);
        console.error(err);
        return;
      }
      console.log(stdout);
      currentStatus = statusAfterCommand;
      tray.setImage(path.join(iconDir, `${statusAfterCommand}.png`));
      statusMenuItem.label = `${statusAfterCommand}`;
      updateContextMenu();
      updateStatusIndicator(currentStatus); // Pass the currentStatus
      if (mainWindow) {
        mainWindow.webContents.send('commandOutput', stdout);
      }
    });
  } else {
    exec(cmd, (err, stdout, _stderr) => {
      if (err) {
        dialog.showErrorBox('Error', err.message);
        console.error(err);
        return;
      }
      console.log(stdout);
      currentStatus = statusAfterCommand;
      tray.setImage(path.join(iconDir, `${statusAfterCommand}.png`));
      statusMenuItem.label = `${statusAfterCommand}`;
      updateContextMenu();
      updateStatusIndicator(currentStatus); // Pass the currentStatus
      if (mainWindow) {
        mainWindow.webContents.send('commandOutput', stdout);
      }
    });
  }
}

function updateStatus() {
  const port = 4567;
  const cmd = os.platform() === 'darwin' ? `lsof -i :${port} | grep LISTEN` : `netstat -ano | findstr :${port}`;

  currentStatus = 'Stopped';
  statusMenuItem.label = 'Stopped';
  updateContextMenu();

  exec(cmd, (err, stdout, _stderr) => {
    if (err) {
      console.error(err);
      return;
    }
    if (stdout.trim() !== '') {
      currentStatus = 'Running';
      statusMenuItem.label = 'Running';
    }
    updateContextMenu();
    updateStatusIndicator(currentStatus); // Pass the currentStatus
  });
}

function updateStatusIndicator(status) {
  mainWindow.webContents.send('updateStatusIndicator', status);
}

function updateContextMenu() {
  tray.setImage(path.join(iconDir, `${currentStatus}.png`));
  contextMenu = Menu.buildFromTemplate(menuItems);
  tray.setContextMenu(contextMenu);
}

function writeToScreen(text) {
  if (mainWindow) {
    mainWindow.webContents.send('commandOutput', text);
  }
  console.log(text);
}

function createMainWindow() {
  if (mainWindow) return;

  mainWindow = new BrowserWindow({
    width: 490,
    minWidth: 490,
    height: 260,
    minHeight: 260,
    webPreferences: {
      nodeIntegration: false,
      contentIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js')
    }
  });

  const openingText = `Monadic Chat ${app.getVersion()}\n\nRun "Build" once after an update of the app\n`;

  setTimeout(() => {
    writeToScreen(openingText);
  }, 500);

  mainWindow.loadFile('index.html');

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  if (process.platform === "darwin") {
    Menu.setApplicationMenu(Menu.buildFromTemplate([]));
  } else {
    mainWindow.removeMenu();
  }

  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });
}

function openBrowser() {
  const url = 'http://localhost:4567';
  const openCommands = {
    win32: ['cmd', ['/c', 'start', url]],
    darwin: ['open', [url]],
    linux: ['xdg-open', [url]]
  };

  const platform = os.platform();

  if (!openCommands[platform]) {
    console.error('Unsupported platform');
    return;
  }

  spawn(...openCommands[platform]);
}

function capitalizeFirstLetter(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}
