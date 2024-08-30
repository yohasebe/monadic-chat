const { app, dialog, shell, Menu, Tray, BrowserWindow, ipcMain } = require('electron');
// Single instance lock
const gotTheLock = app.requestSingleInstanceLock();

let metRequirements = false;

if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    // Someone tried to run a second instance, we should focus our window.
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}

app.commandLine.appendSwitch('no-sandbox');
app.name = 'Monadic Chat';

const { exec, execSync, spawn } = require('child_process');
const extendedContextMenu = require('electron-context-menu');
const path = require('path');
const fs = require('fs');
let dotenv;

if (app.ispackaged) {
  dotenv = require('./node_modules/dotenv');
} else {
  dotenv = require('dotenv');
}

const os = require('os');
const https = require('https');
const net = require('net');

let tray = null;
let justLaunched = true;
let currentStatus = 'Stopped';
let isQuitting = false;
let contextMenu = null;
let initialLaunch = true;

const iconDir = path.isPackaged ? path.join(process.resourcesPath, 'menu_icons') : path.join(__dirname, 'menu_icons');

let dockerInstalled = false;
let wsl2Installed = false;

function checkRequirements() {
  return new Promise((resolve, reject) => {
    if (os.platform() === 'win32') {
      exec('docker -v', function (err) {
        dockerInstalled = !err;
        exec('wsl -l -v', function (err) {
          wsl2Installed = !err;
          if (!dockerInstalled) {
            reject("Docker is not installed.|Please install Docker Desktop for Windows first.");
          } else if (!wsl2Installed) {
            reject("WSL 2 is not installed.|Please install WSL 2 first.");
          } else {
            resolve();
          }
        });
      });
    } else if (os.platform() === 'darwin') {
      exec('/usr/local/bin/docker -v', function (err, stdout) {
        dockerInstalled = stdout.includes('docker') || stdout.includes('Docker');
        if (!dockerInstalled) {
          reject("Docker is not installed.|Please install Docker Desktop for Mac first.");
        } else {
          resolve();
        }
      });
    } else if (os.platform() === 'linux') {
      exec('docker -v', function (err, stdout) {
        dockerInstalled = stdout.includes('docker') || stdout.includes('Docker');
        if (!dockerInstalled) {
          reject("Docker is not installed.|Please install Docker for Linux first.");
        } else {
          resolve();
        }
      });
    } else {
      reject('Unsupported platform');
    }
  });
}

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
  const url = 'https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/lib/monadic/version.rb';

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
      }
    }, 1000);
  });
}

let mainWindow = null;
let settingsWindow = null;

function quitApp() {
  if (isQuitting) return; // Prevent multiple quit attempts
  isQuitting = true;

  let options = {
    type: 'question',
    buttons: ['Cancel', 'Quit'],
    defaultId: 1,
    title: 'Confirm Quit',
    message: 'Quit Monadic Chat Console?',
    detail: 'This will stop all running processes and close the application.',
    icon: path.join(iconDir, 'monadic-chat.png')
  };

  if (process.platform === 'darwin') {
    options.checkboxLabel = 'Shut down Docker Desktop (if possible)';
    options.checkboxChecked = false;
  }

  dialog.showMessageBox(mainWindow, options).then((result) => {
    if (result.response === 1) { // 'Quit' button
      // Stop all running processes
      runCommand('stop', '[HTML]: <p>Stopping all processes . . .</p>', 'Stopping', 'Stopped', true);

      // Shut down Docker if checkbox is checked
      if (result.checkboxChecked && process.platform === 'darwin') {
        shutdownDocker();
      }

      // Clean up resources
      if (tray) {
        tray.destroy();
        tray = null;
      }

      if (mainWindow) {
        mainWindow.removeAllListeners('close');
        mainWindow.close();
      }

      if (settingsWindow) {
        settingsWindow.removeAllListeners('close');
        settingsWindow.close();
      }

      // Force quit after a short delay to allow for cleanup
      setTimeout(() => {
        app.exit(0);
      }, 2000);
    } else {
      isQuitting = false;
    }
  }).catch((err) => {
    console.error('Error in quit dialog:', err);
    app.quit();
  });
}

// Update the app's quit handler
app.on('before-quit', (event) => {
  if (!isQuitting) {
    event.preventDefault();
    quitApp();
  }
});

// Update window close handlers
if (mainWindow) {
  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });
}

