// process.env.ELECTRON_DISABLE_SECURITY_WARNINGS = '1';

const { app, dialog, shell, Menu, Tray, BrowserWindow, ipcMain } = require('electron');
const { autoUpdater } = require('electron-updater');

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
if (app.isPackaged) {
  dotenv = require('./node_modules/dotenv');
} else {
  dotenv = require('dotenv');
}

const iconDir = path.isPackaged ? path.join(process.resourcesPath, 'icons') : path.join(__dirname, 'icons');

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
    if (command === 'start' || command === 'restart') {
      const apiKeySet = checkAndUpdateEnvFile();
      if (!apiKeySet && command === 'start') {
        writeToScreen('[HTML]: <p><b>No API keys are set, but proceeding anyway.</b></p>');
      }
      
      // Reload TTS dictionary if path exists but data is missing or outdated
      const envPath = getEnvPath();
      if (envPath) {
        const envConfig = readEnvFile(envPath);
        if (envConfig.TTS_DICT_PATH && 
            (!envConfig.TTS_DICT_DATA || 
             fs.existsSync(envConfig.TTS_DICT_PATH))) {
          try {
            // Read current file content
            const fileContent = fs.readFileSync(envConfig.TTS_DICT_PATH, 'utf8');
            // Update the dictionary data in the environment settings
            envConfig.TTS_DICT_DATA = fileContent;
            writeEnvFile(envPath, envConfig);
            console.log(`TTS Dictionary reloaded from ${envConfig.TTS_DICT_PATH}`);
          } catch (error) {
            console.error('Error reloading TTS Dictionary:', error);
          }
        }
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
                    message: 'Update Available',
                    detail: `A new version of the app is available. Please update to the latest version.`,
                    icon: path.join(iconDir, 'app-icon.png')
                  });
                }
                // Check if the image is not found and update the status accordingly
              } else if (lines[i].trim() === "[IMAGE NOT FOUND]") {
                writeToScreen('[HTML]: <p>Monadic Chat Docker image not found.</p>');
                currentStatus = "Building";
                updateTrayImage(currentStatus);
                updateStatusIndicator(currentStatus);
                // Check if the server has started and attempt to connect to it
              } else 
                if (lines[i].trim() === "[SERVER STARTED]") {
                  if (!fetchWithRetryCalled) {
                    fetchWithRetryCalled = true;
                    writeToScreen('[HTML]: <p><i class="fa-solid fa-circle-info"></i>Monadic Chat server is starting . . .</p>');
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
                      writeToScreen('[HTML]: <p><b>Failed to start Monadic Chat server.</b></p><p>Please check out <b>server.log</b> in the log folder and start the server again. Rebuild the image ("Menu" → "Action" → "Rebuild"), if necessary.</p><hr />');
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

// Check for updates - called manually when user clicks "Check for Updates"
function checkForUpdates() {
  // Temporarily disable writing update messages to the console
  // This prevents duplicate messages when manually checking for updates
  const originalSendCommandOutput = mainWindow.webContents.send;
  const tempSendFunction = function(channel, ...args) {
    // Block 'command-output' messages that contain update notifications
    if (channel === 'command-output' && typeof args[0] === 'string' && 
       (args[0].includes('A new version') || 
        args[0].includes('You are using the latest version') ||
        args[0].includes('Unable to check for updates'))) {
      // Do not send update messages to console during manual check
      return;
    }
    // Pass through all other messages
    return originalSendCommandOutput.apply(mainWindow.webContents, [channel, ...args]);
  };
  
  // Replace the send function temporarily
  mainWindow.webContents.send = tempSendFunction;
  
  // First try using electron-updater's autoUpdater
  try {
    // Prepare event handlers for user feedback
    const removeUpdateListeners = () => {
      autoUpdater.removeAllListeners('update-available');
      autoUpdater.removeAllListeners('update-not-available');
      autoUpdater.removeAllListeners('error');
      autoUpdater.removeAllListeners('download-progress');
      autoUpdater.removeAllListeners('update-downloaded');
      
      // Restore original send function
      mainWindow.webContents.send = originalSendCommandOutput;
    };
    
    // Set up temporary listeners for this manual check
    autoUpdater.on('update-available', (info) => {
      removeUpdateListeners(); // Clean up listeners
      
      // Always show a dialog when an update is available from manual check
      dialog.showMessageBox(mainWindow, {
        type: 'info',
        buttons: ['Update', 'Cancel'],
        message: 'Update Available',
        detail: `A new version (${info.version}) is available. Would you like to update now?`,
        icon: path.join(iconDir, 'app-icon.png')
      }).then((result) => {
        if (result.response === 0) {
          // Remove existing listeners before starting download
          removeUpdateListeners();
          
          // Create a progress dialog for the download
          let progressWin = new BrowserWindow({
            width: 400,
            height: 220,
            useContentSize: true,
            autoHideMenuBar: true,
            minimizable: false,
            maximizable: false,
            resizable: false,
            alwaysOnTop: true,
            fullscreenable: false,
            webPreferences: {
              nodeIntegration: false,
              contextIsolation: true,
              preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js')
            },
            parent: mainWindow,
            modal: true,
            title: "Downloading Update",
            backgroundColor: '#f8f9fa',
            show: false, // Hidden initially to prevent flickering
            frame: false, // Frameless window looks more modern
            transparent: false
          });
          
          progressWin.loadFile('update-progress.html');
          progressWin.once('ready-to-show', () => {
            progressWin.show();
          });
          
          // Set up new listeners just for this download process
          // Listen for download progress and update UI
          autoUpdater.on('download-progress', (progressObj) => {
            if (!progressWin.isDestroyed()) {
              progressWin.webContents.send('update-progress', progressObj);
            }
          });
          
          // Once download is complete, close progress window and notify user
          autoUpdater.on('update-downloaded', () => {
            if (!progressWin.isDestroyed()) {
              progressWin.close();
            }
            
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              buttons: ['Exit Now', 'Later'],
              message: 'Update Ready',
              detail: 'The update has been downloaded. Please exit the application and restart it to apply the update.',
              icon: path.join(iconDir, 'app-icon.png')
            }).then((btnIdx) => {
              if (btnIdx.response === 0) {
                forceQuit = true;
                
                // Use the original app quit mechanism
                forceQuit = true;
                cleanupAndQuit();
              }
            });
          });
          
          // Start the download - this will trigger progress events
          autoUpdater.downloadUpdate();
        }
      });
    });

    autoUpdater.on('update-not-available', () => {
      // Always show a message when no update is available
      dialog.showMessageBox(mainWindow, {
        type: 'info',
        buttons: ['OK'],
        message: 'Up to Date',
        detail: 'You are using the latest version of the application.',
        icon: path.join(iconDir, 'app-icon.png')
      }).finally(() => {
        // Remove listeners and restore original send function after dialog is closed
        removeUpdateListeners();
      });
    });
    
    // Special error handler for manual checks
    autoUpdater.on('error', (error) => {
      dialog.showMessageBox(mainWindow, {
        type: 'warning',
        buttons: ['OK'],
        message: 'Update Check Failed',
        detail: `Unable to check for updates: ${error.message}\n\nYou can still use the application normally and check our website for updates.`,
        icon: path.join(iconDir, 'app-icon.png')
      }).finally(() => {
        // Remove listeners and restore original send function after dialog is closed
        removeUpdateListeners();
      });
    });

    // Initiate check
    autoUpdater.checkForUpdates();
  } catch (err) {
    // Restore original send function in case of error
    mainWindow.webContents.send = originalSendCommandOutput;
    
    // Fall back to old method if autoUpdater fails
    console.error('Auto-update check failed, falling back to manual check:', err);
    checkForUpdatesManual();
  }
}

