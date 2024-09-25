// process.env.ELECTRON_DISABLE_SECURITY_WARNINGS = '1';

const { app, dialog, shell, Menu, Tray, BrowserWindow, ipcMain } = require('electron');

app.disableHardwareAcceleration();

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

// app.commandLine.appendSwitch('no-sandbox');
app.name = 'Monadic Chat';

if (process.platform === 'darwin') {
  app.commandLine.appendSwitch('no-sound');
}

const { exec, execSync, spawn } = require('child_process');
const extendedContextMenu = require('electron-context-menu');
const path = require('path');
const fs = require('fs');
const os = require('os');
const https = require('https');
const net = require('net');

let tray = null;
let justLaunched = true;
let currentStatus = 'Stopped';
let isQuitting = false;
let contextMenu = null;
let initialLaunch = true;

let dockerInstalled = false;
let wsl2Installed = false;

let dotenv;
if (app.ispackaged) {
  dotenv = require('./node_modules/dotenv');
} else {
  dotenv = require('dotenv');
}

const iconDir = path.isPackaged ? path.join(process.resourcesPath, 'menu_icons') : path.join(__dirname, 'menu_icons');

let monadicScriptPath = path.join(__dirname, 'docker', 'monadic.sh')
  .replace('app.asar', 'app')
  .replace(' ', '\\ ');

if (os.platform() === 'win32') {
  monadicScriptPath = `wsl ${toUnixPath(monadicScriptPath)}`
}

// Docker operations are encapsulated in this class
class DockerManager {
  async checkStatus() {
    return new Promise((resolve, reject) => {
      const cmd = `${monadicScriptPath} check`;
      exec(cmd, (error, stdout, stderr) => {
        if (error) {
          reject(error);
        } else if (stderr) {
          reject(stderr);
        } else {
          const isRunning = stdout.trim() === '1';
          resolve(isRunning);
        }
      });
    });
  }

  startDockerDesktop() {
    return new Promise((resolve, reject) => {
      let command;
      switch (process.platform) {
        case 'darwin':
          command = 'open -a Docker';
          break;
        case 'win32':
          command = '"C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe"';
          break;
        case 'linux':
          command = 'systemctl --user start docker-desktop';
          break;
        default:
          reject('Unsupported platform');
          return;
      }

      exec(command, (error) => {
        if (error) {
          reject('Failed to start Docker Desktop.');
        } else {
          resolve();
        }
      });
    });
  }

  async ensureDockerDesktopRunning() {
    const st = await this.checkStatus();
    if (!st) {
      this.startDockerDesktop()
        .then(async () => {
          updateContextMenu(false);
          updateApplicationMenu();
          await new Promise(resolve => setTimeout(resolve, 120000));
          await this.checkStatus();
        })
        .catch(error => {
          console.error('Failed to start Docker Desktop:', error);
          dialog.showErrorBox('Error', 'Failed to start Docker Desktop. Please start it manually and try again.');
        });
    }
  }