if (settingsWindow) {
  settingsWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      settingsWindow.hide();
    }
  });
}

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
    label: 'Start',
    click: () => {
      openMainWindow();
      checkRequirements()
        .then(() => {
          runCommand('start', '[HTML]: <p>Monadic Chat starting . . .</p>', 'Starting', 'Running');
        })
        .catch((error) => {
          dialog.showErrorBox('Error', error);
        });
    },
    enabled: true
  },
  {
    label: 'Stop',
    click: () => {
      openMainWindow();
      runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
    },
    enabled: true
  },
  {
    label: 'Restart',
    click: () => {
      openMainWindow();
      runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
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
    enabled: false
  },
  {
    label: 'Open Shared Folder',
    click: () => {
      openMainWindow();
      openFolder();
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
      openBrowser('https://yohasebe.github.io/monadic-chat/', true);
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
    label: 'Quit',
    click: () => {
      openMainWindow();
      quitApp(mainWindow);
    },
    enabled: true
  }
];

function initializeApp() {
  app.whenReady().then(() => {
    app.name = 'Monadic Chat'; // Set the application name early

    tray = new Tray(path.join(iconDir, 'Stopped.png'));
    tray.setToolTip('Monadic Chat');
    tray.setContextMenu(contextMenu);

    extendedContextMenu({});

    createMainWindow();
    contextMenu = Menu.buildFromTemplate(menuItems);

    updateStatus();
    mainWindow.webContents.send('updateVersion', app.getVersion());

    ipcMain.on('command', (_event, command) => {
      switch (command) {
        case 'start':
          checkRequirements()
            .then(() => {
              runCommand('start', '[HTML]: <p>Monadic Chat starting . . .</p>', 'Starting', 'Running');
            })
            .catch((error) => {
              let message = error;
              let detail = '';
              let [e1, e2] = error.split('|');
              if (e1 && e2) {
                message = e1;
                detail = e2;
              }
              dialog.showMessageBox({
                type: 'info',
                buttons: ['OK'],
                title: 'Requirements Not Met',
                message: message,
                detail: detail,
                icon: path.join(iconDir, 'monadic-chat.png')
              });
            });
          break;
        case 'stop':
          runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
          break;
        case 'restart':
          runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
          break;
        case 'browser':
          openBrowser('http://localhost:4567');
          break;
        case 'folder':
          openFolder();
          break;
        case 'settings':
          openSettingsWindow();
          break;
        case 'exit':
          quitApp(mainWindow);
          break;
      }
    });

    checkRequirements().then(() => {
      metRequirements = true;
      updateApplicationMenu();
    });

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createMainWindow();
      }
    });

    app.on('before-quit', function (event) {
      if (!isQuitting) {
        event.preventDefault();
        quitApp();
      }
    });

    if (mainWindow) {
      mainWindow.show();
    }
  });
}

function toUnixPath(p) {
  return p.replace(/\\/g, '/').replace(/^([a-zA-Z]):/, '/mnt/$1').toLowerCase();
}

