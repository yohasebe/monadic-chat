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
            message: `A new version (${latestVersion}) of the app is available. Please update to the latest version.`,
            icon: path.join(iconDir, 'monadic-chat.png')
          });
        } else {
          dialog.showMessageBox({
            type: 'info',
            buttons: ['OK'],
            title: 'Up to Date',
            message: `You are already using the latest version (${latestVersion}) of the app.`,
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

function uninstall() {
  let options = {
    type: 'question',
    buttons: ['Cancel', 'Delete all'],
    defaultId: 1,
    title: 'Confirm Uninstall',
    message: 'This will remove all the Monadic Chat images and containers. Do you want to continue?',
    icon: path.join(iconDir, 'monadic-chat.png')
  };

  dialog.showMessageBox(null, options).then((result) => {
    setTimeout(() => {
      if (result.response === 1) {
        runCommand('remove', '[HTML]: <p>Removing containers and images.</p>', 'Uninstalling', 'Uninstalled', false);
      } else {
        return false;
        ;
      }
    }, 1000);
  })
}

function checkDockerInstallation() {
  return new Promise((resolve, reject) => {
    if (os.platform() === 'win32') {
      exec('docker -v', function (_err, _stdout, _stderr) {
        if (_err) {
          reject("Docker is not installed. Please install Docker Desktop for Windows first and then try starting Monadic Chat.");
        } else {
          exec('wsl -l -v', function (_err, _stdout, _stderr) {
            if (_err) {
              reject("WSL 2 is not installed. Please install WSL 2 first and then try starting Monadic Chat.");
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
          reject("Docker is not installed. Please install Docker Desktop for Mac first and then try starting Monadic Chat.");
        }
      });
    } else if (os.platform() === 'linux') {
      exec('docker -v', function (_err, stdout, _stderr) {
        if (stdout.includes('docker') || stdout.includes('Docker')) {
          resolve();
        } else {
          reject("Docker is not installed. Please install Docker for Linux first and then try starting Monadic Chat.");
        }
      });
    } else {
      reject('Unsupported platform');
    }
  });
}

function quitApp() {
  let options = {
    type: 'question',
    buttons: ['Cancel', 'Quit'],
    defaultId: 1,
    title: 'Confirm Quit',
    message: 'Do you want to quit Monadic Chat?',
    icon: path.join(iconDir, 'monadic-chat.png')
  };

  if (process.platform === 'darwin') {
    options.checkboxLabel = 'Shut down Docker Desktop (if possible)';
    options.checkboxChecked = false;
  }

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
  label: 'Status: Stopped',
  enabled: false
};

const menuItems = [
  statusMenuItem,
  { type: 'separator' },
  {
    label: 'Build',
    click: () => {
      openMainWindow();
      runCommand('build', '[HTML]: <p>Building Monadic Chat. Please wait . . .</p>', 'Building', 'Stopped', false);
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Start',
    click: () => {
      openMainWindow();
      runCommand('start', '[HTML]: <p>Monadic Chat starting. This may take a while, especially when running for the first time. Please wait.</p>', 'Starting', 'Running');
    },
    enabled: true
  },
  {
    label: 'Stop',
    click: () => {
      openMainWindow();
      runCommand('stop', '[HTML]: <p>Monadic Chat is stopping. Please wait . . .</p>', 'Stopping', 'Stopped');
    },
    enabled: true
  },
  {
    label: 'Restart',
    click: () => {
      openMainWindow();
      runCommand('restart', '[HTML]: <p>Monadic Chat is restarting. Please wait . . .</p>', 'Restarting', 'Running');
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Open Browser',
    click: () => {
      openMainWindow();
      openBrowser('http://localhost:4567');
    },
    enabled: true
  },
  {
    label: 'Open Console',
    click: () => {
      openMainWindow();
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Documentation',
    click: () => {
      openBrowser('https://yohasebe.github.io/monadic-chat/');
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Check for Updates',
    click: () => {
      openMainWindow();
      checkForUpdates();
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Uninstall',
    click: () => {
      uninstall();
    },
    enabled: true
  },
  { type: 'separator' },
  {
    label: 'Exit',
    click: () => {
      openMainWindow();
      quitApp();
    },
    enabled: true
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
    mainWindow.webContents.send('updateVersion', app.getVersion());

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
          openBrowser('http://localhost:4567');
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
  if (os.platform() === 'darwin') {
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
    if (mainWindow) {
      mainWindow.webContents.send('commandOutput', stdout);
    }
  });
}

function fetchWithRetry(url, options = {}, retries = 20, delay = 1000) {
  const attemptFetch = (attempt) => {
    return fetch(url, options)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        console.log(`Connecting to server: success`);
        return true
      })
      .catch(error => {
        console.log(`Connecting to server: attempt ${attempt} failed`);
        if (attempt <= retries) {
          console.log(`Retrying in ${delay}ms . . .`);
          return new Promise((resolve) => {
            setTimeout(() => {
              resolve(attemptFetch(attempt + 1));
            }, delay);
          });
        } else {
          throw error;
        }
      });
  };
  return attemptFetch(1);
};

function runCommand(command, message, statusWhileCommand, statusAfterCommand, sync = false) {
  writeToScreen(message);
  statusMenuItem.label = `Status: ${statusWhileCommand}`;

  const monadicScriptPath = path.isPackaged ? path.join(process.resourcesPath, 'monadic.sh') : path.join(__dirname, 'monadic.sh');
  const cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;

  currentStatus = statusWhileCommand;
  updateContextMenu(true);
  updateStatusIndicator(statusWhileCommand);

  if (sync) {
    execSync(cmd, (err, stdout, _stderr) => {
      if (err) {
        dialog.showErrorBox('Error', err.message);
        console.error(err);
        return;
      }
      currentStatus = statusAfterCommand;
      tray.setImage(path.join(iconDir, `${statusAfterCommand}.png`));
      statusMenuItem.label = `Status: ${statusAfterCommand}`;
      writeToScreen(stdout);
      updateContextMenu(false);
      updateStatusIndicator(currentStatus);
    });
  } else {
    let subprocess = spawn(cmd, [], { shell: true })

    subprocess.stdout.on('data', function (data) {
      const lines = data.toString().split(require('os').EOL);
      if (lines[lines.length - 1] === '') {
        lines.pop();
      }
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim().startsWith('[VERSION]: ')) { 
          // get the version number from the output
          const imageVersion = lines[i].trim().replace('[VERSION]: ', '');
          if (compareVersions(imageVersion, app.getVersion()) > 0) {
            dialog.showMessageBox({
              type: 'info',
              buttons: ['OK'],
              title: 'Update Available',
              message: `A new version (${version}) of the app is available. Please update to the latest version.`,
              icon: path.join(iconDir, 'monadic-chat.png')
            });
          }
        } else if (lines[i].trim() === "[IMAGE NOT FOUND]"){
          writeToScreen('[HTML]: <p>Monadic Chat Docker image not found.</p>');
          currentStatus = "Building";
          tray.setImage(path.join(iconDir, `${currentStatus}.png`));
          statusMenuItem.label = `Status: ${currentStatus}`;
          updateStatusIndicator(currentStatus);
        } else if (lines[i].trim() === "[SERVER STARTED]") {
          writeToScreen('[HTML]: <p>Monadic Chat server is starting. Please wait . . .</p>');
          fetchWithRetry('http://localhost:4567')
            .then(data => {
              writeToScreen('[HTML]: <p>Monadic Chat server is ready. Press <b>Open Browser</b> button.</p>');
            })
            .catch(error => {
              console.error('Fetch operation failed after retries:', error);
            });
        } else {
          writeToScreen(lines[i]);
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
      statusMenuItem.label = `Status: ${statusAfterCommand}`;

      updateContextMenu(false);
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
    updateContextMenu(false);
    updateStatusIndicator(currentStatus);
  });
}

function updateStatusIndicator(status) {
  // Send the current status to the main window unless it is closed
  if (!mainWindow) return;
  mainWindow.webContents.send('updateStatusIndicator', status);
}

function updateContextMenu(disableControls = false) {
  tray.setImage(path.join(iconDir, `${currentStatus}.png`));
  if (disableControls) {
    menuItems[2].enabled = false;
    menuItems[4].enabled = false;
    menuItems[5].enabled = false;
    menuItems[6].enabled = false;
    menuItems[8].enabled = false;
    menuItems[9].enabled = false;
    menuItems[11].enabled = false;
    menuItems[13].enabled = false;
    menuItems[15].enabled = false;
  } else {
    menuItems[2].enabled = true;
    menuItems[4].enabled = true;
    menuItems[5].enabled = true;
    menuItems[6].enabled = true;
    menuItems[8].enabled = true;
    menuItems[9].enabled = true;
    menuItems[11].enabled = true;
    menuItems[13].enabled = true;
    menuItems[15].enabled = true;
  }
  
  if(currentStatus !== 'Stopped' && currentStatus !== 'Uninstalled'){
    menuItems[2].enabled = false;
    menuItems[5].enabled = false;
  }
  if(currentStatus === 'Uninstalled'){
    menuItems[15].enabled = false;
  }
  if(currentStatus === 'Running'){
    menuItems[4].enabled = false;
    menuItems[5].enabled = true;
    menuItems[6].enabled = true;
  } else {
    menuItems[6].enabled = false;
  }
  if(currentStatus === 'Stopped'){
    menuItems[4].enabled = true;
    menuItems[5].enabled = false;
  }

  contextMenu = Menu.buildFromTemplate(menuItems);
  tray.setContextMenu(contextMenu);
}

function writeToScreen(text) {
  if (mainWindow) {
    mainWindow.webContents.send('commandOutput', text);
  }
}

function createMainWindow() {
  if (mainWindow) return;

  mainWindow = new BrowserWindow({
    width: 600,
    minWidth: 600,
    height: 420,
    minHeight: 260,
    webPreferences: {
      nodeIntegration: false,
      contentIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js')
    }
  });

  let openingText;

  if(justLaunched){
    openingText = `[HTML]: <p>Monadic Chat Docker image and container found.</p><hr /><p><b>IMPORTANT</b></p><p>If you have upgraded Monadic Chat from a previous version, click <b>Build</b> in the taskbar menu to rebuild the image.</p><p>Otherwise, press <b>Start</b> button to initialize the server.</p><hr />`;
    portInUse = false;
    justLaunched = false;
    currentStatus = 'Stopped';

    isPortTaken(4567, function(taken){
      if(taken){
        openingText = `[HTML]: <p>Port 4567 is already in use.</p><hr /><p><b>IMPORTANT</b></p><p>If other applications is using port 4567, shut them down first. Otherwise, Press <b>Start</b> button to initialize the server.</p>`
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

function openBrowser(url) {
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

  // wait until the system is ready on the port 4567
  // before opening the browser with the timeout of 20 seconds
  const timeout = 20000;
  const interval = 500;
  let time = 0;
  const timer = setInterval(() => {
    isPortTaken(4567, (taken) => {
      if (taken) {
        writeToScreen("[HTML]: <p>The server is running on port 4567. Opening the browser.</p>");
        clearInterval(timer);
        spawn(...openCommands[platform]);
      } else {
        if (time == 0) {
          writeToScreen("[HTML]: <p>Waiting for the server to start . . .</p>");
        }
        time += interval;
        if (time >= timeout) {
          clearInterval(timer);
          dialog.showErrorBox('Error', 'Failed to start the server. Please try again.');
        }
      }
    });
  }, interval);
}