  // Check if Docker and WSL 2 are installed (Windows only) or Docker is installed (macOS and Linux)
  checkRequirements() {
    return new Promise((resolve, reject) => {
      if (os.platform() === 'win32') {
        exec('docker -v', function (err) {
          dockerInstalled = !err;
          exec('wsl -l -v', function (err) {
            wsl2Installed = !err;
            if (!dockerInstalled) {
              reject("Docker is not installed. Please install Docker Desktop for Windows first.");
            } else if (!wsl2Installed) {
              reject("WSL 2 is not installed. Please install WSL 2 first.");
            } else {
              resolve();
            }
          });
        });
      } else if (os.platform() === 'darwin') {
        exec('/usr/local/bin/docker -v', function (err, stdout) {
          dockerInstalled = stdout.includes('docker') || stdout.includes('Docker');
          if (!dockerInstalled) {
            reject("Docker is not installed. Please install Docker Desktop for Mac first.");
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

  async runCommand(command, message, statusWhileCommand, statusAfterCommand) {
    // Check if the API key is set when starting the server
    if (command === 'start') {
      const apiKeySet = checkAndUpdateEnvFile();
      if (!apiKeySet) {
        dialog.showMessageBox(mainWindow, {
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

    dockerManager.checkStatus()
    .then((status) => {
      if (!status) {
        writeToScreen('[HTML]: <p>Docker Desktop is not running. Please start Docker Desktop and try again.</p><hr />');
        return
      } else {
        // Write the initial message to the screen
        writeToScreen(message);
        // Update the status indicator in the main window
        updateStatusIndicator(statusWhileCommand);

        // Construct the command to execute
        const cmd = `${monadicScriptPath} ${command}`;

        // Update the current status and context menu
        currentStatus = statusWhileCommand;

        // Reset the fetchWithRetryCalled flag
        fetchWithRetryCalled = false;

        // Update the context menu and application menu
        updateContextMenu();
        updateApplicationMenu();

        // Return a promise that resolves when the command execution is complete
        return new Promise((resolve, _reject) => {
          let subprocess = spawn(cmd, [], {shell: true});

          // Handle stdout data
          subprocess.stdout.on('data', function (data) {
            const lines = data.toString().split(/\r\n|\r|\n/);
            if (lines[lines.length - 1] === '') {
              lines.pop();
            }
            for (let i = 0; i < lines.length; i++) {
              // Check for version information and display update message if needed
              if (lines[i].trim().startsWith('[VERSION]: ')) {
                const imageVersion = lines[i].trim().replace('[VERSION]: ', '');
                if (compareVersions(imageVersion, app.getVersion()) > 0) {
                  dialog.showMessageBox(mainWindow, {
                    type: 'info',
                    buttons: ['OK'],
                    title: 'Update Available',
                    message: `A new version of the app is available. Please update to the latest version.`,
                    icon: path.join(iconDir, 'monadic-chat.png')
                  });
                }
                // Check if the image is not found and update the status accordingly
              } else if (lines[i].trim() === "[IMAGE NOT FOUND]") {
                writeToScreen('[HTML]: <p>Monadic Chat Docker image not found.</p>');
                currentStatus = "Building";
                updateTrayImage(currentStatus);
                updateStatusIndicator(currentStatus);
                // Check if the server has started and attempt to connect to it
              } else if (lines[i].trim() === "[SERVER STARTED]") {
                if (!fetchWithRetryCalled) {
                  fetchWithRetryCalled = true;
                  writeToScreen('[HTML]: <p>Monadic Chat server is starting . . .</p>');
                  fetchWithRetry('http://localhost:4567')
                    .then(() => {
                      updateContextMenu(false);
                      updateStatusIndicator("Ready");
                      writeToScreen('[HTML]: <p>Monadic Chat server is ready. The default web browser will be started automatically</p>');
                      mainWindow.webContents.send('server-ready');
                      writeToScreen(lines[i]);
                      openBrowser('http://localhost:4567');
                    })
                    .catch(error => {
                      writeToScreen('[HTML]: <p><b>Failed to start Monadic Chat server.</b></p><p>Please check out <b>monadic.log</b> in the shared folder and start the server again. Rebuild the image ("Menu" → "Action" → "Rebuild"), if necessary.</p><hr />');
                      console.error('Fetch operation failed after retries:', error);
                      currentStatus = 'Stopped';
                      updateTrayImage(currentStatus);
                      updateStatusIndicator(currentStatus);
                      updateContextMenu(false);
                    });
                }
                // Write other output to the screen
              } else {
                writeToScreen(lines[i]);
              }
            }
          });

          // Handle stderr data
          subprocess.stderr.on('data', function (data) {
            console.error(data.toString());
            return;
          });

          // Handle process close event
          subprocess.on('close', function (code) {
            // Check for errors based on the exit code
            if (code !== 0) {
              dialog.showErrorBox('Error', `monadic.sh exited with code ${code}.`);
            }

            // Update the status, tray image, status indicator, and context menu
            currentStatus = statusAfterCommand;
            updateTrayImage(statusAfterCommand);
            updateStatusIndicator(statusAfterCommand);
            updateContextMenu(false);

            resolve();
          });
        });
      }
    })
  }
}

// Create an instance of DockerManager
const dockerManager = new DockerManager();

// Compare two version strings (e.g., "1.2.3" vs "1.2.4")
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

// Check for updates by comparing the current app version with the latest version on GitHub
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
          dialog.showMessageBox(mainWindow, {
            type: 'info',
            buttons: ['OK'],
            title: 'Update Available',
            message: `A new version (${latestVersion}) of the app is available. Please update to the latest version.`,
            icon: path.join(iconDir, 'monadic-chat.png')
          });
        } else {
          dialog.showMessageBox(mainWindow, {
            type: 'info',
            buttons: ['OK'],
            title: 'Up to Date',
            message: `You are already using the latest version of the app.`,
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

// Uninstall Monadic Chat by removing Docker images and containers
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
        dockerManager.runCommand('remove', '[HTML]: <p>Removing containers and images.</p>', 'Uninstalling', 'Uninstalled');
      } else {
        return false;
      }
    }, 1000);
  });
}

let mainWindow = null;
let settingsWindow = null;

let isQuittingDialogShown = false;

async function quitApp() {
  if (isQuittingDialogShown) return; // Do nothing if the quit dialog is already shown

  isQuittingDialogShown = true;

  let options = {
    type: 'question',
    buttons: ['Cancel', 'Quit'],
    defaultId: 1,
    title: 'Confirm Quit',
    message: 'Quit Monadic Chat Console?',
    detail: 'This will stop all running processes and close the application.',
    icon: path.join(iconDir, 'monadic-chat.png')
  };

  try {
    const result = await dialog.showMessageBox(mainWindow, options);
    if (result.response === 1) {
      try {
        const dockerStatus = await dockerManager.checkStatus();
        if (dockerStatus) {
          await dockerManager.runCommand('stop', '[HTML]: <p>Stopping all processes.</p>', 'Stopping', 'Quitting');
          cleanupAndQuit();
        } else {
          cleanupAndQuit();
        }
      } catch (error) {
        console.error('Error occurred during application quit:', error);
      }
    } else {
      isQuittingDialogShown = false;
    }
  } catch (err) {
    console.error('Error in quit dialog:', err);
    cleanupAndQuit();
  }
}

function cleanupAndQuit() {
  writeToScreen('[HTML]: <p>Quitting Monadic Chat . . .</p>');
  setTimeout(() => {
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

    app.exit(0);
  }, 3000);
}

// Update the app's quit handler
app.on('before-quit', (event) => {
  if (!isQuittingDialogShown) {
    event.preventDefault();
    quitApp();
  }
});

function openMainWindow() {
  createMainWindow();
  mainWindow.show();
  mainWindow.focus();
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
      dockerManager.checkRequirements()
        .then(() => {
          dockerManager.runCommand('start', '[HTML]: <p>Monadic Chat preparing . . .</p>', 'Starting', 'Running');
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
      dockerManager.runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . . </p>', 'Stopping', 'Stopped');
    },
    enabled: true
  },
  {
    label: 'Restart',
    click: () => {
      openMainWindow();
      dockerManager.runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
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
  app.whenReady().then(async () => {
    app.name = 'Monadic Chat';

    setInterval(updateDockerStatus, 2000);

    tray = new Tray(path.join(iconDir, 'Stopped.png'));
    tray.setToolTip('Monadic Chat');
    tray.setContextMenu(contextMenu);

    extendedContextMenu({});

    createMainWindow();
    contextMenu = Menu.buildFromTemplate(menuItems);

    updateStatus();

    ipcMain.on('command', async (_event, command) => {
      try {
        switch (command) {
          case 'start':
            dockerManager.runCommand('start', '[HTML]: <p>Monadic Chat preparing . . .</p>', 'Starting', 'Running');
            break;
          case 'stop':
            dockerManager.runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
            break;
          case 'restart':
            dockerManager.runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
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
      } catch (error) {
        console.error('Error during app initialization:', error);
      }
    });

    // Check requirements and update menu after the main window is ready
    dockerManager.checkRequirements()
      .then(() => {
        metRequirements = true;
      })
      .catch(error => {
        dialog.showErrorBox('Error', error);
      })
      .finally(() => {
        updateApplicationMenu();
        // if docker is not started, start it
        dockerManager.ensureDockerDesktopRunning();
      });

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createMainWindow();
      }
    });

    // Show main window if it exists
    if (mainWindow) {
      mainWindow.show();
    }

    // Set up window close handlers
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
  });
}

// Convert Windows path to Unix path format
function toUnixPath(p) {
  return p.replace(/\\/g, '/').replace(/^([a-zA-Z]):/, '/mnt/$1').toLowerCase();
}

// Fetch a URL with retries and a delay between attempts
function fetchWithRetry(url, options = {}, retries = 30, delay = 2000, timeout = 20000) {
  const attemptFetch = async (attempt) => {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeout);

      const response = await fetch(url, { ...options, signal: controller.signal });
      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      console.log(`Connecting to server: success`);
      return true;
    } catch (error) {
      console.log(`Connecting to server: attempt ${attempt} failed`);
      if (attempt <= retries) {
        console.log(`Retrying in ${delay}ms . . .`);
        await new Promise(resolve => setTimeout(resolve, delay));
        return attemptFetch(attempt + 1);
      } else {
        console.log(`Failed to connect to server after ${retries} attempts. Please check the error log in the shared folder.`);
      }
      throw error;
    }
  };
  return attemptFetch(1);
}

let fetchWithRetryCalled = false;


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
      currentStatus = 'Starting';
      initialLaunch = false;
    } else {
      currentStatus = 'Stopped';
    }
    updateContextMenu(false);
    updateStatusIndicator(currentStatus);
  });
}

// Update the tray image based on the current status
function updateTrayImage(status) {
  if (tray) {
    // catche error and fallback to "Building.png"
    try {
      tray.setImage(path.join(iconDir, `${status}.png`));
    } catch {
      tray.setImage(path.join(iconDir, 'Building.png'));
    }
  }
}

function updateContextMenu(disableControls = false) {
  updateTrayImage(currentStatus);
  if (tray) {
    if (disableControls) {
      menuItems.forEach(item => {
        if (item.label && ['Start', 'Stop', 'Restart', 'Open Browser'].includes(item.label)) {
          item.enabled = false;
        }
      });
    } else {
      menuItems.forEach(item => {
        if (item.label === 'Start') {
          item.enabled = currentStatus === 'Stopped';
        } else if (item.label === 'Stop') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        } else if (item.label === 'Restart') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        } else if (item.label === 'Open Browser') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        }
      });
    }

    contextMenu = Menu.buildFromTemplate(menuItems);
    tray.setContextMenu(contextMenu);

    mainWindow.webContents.send('update-controls', { status: currentStatus, disableControls });
    updateApplicationMenu();
  }
}

function updateApplicationMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: 'File',
      submenu: [
        {
          label: 'About Monadic Chat',
          click: () => {
            dialog.showMessageBox(mainWindow, {
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
            dockerManager.runCommand('start', '[HTML]: <p>Monadic Chat preparing . . .</p>', 'Starting', 'Running');
          },
          enabled: currentStatus === 'Stopped'
        },
        {
          label: 'Stop',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        {
          label: 'Restart',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        {
          type: 'separator'
        },
        {
          label: 'Rebuild',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('build',
              '[HTML]: <p>Building Monadic Chat . . .</p>',
              'Building',
              'Stopped',
              false);
          },
          enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
        },
        {
          type: 'separator'
        },
        {
          label: 'Start JupyterLab',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('start-jupyter', '[HTML]: <p>Starting JupyterLab . . .</p>', 'Ready', 'Ready');
          },
          enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
        },
        {
          label: 'Stop JupyterLab',
          click: () => {
            dockerManager.runCommand('stop-jupyter', '[HTML]: <p>Stopping JupyterLab . . .</p>', 'Ready', 'Ready');
          },
          enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
        },
        {
          type: 'separator'
        },
        {
          label: 'Import Document DB',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('import-db', '[HTML]: <p>Importing Document DB . . .</p>', 'Importing', 'Stopped')
          },
          enabled: currentStatus === 'Stopped' && metRequirements
        },
        {
          label: 'Export Document DB',
          click: () => {
            dockerManager.runCommand('export-db', '[HTML]: <p>Exporting Document DB . . .</p>', 'Exporting', 'Stopped');
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

// Send a message to the renderer process to write to the screen
function writeToScreen(text) {
  if (mainWindow) {
    mainWindow.webContents.send('command-output', text);
  }
}

// Send a message to the renderer process to update the status indicator
function updateStatusIndicator(status) {
  if (mainWindow) {
    mainWindow.webContents.send('update-status-indicator', status);
    statusMenuItem.label = `Status: ${status}`;
  }
}

function createMainWindow() {
  if (mainWindow) return;

  mainWindow = new BrowserWindow({
    width: 780,
    minWidth: 780,
    height: 480,
    minHeight: 480,
    webPreferences: {
      nodeIntegration: false,
      contentIsolation: false,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js'),
      contentSecurityPolicy: "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; script-src 'self' 'unsafe-inline'; connect-src 'self' https://raw.githubusercontent.com; img-src 'self' data:; worker-src 'self';"
    },
    title: "Monadic Chat",
    useContentSize: true
  });

  let openingText;

  if (justLaunched) {
    openingText = `
      [HTML]: 
      <p><i><b>Monadic Chat: Grounding AI Chatbots with Full Linux Environment on Docker</b></i></p>
      <p><i class="fa-solid fa-circle-exclamation"></i>Please make sure Docker Desktop is running while using Monadic Chat.</p>
      <p>Press <b>start</b> button to initialize the server.</p>
      <hr />`
    justLaunched = false;
    currentStatus = 'Stopped';

    // Check if port 4567 is already in use only on initial launch
    isPortTaken(4567, function (taken) {
      if (taken) {
        currentStatus = 'Port in use';
        updateContextMenu(false); // Update context menu immediately if port is in use
        updateStatusIndicator(currentStatus); // Update status indicator immediately if port is in use
      }
    });
  };

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https:') || url.startsWith('http:')) {
      shell.openExternal(url)
    }
    return { action: 'deny' }
  })

  mainWindow.loadFile('index.html');

  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('update-status-indicator', currentStatus);
    mainWindow.webContents.send('update-version', app.getVersion());
    writeToScreen(openingText);
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
      const wslHome = execSync('wsl.exe echo $HOME').toString().trim();
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

function openSettingsWindow() {
  if (!settingsWindow) {
    settingsWindow = new BrowserWindow({
      devTools: true,
      width: 600,
      minWidth: 780,
      height: 400,
      minHeight: 400,
      parent: mainWindow,
      modal: true,
      show: false,
      frame: false,
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
  settingsWindow.show();
  settingsWindow.webContents.send('request-settings');
}

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

  // VISION_MODEL and AI_USER_MODEL are set with default values if not present
  if (!envConfig.VISION_MODEL) {
    envConfig.VISION_MODEL = 'gpt-4o-mini';
  }

  if (!envConfig.AI_USER_MODEL) {
    envConfig.AI_USER_MODEL = 'gpt-4o-mini';
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
  // if (settingsWindow) {
  //   settingsWindow.hide();
  // }
});

app.whenReady().then(() => {
  initializeApp();
});

// Removed duplicate app.on('window-all-closed') and app.on('activate')

ipcMain.on('close-settings', () => {
  if (settingsWindow) {
    settingsWindow.hide();
  }
});

async function updateDockerStatus() {
  if (dockerInstalled) {
    const status = await dockerManager.checkStatus();
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('docker-desktop-status-update', status);
      // if status is false, meaning Docker Desktop is not running,
      // update the context menu and buttons onlly if the current status is not "Stopped"
      if (!status && currentStatus !== 'Stopped') {
        currentStatus = 'Stopped';
        updateContextMenu(false);
        updateStatusIndicator(currentStatus);
        writeToScreen('[SERVER STOPPED]');
        writeToScreen('[HTML]: <hr /><p>Docker Desktop is not running. Please start Docker Desktop and press <b>start</b> button.</p><hr />');
      }
    }
  } 
}
