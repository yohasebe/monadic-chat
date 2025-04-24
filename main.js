// Disable various Electron warnings
process.env.ELECTRON_DISABLE_SECURITY_WARNINGS = '1';
process.env.ELECTRON_NO_ATTACH_CONSOLE = '1';
process.env.ELECTRON_ENABLE_LOGGING = '0';
process.env.ELECTRON_DEBUG_EXCEPTION_LOGGING = '0';

const { app, dialog, shell, Menu, Tray, BrowserWindow, ipcMain } = require('electron');
const { autoUpdater } = require('electron-updater');

// Disable hardware acceleration to reduce issues on some systems
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

// if (process.platform === 'darwin') {
//   app.commandLine.appendSwitch('no-sound');
// }

// Allow autoplay of audio without user gesture in internal browser (Electron webview)
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

const { exec, execSync, spawn } = require('child_process');
const extendedContextMenu = require('electron-context-menu');
const path = require('path');
const fs = require('fs');
const os = require('os');
const https = require('https');
const net = require('net');

// Add debug mode for troubleshooting statusIndicator issues
const debugStatusIndicator = true;

let tray = null;
let justLaunched = true;
let currentStatus = 'Stopped';
let isQuitting = false;
let contextMenu = null;
let initialLaunch = true;
// Preference for browser launch: 'external' or 'internal'
// Default browser mode: 'internal' for internal Electron view
let browserMode = 'internal';