function shutdownDocker() {
  let cmd;
  if (os.platform() === 'darwin') {
    cmd = `osascript -e 'quit app "Docker Desktop"'`;
  } else if (os.platform() === 'linux') {
    cmd = `sudo systemctl stop docker`;
  } else {
    console.error('Unsupported platform');
    return;
  }

  exec(cmd, (err, stdout) => {
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

function fetchWithRetry(url, options = {}, retries = 30, delay = 2000) {
  const attemptFetch = (attempt) => {
    return fetch(url, options)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        console.log(`Connecting to server: success`);
        return true;
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
}

let fetchWithRetryCalled = false;

function runCommand(command, message, statusWhileCommand, statusAfterCommand, sync = false) {
  if (command === 'start') {
    const apiKeySet = checkAndUpdateEnvFile();
    if (!apiKeySet) {
      dialog.showMessageBox({
        type: 'info',
        buttons: ['OK'],
        title: 'API Key Required',
        message: 'OpenAI API key is not set',
        detail: 'Please set it in the Settings before starting the system.',
        icon: path.join(iconDir, 'monadic-chat.png')
      });
      writeToScreen('[HTML]: <p>OpenAI API Key is not set. Please set it in the Settings before starting the system.</p><hr />');
      return;
    }
  }

  writeToScreen(message);
  statusMenuItem.label = `Status: ${statusWhileCommand}`;

  const monadicScriptPath = path.join(__dirname, 'docker', 'monadic.sh').replace('app.asar', 'app').replace(' ', '\\ ');

  const cmd = `${os.platform() === 'win32' ? 'wsl ' : ''}${os.platform() === 'win32' ? toUnixPath(monadicScriptPath) : monadicScriptPath} ${command}`;

  currentStatus = statusWhileCommand;
  updateContextMenu(true);
  updateStatusIndicator(statusWhileCommand);

  fetchWithRetryCalled = false; // Reset the flag before running the command

  if (sync) {
    execSync(cmd, (err, stdout) => {
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
    let subprocess = spawn(cmd, [], { shell: true });

    subprocess.stdout.on('data', function (data) {
      const lines = data.toString().split(/\r\n|\r|\n/);
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
              message: `A new version of the app is available. Please update to the latest version.`,
              icon: path.join(iconDir, 'monadic-chat.png')
            });
          }
        } else if (lines[i].trim() === "[IMAGE NOT FOUND]") {
          writeToScreen('[HTML]: <p>Monadic Chat Docker image not found.</p>');
          currentStatus = "Building";
          tray.setImage(path.join(iconDir, `${currentStatus}.png`));
          statusMenuItem.label = `Status: ${currentStatus}`;
          updateStatusIndicator(currentStatus);
        } else if (lines[i].trim() === "[SERVER STARTED]") {
          if (!fetchWithRetryCalled) {
            fetchWithRetryCalled = true;
            writeToScreen('[HTML]: <p>Monadic Chat server is starting . . .</p>');
            fetchWithRetry('http://localhost:4567')
              .then(() => {
                menuItems[6].enabled = true;
                contextMenu = Menu.buildFromTemplate(menuItems);
                tray.setContextMenu(contextMenu);
                updateStatusIndicator("Ready");
                writeToScreen('[HTML]: <p>Monadic Chat server is ready. Press <b>Open Browser</b> button.</p>');
                // Send the message to the renderer process immediately
                mainWindow.webContents.send('serverReady');
                openBrowser('http://localhost:4567');
              })
              .catch(error => {
                writeToScreen('[HTML]: <p><b>Failed to start Monadic Chat server.</b></p><p>Please try rebuilding the image ("Menu" → "Action" → "Rebuild") and starting the server again.</p><hr />');
                console.error('Fetch operation failed after retries:', error);
                // switch the status back to Stopped
                currentStatus = 'Stopped';
                tray.setImage(path.join(iconDir, `${currentStatus}.png`));
                statusMenuItem.label = `Status: ${currentStatus}`;
                updateContextMenu(false);
                updateStatusIndicator(currentStatus);
              });
          }
        } else {
          writeToScreen(lines[i]);
        }
      }
    });

    subprocess.stderr.on('data', function (data) {
      console.error(data.toString());
      return;
    });

    subprocess.on('close', function () {
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
    menuItems[3].enabled = false;
    menuItems[4].enabled = false;
    menuItems[6].enabled = false;
    menuItems[8].enabled = false;
    menuItems[10].enabled = false;
    menuItems[12].enabled = false;
    menuItems[14].enabled = false;
  } else {
    menuItems[2].enabled = true;
    menuItems[3].enabled = true;
    menuItems[4].enabled = true;
    menuItems[8].enabled = true;
    menuItems[10].enabled = true;
    menuItems[12].enabled = true;
    menuItems[14].enabled = true;
  }

  if (currentStatus === 'Running') {
    menuItems[2].enabled = false;
    menuItems[3].enabled = true;
    menuItems[4].enabled = true;
    menuItems[6].enabled = false;
  } else {
    menuItems[4].enabled = false;
  }

  if (currentStatus === 'Stopped') {
    menuItems[2].enabled = true;
    menuItems[3].enabled = false;
    menuItems[5].enabled = false;
    menuItems[6].enabled = false;
  }

  contextMenu = Menu.buildFromTemplate(menuItems);
  tray.setContextMenu(contextMenu);

  // Update main window buttons and menu items
  updateMainWindowControls(disableControls);
  updateApplicationMenu();
}

function updateMainWindowControls(disableControls) {
  if (!mainWindow) return;

  const status = currentStatus;
  mainWindow.webContents.send('updateControls', { status, disableControls });
}

function updateApplicationMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: 'File',
      submenu: [
        {
          label: 'About Monadic Chat',
          click: () => {
            dialog.showMessageBox({
              type: 'info',
              title: 'About Monadic Chat',
              message: `Monadic Chat\nVersion: ${app.getVersion()}`,
              detail: 'Grounding AI Chatbots with Full Linux Environment on Docker\n\n© 2024 Yoichiro Hasebe',
              buttons: ['OK'],
              icon: path.join(iconDir, 'monadic-chat.png')
            });
          }
        },
        {
          type: 'separator'
        },
        {
          label: 'Check for Updates',
          click: () => {
            openMainWindow();
            checkForUpdates();
          }
        },
        {
          label: 'Uninstall Images and Containers',
          click: () => {
            uninstall();
          }
        },
        {
          type: 'separator'
        },
        {
          label: 'Open Console',
          accelerator: 'Cmd+N',
          click: () => {
            openMainWindow();
          }
        },
        {
          label: 'Minimize',
          accelerator: 'Cmd+M',
          click: () => {
            if (mainWindow) {
              mainWindow.minimize();
            }
          }
        },
        {
          label: 'Close Window',
          accelerator: 'Cmd+W',
          click: () => {
            if (mainWindow) {
              mainWindow.close();
            }
          }
        },
        {
          type: 'separator'
        },
        {
          label: 'Quit Monadic Chat',
          accelerator: process.platform === 'darwin' ? 'Cmd+Q' : 'Ctrl+Q',
          click: () => {
            quitApp(mainWindow);
          }
        }
      ]
    },
    {
      label: 'Actions',
      submenu: [
        {
          label: 'Start',
          click: () => {
            openMainWindow();
            checkRequirements()
              .then(() => {
                runCommand('start', '[HTML]: <p>Monadic Chat starting . . .</p>', 'Starting', 'Running');
              })
              .catch((error) => {
                dialog.showErrorBox('Error', error);
              });
          },
          enabled: currentStatus === 'Stopped'
        },
        {
          label: 'Stop',
          click: () => {
            openMainWindow();
            runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
          },
          enabled: currentStatus === 'Running'
        },
        {
          label: 'Restart',
          click: () => {
            openMainWindow();
            runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
          },
          enabled: currentStatus === 'Running'
        },
        {
          type: 'separator'
        },
        {
          label: 'Rebuild',
          click: () => {
            openMainWindow();
            checkRequirements()
              .then(() => {
                runCommand('build', '[HTML]: <p>Building Monadic Chat . . .</p>', 'Building', 'Stopped', false);
              })
              .catch((error) => {
                dialog.showErrorBox('Error', error);
              });
          },
          enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
        },
        {
          type: 'separator'
        },
        {
          label: 'Import Document DB',
          click: () => {
            openMainWindow();
            runCommand('import-db', '[HTML]: <hr /><p>Importing Document DB . . .</p>', 'Importing', 'Stopped', false)
          },
          enabled: currentStatus === 'Stopped' && metRequirements
        },
        {
          label: 'Export Document DB',
          click: () => {
            runCommand('export-db', '[HTML]: <hr /><p>Exporting Document DB . . .</p>', 'Exporting', 'Stopped', false);
          },
          enabled: currentStatus === 'Stopped' && metRequirements
        },
      ]
    },
    {
      label: 'Open',
      submenu: [
        {
          label: 'Open Browser',
          click: () => {
            openMainWindow();
            openBrowser('http://localhost:4567');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        {
          label: 'Open Shared Folder',
          click: () => {
            openMainWindow();
            openFolder();
          }
        },
        {
          label: 'Open Console',
          click: () => {
            openMainWindow();
          }
        },
        { type: 'separator' },
        {
          label: 'Settings',
          click: () => {
            openSettingsWindow();
          }
        }
      ]
    },
    {
      label: 'Help',
      submenu: [
        {
          label: 'Documentation',
          click: () => {
            openBrowser('https://yohasebe.github.io/monadic-chat/', true);
          }
        }
      ]
    }
  ]);

  Menu.setApplicationMenu(menu);
}

function writeToScreen(text) {
  if (mainWindow) {
    mainWindow.webContents.send('commandOutput', text);
  }
}

function prepareSettingsWindow() {
  if (settingsWindow) return;

  settingsWindow = new BrowserWindow({
    width: 600,
    minWidth: 780,
    height: 400,
    minHeight: 400,
    parent: mainWindow,
    modal: true,
    show: false,
    frame: false, // Remove the default window frame
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js'),
      contentSecurityPolicy: "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; script-src 'self' 'unsafe-inline'; connect-src 'self' https://raw.githubusercontent.com; img-src 'self' data:; worker-src 'self';"
    }
  });

  settingsWindow.loadFile('settings.html');

  settingsWindow.on('close', (event) => {
    event.preventDefault();
    settingsWindow.hide();
  });
}