// Manual version check as a fallback
function checkForUpdatesManual() {
  // No specific handling needed for manual check, as it uses different methods
  // and doesn't trigger the standard update-available/update-not-available events
  
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
            message: 'Update Available',
            detail: `A new version (${latestVersion}) of the app is available. Please update to the latest version.`,
            icon: path.join(iconDir, 'app-icon.png')
          });
        } else {
          dialog.showMessageBox(mainWindow, {
            type: 'info',
            buttons: ['OK'],
            message: 'Up to Date',
            detail: `You are already using the latest version of the app.`,
            icon: path.join(iconDir, 'app-icon.png')
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
    message: 'Confirm Uninstall',
    detail: 'This will remove all the Monadic Chat images and containers. Do you want to continue?',
    icon: path.join(iconDir, 'app-icon.png')
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
let forceQuit = false;
let isQuittingDialogShown = false;

async function quitApp() {
  if (isQuittingDialogShown || forceQuit) return;

  isQuittingDialogShown = true;

  let options = {
    type: 'question',
    buttons: ['Cancel', 'Quit'],
    defaultId: 1,
    title: 'Confirm Quit',
    message: 'Quit Monadic Chat Console?',
    detail: 'This will stop all running processes and close the application.',
    icon: path.join(iconDir, 'app-icon.png')
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
  // Send a shutdown notification to the web app
  writeToScreen('[HTML]: <p>Quitting Monadic Chat . . .</p>');
  
  // No shutdown notification needed with the simplified approach
  
  // Delay actual exit to allow message to be processed by browser
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

    // Ensure we bypass any confirmation dialogs
    forceQuit = true;
    
    // Exit the app completely
    app.exit(0);
  }, 3000);
}

// Update the app's quit handler
app.on('before-quit', (event) => {
  // If forceQuit is true, allow the app to quit normally without showing dialog
  if (forceQuit) {
    return; // Exit handler without preventing quit
  }
  
  // Otherwise, prevent quit and show confirmation dialog
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
    label: 'Open Console',
    click: () => {
      openMainWindow();
    },
    enabled: true
  },
  {
    label: 'Open Browser',
    click: () => {
      openMainWindow();
      openBrowser('http://localhost:4567');
    },
    enabled: false
  },
  { type: 'separator' },
  {
    label: 'Open Shared Folder',
    click: () => {
      openMainWindow();
      openSharedFolder();
    },
    enabled: true
  },
  {
    label: 'Open Config Folder',
    click: () => {
      openMainWindow();
      openConfigFolder();
    },
    enabled: true
  },
  {
    label: 'Open Log Folder',
    click: () => {
      openMainWindow();
      openLogFolder();
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

let updateMessage = '';

// Auto-update related functions
function setupAutoUpdater() {
  // Allow pre-release versions to be detected for testing
  autoUpdater.allowPrerelease = true;
  // Allow downgrading to lower versions during testing
  autoUpdater.allowDowngrade = true;
  // Disable automatic downloading of updates
  autoUpdater.autoDownload = false;
  // Enable automatic installation of updates when quitting
  autoUpdater.autoInstallOnAppQuit = true;
  
  // Global error handler for auto-updater
  autoUpdater.on('error', (error) => {
    // Just log errors, don't show dialog for background checks
    console.error('Auto-update error:', error.message);
    // Set update message to indicate there was an error checking
    updateMessage = '[HTML]: <p><i class="fa-solid fa-circle-info" style="color: blue;"></i> Unable to check for updates. Please check manually later.</p>';
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', updateMessage);
    }
  });
  
  // Set update notification behavior
  autoUpdater.on('update-available', (info) => {
    // Update the message to indicate an update is available
    updateMessage = `[HTML]: <p><i class="fa-solid fa-circle-exclamation" style="color: orange;"></i> A new version (${info.version}) is available. Use "File" → "Check for Updates" to update.</p>`;
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', updateMessage);
    }
    
    // No dialog is shown on startup - user must click "Check for Updates" manually
  });
  
  // Handle the case when no update is available
  autoUpdater.on('update-not-available', () => {
    const currentVersion = app.getVersion();
    updateMessage = `[HTML]: <p><i class="fa-solid fa-circle-check" style="color: green;"></i> You are using the latest version (${currentVersion}).</p>`;
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', updateMessage);
    }
  });
  
  // Check for updates on startup, but only notify if available (don't auto-download)
  autoUpdater.checkForUpdates();
}

// Create update progress HTML file if it doesn't exist
function createUpdateProgressHTML() {
  const progressHtmlPath = path.join(__dirname, 'update-progress.html');
  if (!fs.existsSync(progressHtmlPath)) {
    const progressHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Downloading Update</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      padding: 20px;
      text-align: center;
    }
    progress {
      width: 100%;
      height: 20px;
      margin-top: 15px;
    }
    .status {
      margin-top: 10px;
      font-size: 12px;
      color: #666;
    }
  </style>
</head>
<body>
  <h3>Downloading Update...</h3>
  <progress id="progressBar" value="0" max="100"></progress>
  <div id="progressText" class="status">0%</div>
  <div id="speedText" class="status"></div>
  
  <script>
    // Preload script will expose this method
    window.addEventListener('message', (event) => {
      if (event.data.type === 'update-progress') {
        const progress = event.data.progress;
        const progressBar = document.getElementById('progressBar');
        const progressText = document.getElementById('progressText');
        const speedText = document.getElementById('speedText');
        
        progressBar.value = progress.percent || 0;
        progressText.textContent = \`\${Math.round(progress.percent || 0)}%\`;
        
        if (progress.bytesPerSecond) {
          const speed = (progress.bytesPerSecond / 1024 / 1024).toFixed(2);
          const transferred = (progress.transferred / 1024 / 1024).toFixed(2);
          const total = (progress.total / 1024 / 1024).toFixed(2);
          speedText.textContent = \`\${speed} MB/s - \${transferred} MB / \${total} MB\`;
        }
      }
    });
  </script>
</body>
</html>`;

    fs.writeFileSync(progressHtmlPath, progressHtml);
  }
}

function initializeApp() {
  app.whenReady().then(async () => {
    // Check if there's a pending update that was downloaded before restart
    if (autoUpdater.isUpdaterActive()) {
      console.log('Checking for downloaded updates to install...');
    }
    
    // Setup auto-updater - this will update the updateMessage variable
    setupAutoUpdater();
    
    // Check internet connection
    try {
      const response = await fetch('https://api.github.com', { timeout: 5000 });
      if (!response.ok) {
        throw new Error('Internet connection test failed');
      }
      
      // Note: We no longer perform a separate version check here
      // The autoUpdater will handle checking for updates and updating the message
      // This avoids displaying potentially conflicting information
      
    } catch (error) {
      forceQuit = true;
      dialog.showMessageBox(null, {
        type: 'error',
        title: 'Connection Error',
        message: 'No internet connection available',
        detail: 'Please check your internet connection and try again.',
        buttons: ['OK']
      }).then(() => {
        cleanupAndQuit();
      });
      return;
    }

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
          case 'sharedfolder':
            openSharedFolder();
            break;
          // case 'logfolder':
          //   openLogFolder();
          //   break;
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
        console.log(`Failed to connect to server after ${retries} attempts. Please check the error log in the log folder.`);
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
    // catch error and fallback to "Building.png"
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
              detail: 'Grounding AI Chatbots with Full Linux Environment on Docker\n\n© 2025 Yoichiro Hasebe',
              buttons: ['OK'],
              icon: path.join(iconDir, 'app-icon.png')
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
          label: 'Build All',
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
          label: 'Build Ruby Container',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('build_ruby_container',
              '[HTML]: <p>Building Ruby container . . .</p>',
              'Building',
              'Stopped',
              false);
          },
          enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
        },
        {
          label: 'Build Python Container',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('build_python_container',
              '[HTML]: <p>Building Python container . . .</p>',
              'Building',
              'Stopped',
              false);
          },
          enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
        },
        {
          label: 'Build User Containers',
          click: () => {
            openMainWindow();
            dockerManager.runCommand('build_user_containers',
              '[HTML]: <p>Building user containers . . .</p>',
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
            dockerManager.runCommand('start-jupyter', '[HTML]: <p>Starting JupyterLab . . .</p>', 'Starting', 'Running');
          },
          enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
        },
        {
          label: 'Stop JupyterLab',
          click: () => {
            dockerManager.runCommand('stop-jupyter', '[HTML]: <p>Stopping JupyterLab . . .</p>', 'Starting', 'Running');
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
          label: 'Open Console',
          click: () => {
            openMainWindow();
          }
        },
        {
          label: 'Open Browser',
          click: () => {
            openMainWindow();
            openBrowser('http://localhost:4567');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        { type: 'separator' },
        {
          label: 'Open Shared Folder',
          click: () => {
            openMainWindow();
            openSharedFolder();
          }
        },
        {
          label: 'Open Config Folder',
          click: () => {
            openMainWindow();
            openConfigFolder();
          }
        },
        {
          label: 'Open Log Folder',
          click: () => {
            openMainWindow();
            openLogFolder();
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
      contextIsolation: true,
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
      <p><b>Monadic Chat: Grounding AI Chatbots with Full Linux Environment on Docker</b></p>
      <p><i class="fa-solid fa-circle-info"></i> Please make sure Docker Desktop is running while using Monadic Chat.</p>
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

function openSharedFolder() {
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

  // create folderPath if it does not exist
  if (!fs.existsSync(folderPath)) {
    fs.mkdirSync(folderPath, {recursive: true});
  }

  shell.openPath(folderPath).then((result) => {
    if (result) {
      console.error('Error opening path:', result);
    }
  });
}

function openConfigFolder() {
  let folderPath;
  if (os.platform() === 'darwin' || os.platform() === 'linux') {
    folderPath = path.join(os.homedir(), 'monadic', 'config');
  } else if (os.platform() === 'win32') {
    try {
      const wslHome = execSync('wsl.exe echo $HOME').toString().trim();
      const wslPath = `/home/${path.basename(wslHome)}/monadic/config`;
      folderPath = execSync(`wsl.exe wslpath -w ${wslPath}`).toString().trim();
    } catch (error) {
      console.error('Error retrieving WSL path:', error);
      return;
    }
  }
  
  // create folderPath if it does not exist
  if (!fs.existsSync(folderPath)) {
    fs.mkdirSync(folderPath, {recursive: true});
  }

  shell.openPath(folderPath).then((result) => {
    if (result) {
      console.error('Error opening path:', result);
    }
  });
}

function openLogFolder() {
  let folderPath;
  if (os.platform() === 'darwin' || os.platform() === 'linux') {
    folderPath = path.join(os.homedir(), 'monadic', 'log');
  } else if (os.platform() === 'win32') {
    try {
      const wslHome = execSync('wsl.exe echo $HOME').toString().trim();
      const wslPath = `/home/${path.basename(wslHome)}/monadic/log`;
      folderPath = execSync(`wsl.exe wslpath -w ${wslPath}`).toString().trim();
    } catch (error) {
      console.error('Error retrieving WSL path:', error);
      return;
    }
  }
  
  // create folderPath if it does not exist
  if (!fs.existsSync(folderPath)) {
    fs.mkdirSync(folderPath, {recursive: true});
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
        writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-check' style='color: green;'></i>The server is running on port 4567. Opening the browser.</p>");
        spawn(...openCommands[platform]);
      } else {
        if (time == 0) {
          writeToScreen("[HTML]: <p>Waiting for the server to start . . .</p>");
        }
        time += interval;
        if (time >= timeout) {
          clearInterval(timer);
          dialog.showErrorBox('Error', "Failed to start the server. Please try again.");
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
        nodeIntegration: false,
        contextIsolation: true,
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
      const wslPath = `/home/${path.basename(wslHome)}/monadic/config/env`;
      return execSync(`wsl.exe wslpath -w ${wslPath}`).toString().trim();
    } catch (error) {
      console.error('Error getting WSL path:', error);
      return null;
    }
  } else {
    return path.join(os.homedir(), 'monadic', 'config', 'env');
  }
}

// Read the ENV file; if it does not exist, create it
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

// Write the ENV file by converting config entries to newline-separated key=value pairs
function writeEnvFile(envPath, envConfig) {
    const envContent = Object.entries(envConfig)
        .map(([key, value]) => `${key}=${value}`)
        .join('\n');

    try {
        fs.writeFileSync(envPath, envContent);
        // console.log('Settings saved successfully to', envPath);
    } catch (error) {
        console.error('Error saving settings:', error);
    }
}

// Update ENV file settings; if a key is missing, set default value (do not override TTS_DICT_PATH if present)
function checkAndUpdateEnvFile() {
    const envPath = getEnvPath();
    if (!envPath) return false;

    let envConfig = readEnvFile(envPath);

    // Set default values if not already specified
    if (!envConfig.ROUGE_THEME) {
        envConfig.ROUGE_THEME = 'github:light';
    }

    if (!envConfig.STT_MODEL) {
        envConfig.STT_MODEL = 'gpt-4o-transcribe';
    }

    if (!envConfig.AI_USER_MODEL) {
        envConfig.AI_USER_MODEL = 'gpt-4o';
    }

    if (!envConfig.AI_USER_MAX_TOKENS) {
        envConfig.AI_USER_MAX_TOKENS = '2000';
    }

    if (!envConfig.EMBEDDING_MODEL) {
        envConfig.EMBEDDING_MODEL = 'text-embedding-3-small';
    }

    if (!envConfig.WEBSEARCH_MODEL) {
        envConfig.WEBSEARCH_MODEL = 'gpt-4o-mini-search-preview';
    }

    // Set default models for each provider if not already specified
    if (!envConfig.OPENAI_DEFAULT_MODEL) {
        envConfig.OPENAI_DEFAULT_MODEL = 'gpt-4o';
    }

    if (!envConfig.ANTHROPIC_DEFAULT_MODEL) {
        envConfig.ANTHROPIC_DEFAULT_MODEL = 'claude-3-5-sonnet-20241022';
    }

    if (!envConfig.COHERE_DEFAULT_MODEL) {
        envConfig.COHERE_DEFAULT_MODEL = 'command-r-plus';
    }

    if (!envConfig.GEMINI_DEFAULT_MODEL) {
        envConfig.GEMINI_DEFAULT_MODEL = 'gemini-2.0-flash';
    }

    if (!envConfig.MISTRAL_DEFAULT_MODEL) {
        envConfig.MISTRAL_DEFAULT_MODEL = 'mistral-large-latest';
    }

    if (!envConfig.GROK_DEFAULT_MODEL) {
        envConfig.GROK_DEFAULT_MODEL = 'grok-2';
    }

    if (!envConfig.PERPLEXITY_DEFAULT_MODEL) {
        envConfig.PERPLEXITY_DEFAULT_MODEL = 'sonar';
    }

    if (!envConfig.DEEPSEEK_DEFAULT_MODEL) {
        envConfig.DEEPSEEK_DEFAULT_MODEL = 'deepseek-chat';
    }

    // Do not override TTS_DICT_PATH if it already exists
    if (envConfig.TTS_DICT_PATH === undefined) {
        envConfig.TTS_DICT_PATH = '';
    }

    if (envConfig.EXTRA_LOGGING === undefined) {
      envConfig.EXTRA_LOGGING = 'false';
    }

    // Check for the presence of any API key
    const api_list = [
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'COHERE_API_KEY',
        'GEMINI_API_KEY',
        'XAI_API_KEY',
        'PERPLEXITY_API_KEY',
        'DEEPSEEK_API_KEY',
        'ELEVENLABS_API_KEY',
        'TAVILY_API_KEY'
    ];
    const hasApiKey = api_list.some(key => envConfig[key]);
    
    // Save updated config to file
    writeEnvFile(envPath, envConfig);
    return hasApiKey;
}

// Save the settings received from the settings UI
function saveSettings(data) {
    const envPath = getEnvPath();
    if (envPath) {
        // Ensure that TTS_DICT_PATH is not undefined
        if (typeof data.TTS_DICT_PATH === 'undefined' || data.TTS_DICT_PATH === null) {
            data.TTS_DICT_PATH = ''; // default to an empty string if undefined
        }
        
        // Read the existing configuration from the file
        let envConfig = readEnvFile(envPath);
        
        // Check if TTS_DICT_PATH has changed and needs updated content
        if (data.TTS_DICT_PATH !== envConfig.TTS_DICT_PATH && data.TTS_DICT_PATH !== '') {
            try {
                // Read the CSV file content
                const fileContent = fs.readFileSync(data.TTS_DICT_PATH, 'utf8');
                // Store the CSV content in a separate environment variable
                data.TTS_DICT_DATA = fileContent;
            } catch (error) {
                console.error('Error reading TTS dictionary file:', error);
                // If there's an error reading the file, keep the existing data or clear it
                if (data.TTS_DICT_PATH === '') {
                    data.TTS_DICT_DATA = '';
                }
            }
        } else if (data.TTS_DICT_PATH === '') {
            // If the path is being cleared, also clear the data
            data.TTS_DICT_DATA = '';
        }
        
        // Override existing settings with new data (empty string values are included)
        Object.assign(envConfig, data);
        // Write the updated configuration back to the file
        writeEnvFile(envPath, envConfig);
    }
}

function loadSettings() {
  const envPath = getEnvPath();
  return envPath ? readEnvFile(envPath) : {};
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

// Add IPC handler for selecting TTS dictionary file
ipcMain.handle('select-tts-dict', async () => {
    const result = await dialog.showOpenDialog({
        properties: ['openFile'],
        filters: [{ name: 'CSV Files', extensions: ['csv'] }]
    });
    if (!result.canceled && result.filePaths.length > 0) {
        // Save the file path
        const filePath = result.filePaths[0];
        
        try {
            // Read the CSV file content
            const fileContent = fs.readFileSync(filePath, 'utf8');
            
            // Store the content to be passed to the Ruby side
            const envPath = getEnvPath();
            if (envPath) {
                let envConfig = readEnvFile(envPath);
                envConfig.TTS_DICT_PATH = filePath;
                // Store the CSV content in a separate environment variable
                envConfig.TTS_DICT_DATA = fileContent;
                writeEnvFile(envPath, envConfig);
            }
            
            return filePath;
        } catch (error) {
            console.error('Error reading TTS dictionary file:', error);
            dialog.showErrorBox('Error', `Failed to read TTS dictionary file: ${error.message}`);
            return '';
        }
    }
    return '';
});

async function updateDockerStatus() {
  if (dockerInstalled) {
    const status = await dockerManager.checkStatus();
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('docker-desktop-status-update', status);
      // if status is false, meaning Docker Desktop is not running,
      // update the context menu and buttons only if the current status is not "Stopped"
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