// Internal browser window reference and opener
let webviewWindow = null;
// State for in-page search to filter invisible matches
// State for in-page search (filtering invisible matches)
let findState = { term: '', forward: true, requestId: null };
function openWebViewWindow(url) {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    webviewWindow.focus();
    return;
  }
  webviewWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    // Prevent width below 320px; mobile styles apply below 1024px
    minWidth: 412,
    minHeight: 600,
    title: 'Monadic Chat',
    // Add background color to match web app theme - at the correct level
    backgroundColor: '#DCDCDC',
    webPreferences: {
      preload: path.join(__dirname, 'webview-preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      spellcheck: false, // Disable spellcheck as it can interfere with keyboard events
      // Enable media permissions for microphone access
      webSecurity: true,
      allowRunningInsecureContent: false,
      // Enable permissions for media devices explicitly
      permissions: {
        media: true,
        audioCapture: true,
        microphone: true
      }
    }
  });
  // Set permission request handler to auto-approve media access requests
  webviewWindow.webContents.session.setPermissionRequestHandler((webContents, permission, callback) => {
    const allowedPermissions = ['media', 'microphone', 'audioCapture'];
    if (allowedPermissions.includes(permission)) {
      // Auto-approve media permission requests and log for debugging
      console.log(`Approving permission request for: ${permission}`);
      callback(true);
    } else {
      // Deny other permission requests
      callback(false);
    }
  });
  
  webviewWindow.loadURL(url);
  // Filter out invisible matches: skip zero-sized selections
  webviewWindow.webContents.on('found-in-page', (event, result) => {
    // Only handle our own search requests
    if (result.requestId !== findState.requestId) return;
    // Ignore final update events
    if (result.finalUpdate) return;
    // Only skip when we have an active match
    if (result.activeMatchOrdinal && result.activeMatchOrdinal > 0) {
      const rect = result.selectionRect;
      // If selection has no size, skip this match
      if (!rect || rect.width === 0 || rect.height === 0) {
        webviewWindow.webContents.findInPage(findState.term, { forward: findState.forward, findNext: true });
      }
    }
  });
  // Custom menu is set further down in the code
  // Inject a floating button into the web page to bring the main window to front
  webviewWindow.webContents.on('dom-ready', () => {
    // Explicitly request microphone permission when the DOM is ready
    webviewWindow.webContents.executeJavaScript('window.electronAPI.requestMediaPermissions()').catch(err => {
      console.error('Failed to request media permissions:', err);
    });
    
    const injectButtonJS = `
      (function() {
        const container = document.createElement('div');
        container.style.position = 'fixed';
        container.style.bottom = '10px';
        container.style.right = '10px';
        container.style.display = 'flex';
        container.style.gap = '6px';
        container.style.zIndex = '9999';
        // Initial transform to counteract zoom when factor = 1
        container.style.transform = 'scale(1)';
        container.style.transformOrigin = 'bottom right';

        function makeBtn(iconClass, bgColor, onClick) {
          const btn = document.createElement('button');
          // Use string concatenation to avoid nested template literals
          btn.innerHTML = '<i class="' + iconClass + '"></i>';
          // Match toggle-menu dimensions and styling
          btn.style.width = '30px';
          btn.style.height = '30px';
          btn.style.padding = '0';
          btn.style.background = bgColor;
          btn.style.border = '1px solid rgba(0, 0, 0, 0.2)';
          btn.style.borderRadius = '4px';
          btn.style.cursor = 'pointer';
          btn.style.fontSize = '14px'; 
          btn.style.display = 'flex';
          btn.style.alignItems = 'center';
          btn.style.justifyContent = 'center';
          btn.style.boxShadow = '0 1px 3px rgba(0,0,0,0.1)';
          btn.onclick = onClick;
          return btn;
        }

        container.appendChild(makeBtn('fa-solid fa-magnifying-glass-plus', 'rgba(255,255,255,0.9)', () => window.electronAPI.zoomIn()));
        container.appendChild(makeBtn('fa-solid fa-magnifying-glass-minus', 'rgba(255,255,255,0.9)', () => window.electronAPI.zoomOut()));
        container.appendChild(makeBtn('fa-solid fa-arrows-rotate', 'rgba(66,139,202,0.9)', () => window.electronAPI.resetWebUI()));
        container.appendChild(makeBtn('fa-solid fa-terminal', 'rgba(255,193,7,0.9)', () => window.electronAPI.focusMainWindow()));

        document.body.appendChild(container);
        // Adjust overlay container on zoom change
        if (window.electronAPI && typeof window.electronAPI.onZoomChanged === 'function') {
          window.electronAPI.onZoomChanged((_event, factor) => {
            const scale = 1 / factor;
            // Use string concatenation to avoid nested template literals
            container.style.transform = 'scale(' + scale + ')';
            container.style.transformOrigin = 'bottom right';
            const offset = 10 / factor;
            container.style.right = offset + 'px';
            container.style.bottom = offset + 'px';
          });
        }
      })();
    `;
    webviewWindow.webContents.executeJavaScript(injectButtonJS).catch(err => {
      console.error('Failed to inject focus button:', err);
    });
  });
  // Make sure Menu is visible for standard edit commands
  const editMenu = Menu.buildFromTemplate([
    {
      label: 'Edit',
      submenu: [
        {
          label: 'Undo',
          accelerator: 'CmdOrCtrl+Z',
          click: () => {
            webviewWindow.webContents.undo();
          }
        },
        {
          label: 'Redo',
          accelerator: process.platform === 'darwin' ? 'CmdOrCtrl+Shift+Z' : 'CmdOrCtrl+Y',
          click: () => {
            webviewWindow.webContents.redo();
          }
        },
        { type: 'separator' },
        {
          label: 'Cut',
          accelerator: 'CmdOrCtrl+X',
          click: () => {
            webviewWindow.webContents.cut();
          }
        },
        {
          label: 'Copy',
          accelerator: 'CmdOrCtrl+C',
          click: () => {
            webviewWindow.webContents.copy();
          }
        },
        {
          label: 'Paste',
          accelerator: 'CmdOrCtrl+V',
          click: () => {
            webviewWindow.webContents.paste();
          }
        },
        { type: 'separator' },
        {
          label: 'Select All',
          accelerator: 'CmdOrCtrl+A',
          click: () => {
            webviewWindow.webContents.selectAll();
          }
        }
      ]
    },
    {
      label: 'View',
      submenu: [
        { 
          label: 'Reload',
          accelerator: 'CmdOrCtrl+R',
          click: () => {
            webviewWindow.reload();
          }
        },
        { 
          label: 'Toggle DevTools',
          accelerator: 'CmdOrCtrl+Shift+I',
          click: () => {
            webviewWindow.webContents.toggleDevTools();
          }
        },
        { type: 'separator' },
        { 
          label: 'Zoom In',
          accelerator: 'CmdOrCtrl+Plus',
          click: () => {
            webviewWindow.webContents.send('zoom-in-menu');
          }
        },
        { 
          label: 'Zoom Out',
          accelerator: 'CmdOrCtrl+-',
          click: () => {
            webviewWindow.webContents.send('zoom-out-menu');
          }
        },
        { type: 'separator' },
        { 
          label: 'Toggle Fullscreen',
          accelerator: process.platform === 'darwin' ? 'Ctrl+Command+F' : 'F11',
          click: () => {
            const isFullScreen = webviewWindow.isFullScreen();
            webviewWindow.setFullScreen(!isFullScreen);
          }
        }
      ]
    }
  ]);
  
  // Apply menu to the webview window
  webviewWindow.setMenu(editMenu);
  
  // Register built-in shortcuts but don't intercept most keyboard events
  webviewWindow.webContents.on('before-input-event', (event, input) => {
    // Only intercept fullscreen toggle to make sure it works
    const isMac = process.platform === 'darwin';
    if (input.type === 'keyDown') {
      // OS-specific fullscreen shortcuts
      if (isMac && input.control && input.meta && input.key.toLowerCase() === 'f') {
        const isFullScreen = webviewWindow.isFullScreen();
        webviewWindow.setFullScreen(!isFullScreen);
        event.preventDefault();
        return;
      } else if (!isMac && input.key === 'F11') {
        const isFullScreen = webviewWindow.isFullScreen();
        webviewWindow.setFullScreen(!isFullScreen);
        event.preventDefault();
        return;
      }
      // Handle standard edit shortcuts
      if (input.meta || input.control) {
        const key = input.key.toLowerCase();
        if (key === 'z' && !input.shift) {
          webviewWindow.webContents.undo();
          event.preventDefault();
          return;
        } else if ((key === 'z' && input.shift) || key === 'y') {
          webviewWindow.webContents.redo();
          event.preventDefault();
          return;
        } else if (key === 'x') {
          webviewWindow.webContents.cut();
          event.preventDefault();
          return;
        } else if (key === 'c') {
          webviewWindow.webContents.copy();
          event.preventDefault();
          return;
        } else if (key === 'v') {
          webviewWindow.webContents.paste();
          event.preventDefault();
          return;
        } else if (key === 'a') {
          webviewWindow.webContents.selectAll();
          event.preventDefault();
          return;
        }
      }
      // Let all other keyboard events pass through to the webview
    }
  });
  webviewWindow.on('closed', () => {
    webviewWindow = null;
  });
}

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
  constructor() {
    // Default to standalone mode (not server mode)
    this.serverMode = false;
    
    // Docker containers use fixed ports
    this.rubyPort = '4567';     // Ruby Sinatra web server
    this.pythonPort = '5070';   // Python Flask API server
    this.jupyterPort = '8889';  // JupyterLab server (disabled in server mode)
    
    // Configuration will be loaded from .env file
    // HOST_BINDING will be set to:
    // - 127.0.0.1 for standalone mode (local access only)
    // - 0.0.0.0 for server mode (accessible from network)
  }

  // Load distributed mode settings (unified method that handles both server and standalone modes)
  loadDistributedModeSettings() {
    const envPath = getEnvPath();
    if (envPath) {
      const envConfig = readEnvFile(envPath);
      this.serverMode = envConfig.DISTRIBUTED_MODE === 'server';
      
      // Set host binding based on mode - 0.0.0.0 for server mode, 127.0.0.1 for standalone
      envConfig.HOST_BINDING = this.serverMode ? '0.0.0.0' : '127.0.0.1';
      writeEnvFile(envPath, envConfig);
      
      // Get local IP address for server mode
      let localIPAddress = '127.0.0.1';
      if (this.serverMode) {
        try {
          const networkInterfaces = os.networkInterfaces();
          // Find the first non-internal IPv4 address
          for (const interfaceName in networkInterfaces) {
            const interfaces = networkInterfaces[interfaceName];
            for (const iface of interfaces) {
              if (iface.family === 'IPv4' && !iface.internal) {
                localIPAddress = iface.address;
                break;
              }
            }
            if (localIPAddress !== '127.0.0.1') break;
          }
        } catch (err) {
          console.error('Error getting network interfaces:', err);
        }
      }
      
      // Sync with main window if it exists
      if (mainWindow && !mainWindow.isDestroyed() && mainWindow.webContents) {
        try {
          mainWindow.webContents.executeJavaScript(`
            document.cookie = "distributed-mode=${this.serverMode ? 'server' : 'off'}; path=/; max-age=31536000";
          `);
          mainWindow.webContents.send('update-distributed-mode', {
            mode: this.serverMode ? 'server' : 'off',
            localIP: localIPAddress,
            showNotification: false
          });
        } catch (error) {
          console.error('Error syncing distributed mode', error);
        }
      }
      
      // Using fixed default ports as Docker containers have hardcoded port bindings
      this.rubyPort = '4567';
      this.pythonPort = '5070';
      this.jupyterPort = '8889';
    }
    return this.serverMode;
  }
  
  // Alias for backward compatibility
  loadServerModeSettings() {
    return this.loadDistributedModeSettings();
  }

  // Check if we're in server mode
  isServerMode() {
    this.loadDistributedModeSettings();
    return this.serverMode;
  }

  // Other methods remain unchanged
  async checkStatus() {
    // Docker status check
    return new Promise((resolve, reject) => {
      const cmd = `${monadicScriptPath} check`;
      exec(cmd, (error, stdout, stderr) => {
        if (error) {
          console.error(`Docker status check error: ${error.message}`);
          reject(error);
        } else if (stderr) {
          console.error(`Docker status check stderr: ${stderr}`);
          reject(stderr);
        } else {
          const isRunning = stdout.trim() === '1';
          console.log(`Docker status check result: ${isRunning}`);
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
    // Check Docker Desktop status
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
    // Write the initial message to the screen
    writeToScreen(message);
    
    // Update the status indicator in the main window
    updateStatusIndicator(statusWhileCommand);
    // Docker command execution
    return this.checkStatus()
      .then((status) => {
        if (!status) {
          writeToScreen('[HTML]: <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> Docker Desktop is not running. Please start Docker Desktop and try again.</p><hr />');
          return;
        } else {
          // Construct the command to execute
          const cmd = `${monadicScriptPath} ${command}`;
          
          // Update the current status and context menu
          currentStatus = statusWhileCommand;
          
          // Reset the fetchWithRetryCalled flag
          fetchWithRetryCalled = false;
          
          // Update the context menu and application menu
          updateContextMenu();
          updateApplicationMenu();
          
          // Simple command execution that handles SERVER STARTED messages
          return new Promise((resolve, reject) => {
            let subprocess = spawn(cmd, [], {shell: true});
            
            subprocess.stdout.on('data', function (data) {
              writeToScreen(data.toString());
              
              // Check for server started message
              if (data.toString().includes("[SERVER STARTED]")) {
                fetchWithRetry('http://localhost:4567')
                  .then(() => {
                    updateContextMenu(false);
                    
                    // Set status to Ready - this will update UI
                    currentStatus = "Ready";
                    updateStatusIndicator("Ready");
                    
                    // Signal successful server start with an event
                    writeToScreen('[HTML]: <p><i class="fa-solid fa-check-circle" style="color:#22ad50;"></i> <span style="color:#22ad50;">Server verification complete</span></p>');
                    
                    // Force a small delay to ensure status update is processed first
                    setTimeout(() => {
                      // In server mode, show network URL but don't auto-open browser
                      if (dockerManager.isServerMode()) {
                        // Get local IP address for network access info
                        let localIPAddress = '127.0.0.1';
                        try {
                          const networkInterfaces = os.networkInterfaces();
                          for (const interfaceName in networkInterfaces) {
                            const interfaces = networkInterfaces[interfaceName];
                            for (const iface of interfaces) {
                              if (iface.family === 'IPv4' && !iface.internal) {
                                localIPAddress = iface.address;
                                break;
                              }
                            }
                            if (localIPAddress !== '127.0.0.1') break;
                          }
                        } catch (err) {
                          console.error('Error getting network interfaces:', err);
                        }
                        
                        // Send a custom command to show network URL exactly once
                        if (mainWindow && !mainWindow.isDestroyed()) {
                          mainWindow.webContents.send('display-network-url', {
                            localIP: localIPAddress
                          });
                        }
                      } else {
                        // For standalone mode - send network URL event for proper status update first
                        if (mainWindow && !mainWindow.isDestroyed()) {
                          mainWindow.webContents.send('display-network-url', {
                            localIP: '127.0.0.1'
                          });
                        }

                        // Then open based on browser mode preference
                        if (browserMode === 'internal') {
                          openWebViewWindow('http://localhost:4567');
                        } else {
                          try {
                            shell.openExternal('http://localhost:4567').catch(err => {
                              console.error('Error opening browser:', err);
                              writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: #FF7F07;'></i>Please open browser manually at http://localhost:4567</p>");
                            });
                            writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Opening the browser.</p>");
                          } catch (err) {
                            console.error('Error opening browser:', err);
                          }
                        }
                      }
                    }, 500);
                  })
                  .catch(error => {
                    console.error('Fetch failed:', error);
                  });
              }
            });
            
            subprocess.stderr.on('data', function (data) {
              console.error(data.toString());
            });
            
            subprocess.on('close', function (code) {
              if (code !== 0) {
                dialog.showErrorBox('Error', `Docker command exited with code ${code}.`);
              }
              
              currentStatus = statusAfterCommand;
              updateTrayImage(statusAfterCommand);
              updateStatusIndicator(statusAfterCommand);
              updateContextMenu(false);
              
              resolve();
            });
          });
        }
      })
      .catch(error => {
        console.error('Error checking Docker status:', error);
        writeToScreen(`[ERROR]: ${error.message}`);
      });
  }
} // End of DockerManager class

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
          
          // Flag to track if progress window was manually closed
          let progressWinClosed = false;
          
          // Safety timeout for progress window - if it gets stuck for too long
          const progressTimeoutID = setTimeout(() => {
            if (!progressWinClosed && !progressWin.isDestroyed()) {
              console.log('Progress window timeout - closing stuck window');
              progressWin.close();
              
              dialog.showMessageBox(mainWindow, {
                type: 'warning',
                buttons: ['OK'],
                message: 'Update Download Timeout',
                detail: 'The update download process is taking longer than expected. Please try again later or check for issues with your internet connection.',
                icon: path.join(iconDir, 'app-icon.png')
              });
            }
          }, 10 * 60 * 1000); // 10 minute timeout
          
          // Track window closed event
          progressWin.on('closed', () => {
            progressWinClosed = true;
            clearTimeout(progressTimeoutID);
          });
          
          progressWin.loadFile('update-progress.html');
          progressWin.once('ready-to-show', () => {
            progressWin.show();
          });
          
          // Set up new listeners just for this download process
          // Listen for download progress and update UI
          autoUpdater.on('download-progress', (progressObj) => {
            if (!progressWinClosed && !progressWin.isDestroyed()) {
              // Clear timeout and set a new one on each progress update
              clearTimeout(progressTimeoutID);
              
              // Send progress data to the window
              progressWin.webContents.send('update-progress', progressObj);
            }
          });
          
          // Once download is complete, close progress window and notify user
          autoUpdater.on('update-downloaded', (info) => {
            // Clear safety timeout
            clearTimeout(progressTimeoutID);
            
            if (!progressWinClosed && !progressWin.isDestroyed()) {
              progressWin.close();
            }
            
            // Save update state to file system for persistence between app sessions
            try {
              const saved = saveUpdateState({
                updateReady: true,
                version: info.version,
                timestamp: Date.now()
              });
              
              if (!saved) {
                console.error('Failed to save update state');
              }
            } catch (error) {
              console.error('Error in update-downloaded handler while saving state:', error);
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
                
                // Use autoUpdater.quitAndInstall() instead of just quitting
                // This will ensure the update is properly installed
                autoUpdater.quitAndInstall(false, true);
              }
            }).catch(err => {
              console.error('Error showing update message dialog:', err);
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

// Add mode status to menu
function getDistributedModeLabel() {
  if (dockerManager.isServerMode()) {
    return "Server Mode";
  } else {
    return "Standalone Mode";
  }
}

let serverModeItem = {
  label: `Mode: ${getDistributedModeLabel()}`,
  enabled: false
};

const menuItems = [
  statusMenuItem,
  serverModeItem,
  { type: 'separator' },
  {
    label: 'Start',
    click: () => {
      openMainWindow();
      // Check requirements first
      dockerManager.checkRequirements()
        .then(() => {
          dockerManager.runCommand('start', '[HTML]: <p>Monadic Chat preparing . . .</p>', 'Starting', 'Running');
        })
        .catch((error) => {
          console.log(`Docker requirements check failed: ${error}`);
          // Show error dialog about Docker requirements
          dialog.showErrorBox('Docker Error', error);
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
      const url = 'http://localhost:4567';
      if (browserMode === 'internal') {
        openWebViewWindow(url);
      } else {
        openBrowser(url);
      }
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
    updateMessage = '[HTML]: <p><i class="fa-solid fa-circle-info" style="color: #61b0ff;"></i> Unable to check for updates. Please check manually later.</p>';
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', updateMessage);
    }
  });
  
  // Set update notification behavior
  autoUpdater.on('update-available', (info) => {
    // Update the message to indicate an update is available
    updateMessage = `[HTML]: <p><i class="fa-solid fa-circle-exclamation" style="color: #FF7F07;"></i> A new version (${info.version}) is available. Use "File" → "Check for Updates" to update.</p>`;
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', updateMessage);
    }
    
    // No dialog is shown on startup - user must click "Check for Updates" manually
  });
  
  // Handle the case when no update is available
  autoUpdater.on('update-not-available', () => {
    const currentVersion = app.getVersion();
    updateMessage = `[HTML]: <p><i class="fa-solid fa-circle-check" style="color: #22ad50;"></i> You are using the latest version (${currentVersion}).</p>`;
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
  console.log('Initializing application...');
  
  // Load saved settings and initialize browser mode preference
  try {
    const settings = loadSettings() || {};
    // Fallback to internal if not set
    browserMode = settings.BROWSER_MODE || 'internal';
    console.log('Browser mode set to:', browserMode);
  } catch (err) {
    console.error('Error loading browser mode setting:', err);
  }
  
  // Clear update state if we've gotten here after a successful update
  // Since this function only runs after a successful startup, it's safe
  // to clear any pending update state at this point
  const pendingUpdateState = readUpdateState();
  if (pendingUpdateState && pendingUpdateState.updateReady) {
    console.log('Update appears to have been successfully applied, clearing state');
    clearUpdateState();
  }
  
  // Setup auto-updater - this will update the updateMessage variable
  if (autoUpdater.isUpdaterActive()) {
    console.log('Auto-updater is active, setting up update checking');
    setupAutoUpdater();
  }
  
  // Continue with the rest of the initialization
  (async () => {
    
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

    // Set up Docker status polling
    setInterval(updateDockerStatus, 5000);

    tray = new Tray(path.join(iconDir, 'Stopped.png'));
    tray.setToolTip('Monadic Chat');
    tray.setContextMenu(contextMenu);

    extendedContextMenu({
      showSaveImageAs: true,
      showInspectElement: true,
      showSearchWithGoogle: false,
      showCopyImage: true,
      showCopyImageAddress: true
    });

    createMainWindow();
    contextMenu = Menu.buildFromTemplate(menuItems);

    updateStatus();

    ipcMain.on('command', async (_event, command) => {
      try {
        switch (command) {
          case 'start':
            // Check requirements first
            dockerManager.checkRequirements()
              .then(() => {
                dockerManager.runCommand('start', '[HTML]: <p>Monadic Chat preparing . . .</p>', 'Starting', 'Running');
              })
              .catch((error) => {
                console.log(`Docker requirements check failed: ${error}`);
                // Show error dialog for Docker issues
                dialog.showErrorBox('Docker Error', error);
              });
            break;
          case 'stop':
            dockerManager.runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped');
            break;
          case 'restart':
            dockerManager.runCommand('restart', '[HTML]: <p>Monadic Chat is restarting . . .</p>', 'Restarting', 'Running');
            break;
          case 'browser': {
            const url = 'http://localhost:4567';
            if (browserMode === 'internal') {
              openWebViewWindow(url);
            } else {
              openBrowser(url);
            }
            break;
          }
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
        console.log(`Docker requirements check failed: ${error}`);
        // Show error dialog
        dialog.showErrorBox('Error', error);
      })
      .finally(() => {
        updateApplicationMenu();
        // Only try to start Docker if we successfully met requirements
        if (metRequirements) {
          dockerManager.ensureDockerDesktopRunning();
        }
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
  })();
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
        // Only log error but don't throw it to avoid showing error dialog
        console.log(`Failed to connect to server after ${retries} attempts. Please check the error log in the log folder.`);
        // Return false instead of throwing error to indicate failure without causing an exception
        return false;
      }
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
  
  // Standard port check for Docker mode
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
    // Map status to appropriate icon filenames
    let iconFile = status;
    
    // Special handling for Ready status to use Running icon
    if (status === 'Ready') {
      iconFile = 'Running';
    }
    
    
    // Try to use the mapped icon file, fallback to Building.png if there's an error
    try {
      tray.setImage(path.join(iconDir, `${iconFile}.png`));
    } catch (error) {
      console.error(`Error loading tray icon for status ${status}:`, error);
      tray.setImage(path.join(iconDir, 'Building.png'));
    }
  }
}

function updateContextMenu(disableControls = false) {
  // Load the distributed mode settings
  dockerManager.loadDistributedModeSettings();
  
  updateTrayImage(currentStatus);
  if (tray) {
    // Update mode label
    serverModeItem.label = `Mode: ${getDistributedModeLabel()}`;
    
    if (disableControls) {
      menuItems.forEach(item => {
        if (item.label && ['Start', 'Stop', 'Restart', 'Open Browser'].includes(item.label)) {
          item.enabled = false;
        }
      });
    } else {
      // Enable/disable menu items based on status
      menuItems.forEach(item => {
        if (item.label === 'Start') {
          item.enabled = currentStatus === 'Stopped';
        } else if (item.label === 'Stop') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        } else if (item.label === 'Restart') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        } else if (item.label === 'Open Browser') {
          item.enabled = currentStatus === 'Running' || currentStatus === 'Ready';
        } else if (item.label === 'Build All' || item.label === 'Build Ruby Container' || 
                   item.label === 'Build Python Container' || item.label === 'Build User Containers') {
          item.enabled = currentStatus === 'Stopped' || currentStatus === 'Uninstalled';
        } else if (item.label === 'Import Document DB' || item.label === 'Export Document DB') {
          item.enabled = currentStatus === 'Stopped';
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
  // Make sure to update menu structure to reflect the current status
  
  // Create standard menu
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
        
        // Docker build commands
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
              // First check if we're in server mode
              if (dockerManager.isServerMode()) {
                dialog.showMessageBox(mainWindow, {
                  type: 'warning',
                  title: 'Jupyter Disabled',
                  message: 'JupyterLab is disabled in Server Mode',
                  detail: 'For security reasons, JupyterLab is not available when running in Server Mode. Switch to Standalone Mode in Settings to use JupyterLab.',
                  buttons: ['OK']
                });
                return;
              }
              openMainWindow();
              dockerManager.runCommand('start-jupyter', '[HTML]: <p>Starting JupyterLab . . .</p>', 'Starting', 'Running');
            },
            enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
          },
          {
            label: 'Stop JupyterLab',
            click: () => {
              // First check if we're in server mode
              if (dockerManager.isServerMode()) {
                dialog.showMessageBox(mainWindow, {
                  type: 'warning',
                  title: 'Jupyter Disabled',
                  message: 'JupyterLab is disabled in Server Mode',
                  detail: 'For security reasons, JupyterLab is not available when running in Server Mode. Switch to Standalone Mode in Settings to use JupyterLab.',
                  buttons: ['OK']
                });
                return;
              }
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
          }
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
            const url = 'http://localhost:4567';
            if (browserMode === 'internal') {
              openWebViewWindow(url);
            } else {
              openBrowser(url);
            }
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
    ,
    {
      label: 'Window',
      submenu: [
        {
          role: 'minimize',
          accelerator: process.platform === 'darwin' ? 'Cmd+M' : 'Ctrl+M'
        },
        {
          role: 'close',
          accelerator: process.platform === 'darwin' ? 'Cmd+W' : 'Ctrl+W'
        },
        { type: 'separator' },
        {
          role: 'reload',
          accelerator: process.platform === 'darwin' ? 'Cmd+R' : 'Ctrl+R'
        },
        {
          role: 'toggleDevTools',
          accelerator: process.platform === 'darwin' ? 'Alt+Cmd+I' : 'Ctrl+Shift+I'
        }
      ]
    }
  ]);

  Menu.setApplicationMenu(menu);
}

// Send a message to the renderer process to write to the screen
function writeToScreen(text) {
  if (mainWindow) {
    // No additional preprocessing needed - the renderer will handle HTML tags correctly
    mainWindow.webContents.send('command-output', text);
  }
}

// Send a message to the renderer process to update the status indicator
function updateStatusIndicator(status) {
  if (debugStatusIndicator) {
    console.log(`[STATUS INDICATOR] Setting status to: ${status}`);
    console.log(`[STATUS INDICATOR] Current distributed mode: ${dockerManager.isServerMode() ? 'server' : 'standalone'}`);
    console.trace();
  }
  
  if (mainWindow) {
    mainWindow.webContents.send('update-status-indicator', status);
    statusMenuItem.label = `Status: ${status}`;
  }
}

function createMainWindow() {
  if (mainWindow) return;
  
  // Ensure Docker Manager loads settings on startup
  dockerManager.loadServerModeSettings();

  mainWindow = new BrowserWindow({
    width: 780,
    minWidth: 780,
    height: 480,
    minHeight: 480,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.isPackaged ? path.join(process.resourcesPath, 'preload.js') : path.join(__dirname, 'preload.js'),
      contentSecurityPolicy: "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; script-src 'self' 'unsafe-inline'; connect-src 'self' https://raw.githubusercontent.com; img-src 'self' data:; worker-src 'self';",
      devTools: true, // Enable developer tools
      spellcheck: false // Disable spellcheck to avoid IMKit related errors
    },
    title: "Monadic Chat",
    useContentSize: true,
    // Show menu bar to enable standard shortcuts
    autoHideMenuBar: false,
    backgroundColor: '#f0f0f0'
  });

  let openingText;

  if (justLaunched) {
    // Check what mode we're in
    const isServerMode = dockerManager.isServerMode();
    
    if (isServerMode) {
      openingText = `
        [HTML]: 
        <p><b>Monadic Chat: <span style="color: #DC4C64; font-weight: bold;">Server Mode</span></b></p>
        <p><i class="fa-solid fa-server" style="color:#DC4C64;"></i> Running in server mode. Services will be accessible from external devices.</p>
        <p><i class="fa-solid fa-shield-halved" style="color:#FFC107;"></i> <strong>Security notice:</strong> Jupyter features are disabled in Server Mode for security.</p>
        <p>Press <b>start</b> button to initialize the server.</p>
        <hr />`
      currentStatus = 'Stopped';
    } else {
      openingText = `
        [HTML]: 
        <p><b>Monadic Chat: <span style="color: #4CACDC; font-weight: bold;">Standalone Mode</span></b></p>
        <p><i class="fa-solid fa-laptop" style="color:#4CACDC;"></i> Running in standalone mode. Services are accessible locally only.</p>
        <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> Please make sure Docker Desktop is running while using Monadic Chat.</p>
        <p>Press <b>start</b> button to initialize the server.</p>
        <hr />`
      currentStatus = 'Stopped';
    }
    justLaunched = false;

    // Check if port 4567 is already in use on initial launch
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

  // Register standard keyboard shortcuts
  mainWindow.webContents.on('before-input-event', (event, input) => {
    // For Cmd+C / Ctrl+C (Copy)
    if ((input.meta || input.control) && input.key === 'c') {
      mainWindow.webContents.copy();
    }
    // Disable Cmd+A / Ctrl+A (Select All) in main window
    else if ((input.meta || input.control) && input.key === 'a') {
      event.preventDefault();
    }
  });

  mainWindow.webContents.on('did-finish-load', () => {
    
    mainWindow.webContents.send('update-status-indicator', currentStatus);
    mainWindow.webContents.send('update-version', app.getVersion());
    
    // Set the distributed mode cookie based on actual settings (not just when changing settings)
    const isServerMode = dockerManager.isServerMode();
    mainWindow.webContents.executeJavaScript(`
      document.cookie = "distributed-mode=${isServerMode ? 'server' : 'off'}; path=/; max-age=31536000";
    `);
    
    // Send the mode update to the renderer process
    mainWindow.webContents.send('update-distributed-mode', {
      mode: isServerMode ? 'server' : 'off',
      showNotification: false
    });
    
    writeToScreen(openingText);
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  // Create minimal application menu with only Edit functionality for keyboard shortcuts
  const template = [
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'delete' }
      ]
    }
  ];

  // Set the same simple menu for all platforms
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));

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

function openBrowser(url, outside = false, forceOpen = false) {
  // No more client mode modifications needed

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

  // Enhanced browser opening function used in multiple places
  const launchBrowser = () => {
    console.log(`Opening browser to: ${url}`);
    writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Opening the browser.</p>");
    
    // Use shell.openExternal instead of spawn for more reliable behavior
    shell.openExternal(url).catch(err => {
      console.error('Error opening browser with shell.openExternal:', err);
      // Fallback to spawn if shell.openExternal fails
      try {
        spawn(...openCommands[platform]);
        console.log('Browser opened with spawn fallback');
      } catch (spawnErr) {
        console.error('Error opening browser with spawn fallback:', spawnErr);
        writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: #FF7F07;'></i>Failed to open browser automatically. Please open manually by navigating to: http://localhost:4567</p>");
      }
    });
  };
  
  // For forced opens or when current status is Ready/Running, bypass port checking
  if (outside || forceOpen || currentStatus === 'Ready' || currentStatus === 'Running') {
    // Open immediately without checking the port again
    launchBrowser();
    return;
  }

  // For server or standalone mode, check if port is available first
  const port = 4567;
  const timeout = 20000;
  const interval = 500;
  let time = 0;
  const timer = setInterval(() => {
    isPortTaken(port, (taken) => {
      if (taken) {
        clearInterval(timer);
        writeToScreen("[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>The server is running on port 4567. Opening the browser.</p>");
        launchBrowser();
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

// Opens an internal Electron window to display the app's web UI
let webviewWindow = null;
function openWebViewWindow(url) {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    webviewWindow.focus();
    return;
  }
  webviewWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    },
    title: 'Monadic Chat'
  });
  webviewWindow.loadURL(url);
  webviewWindow.on('closed', () => {
    webviewWindow = null;
  });
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
    // Enable standard edit shortcuts in settings window
    extendedContextMenu({
      window: settingsWindow,
      showUndo: true,
      showRedo: true,
      showCut: true,
      showCopy: true,
      showPaste: true,
      showSelectAll: true
    });
    // Handle keyboard shortcuts in settings window
    settingsWindow.webContents.on('before-input-event', (event, input) => {
      if (input.type === 'keyDown' && (input.meta || input.control)) {
        const key = input.key.toLowerCase();
        if (key === 'c') {
          settingsWindow.webContents.copy();
          event.preventDefault();
        } else if (key === 'x') {
          settingsWindow.webContents.cut();
          event.preventDefault();
        } else if (key === 'v') {
          settingsWindow.webContents.paste();
          event.preventDefault();
        } else if (key === 'a') {
          settingsWindow.webContents.selectAll();
          event.preventDefault();
        } else if (key === 'z' && !input.shift) {
          settingsWindow.webContents.undo();
          event.preventDefault();
        } else if ((key === 'z' && input.shift) || key === 'y') {
          settingsWindow.webContents.redo();
          event.preventDefault();
        }
      }
    });

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

// Functions to manage update state persistence using the existing env file
// Save update state to the env file
function saveUpdateState(state) {
  try {
    const envPath = getEnvPath();
    if (!envPath) {
      console.error('Failed to get env path');
      return false;
    }
    
    let envConfig = readEnvFile(envPath);
    
    // Store update state properties in env config
    envConfig.UPDATE_READY = state.updateReady ? 'true' : 'false';
    envConfig.UPDATE_VERSION = state.version || '';
    envConfig.UPDATE_TIMESTAMP = state.timestamp || Date.now();
    
    // Write back to env file
    writeEnvFile(envPath, envConfig);
    console.log('Update state saved to env file:', state);
    return true;
  } catch (error) {
    console.error('Failed to save update state:', error);
    return false;
  }
}

// Read update state from env file
function readUpdateState() {
  try {
    const envPath = getEnvPath();
    if (!envPath) {
      return null;
    }
    
    const envConfig = readEnvFile(envPath);
    
    // Only return state object if UPDATE_READY exists
    if (envConfig.UPDATE_READY) {
      return {
        updateReady: envConfig.UPDATE_READY === 'true',
        version: envConfig.UPDATE_VERSION || '',
        timestamp: parseInt(envConfig.UPDATE_TIMESTAMP) || 0
      };
    }
  } catch (error) {
    console.error('Failed to read update state:', error);
  }
  return null;
}

// Clear update state in env file
function clearUpdateState() {
  try {
    const envPath = getEnvPath();
    if (!envPath) {
      return false;
    }
    
    let envConfig = readEnvFile(envPath);
    
    // Remove update state properties
    delete envConfig.UPDATE_READY;
    delete envConfig.UPDATE_VERSION;
    delete envConfig.UPDATE_TIMESTAMP;
    
    // Write back to env file
    writeEnvFile(envPath, envConfig);
    console.log('Update state cleared from env file');
    return true;
  } catch (error) {
    console.error('Failed to clear update state:', error);
    return false;
  }
}

// Check for pending updates at startup
function checkPendingUpdates() {
  try {
    const state = readUpdateState();
    if (state && state.updateReady) {
      console.log('Found pending update to install:', state);
      
      // We now only clear the state after confirming successful installation
      // This helps prevent update loss if installation fails
      
      // Check if the update is too old (more than 7 days)
      const now = Date.now();
      const updateAge = now - (state.timestamp || now);
      const maxAge = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds
      
      if (updateAge > maxAge) {
        console.log('Update is too old (over 7 days), clearing state');
        clearUpdateState();
        return false;
      }
      
      // Return true to indicate we have a pending update
      return true;
    }
  } catch (error) {
    console.error('Error checking pending updates:', error);
  }
  return false;
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
        envConfig.AI_USER_MODEL = 'gpt-4.1';
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
        envConfig.OPENAI_DEFAULT_MODEL = 'gpt-4.1';
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

    // Set mode defaults if not specified or empty
    if (!envConfig.DISTRIBUTED_MODE || envConfig.DISTRIBUTED_MODE === '') {
      // Set to standalone mode as the default
      envConfig.DISTRIBUTED_MODE = 'off';
    }

    // Port settings are no longer user-configurable
    // Docker containers use hardcoded ports
    envConfig.RUBY_PORT = '4567';
    envConfig.PYTHON_PORT = '5070';
    envConfig.JUPYTER_PORT = '8889';

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
    
    // Ensure DISTRIBUTED_MODE is set
    if (!envConfig.DISTRIBUTED_MODE || envConfig.DISTRIBUTED_MODE === '') {
        // Set to standalone mode by default
        envConfig.DISTRIBUTED_MODE = 'off';
    }
    
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
        
        // Check if TTS_DICT_PATH has changed and copy the file to config directory
        if (data.TTS_DICT_PATH !== envConfig.TTS_DICT_PATH) {
            // Remove old TTS_DICT_DATA environment variable since we're not using it anymore
            delete data.TTS_DICT_DATA;
            
            if (data.TTS_DICT_PATH && data.TTS_DICT_PATH !== '') {
                try {
                    // Copy the dictionary file to the config directory
                    const configDir = path.dirname(envPath);
                    const ttsDictFile = path.join(configDir, 'TTS_DICT.csv');
                    fs.copyFileSync(data.TTS_DICT_PATH, ttsDictFile);
                    console.log(`TTS Dictionary copied to ${ttsDictFile}`);
                } catch (error) {
                    console.error('Error copying TTS dictionary file:', error);
                }
            } else {
                // If path is empty, try to remove the TTS_DICT.csv file
                try {
                    const configDir = path.dirname(envPath);
                    const ttsDictFile = path.join(configDir, 'TTS_DICT.csv');
                    if (fs.existsSync(ttsDictFile)) {
                        fs.unlinkSync(ttsDictFile);
                        console.log(`TTS Dictionary file removed from ${ttsDictFile}`);
                    }
                } catch (error) {
                    console.error('Error removing TTS dictionary file:', error);
                }
            }
        }
        
        // Handle mode settings - save cookies for the web UI
        if (mainWindow && !mainWindow.isDestroyed()) {
            // Save mode settings as cookies for UI access
            if (data.DISTRIBUTED_MODE) {
                try {
                    // Log mode change for troubleshooting
                    console.log(`Changing distributed mode from ${envConfig.DISTRIBUTED_MODE || 'off'} to ${data.DISTRIBUTED_MODE}`);
                    
                    // Set cookie for web UI
                    mainWindow.webContents.executeJavaScript(`
                        document.cookie = "distributed-mode=${data.DISTRIBUTED_MODE}; path=/; max-age=31536000";
                    `);
                    
                    // Show notification about Jupyter in Server mode
                    if (data.DISTRIBUTED_MODE === 'server') {
                        try {
                            // Add notification to console
                            writeToScreen(`[HTML]: <div class="alert alert-warning">
                                <i class="fas fa-exclamation-triangle"></i> Server Mode activated. 
                                Jupyter features have been disabled for security reasons.
                                <br>
                                <small>Network interfaces are now bound to 0.0.0.0 for external access.</small>
                            </div>`);
                        } catch (error) {
                            console.error('Error showing server mode notification:', error);
                        }
                    } else if (envConfig.DISTRIBUTED_MODE === 'server' && data.DISTRIBUTED_MODE === 'off') {
                        // Switching from server mode to standalone mode
                        try {
                            // Add notification to console
                            writeToScreen(`[HTML]: <div class="alert alert-info">
                                <i class="fas fa-info-circle"></i> Standalone Mode activated.
                                <br>
                                <small>Network interfaces are now bound to 127.0.0.1 for local access only.</small>
                            </div>`);
                        } catch (error) {
                            console.error('Error showing standalone mode notification:', error);
                        }
                    }
                    
                    // Send the mode update to the renderer process to update the UI immediately
                    // Include showNotification flag since this is an explicit mode change
                    mainWindow.webContents.send('update-distributed-mode', {
                        mode: data.DISTRIBUTED_MODE,
                        showNotification: true // Show notification for explicit settings changes
                    });
                } catch (error) {
                    console.error('Error updating distributed mode:', error);
                    dialog.showErrorBox('Mode Change Error', 
                        `Failed to change distributed mode to ${data.DISTRIBUTED_MODE}. Error: ${error.message}`);
                }
            }
            
            // Port settings have been removed since they don't affect Docker containers
            // Default values will be used (4567, 5070, 8889)
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

// Handle settings save from settings window
ipcMain.on('save-settings', (_event, data) => {
  saveSettings(data);
  // Apply browser mode immediately without restart
  if (data.BROWSER_MODE) {
    browserMode = data.BROWSER_MODE;
    if (mainWindow && mainWindow.webContents) {
      mainWindow.webContents.send('update-browser-mode', { mode: browserMode });
    }
  }
});

// This is the main entry point for app initialization
app.whenReady().then(() => {
  // Setup update-related error handlers first
  process.on('uncaughtException', (error) => {
    console.error('Uncaught exception during update process:', error);
    // Continue with normal initialization if update process crashes
    initializeApp();
  });
  
  // Check for pending updates before initializing the app
  const pendingUpdateState = readUpdateState();
  if (pendingUpdateState && pendingUpdateState.updateReady) {
    console.log('Found pending update to install:', pendingUpdateState);
    
    // Don't clear update state yet - only clear it after successful restart
    // This ensures we can retry if the update installation fails
    
    // Wait a moment to ensure app is ready before installing update
    setTimeout(() => {
      try {
        console.log('Installing pending update...');
        autoUpdater.quitAndInstall(false, true);
        
        // Set another timeout as a fallback - if we're still running after 10 seconds,
        // the update may have failed to install properly
        setTimeout(() => {
          console.log('Update installation may have failed - continuing with normal startup');
          // Continue with normal app initialization
          initializeApp();
        }, 10000);
      } catch (error) {
        console.error('Error installing update:', error);
        // Continue with normal app initialization
        initializeApp();
      }
    }, 2000);
  } else {
    // No pending updates, proceed with normal initialization
    initializeApp();
  }
});

// Removed duplicate app.on('window-all-closed') and app.on('activate')

ipcMain.on('close-settings', () => {
  if (settingsWindow) {
    settingsWindow.hide();
  }
});

// Handle restart request from renderer process - removed automatic restart functionality
// as it could interrupt active server instances
ipcMain.on('restart-app', () => {
  // This functionality is now deprecated - we ask the user to restart manually
  console.log('Restart request received but manual restart is preferred');
});

// Handle clear messages request from renderer process
ipcMain.on('clear-messages', () => {
  console.log('Clearing message area due to mode change');
});

// Handle zoom commands from internal browser
// Zoom In: increase page zoom for webview content only
ipcMain.on('zoom-in', () => {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    const wc = webviewWindow.webContents;
    const current = wc.getZoomFactor();
    // Handle promise or direct number
    Promise.resolve(current).then(f => {
      const newFactor = f + 0.1;
      wc.setZoomFactor(newFactor);
      // Notify webview to adjust overlay
      wc.send('zoom-changed', newFactor);
    });
  }
});
// Zoom Out: decrease page zoom for webview content only
ipcMain.on('zoom-out', () => {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    const wc = webviewWindow.webContents;
    const current = wc.getZoomFactor();
    Promise.resolve(current).then(f => {
      const newFactor = f - 0.1;
      wc.setZoomFactor(newFactor);
      wc.send('zoom-changed', newFactor);
    });
  }
});
// Find in page: listen for search requests from webview preload
ipcMain.on('find-in-page', (_event, searchText) => {
  if (webviewWindow && !webviewWindow.isDestroyed() && searchText) {
    // Clear previous highlights
    webviewWindow.webContents.stopFindInPage('clearSelection');
    // Initialize search state
    findState.term = searchText;
    findState.forward = true;
    try {
      // Start a new find request, store its ID
      findState.requestId = webviewWindow.webContents.findInPage(searchText);
    } catch (err) {
      console.error('Error performing findInPage:', err);
    }
  }
});
// Stop find in page: clear search highlights
ipcMain.on('stop-find-in-page', () => {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    try {
      webviewWindow.webContents.stopFindInPage('clearSelection');
    } catch (err) {
      console.error('Error performing stopFindInPage:', err);
    }
  }
});
// Find navigation: next/prev match controls (Enter/Shift+Enter or ◀/▶)
ipcMain.on('find-in-page-nav', (_event, {term, forward}) => {
  if (webviewWindow && !webviewWindow.isDestroyed() && term) {
    // Update search state
    findState.term = term;
    findState.forward = forward;
    try {
      // Request next/prev match
      findState.requestId = webviewWindow.webContents.findInPage(term, {forward: forward, findNext: true});
    } catch (err) {
      console.error('Error performing findInPage navigation:', err);
    }
  }
});
// Reset Web UI: reload the webview to start a fresh session
ipcMain.on('reset-web-ui', () => {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    // Clear storage data (session, local storage, etc)
    webviewWindow.webContents.session.clearStorageData()
      .then(() => {
        console.log('Web UI session data cleared');
        // Reload the page to get a fresh UI
        webviewWindow.reload();
      })
      .catch(err => {
        console.error('Error clearing web UI session:', err);
        // Try to reload anyway
        webviewWindow.reload();
      });
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
            // Store the path and copy the file to config directory
            const envPath = getEnvPath();
            if (envPath) {
                let envConfig = readEnvFile(envPath);
                envConfig.TTS_DICT_PATH = filePath;
                
                // Remove old TTS_DICT_DATA if it exists
                if (envConfig.TTS_DICT_DATA) {
                    delete envConfig.TTS_DICT_DATA;
                }
                
                // Copy the file to the config directory
                try {
                    const configDir = path.dirname(envPath);
                    const ttsDictFile = path.join(configDir, 'TTS_DICT.csv');
                    fs.copyFileSync(filePath, ttsDictFile);
                    console.log(`TTS Dictionary copied to ${ttsDictFile}`);
                } catch (error) {
                    console.error('Error copying TTS dictionary file:', error);
                }
                
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
// Bring the main window to the foreground when requested by the internal webview
ipcMain.on('focus-main-window', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  }
});
// Open external URLs in the default browser when requested by the renderer
ipcMain.on('open-external', (_event, url) => {
  shell.openExternal(url).catch(err => console.error('Failed to open external link:', err));
});

// Keep track of last check time to reduce frequency
let lastDockerStatusCheckTime = 0;
const DOCKER_STATUS_CHECK_INTERVAL = 2000; // Check every 2 seconds for better responsiveness

// Track mode to avoid unnecessary updates
let lastKnownMode = null;

async function updateDockerStatus() {
  const now = Date.now();
  // Only perform check if enough time has passed since last check
  if (now - lastDockerStatusCheckTime < DOCKER_STATUS_CHECK_INTERVAL) {
    return;
  }
  lastDockerStatusCheckTime = now;
  
  // Ensure distributed mode is synced before checking docker status,
  // but only if there's actually been a change to reduce message traffic
  if (mainWindow && !mainWindow.isDestroyed()) {
    // Explicitly load from environment file each time to make sure we have the latest setting
    const envPath = getEnvPath();
    if (envPath) {
      const envConfig = readEnvFile(envPath);
      const isServerMode = envConfig.DISTRIBUTED_MODE === 'server';
      const currentMode = isServerMode ? 'server' : 'off';
      
      // Only send update if the mode has actually changed since last check
      if (lastKnownMode !== currentMode) {
        lastKnownMode = currentMode;
        mainWindow.webContents.send('update-distributed-mode', {
          mode: currentMode,
          showNotification: false
        });
        console.log("Syncing mode from env file:", currentMode);
      }
    }
  }
  
  // Check Docker status
  if (dockerInstalled) {
    const status = await dockerManager.checkStatus();
    if (mainWindow && !mainWindow.isDestroyed()) {
      // Pass Docker status to UI (running or not)
      mainWindow.webContents.send('docker-desktop-status-update', status);
      // if status is false, meaning Docker Desktop is not running,
      // update the context menu and buttons only if the current status is not "Stopped"
      if (!status && currentStatus !== 'Stopped') {
        currentStatus = 'Stopped';
        updateContextMenu(false);
        updateStatusIndicator(currentStatus);
        writeToScreen('[SERVER STOPPED]');
        writeToScreen('[HTML]: <hr /><p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> Docker Desktop is not running. Please start Docker Desktop and press <b>start</b> button.</p><hr />');
      }
    }
  }
}