function createMainWindow() {
  if (mainWindow) return;

  mainWindow = new BrowserWindow({
    width: 780,
    minWidth: 780,
    height: 480,
    minHeight: 480,
    webPreferences: {
      nodeIntegration: true,
      contentIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js')
    },
    title: "Monadic Chat",
    useContentSize: true
  });

  let openingText;

  if (justLaunched) {
    openingText = `
      [HTML]: 
      <p><i><b>Monadic Chat: Grounding AI Chatbots with Full Linux Environment on Docker</b></i></p>
      <p>Press <b>Start</b> button to initialize the server. It will take some time for the image rebuild to complete.</p>
      <hr />`
    justLaunched = false;
    currentStatus = 'Stopped';

    isPortTaken(4567, function (taken) {
      if (taken) {
        openingText += `<p>Port 4567 is already in use. If other applications is using port 4567, shut them down first.</p><hr />`
        currentStatus = 'Port in use';
      }
    })
  };

  setTimeout(() => {
    writeToScreen(openingText);
  }, 1000);

  mainWindow.loadFile('index.html');

  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('updateStatusIndicator', currentStatus);
    prepareSettingsWindow();
  });

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

function openFolder() {
  let folderPath;
  if (os.platform() === 'darwin' || os.platform() === 'linux') {
    folderPath = path.join(os.homedir(), 'monadic', 'data');
  } else if (os.platform() === 'win32') {
    try {
      // Get the WSL home directory using the `wslpath` command
      const wslHome = execSync('wsl.exe echo $HOME').toString().trim();
      // Construct the WSL path
      const wslPath = `/home/${path.basename(wslHome)}/monadic/data`;
      folderPath = execSync(`wsl.exe wslpath -w ${wslPath}`).toString().trim();
    } catch (error) {
      console.error('Error retrieving WSL path:', error);
      return;
    }
  }

  shell.openPath(folderPath).then((result) => {
    if (result) {
      console.error('Error opening path:', result);
    }
  });
}

