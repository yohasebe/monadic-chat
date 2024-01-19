const { app, dialog, Menu, Tray, BrowserWindow, ipcMain } = require('electron')
app.commandLine.appendSwitch('no-sandbox');
const { exec, execSync, spawn} = require('child_process');
const extendedContextMenu = require('electron-context-menu');
const path = require('path')
const os = require('os');
const https = require('https');
const net = require('net');

let tray = null;
let justLaunched = true;
let portInUse = false;
let currentStatus = 'Stopped';
let isQuitting = false;
let contextMenu = null;
let initialLaunch = true;

const iconDir = path.isPackaged ? path.join(process.resourcesPath, 'menu_icons') : path.join(__dirname, 'menu_icons');

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
            icon: path.join(iconDir, 'monadic-chat.png')
          });
        } else {
          dialog.showMessageBox({
            type: 'info',
            buttons: ['OK'],
            title: 'Up to Date',
            message: 'You are already using the latest version of the app.',
            icon: path.join(iconDir, 'monadic-chat.png')
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
        runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped', true);
        if (result.checkboxChecked) {
          shutdownDocker();
        }
        isQuitting = true;
        app.quit();
      } else {
        return false;
        ;
      }
    }, 1000);
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
      runCommand('build', '[HTML]: <p>Building Monadic Chat . . .</p>', 'Building', 'Stopped');
    }
  },
  { type: 'separator' },
  {
    label: 'Start',
    click: () => {
      openMainWindow();
      runCommand('start', '[HTML]: <p>Monadic Chat starting. This may take a while, especially when running for the first time. Please wait.</p>', 'Starting', 'Running');
    }
  },
  {
    label: 'Stop',
    click: () => {
      openMainWindow();
      runCommand('stop', '[HTML]: <p>Monadic Chat is stopping. Please wait . . .</p>', 'Stopping', 'Stopped');
    }
  },
  {
    label: 'Restart',
    click: () => {
      openMainWindow();
      runCommand('restart', '[HTML]: <p>Monadic Chat is restarting. Please wait . . .</p>', 'Restarting', 'Running');
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
    tray = new Tray(path.join(iconDir, 'Stopped.png'))
    tray.setToolTip('Monadic Chat')
    tray.setContextMenu(contextMenu)

    extendedContextMenu({});

    createMainWindow();
    contextMenu = Menu.buildFromTemplate(menuItems);

    updateStatus();

    ipcMain.on('command', (_event, command) => {
      switch (command) {
        case 'start':
          runCommand('start', '[HTML]: <p>Monadic Chat starting. Please wait . . .</p>', 'Starting', 'Running');
          break;
        case 'stop':
          runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
          break;
        case 'restart':
          runCommand('restart', '[HTML]: <p>Monadic Chat is restarting. Please wait . . .</p>', 'Restarting', 'Running');
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
  })
}

function toUnixPath(p) {
  return p.replace(/\\/g, '/').replace(/^([a-zA-Z]):/, '/mnt/$1').toLowerCase();
}

function shutdownDocker() {
  const command = "shutdown"
  const monadicScriptPath = path.isPackaged ? path.join(process.resourcesPath, 'monadic.sh') : path.join(__dirname, 'monadic.sh');

  let cmd;
  if (os.platform() === 'win32') {
    // cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;
    cmd = "net stop docker"
  }
  else if (os.platform() === 'darwin') {
    // gracefully shutdown Docker Desktop on MacOS
    cmd = `osascript -e 'quit app "Docker Desktop"'`;

  }
  else if (os.platform() === 'linux') {
    cmd = `sudo systemctl stop docker`;
  }
  else {
    console.error('Unsupported platform');
    return;
  }

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

function runCommand(command, message, statusWhileCommand, statusAfterCommand, sync = false) {
  writeToScreen(message);
  tray.setImage(path.join(iconDir, `${capitalizeFirstLetter(command)}.png`));
  statusMenuItem.label = `${capitalizeFirstLetter(command)}`;

  const monadicScriptPath = path.isPackaged ? path.join(process.resourcesPath, 'monadic.sh') : path.join(__dirname, 'monadic.sh');
  const cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;

  updateStatusIndicator(statusWhileCommand);

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
      updateStatusIndicator(currentStatus);
      if (mainWindow) {
        mainWindow.webContents.send('commandOutput', stdout);
      }
    });
  } else {
    let subprocess = spawn(cmd, [], { shell: true })
    subprocess.stdout.on('data', function (data) {
      const lines = data.toString().split(require('os').EOL);
      if (lines[lines.length - 1] === '') {
        lines.pop();
      }
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim() === "[IMAGE NOT FOUND]"){
          currentStatus = "Building"
          tray.setImage(path.join(iconDir, `${currentStatus}.png`));
          statusMenuItem.label = currentStatus;

          updateContextMenu();
          updateStatusIndicator(currentStatus);
        }
        console.log(`Line ${i}: ${lines[i]}`);
        if (mainWindow) {
          mainWindow.webContents.send('commandOutput', lines[i]);
        }
      }
    });

    subprocess.stderr.on('data', function (data) {
      console.error(data.toString());
      return;
    });

    subprocess.on('close', function (code) {
      currentStatus = statusAfterCommand;
      tray.setImage(path.join(iconDir, `${statusAfterCommand}.png`));
      statusMenuItem.label = `${statusAfterCommand}`;

      updateContextMenu();
      updateStatusIndicator(currentStatus);
    });
  }
}

function isPortTaken(port, callback) {
  const tester = net.createServer()
    .once('error', err => {
      if (err.code === 'EADDRINUSE') {
        callback(true);
      } else {
        callback(err);
      }
    })
    .once('listening', () => {
      tester.once('close', () => {
        callback(false);
      }).close();
    })
    .listen(port);
}

function updateStatus() {
  const port = 4567;

  isPortTaken(port, (taken) => {
    if (taken && !initialLaunch) {
      currentStatus = 'Running';
      initialLaunch = false;
    } else {
      currentStatus = 'Stopped';
    }
    updateContextMenu();
    updateStatusIndicator(currentStatus);
  });
}

function updateStatusIndicator(status) {
  // Send the current status to the main window unless it is closed
  if (!mainWindow) return;
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
    width: 560,
    minWidth: 560,
    height: 340,
    minHeight: 260,
    webPreferences: {
      nodeIntegration: false,
      contentIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js')
    }
  });

  let openingText;

  if(justLaunched){
    openingText = `[HTML]: <p><b>Monadic Chat</b> ${app.getVersion()}</p><p>Press <b>Start</b> to initialize the server.</p>`;
    portInUse = false;
    justLaunched = false;
    currentStatus = 'Stopped';

    isPortTaken(4567, function(taken){
      if(taken){
        openingText = `[HTML]: <p><b>Monadic Chat</b> ${app.getVersion()}</p><p>Port 4567 is already in use.</p><p>Press <b>Start</b> to initialize the server.</p>`
        portInUse = true;
        currentStatus = 'Port in use';
      } 
    })
  };

  setTimeout(() => {
    writeToScreen(openingText);
  }, 1000);

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

  // Send the current status to the main window right after it is created
  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('updateStatusIndicator', currentStatus);
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