function openBrowser(url, outside = false) {
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

  if (outside) {
    spawn(...openCommands[platform]);
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
        clearInterval(timer);
        writeToScreen("[HTML]: <p>The server is running on port 4567. Opening the browser.</p>");
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

let settingsView = null;

function openSettingsWindow() {
  if (!settingsWindow) {
    prepareSettingsWindow();
  }
  settingsWindow.show();
  settingsWindow.webContents.send('request-settings');
}

ipcMain.on('close-settings', () => {
  if (settingsView) {
    mainWindow.removeBrowserView(settingsView);
  }
});

function getEnvPath() {
  if (os.platform() === 'win32') {
    try {
      const wslHome = execSync('wsl.exe echo $HOME').toString().trim();
      const wslPath = `/home/${path.basename(wslHome)}/monadic/data/.env`;
      return execSync(`wsl.exe wslpath -w ${wslPath}`).toString().trim();
    } catch (error) {
      console.error('Error getting WSL path:', error);
      return null;
    }
  } else {
    return path.join(os.homedir(), 'monadic', 'data', '.env');
  }
}

function readEnvFile(envPath) {
  try {
    let envContent = fs.readFileSync(envPath, 'utf8');
    envContent = envContent.replace(/\r\n/g, '\n');
    return dotenv.parse(envContent);
  } catch {
    // create a new .env file creating the nested directories if it doesn't exist
    const envDir = path.dirname(envPath);
    fs.mkdirSync(envDir, { recursive: true });
    fs.writeFileSync(envPath, '');
    return {};
  }
}

function writeEnvFile(envPath, envConfig) {
  const envContent = Object.entries(envConfig)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  try {
    fs.writeFileSync(envPath, envContent);
    console.log('Settings saved successfully');
  } catch (error) {
    console.error('Error saving settings:', error);
  }
}

function checkAndUpdateEnvFile() {
  const envPath = getEnvPath();
  if (!envPath) return false;

  let envConfig = readEnvFile(envPath);
  let updated = false;

  if (!envConfig.VISION_MODEL) {
    envConfig.VISION_MODEL = 'gpt-4o-mini';
    updated = true;
  }

  if (!envConfig.AI_USER_MODEL) {
    envConfig.AI_USER_MODEL = 'gpt-4o-mini';
    updated = true;
  }

  if (updated) {
    writeEnvFile(envPath, envConfig);
  }

  return !!envConfig.OPENAI_API_KEY;
}

function loadSettings() {
  const envPath = getEnvPath();
  return envPath ? readEnvFile(envPath) : {};
}

function saveSettings(data) {
  const envPath = getEnvPath();
  if (envPath) {
    writeEnvFile(envPath, data);
  }
}

ipcMain.on('request-settings', (event) => {
  const settings = loadSettings();
  event.sender.send('load-settings', settings);
});

ipcMain.on('save-settings', (_event, data) => {
  saveSettings(data);
  if (settingsView) {
    mainWindow.removeBrowserView(settingsView);
  }
});

// Initialize the app
app.whenReady().then(() => {
  initializeApp();
});

// Quit when all windows are closed, except on macOS
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createMainWindow();
  }
});

ipcMain.on('close-settings', () => {
  if (settingsWindow) {
    settingsWindow.hide();
  }
});

