// Disable various Electron warnings
process.env.ELECTRON_DISABLE_SECURITY_WARNINGS = '1';
process.env.ELECTRON_NO_ATTACH_CONSOLE = '1';
process.env.ELECTRON_ENABLE_LOGGING = '0';
process.env.ELECTRON_DEBUG_EXCEPTION_LOGGING = '0';

const { app, dialog, shell, Menu, Tray, BrowserWindow, ipcMain } = require('electron');
const { autoUpdater } = require('electron-updater');
const extendedContextMenu = require('electron-context-menu');
const i18n = require('./i18n');

// Splash window for updates
let updateSplashWindow = null;

// Update splash disabled

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

// Audio configuration for all platforms
// Note: AudioServiceOutOfProcess should remain ENABLED (default) on macOS
// to prevent interference with system-wide audio (e.g., HDMI audio output)
if (process.platform === 'darwin') {
  // macOS: Use default audio service (out-of-process) to avoid conflicts
  app.commandLine.appendSwitch('enable-features', 'WebRtcHWH264Encoding');
} else {
  // Other platforms: Enable hardware audio acceleration
  app.commandLine.appendSwitch('enable-features', 'AudioServiceHWAVAudioIO,WebRtcHWH264Encoding');
}

const { exec, execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const https = require('https');
const net = require('net');

// Add debug mode for troubleshooting statusIndicator issues
const debugStatusIndicator = false;

let tray = null;
let justLaunched = true;
let currentStatus = 'Stopped';
let isQuitting = false;
let contextMenu = null;
let initialLaunch = true;
let lastUpdateCheckResult = null; // Store the last update check result
let seleniumEnabled = true; // Selenium container start/stop state (default: enabled)
// Preference for browser launch: 'external' or 'internal'
// Default browser mode: 'internal' for internal Electron view
let browserMode = 'internal';

// Internal browser window reference and opener
let webviewWindow = null;
// State for in-page search to filter invisible matches
// State for in-page search (filtering invisible matches)
let findState = { term: '', forward: true, requestId: null };
function openWebViewWindow(url, forceReload = false) {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    if (forceReload) {
      // Force reload for restart
      webviewWindow.webContents.reload();
    }
    webviewWindow.focus();
    return;
  }

  // Create a custom session for the WebView with specific permissions
  const { session } = require('electron');
  const customSession = session.fromPartition('persist:monadicchat', {
    cache: true
  });

  // Configure the session to allow localhost resources
  customSession.webRequest.onBeforeSendHeaders(
    { urls: ['http://localhost:4567/*', 'http://127.0.0.1:4567/*'] },
    (details, callback) => {
      // Add necessary headers for localhost requests
      details.requestHeaders['Origin'] = 'http://localhost:4567';
      callback({ requestHeaders: details.requestHeaders });
    }
  );

  // Modify CSP headers to allow localhost resources
  customSession.webRequest.onHeadersReceived(
    { urls: ['http://localhost:4567/*', 'http://127.0.0.1:4567/*'] },
    (details, callback) => {
      const responseHeaders = { ...details.responseHeaders };

      // Remove restrictive CSP if present
      delete responseHeaders['content-security-policy'];
      delete responseHeaders['Content-Security-Policy'];

      // Add permissive CSP for localhost
      responseHeaders['Content-Security-Policy'] = [
        "default-src * 'unsafe-inline' 'unsafe-eval' data: blob: filesystem: about: ws: wss: 'self' http://localhost:* http://127.0.0.1:*;"
      ];

      callback({ responseHeaders });
    }
  );

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
      // Use custom session with proper security
      session: customSession,
      webSecurity: true, // Re-enable web security
      allowRunningInsecureContent: false,
      // Enable DevTools for debugging
      devTools: true
    }
  });
  // Set permission request handler to auto-approve media access requests
  webviewWindow.webContents.session.setPermissionRequestHandler((webContents, permission, callback, details) => {
    const allowedPermissions = ['media', 'microphone', 'audioCapture'];
    if (allowedPermissions.includes(permission)) {
      // Auto-approve media permission requests and log for debugging
      console.log(`Approving permission request for: ${permission}`, details);
      // Always approve media permissions
      callback(true);
    } else {
      // Deny other permission requests
      callback(false);
    }
  });
  
  // Clear cache to ensure fresh CSS load
  webviewWindow.webContents.session.clearCache();

  webviewWindow.loadURL(url);

  // Open DevTools only if debugging
  if (process.env.DEBUG_CSS) {
    webviewWindow.webContents.openDevTools();
  }
  
  // Set interface language when page loads
  webviewWindow.webContents.on('did-finish-load', () => {
    const envPath = getEnvPath();
    if (envPath) {
      const envConfig = readEnvFile(envPath);
      const uiLanguage = envConfig.UI_LANGUAGE || 'en';
      webviewWindow.webContents.executeJavaScript(`
        document.cookie = "ui-language=${uiLanguage}; path=/; max-age=31536000";
        if (window.webUIi18n) {
          window.webUIi18n.setLanguage('${uiLanguage}');
        }
      `);
    }
  });
  
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
    // Use a timeout to ensure the page is fully loaded before requesting permissions
    setTimeout(() => {
      webviewWindow.webContents.executeJavaScript('window.electronAPI.requestMediaPermissions()').then(result => {
        console.log('Media permissions request result:', result);
      }).catch(err => {
        console.error('Failed to request media permissions:', err);
      });
    }, 1000);
    
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

        function makeBtn(iconClass, bgColor, onClick, tooltip) {
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
          btn.title = tooltip; // Add tooltip
          btn.onclick = onClick;
          return btn;
        }

        container.appendChild(makeBtn('fa-solid fa-magnifying-glass-plus', 'rgba(255,255,255,0.9)', () => window.electronAPI.zoomIn(), 'Zoom In'));
        container.appendChild(makeBtn('fa-solid fa-magnifying-glass-minus', 'rgba(255,255,255,0.9)', () => window.electronAPI.zoomOut(), 'Zoom Out'));
        container.appendChild(makeBtn('fa-solid fa-magnifying-glass', 'rgba(255,255,255,0.9)', () => window.electronAPI.zoomReset(), 'Reset Zoom'));
        container.appendChild(makeBtn('fa-solid fa-arrows-rotate', 'rgba(66,139,202,0.9)', () => {
          if(confirm('Reset will clear all data and return to the initial state, including app selection. Continue?')) {
            window.electronAPI.resetWebUI();
          }
        }, 'New Session'));
        container.appendChild(makeBtn('fa-solid fa-terminal', 'rgba(255,193,7,0.9)', () => window.electronAPI.focusMainWindow(), 'Monadic Chat Console'));

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
  // Use the global application menu for edit/view roles
  
  // Register built-in shortcuts but don't intercept most keyboard events
  webviewWindow.webContents.on('before-input-event', (event, input) => {
    // Only intercept fullscreen toggle to make sure it works
    const isMac = process.platform === 'darwin';
    if (input.type === 'keyDown') {
      // Handle Mac minimize shortcut (Cmd+m)
      if (isMac && input.meta && !input.control && input.key.toLowerCase() === 'm') {
        webviewWindow.minimize();
        event.preventDefault();
        return;
      }
      // Handle Mac close window shortcut (Cmd+w)
      if (isMac && input.meta && !input.control && input.key.toLowerCase() === 'w') {
        webviewWindow.close();
        event.preventDefault();
        return;
      }
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
      // Handle zoom shortcuts only; let edit shortcuts fall through
      if (input.meta || input.control) {
        const key = input.key.toLowerCase();
        if (key === '+' || key === '=' || (input.shift && key === ';')) {
          // Handle zoom in: Cmd/Ctrl + '+' or '=' or ';' (with shift for Japanese keyboard)
          const wc = webviewWindow.webContents;
          const current = wc.getZoomFactor();
          Promise.resolve(current).then(f => {
            const newFactor = f + 0.1;
            wc.setZoomFactor(newFactor);
            wc.send('zoom-changed', newFactor);
          });
          event.preventDefault();
          return;
        } else if (key === '-') {
          // Handle zoom out: Cmd/Ctrl + '-'
          const wc = webviewWindow.webContents;
          const current = wc.getZoomFactor();
          Promise.resolve(current).then(f => {
            const newFactor = f - 0.1;
            wc.setZoomFactor(newFactor);
            wc.send('zoom-changed', newFactor);
          });
          event.preventDefault();
          return;
        } else if (key === '0') {
          // Handle zoom reset: Cmd/Ctrl + '0'
          const wc = webviewWindow.webContents;
          const defaultFactor = 1.0;
          wc.setZoomFactor(defaultFactor);
          wc.send('zoom-changed', defaultFactor);
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
  dotenv = require('dotenv');
} else {
  dotenv = require('dotenv');
}

const iconDir = app.isPackaged
  ? path.join(process.resourcesPath, 'app.asar', 'icons')
  : path.join(__dirname, '..', 'icons');

let monadicScriptPath = app.isPackaged
  ? path.join(process.resourcesPath, 'app', 'docker', 'monadic.sh')
  : path.join(__dirname, '..', 'docker', 'monadic.sh');

const isWindows = os.platform() === 'win32';
function monadicCmd(args) {
  return isWindows
    ? `wsl "${toUnixPath(monadicScriptPath)}" ${args}`
    : `"${monadicScriptPath}" ${args}`;
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
      const cmd = monadicCmd('check');
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
    // Track if this is a restart command
    const isRestart = command === 'restart';
    const isBuildPython = command === 'build_python_container';
    let buildTracker = isBuildPython ? { runDir: null, files: {}, status: 'in_progress' } : null;
    
    // Write the initial message to the screen
    writeToScreen(message);
    
    // Update the status indicator in the main window
    updateStatusIndicator(statusWhileCommand);
    // Docker command execution
    return this.checkStatus()
      .then((status) => {
        if (!status) {
          writeToScreen(formatMessage('info', 'messages.dockerNotRunning') + '<hr />');
          // Reset status to 'Stopped' and update UI
          currentStatus = 'Stopped';
          updateStatusIndicator(currentStatus);
          updateContextMenu(false);
          return;
        } else {
          // Construct the command to execute
          const cmd = monadicCmd(`${command}`);
          
          // Update the current status and context menu
          currentStatus = statusWhileCommand;
          
          // Reset the fetchWithRetryCalled flag
          fetchWithRetryCalled = false;
          
          // Update the context menu and application menu
          updateContextMenu();
          updateApplicationMenu();
          
          // Simple command execution that handles SERVER STARTED messages
          return new Promise((resolve, reject) => {
            // Load environment variables from config file for Electron build
            const envPath = getEnvPath();
            const envConfig = readEnvFile(envPath);

            // For build commands, always force rebuild by setting FORCE_REBUILD=true
            const isBuildCommand = ['build', 'build_ruby_container', 'build_python_container', 'build_user_containers'].includes(command);
            const buildEnv = isBuildCommand ? { FORCE_REBUILD: 'true' } : {};

            let subprocess = spawn(cmd, [], {
              shell: true,
              env: {
                ...process.env,  // Keep existing environment variables
                ...envConfig,    // Add variables from ~/monadic/config/env
                ...buildEnv      // Add FORCE_REBUILD for build commands
              }
            });
            
            subprocess.stdout.on('data', function (data) {
              const output = data.toString();
              
              // Translate Docker messages before displaying
              let translatedOutput = output;
              
              // Handle HTML messages with specific patterns
              if (output.includes('Custom Ruby setup script')) {
                translatedOutput = formatMessage('info', 'messages.customRubySetup');
              } else if (output.includes('Custom Python setup script')) {
                translatedOutput = formatMessage('info', 'messages.customPythonSetup');
              } else if (output.includes('Custom Ollama setup script')) {
                translatedOutput = formatMessage('info', 'messages.customOllamaSetup');
              } else if (output.includes('Checking container integrity')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.checkingContainerIntegrity')}</p>`;
              } else if (output.includes('Starting Docker...')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.startingDocker')}</p>`;
              } else if (output.includes('Building Ollama container...')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.buildingOllama')}</p>`;
              } else if (output.includes('Build of Ruby container has finished')) {
                translatedOutput = formatMessage('success', 'messages.buildRubyFinished');
              } else if (output.includes('Build of Python container has finished')) {
                translatedOutput = formatMessage('success', 'messages.buildPythonFinished');
              } else if (output.includes('Build of user containers has finished')) {
                translatedOutput = formatMessage('success', 'messages.buildUserFinished');
              } else if (output.includes('Build of Ollama container has finished')) {
                translatedOutput = formatMessage('success', 'messages.buildOllamaFinished');
              } else if (output.includes('Build of Monadic Chat has finished')) {
                translatedOutput = formatMessage('success', 'messages.buildMonadicFinished');
              } else if (output.includes('Container failed to build')) {
                translatedOutput = formatMessage('error', 'messages.containerFailedBuild');
              } else if (output.includes('No user containers to build')) {
                translatedOutput = formatMessage('info', 'messages.noUserContainers');
              } else if (output.includes('Ollama container failed to build')) {
                translatedOutput = formatMessage('error', 'messages.ollamaContainerFailed');
              } else if (output.includes('Build logs are available')) {
                translatedOutput = formatMessage('info', 'messages.buildLogsAvailable');
              } else if (output.includes('Please check the following log files')) {
                translatedOutput = formatMessage('warning', 'messages.checkLogFiles');
              } else if (output.includes('All containers are available')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.allContainersAvailable')}</p>`;
              } else if (output.includes('Starting Ollama container')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.startingOllamaContainer')}</p>`;
              } else if (output.includes('Updating Ruby container to detect Ollama')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.updatingRubyContainer')}</p>`;
              } else if (output.includes('Running Containers')) {
                translatedOutput = `[HTML]: <p><b>${i18n.t('messages.runningContainers')}</b></p>`;
              } else if (output.includes('You can directly access the containers')) {
                translatedOutput = `[HTML]: <p>${i18n.t('messages.containerAccessInfo')}</p>`;
              } else if (output.includes('System available at:')) {
                // Extract URL and translate
                const urlMatch = output.match(/http:\/\/[0-9.:]+/);
                if (urlMatch) {
                  translatedOutput = `[HTML]: <p>${i18n.t('messages.systemAvailableAt')}: ${urlMatch[0]}</p>`;
                }
              } else if (output.includes('Monadic Chat app v') && output.includes('Container image v')) {
                // Extract versions - include all characters until whitespace or end of line
                const appVersionMatch = output.match(/Monadic Chat app v([^\s]+)/);
                const containerVersionMatch = output.match(/Container image v([^\s]+)/);
                if (appVersionMatch && containerVersionMatch) {
                  translatedOutput = `[HTML]: <p>${i18n.t('messages.versionInfo', { appVersion: appVersionMatch[1], containerVersion: containerVersionMatch[1] })}</p>`;
                }
              }
              
              writeToScreen(translatedOutput);

              // Parse build markers to optionally summarize into main window messages
              if (isBuildPython) {
                const mDir = output.match(/\[BUILD_RUN_DIR\]\s+(.*)/);
                if (mDir) buildTracker.runDir = mDir[1].trim();
                const mBuild = output.match(/\[BUILD_LOG\]\s+(.*)/); if (mBuild) buildTracker.files.build_log = mBuild[1].trim();
                const mPost = output.match(/\[POST_SETUP_LOG\]\s+(.*)/); if (mPost) buildTracker.files.post_install_log = mPost[1].trim();
                const mHealth = output.match(/\[HEALTH_JSON\]\s+(.*)/); if (mHealth) buildTracker.files.health_json = mHealth[1].trim();
                const mMeta = output.match(/\[META_JSON\]\s+(.*)/); if (mMeta) buildTracker.files.meta_json = mMeta[1].trim();
                const mDone = output.match(/\[BUILD_COMPLETE\]\s+(success|failed)/);
                if (mDone) {
                  buildTracker.status = mDone[1] === 'success' ? 'success' : 'failed';
                  // Emit a concise summary to the main window (messages area)
                  if (mainWindow && !mainWindow.isDestroyed()) {
                    const icon = buildTracker.status === 'success' ? '<i class="fa-solid fa-circle-check" style="color:#22ad50;"></i>' : '<i class="fa-solid fa-circle-exclamation" style="color:#DC4C64;"></i>';
                    const runDir = buildTracker.runDir ? buildTracker.runDir : '';
                    mainWindow.webContents.send('command-output', `[HTML]: <p>${icon} Python build ${buildTracker.status}. ${runDir ? 'Logs: '+runDir : ''}</p>`);
                  }
                }
              }
              
              // Check for server started message
              if (data.toString().includes("[SERVER STARTED]")) {
                fetchWithRetry('http://localhost:4567')
                  .then((success) => {
                    if (success) {
                      // First set to Running state
                      currentStatus = "Running";
                      updateTrayImage("Running");
                      updateStatusIndicator("Running");
                      updateContextMenu(false);
                      
                      // Then set to Ready
                      currentStatus = "Ready";
                      updateStatusIndicator("Ready");
                      
                      // Signal successful server start with an event
                      const verificationMessage = dockerManager.isServerMode() 
                        ? 'Server verification complete'
                        : 'System initialization complete';
                      const msgKey = dockerManager.isServerMode() ? 'messages.serverModeActivated' : 'messages.systemInitComplete';
                      const msgParams = dockerManager.isServerMode() ? { url: dockerManager.serverUrl } : {};
                      writeToScreen(formatMessage('success', msgKey, msgParams));
                      
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
                            openWebViewWindow('http://localhost:4567', isRestart);
                          } else {
                            try {
                              // For restart, force reload by adding timestamp parameter
                              const browserUrl = isRestart ? 
                                `http://localhost:4567?reload=${Date.now()}` : 
                                'http://localhost:4567';
                              shell.openExternal(browserUrl).catch(err => {
                                console.error('Error opening browser:', err);
                                writeToScreen(formatMessage('warning', 'messages.openBrowserManually'));
                              });
                              writeToScreen(formatMessage('success', 'messages.openingBrowser'));
                            } catch (err) {
                              console.error('Error opening browser:', err);
                            }
                          }
                        }
                      }, 500);
                    } else {
                      // Server verification failed after max retries
                      writeToScreen(formatMessage('error', 'messages.serverVerifyFailed'));
                      // Reset status to allow retry
                      currentStatus = 'Stopped';
                      updateStatusIndicator(currentStatus);
                      updateContextMenu(false);
                    }
                  })
                  .catch(error => {
                    console.error('Fetch failed:', error);
                    // Reset status on error to prevent UI from getting stuck
                    currentStatus = 'Stopped';
                    updateStatusIndicator(currentStatus);
                    updateContextMenu(false);
                    writeToScreen(formatMessage('error', 'messages.errorConnecting'));
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
              
              // Don't update status here for 'start' command - wait for SERVER STARTED
              if (command !== 'start') {
                currentStatus = statusAfterCommand;
                updateTrayImage(statusAfterCommand);
                updateStatusIndicator(statusAfterCommand);
                updateContextMenu(false);
              }
              
              resolve();
            });
          });
        }
      })
      .catch(error => {
        console.error('Error checking Docker status:', error);
        writeToScreen(`[ERROR]: ${error.message}`);
        // Reset status on error to prevent UI from getting stuck
        currentStatus = 'Stopped';
        updateStatusIndicator(currentStatus);
        updateContextMenu(false);
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
  checkForUpdatesManual(true); // true = show dialog
}

// Version check - shows download link instead of auto-updating
function checkForUpdatesManual(showDialog = false) {
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
          if (showDialog) {
            // Show dialog only when menu is clicked
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              buttons: ['Download Now', 'View All Releases', 'Cancel'],
              message: 'Update Available',
              detail: `A new version (${latestVersion}) is available.\nCurrent version: ${currentVersion}\n\nClick "Download Now" to download the version for your system directly.`,
              icon: path.join(iconDir, 'app-icon.png')
            }).then((result) => {
              if (result.response === 0) {
                // Download directly based on platform and architecture
                const platform = process.platform;
                const arch = process.arch;
                let downloadUrl = '';
                
                if (platform === 'darwin') {
                  // macOS
                  if (arch === 'arm64') {
                    downloadUrl = `https://github.com/yohasebe/monadic-chat/releases/download/v${latestVersion}/Monadic.Chat-${latestVersion}-arm64.dmg`;
                  } else {
                    downloadUrl = `https://github.com/yohasebe/monadic-chat/releases/download/v${latestVersion}/Monadic.Chat-${latestVersion}-x64.dmg`;
                  }
                } else if (platform === 'win32') {
                  // Windows
                  downloadUrl = `https://github.com/yohasebe/monadic-chat/releases/download/v${latestVersion}/Monadic.Chat.Setup.${latestVersion}.exe`;
                } else if (platform === 'linux') {
                  // Linux
                  if (arch === 'arm64') {
                    downloadUrl = `https://github.com/yohasebe/monadic-chat/releases/download/v${latestVersion}/monadic-chat_${latestVersion}_arm64.deb`;
                  } else {
                    downloadUrl = `https://github.com/yohasebe/monadic-chat/releases/download/v${latestVersion}/monadic-chat_${latestVersion}_amd64.deb`;
                  }
                }
                
                if (downloadUrl) {
                  shell.openExternal(downloadUrl);
                } else {
                  // Fallback to releases page
                  shell.openExternal('https://github.com/yohasebe/monadic-chat/releases');
                }
              } else if (result.response === 1) {
                // View all releases
                shell.openExternal('https://github.com/yohasebe/monadic-chat/releases');
              }
            });
          } else {
            // Display update notification in main window only on startup
            if (mainWindow && !mainWindow.isDestroyed()) {
              lastUpdateCheckResult = formatMessage('warning', 'messages.newVersionAvailable', { version: latestVersion, current: currentVersion });
              mainWindow.webContents.send('command-output', lastUpdateCheckResult);
            }
          }
        } else {
          if (showDialog) {
            // Show dialog only when menu is clicked
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              buttons: ['OK'],
              message: 'Up to Date',
              detail: `You are already using the latest version (${currentVersion}).`,
              icon: path.join(iconDir, 'app-icon.png')
            });
          } else {
            // Display up-to-date message in main window only on startup
            if (mainWindow && !mainWindow.isDestroyed()) {
              lastUpdateCheckResult = formatMessage('success', 'messages.usingLatestVersion', { version: currentVersion });
              mainWindow.webContents.send('command-output', lastUpdateCheckResult);
            }
          }
        }
      } else {
        if (showDialog) {
          // Show error dialog only when menu is clicked
          dialog.showErrorBox('Error', 'Failed to retrieve the latest version number.');
        } else {
          // Display error in main window only on startup
          if (mainWindow && !mainWindow.isDestroyed()) {
            lastUpdateCheckResult = formatMessage('info', 'messages.failedToRetrieveVersion');
            mainWindow.webContents.send('command-output', lastUpdateCheckResult);
          }
        }
      }
    });
  }).on('error', (err) => {
    if (showDialog) {
      // Show error dialog only when menu is clicked
      dialog.showErrorBox('Error', `Failed to check for updates: ${err.message}`);
    } else {
      // Display error in main window only on startup
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('command-output', 
          formatMessage('info', 'messages.failedToCheckUpdates', { error: err.message }));
      }
    }
  });
}

// Uninstall Monadic Chat by removing Docker images and containers
function uninstall() {
  let options = {
    type: 'question',
    buttons: [i18n.t('dialogs.cancel'), i18n.t('dialogs.deleteAll')],
    defaultId: 1,
    message: i18n.t('dialogs.confirmUninstall'),
    detail: i18n.t('dialogs.uninstallMessage'),
    icon: path.join(iconDir, 'app-icon.png')
  };

  dialog.showMessageBox(null, options).then((result) => {
    setTimeout(() => {
      if (result.response === 1) {
        dockerManager.runCommand('remove', formatMessage(null, 'messages.removingContainers'), 'Uninstalling', 'Uninstalled');
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
  // Auto-update on quit has been disabled
  // Proceed with normal quit confirmation
  isQuittingDialogShown = true;

  let options = {
    type: 'question',
    buttons: [i18n.t('dialogs.cancel'), i18n.t('menu.quit')],
    defaultId: 1,
    title: i18n.t('dialogs.quitConfirmTitle'),
    message: i18n.t('dialogs.quitConfirmTitle'),
    detail: i18n.t('dialogs.quitConfirmMessage'),
    icon: path.join(iconDir, 'app-icon.png')
  };

  try {
    const result = await dialog.showMessageBox(mainWindow, options);
    if (result.response === 1) {
      try {
        const dockerStatus = await dockerManager.checkStatus();
        if (dockerStatus) {
          // Start the Docker stop process but don't wait for it to complete
          // This allows the app to quit more quickly while Docker handles cleanup in the background
          dockerManager.runCommand('stop', formatMessage(null, 'messages.stoppingAllProcesses'), 'Stopping', 'Quitting')
            .catch(error => {
              console.error('Error stopping Docker containers during quit:', error);
            });
          // Immediately proceed with cleanup - don't wait for Docker stop to complete
          cleanupAndQuit();
        } else {
          cleanupAndQuit();
        }
      } catch (error) {
        console.error('Error occurred during application quit:', error);
        cleanupAndQuit();
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
  
  // Reduce delay from 3000ms to 1000ms to allow message to be processed by browser
  // This makes the app feel more responsive when quitting
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
  }, 1000);
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

// Clean up OpenAI Files and Vector Stores created by Monadic Chat
async function cleanupOpenAIStorage() {
  try {
    const envPath = getEnvPath();
    const envConfig = envPath ? readEnvFile(envPath) : {};
    const apiKey = envConfig.OPENAI_API_KEY;
    if (!apiKey) {
      dialog.showErrorBox(i18n.t('dialogs.error'), 'OPENAI_API_KEY is not configured.');
      return;
    }

    const res = await dialog.showMessageBox(mainWindow, {
      type: 'warning',
      buttons: [i18n.t('dialogs.cancel'), i18n.t('dialogs.yes')],
      defaultId: 1,
      title: i18n.t('dialogs.cleanupCloudConfirmTitle') || 'Cleanup Cloud Storage',
      message: i18n.t('dialogs.cleanupCloudConfirmTitle') || 'Cleanup Cloud Storage',
      detail: i18n.t('dialogs.cleanupCloudConfirmMessage') || "This will delete all Vector Stores whose names start with 'monadic-' and any files attached to them.",
      icon: path.join(iconDir, 'app-icon.png')
    });
    if (res.response !== 1) return;

    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', formatMessage('info', 'messages.cleaningCloudStorage'));
    }

    const https = require('https');
    const base = 'api.openai.com';
    function request(method, path, body) {
      const opts = {
        hostname: base,
        port: 443,
        path: `/v1${path}`,
        method,
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        }
      };
      return new Promise((resolve, reject) => {
        const req = https.request(opts, (resp) => {
          let data = '';
          resp.on('data', (chunk) => data += chunk);
          resp.on('end', () => {
            try {
              const json = data ? JSON.parse(data) : {};
              resolve({ status: resp.statusCode, json });
            } catch (e) {
              resolve({ status: resp.statusCode, json: {} });
            }
          });
        });
        req.on('error', reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
      });
    }

    // List vector stores (first 100)
    const vsList = await request('GET', '/vector_stores?limit=100');
    const stores = (vsList.json && vsList.json.data) ? vsList.json.data : [];
    const monadicStores = stores.filter(s => (s.name || '').toLowerCase().startsWith('monadic-'));

    // Build a set of file IDs that are attached to non-monadic stores (protect them from deletion)
    const nonMonadicFileIds = new Set();
    for (const st of stores) {
      const isMonadic = (st.name || '').toLowerCase().startsWith('monadic-');
      if (isMonadic) continue;
      try {
        const fr = await request('GET', `/vector_stores/${st.id}/files?limit=200`);
        const arr = (fr.json && fr.json.data) ? fr.json.data : [];
        arr.forEach(f => nonMonadicFileIds.add(f.id));
      } catch {}
    }

    // Build an allowlist of file IDs that were uploaded by Monadic Chat (from local meta files, best-effort)
    const allowedFileIds = new Set();
    try {
      const dataDir = path.join(os.homedir(), 'monadic', 'data');
      const metaPath = path.join(dataDir, 'pdf_navigator_openai.json');
      if (fs.existsSync(metaPath)) {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        (meta.files || []).forEach(item => { if (item.file_id) allowedFileIds.add(item.file_id); });
      }
      const registryPath = path.join(dataDir, 'document_store_registry.json');
      if (fs.existsSync(registryPath)) {
        const reg = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
        Object.values(reg || {}).forEach(appEntry => {
          if (appEntry && appEntry.files && Array.isArray(appEntry.files)) {
            appEntry.files.forEach(fid => allowedFileIds.add(fid));
          }
        });
      }
    } catch {}
    let deletedStores = 0;
    let deletedFiles = 0;
    for (const store of monadicStores) {
      const vsId = store.id;
      // List files in store
      try {
        const filesRes = await request('GET', `/vector_stores/${vsId}/files?limit=200`);
        const files = (filesRes.json && filesRes.json.data) ? filesRes.json.data : [];
        for (const f of files) {
          const fid = f.id;
          // Always detach from the monadic store
          try { await request('DELETE', `/vector_stores/${vsId}/files/${fid}`); } catch {}
          // Delete the File object only if:
          // - it is NOT attached to any non-monadic store
          // - AND it's in our allowlist (uploaded by Monadic Chat) if allowlist exists
          const allowlistPresent = allowedFileIds.size > 0;
          const allowed = allowlistPresent ? allowedFileIds.has(fid) : true;
          if (!nonMonadicFileIds.has(fid) && allowed) {
            try { await request('DELETE', `/files/${fid}`); deletedFiles++; } catch {}
          }
        }
      } catch {}
      // Delete store itself
      try { await request('DELETE', `/vector_stores/${vsId}`); deletedStores++; } catch {}
    }

    // Remove local meta/registry files (best-effort)
    try {
      const dataDir = path.join(os.homedir(), 'monadic', 'data');
      const metaPath = path.join(dataDir, 'pdf_navigator_openai.json');
      if (fs.existsSync(metaPath)) fs.unlinkSync(metaPath);
      const registryPath = path.join(dataDir, 'document_store_registry.json');
      if (fs.existsSync(registryPath)) fs.unlinkSync(registryPath);
    } catch {}

    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('command-output', formatMessage('success', 'messages.cloudCleanupFinished', { files: deletedFiles, stores: deletedStores }));
    }
  } catch (err) {
    dialog.showErrorBox(i18n.t('dialogs.error'), `Cloud cleanup failed: ${err.message}`);
  }
}

let statusMenuItem = {
  label: `${i18n.t('menu.status')}: ${i18n.t('status.stopped')}`,
  enabled: false
};

// Add mode status to menu
function getDistributedModeLabel() {
  if (dockerManager.isServerMode()) {
    return i18n.t('menu.server');
  } else {
    return i18n.t('menu.standalone');
  }
}

let serverModeItem = {
  label: `${i18n.t('menu.mode')}: ${getDistributedModeLabel()}`,
  enabled: false
};

// Note: Old unused menuItems array removed.
// Actual menus are defined in:
// - Tray menu: freshMenuItems (line ~1809)
// - Application menu bar: Menu.buildFromTemplate (line ~1896)

let updateMessage = '';

// Auto-update related functions have been removed
// Updates are now handled manually through checkForUpdatesManual()

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
    
    // Display a notification to the user that the update has been applied
    setTimeout(() => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('command-output', `
          [HTML]: <div style="margin: 10px 0; padding: 10px; background-color: #e8f5e9; border-left: 4px solid #4caf50; border-radius: 4px;">
            <p style="margin: 0; font-weight: bold;">
              <i class="fa-solid fa-check-circle" style="color:#4caf50;"></i> 
              Update Successful: Version ${pendingUpdateState.version || app.getVersion()}
            </p>
            <p style="margin: 5px 0 0 0;">
              Monadic Chat has been successfully updated to the latest version.
            </p>
          </div>
        `);
      }
    }, 2000); // Delay to ensure the main window is ready
    
    clearUpdateState();
  }
  
  // Manual update checking will be done after main window is created
  
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
      // Enable common edit actions via mouse across all windows
      showCopy: true,
      showCut: true,
      showPaste: true,
      showSelectAll: true,
      // Useful extras
      showSaveImageAs: true,
      showCopyImage: true,
      showCopyImageAddress: true,
      showInspectElement: true,
      showSearchWithGoogle: false
    });

    createMainWindow();
    
    updateStatus();
    
    // Update menus with localized labels after initialization
    updateApplicationMenu();
    updateTrayMenu();

    ipcMain.on('command', async (_event, command) => {
      try {
        switch (command) {
          case 'start':
            // Check requirements first
            dockerManager.checkRequirements()
              .then(() => {
                dockerManager.runCommand('start', formatMessage(null, 'messages.monadicChatPreparing'), 'Starting', 'Running');
              })
              .catch((error) => {
                console.log(`Docker requirements check failed: ${error}`);
                // Show error dialog for Docker issues
                dialog.showErrorBox('Docker Error', error);
              });
            break;
          case 'stop':
            // Inform the embedded browser to suppress reconnect noise (show "Stopped")
            try {
              if (webviewWindow && !webviewWindow.isDestroyed()) {
                webviewWindow.webContents.executeJavaScript(`
                  try {
                    window.silentReconnectMode = true;
                    document.cookie = 'silent_reconnect=true; path=/';
                  } catch(_) {}
                `);
              }
            } catch (e) {
              console.warn('Failed to set silentReconnectMode in webview:', e);
            }
            dockerManager.runCommand('stop', '[HTML]: <p>Monadic Chat is stopping . . .</p>', 'Stopping', 'Stopped')
              .then(() => {
                // Send reset display command after stop is complete
                if (mainWindow && !mainWindow.isDestroyed()) {
                  // Send the last update check result along with reset command
                  mainWindow.webContents.send('reset-display-to-initial', lastUpdateCheckResult);
                }
              });
            break;
          case 'restart':
            dockerManager.runCommand('restart', formatMessage(null, 'messages.monadicChatRestarting'), 'Restarting', 'Running');
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
          // (removed) capture-chat-demo command
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
      // Only create main window if it doesn't exist
      if (!mainWindow || mainWindow.isDestroyed()) {
        createMainWindow();
      } else {
        // If mainWindow exists, just show it
        mainWindow.show();
        mainWindow.focus();
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
      const attemptMessage = `Connecting to server: attempt ${attempt} failed`;
      console.log(attemptMessage);
      // Only send to UI if English is selected (for other languages, these are intentionally hidden)
      const currentLang = i18n.currentLanguage || 'en';
      if (currentLang === 'en' && mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('command-output', attemptMessage);
      }
      
      if (attempt <= retries) {
        // Add more informative messages based on attempt number (English only)
        if (currentLang === 'en') {
          let statusMessage = '';
          if (attempt === 2) {
            statusMessage = `🚀 Starting Docker containers and Ruby server...`;
          } else if (attempt === 5) {
            statusMessage = `📦 Loading application modules...`;
          } else if (attempt === 10) {
            statusMessage = `⏳ Almost ready, please wait...`;
          }
          
          if (statusMessage) {
            console.log(statusMessage);
            if (mainWindow && !mainWindow.isDestroyed()) {
              mainWindow.webContents.send('command-output', statusMessage);
            }
          }
        }
        
        const retryMessage = `Retrying in ${delay}ms . . .`;
        console.log(retryMessage);
        // Only send to UI if English is selected (for other languages, these are intentionally hidden)
        if (currentLang === 'en' && mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('command-output', retryMessage);
        }
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
    // Create fresh menu items with current translations
    const freshMenuItems = [
      statusMenuItem,
      serverModeItem,
      { type: 'separator' },
      {
        label: i18n.t('menu.start'),
        click: () => {
          openMainWindow();
          dockerManager.checkRequirements()
            .then(() => {
              dockerManager.runCommand('start', formatMessage(null, 'messages.monadicChatPreparing'), 'Starting', 'Running');
            })
            .catch((error) => {
              console.log(`Docker requirements check failed: ${error}`);
              dialog.showErrorBox('Docker Error', error);
            });
        },
        enabled: disableControls ? false : currentStatus === 'Stopped'
      },
      {
        label: i18n.t('menu.stop'),
        click: () => {
          openMainWindow();
          dockerManager.runCommand('stop', formatMessage(null, 'messages.monadicChatStopping'), 'Stopping', 'Stopped');
        },
        enabled: disableControls ? false : ['Running', 'Ready', 'Starting', 'Building'].includes(currentStatus)
      },
      {
        label: i18n.t('menu.restart'),
        click: () => {
          openMainWindow();
          dockerManager.runCommand('restart', formatMessage(null, 'messages.monadicChatRestarting'), 'Restarting', 'Running');
        },
        enabled: disableControls ? false : (currentStatus === 'Running' || currentStatus === 'Ready')
      },
      { type: 'separator' },
      {
        label: i18n.t('menu.openConsole'),
        click: () => {
          openMainWindow();
        }
      },
      {
        label: i18n.t('menu.openBrowser'),
        click: () => {
          shell.openExternal('http://localhost:4567');
        },
        enabled: disableControls ? false : (currentStatus === 'Running' || currentStatus === 'Ready')
      },
      {
        label: i18n.t('menu.openSharedFolder'),
        click: () => {
          openSharedFolder();
        }
      },
      { type: 'separator' },
      {
        label: i18n.t('menu.settings'),
        click: () => {
          openSettingsWindow();
        }
      },
      {
        label: i18n.t('menu.quit'),
        click: () => {
          quitApp(mainWindow);
        }
      }
    ];
    
    // Update mode label
    serverModeItem.label = `Mode: ${getDistributedModeLabel()}`;

    contextMenu = Menu.buildFromTemplate(freshMenuItems);
    tray.setContextMenu(contextMenu);

    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('update-controls', { status: currentStatus, disableControls });
    }
    updateApplicationMenu();
  }
}

function updateApplicationMenu() {
  // Make sure to update menu structure to reflect the current status
  
  // Create standard menu
  const menu = Menu.buildFromTemplate([
    {
      label: i18n.t('menu.file'),
      submenu: [
        {
          label: i18n.t('menu.about'),
          click: () => {
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: i18n.t('menu.about'),
              message: i18n.t('menu.aboutMessage', { version: app.getVersion() }),
              detail: i18n.t('menu.aboutDetail'),
              buttons: [i18n.t('dialogs.ok')],
              icon: path.join(iconDir, 'app-icon.png')
            });
          }
        },
        {
          type: 'separator'
        },
        {
          label: i18n.t('menu.checkForUpdates'),
          click: () => {
            openMainWindow();
            checkForUpdates();
          }
        },
        {
          label: i18n.t('menu.uninstall'),
          click: () => {
            uninstall();
          }
        },
        {
          type: 'separator'
        },
        {
          label: i18n.t('menu.window'),
          accelerator: 'Cmd+N',
          click: () => {
            openMainWindow();
          }
        },
        {
          label: i18n.t('menu.minimize'),
          accelerator: 'Cmd+M',
          click: () => {
            if (mainWindow) {
              mainWindow.minimize();
            }
          }
        },
        {
          label: i18n.t('menu.close'),
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
          label: i18n.t('menu.quit'),
          accelerator: process.platform === 'darwin' ? 'Cmd+Q' : 'Ctrl+Q',
          click: () => {
            quitApp(mainWindow);
          }
        }
      ]
    },
    // Standard Edit menu with role-based items so shortcuts work
    // in any focused window (including DevTools)
    {
      label: i18n.t('menu.edit'),
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { type: 'separator' },
        { role: 'selectAll' }
      ]
    },
    {
      label: i18n.t('menu.actions'),
      submenu: [
        {
          label: i18n.t('menu.installOptions') || 'Install Options',
          click: () => {
            openInstallOptionsWindow();
          }
        },
        { type: 'separator' },
        {
          label: i18n.t('menu.start'),
          click: () => {
            openMainWindow();
            dockerManager.checkRequirements()
              .then(() => {
                dockerManager.runCommand('start', formatMessage(null, 'messages.monadicChatPreparing'), 'Starting', 'Running');
              })
              .catch((error) => {
                console.log(`Docker requirements check failed: ${error}`);
                dialog.showErrorBox('Docker Error', error);
              });
          },
          enabled: currentStatus === 'Stopped'
        },
        {
          label: i18n.t('menu.stop'),
          click: () => {
            openMainWindow();
            dockerManager.runCommand('stop', formatMessage(null, 'messages.monadicChatStopping'), 'Stopping', 'Stopped');
          },
          enabled: ['Running', 'Ready', 'Starting', 'Building'].includes(currentStatus)
        },
        {
          label: i18n.t('menu.restart'),
          click: () => {
            openMainWindow();
            dockerManager.runCommand('restart', formatMessage(null, 'messages.monadicChatRestarting'), 'Restarting', 'Running');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        {
          type: 'separator'
        },
        
        // Docker build commands
          {
            label: i18n.t('menu.buildAll'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('build',
                formatMessage(null, 'messages.buildingMonadicChat'),
                'Building',
                'Stopped',
                false);
            },
            enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
          },
          {
            label: i18n.t('menu.buildRubyContainer'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('build_ruby_container',
                formatMessage(null, 'messages.buildingRubyContainer'),
                'Building',
                'Stopped',
                false);
            },
            enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
          },
          {
            label: i18n.t('menu.buildPythonContainer'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('build_python_container',
                formatMessage(null, 'messages.buildingPythonContainer'),
                'Building',
                'Stopped',
                false);
            },
            enabled: currentStatus === 'Stopped' || currentStatus === 'Uninstalled'
          },
          {
            label: i18n.t('menu.buildUserContainers'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('build_user_containers',
                formatMessage(null, 'messages.buildingUserContainers'),
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
            label: i18n.t('menu.buildOllamaContainer'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('build_ollama_container',
                formatMessage(null, 'messages.buildingOllamaContainer'),
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
            label: i18n.t('menu.startJupyterLab'),
            click: () => {
              // First check if we're in server mode
              if (dockerManager.isServerMode()) {
                dialog.showMessageBox(mainWindow, {
                  type: 'warning',
                  title: i18n.t('menu.jupyterDisabled'),
                  message: i18n.t('menu.jupyterDisabledMessage'),
                  detail: i18n.t('menu.jupyterDisabledDetail'),
                  buttons: [i18n.t('dialogs.ok')]
                });
                return;
              }
              openMainWindow();
              dockerManager.runCommand('start-jupyter', formatMessage(null, 'messages.startingJupyterLab'), 'Starting', 'Running');
            },
            enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
          },
          {
            label: i18n.t('menu.stopJupyterLab'),
            click: () => {
              // First check if we're in server mode
              if (dockerManager.isServerMode()) {
                dialog.showMessageBox(mainWindow, {
                  type: 'warning',
                  title: i18n.t('menu.jupyterDisabled'),
                  message: i18n.t('menu.jupyterDisabledMessage'),
                  detail: i18n.t('menu.jupyterDisabledDetail'),
                  buttons: [i18n.t('dialogs.ok')]
                });
                return;
              }
              dockerManager.runCommand('stop-jupyter', formatMessage(null, 'messages.stoppingJupyterLab'), 'Starting', 'Running');
            },
            enabled: (currentStatus === 'Running' || currentStatus === 'Ready') && metRequirements
          },
          {
            type: 'separator'
          },
          {
            label: i18n.t('menu.startSeleniumContainer'),
            click: () => {
              openMainWindow();
              seleniumEnabled = true;
              dockerManager.runCommand('start-selenium', formatMessage(null, 'messages.startingSeleniumContainer'), 'Starting', 'Stopped');
            },
            enabled: currentStatus === 'Stopped',
            visible: !seleniumEnabled
          },
          {
            label: i18n.t('menu.stopSeleniumContainer'),
            click: () => {
              openMainWindow();
              seleniumEnabled = false;
              dockerManager.runCommand('stop-selenium', formatMessage(null, 'messages.stoppingSeleniumContainer'), 'Stopping', 'Stopped');
            },
            enabled: currentStatus === 'Stopped',
            visible: seleniumEnabled
          },
          {
            type: 'separator'
          },
          {
            label: i18n.t('menu.importDocumentDB'),
            click: () => {
              openMainWindow();
              dockerManager.runCommand('import-db', formatMessage(null, 'messages.importingDocumentDB'), 'Importing', 'Stopped')
            },
            enabled: currentStatus === 'Stopped' && metRequirements
          },
          {
            label: i18n.t('menu.exportDocumentDB'),
            click: () => {
              dockerManager.runCommand('export-db', formatMessage(null, 'messages.exportingDocumentDB'), 'Exporting', 'Stopped');
            },
            enabled: currentStatus === 'Stopped' && metRequirements
          }
      ]
    },
    {
      label: i18n.t('menu.open'),
      submenu: [
        {
          label: i18n.t('menu.openConsole'),
          click: () => {
            openMainWindow();
          }
        },
        {
          label: i18n.t('menu.openBrowser'),
          click: () => {
            shell.openExternal('http://localhost:4567');
          },
          enabled: currentStatus === 'Running' || currentStatus === 'Ready'
        },
        { type: 'separator' },
        {
          label: i18n.t('menu.openSharedFolder'),
          click: () => {
            openMainWindow();
            openSharedFolder();
          }
        },
        {
          label: i18n.t('menu.openConfigFolder'),
          click: () => {
            openMainWindow();
            openConfigFolder();
          }
        },
        {
          label: i18n.t('menu.openLogFolder'),
          click: () => {
            openMainWindow();
            openLogFolder();
          }
        },
        { type: 'separator' },
        {
          label: i18n.t('menu.settings'),
          click: () => {
            openSettingsWindow();
          }
        }
      ]
    },
    {
      label: i18n.t('menu.help'),
      submenu: [
        {
          label: i18n.t('menu.documentation'),
          click: () => {
            openBrowser('https://yohasebe.github.io/monadic-chat/', true);
          }
        }
      ]
    }
    ,
    {
      label: i18n.t('menu.window'),
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

// Update tray menu with localized labels
function updateTrayMenu() {
  if (!tray) return;
  
  // Update the global statusMenuItem with translated status
  statusMenuItem.label = translateStatus(currentStatus || 'Stopped');
  
  const serverModeItem = {
    label: dockerManager.serverMode ? `${i18n.t('menu.network')}: ${dockerManager.serverUrl}` : i18n.t('menu.standaloneMode'),
    enabled: false
  };
  
  const menuItems = [
    statusMenuItem,
    serverModeItem,
    { type: 'separator' },
    {
      label: i18n.t('menu.startDockerContainers'),
      click: () => {
        openMainWindow();
        dockerManager.checkRequirements()
          .then(() => {
            dockerManager.runCommand('start', formatMessage(null, 'messages.monadicChatPreparing'), 'Starting', 'Running');
          })
          .catch((error) => {
            console.log(`Docker requirements check failed: ${error}`);
            dialog.showErrorBox(i18n.t('dialogs.error'), error);
          });
      }
    },
    {
      label: i18n.t('menu.stopDockerContainers'),
      click: () => {
        openMainWindow();
        dockerManager.runCommand('stop', '[HTML]: <p>Stopping the Docker services . . .</p>', 'Stopping', 'Stopped');
      }
    },
    { type: 'separator' },
    {
      label: i18n.t('tray.show'),
      click: () => {
        openMainWindow();
      }
    },
    {
      label: i18n.t('menu.settings'),
      click: () => {
        openSettingsWindow();
      }
    },
    { type: 'separator' },
    {
      label: i18n.t('tray.quit'),
      click: () => {
        quitApp(mainWindow);
      }
    }
  ];
  
  const contextMenu = Menu.buildFromTemplate(menuItems);
  tray.setContextMenu(contextMenu);
}

// Helper function to translate status values
function translateStatus(status) {
  if (!status) return '';
  const statusKey = status.toLowerCase().replace(/\s+/g, '');
  return i18n.t(`status.${statusKey}`) || status;
}

// Helper function to format HTML messages with translations
function formatMessage(type, messageKey, params = {}) {
  const icons = {
    info: '<i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i>',
    success: '<i class="fa-solid fa-circle-check" style="color: #22ad50;"></i>',
    warning: '<i class="fa-solid fa-circle-exclamation" style="color: #FF7F07;"></i>',
    error: '<i class="fa-solid fa-circle-exclamation" style="color:#DC4C64;"></i>',
    sync: '<i class="fa-solid fa-sync fa-spin"></i>',
    server: '<i class="fa-solid fa-server" style="color:#DC4C64;"></i>',
    laptop: '<i class="fa-solid fa-laptop" style="color:#4CACDC;"></i>'
  };
  
  let message = i18n.t(messageKey, params);
  if (type && icons[type]) {
    // Include data attributes for re-translation
    return `[HTML]: <p data-i18n-key="${messageKey}" data-i18n-type="${type}" data-i18n-params='${JSON.stringify(params)}'>${icons[type]} ${message}</p>`;
  }
  return `[HTML]: <p data-i18n-key="${messageKey}" data-i18n-params='${JSON.stringify(params)}'>${message}</p>`;
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
  
  // Update current status
  currentStatus = status;
  
  // Update the global statusMenuItem with translated status
  const translatedStatus = translateStatus(status);
  statusMenuItem.label = translatedStatus;
  
  if (mainWindow) {
    // Send both the original status and translated version
    mainWindow.webContents.send('update-status-indicator', status, translatedStatus);
  }
  
  // Update tray menu to reflect the new status
  updateContextMenu(false);
}

// IPC handler for programmatic chat capture (no Selenium)
// (removed) capture-chat-screenshot IPC handler

// ---------------- Install Options Window ----------------
let installOptionsWindow = null;
let pendingCloseTimers = { settings: null, installOptions: null };
function openInstallOptionsWindow() {
  if (installOptionsWindow && !installOptionsWindow.isDestroyed()) {
    installOptionsWindow.focus();
    return;
  }
  installOptionsWindow = new BrowserWindow({
    devTools: true,
    width: 600,
    minWidth: 600,
    height: 400,
    minHeight: 400,
    resizable: true,
    title: 'Install Options',
    parent: mainWindow,
    modal: true,
    show: false,
    frame: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true
    }
  });
  installOptionsWindow.loadFile(path.join(__dirname, 'installOptions.html'));
  installOptionsWindow.once('ready-to-show', () => installOptionsWindow.show());
  // Trigger translation refresh after load
  installOptionsWindow.webContents.once('did-finish-load', () => {
    installOptionsWindow.webContents.executeJavaScript(`
      if (typeof installOptionsReloadTranslations === 'function') {
        installOptionsReloadTranslations();
      }
    `);
  });
  installOptionsWindow.on('closed', () => { installOptionsWindow = null; });
  // Route close attempts to renderer for unsaved-change prompt
  installOptionsWindow.on('close', (event) => {
    if (installOptionsWindow && !installOptionsWindow.isDestroyed()) {
      event.preventDefault();
      installOptionsWindow.webContents.send('attempt-close-install-options');
      // Fallback: force close if renderer does not respond within 3s
      if (pendingCloseTimers.installOptions) clearTimeout(pendingCloseTimers.installOptions);
      pendingCloseTimers.installOptions = setTimeout(() => {
        try {
          if (installOptionsWindow && !installOptionsWindow.isDestroyed()) {
            console.warn('[Main] Forcing close of Install Options (renderer unresponsive)');
            installOptionsWindow.destroy();
          }
        } catch (_) {}
      }, 3000);
    }
  });
}

// IPC handlers for Install Options
ipcMain.handle('get-install-options', async () => {
  const envPath = getEnvPath();
  const cfg = envPath ? readEnvFile(envPath) : {};
  // Normalize booleans (strings to true/false)
  const toBool = (v) => {
    if (typeof v === 'boolean') return v;
    if (!v) return false;
    const s = String(v).toLowerCase();
    return ['1','true','yes','on'].includes(s);
  };
  return {
    INSTALL_LATEX: toBool(cfg.INSTALL_LATEX),
    PYOPT_NLTK: toBool(cfg.PYOPT_NLTK),
    PYOPT_SPACY: toBool(cfg.PYOPT_SPACY),
    PYOPT_SCIKIT: toBool(cfg.PYOPT_SCIKIT),
    PYOPT_GENSIM: toBool(cfg.PYOPT_GENSIM),
    PYOPT_LIBROSA: toBool(cfg.PYOPT_LIBROSA),
    PYOPT_MEDIAPIPE: toBool(cfg.PYOPT_MEDIAPIPE),
    PYOPT_TRANSFORMERS: toBool(cfg.PYOPT_TRANSFORMERS),
    IMGOPT_IMAGEMAGICK: toBool(cfg.IMGOPT_IMAGEMAGICK)
  };
});

ipcMain.handle('get-install-options-translations', async () => {
    try {
      const panel = (i18n.getSection('menu') || {}).installOptionsPanel || {};
      const dialogs = i18n.getSection('dialogs') || {};
      return {
        panel,
        dialogs,
        language: i18n.getLanguage()
      };
    } catch (err) {
      console.error('Failed to build install options translations:', err);
      return { panel: {}, dialogs: {}, language: i18n.getLanguage() };
    }
  });

let installOptionsSaving = false;
ipcMain.handle('save-install-options', async (_e, options) => {
  if (installOptionsSaving) {
    return { success: true, skipped: true };
  }
  installOptionsSaving = true;
  const envPath = getEnvPath();
  if (!envPath) throw new Error('Config path not found');
  const cfg = readEnvFile(envPath) || {};
  const setBool = (k, v) => { cfg[k] = v ? 'true' : 'false'; };
  setBool('INSTALL_LATEX', !!options.INSTALL_LATEX);
  setBool('PYOPT_NLTK', !!options.PYOPT_NLTK);
  setBool('PYOPT_SPACY', !!options.PYOPT_SPACY);
  setBool('PYOPT_SCIKIT', !!options.PYOPT_SCIKIT);
  setBool('PYOPT_GENSIM', !!options.PYOPT_GENSIM);
  setBool('PYOPT_LIBROSA', !!options.PYOPT_LIBROSA);
  setBool('PYOPT_MEDIAPIPE', !!options.PYOPT_MEDIAPIPE);
  setBool('PYOPT_TRANSFORMERS', !!options.PYOPT_TRANSFORMERS);
  setBool('IMGOPT_IMAGEMAGICK', !!options.IMGOPT_IMAGEMAGICK);
  try {
    writeEnvFile(envPath, cfg);
  } catch (err) {
    console.error('Failed to save install options:', err);
    dialog.showErrorBox(i18n.t('dialogs.error'), `Failed to save options: ${err.message}`);
    installOptionsSaving = false;
    throw new Error(`Failed to save: ${err.message}`);
  }

  // No rebuild prompt here. Rebuild must be initiated explicitly by the user
  installOptionsSaving = false;
  return { success: true };
});

// ---------------- Translations loader for renderer ----------------
ipcMain.handle('get-translations', async (_e, lang) => {
  try {
    const fs = require('fs');
    const path = require('path');
    const baseDir = path.join(__dirname, 'translations');
    const safeLang = (lang || 'en').toLowerCase();
    const candidate = path.join(baseDir, `${safeLang}.json`);
    const fallback = path.join(baseDir, `en.json`);
    let data = null;
    if (fs.existsSync(candidate)) {
      data = JSON.parse(fs.readFileSync(candidate, 'utf8'));
    } else if (fs.existsSync(fallback)) {
      data = JSON.parse(fs.readFileSync(fallback, 'utf8'));
    } else {
      return {};
    }
    return data || {};
  } catch (err) {
    console.error('Failed to load translations:', err);
    return {};
  }
});

function createMainWindow() {
  if (mainWindow) return;
  
  // Ensure Docker Manager loads settings on startup
  dockerManager.loadServerModeSettings();

  mainWindow = new BrowserWindow({
    width: 820,
    minWidth: 820,
    height: 480,
    minHeight: 480,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      contentSecurityPolicy: "default-src 'self' http://localhost:4567 http://127.0.0.1:4567; style-src 'self' 'unsafe-inline' http://localhost:4567 http://127.0.0.1:4567 https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src 'self' data: http://localhost:4567 http://127.0.0.1:4567 https://fonts.gstatic.com https://cdnjs.cloudflare.com; script-src 'self' 'unsafe-inline' http://localhost:4567 http://127.0.0.1:4567; connect-src 'self' http://localhost:4567 ws://localhost:4567 http://127.0.0.1:4567 ws://127.0.0.1:4567 https://raw.githubusercontent.com; img-src 'self' data: http://localhost:4567 http://127.0.0.1:4567; worker-src 'self';",
      devTools: true, // Enable developer tools
      spellcheck: false // Disable spellcheck to avoid IMKit related errors
    },
    title: "Monadic Chat",
    useContentSize: true,
    // Show menu bar to enable standard shortcuts
    autoHideMenuBar: false,
    backgroundColor: '#f0f0f0'
  });

  // Check if port 4567 is already in use on initial launch
  if (justLaunched) {
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

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  
  // Ensure initial messages are sent after the window loads
  mainWindow.webContents.once('did-finish-load', () => {
    // Send initial status and version
    mainWindow.webContents.send('update-status-indicator', currentStatus);
    mainWindow.webContents.send('update-version', app.getVersion());
    
    // Send interface language to Web UI
    const envPath = getEnvPath();
    let interfaceLanguage = 'en';
    if (envPath) {
      const envConfig = readEnvFile(envPath);
      interfaceLanguage = envConfig.UI_LANGUAGE || 'en';
      mainWindow.webContents.send('ui-language-changed', { 
        language: interfaceLanguage 
      });
    }
    
    // Set cookies
    const isServerMode = dockerManager.isServerMode();
    mainWindow.webContents.executeJavaScript(`
      document.cookie = "distributed-mode=${isServerMode ? 'server' : 'off'}; path=/; max-age=31536000";
      document.cookie = "ui-language=${interfaceLanguage}; path=/; max-age=31536000";
    `);
    
    // Send mode update
    mainWindow.webContents.send('update-distributed-mode', {
      mode: isServerMode ? 'server' : 'off',
      showNotification: false
    });
    
    // Send opening message if just launched
    if (justLaunched) {
      let openingText;
      if (isServerMode) {
        openingText = `
          [HTML]: 
          <p><b>${i18n.t('messages.serverModeTitle')}</b></p>
          <p><i class="fa-solid fa-server" style="color:#DC4C64;"></i> ${i18n.t('messages.serverModeDesc')}</p>
          <p><i class="fa-solid fa-shield-halved" style="color:#FFC107;"></i> <strong>${i18n.t('dialogs.warning')}:</strong> ${i18n.t('menu.jupyterDisabledMessage')}</p>
          <p>${i18n.t('messages.pressStartButton')}</p>
          <hr />`;
      } else {
        openingText = `
          [HTML]: 
          <p><b>${i18n.t('messages.standaloneModeTitle')}</b></p>
          <p><i class="fa-solid fa-laptop" style="color:#4CACDC;"></i> ${i18n.t('messages.standaloneModeDesc')}</p>
          <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> ${i18n.t('messages.standaloneModeTip')}</p>
          <p>${i18n.t('messages.pressStartButton')}</p>
          <hr />`;
      }
      writeToScreen(openingText);
      justLaunched = false;
      
      // Show update checking message
      writeToScreen(`[HTML]: <p style="color: #666; font-size: 12px;"><i class="fa-solid fa-sync fa-spin"></i> ${i18n.t('messages.checkingForUpdates')}</p>`);
      
      // Check for updates after main window is loaded (no dialog)
      setTimeout(() => {
        checkForUpdatesManual(false); // false = no dialog, only main window notification
      }, 2000); // Delay to ensure window is fully loaded
    }
  });

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

  // Don't set menu here - updateApplicationMenu() handles it

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
          // Reduce UI noise: log to console output instead of user-facing messages
          writeToScreen('Waiting for the server to start . . .');
        }
        time += interval;
        if (time >= timeout) {
          clearInterval(timer);
          dialog.showErrorBox('Error', "Failed to start the server. Please try again.");
        }
      }

// (Removed duplicate openWebViewWindow; unified earlier definition is used)
    });
  }, interval);
}

function openSettingsWindow() {
  if (!settingsWindow) {
    settingsWindow = new BrowserWindow({
      devTools: true,
      width: 600,
      minWidth: 600,
      height: 400,
      minHeight: 400,
      parent: mainWindow,
      modal: true,
      show: false,
      frame: false,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        preload: path.join(__dirname, 'preload.js'),
        contentSecurityPolicy: "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; script-src 'self' 'unsafe-inline'; connect-src 'self' https://raw.githubusercontent.com; img-src 'self' data:; worker-src 'self';"
      }
    });

    settingsWindow.loadFile(path.join(__dirname, 'settings.html'));
    
    // Send the current interface language to the settings window after it loads
    settingsWindow.webContents.once('did-finish-load', () => {
      const envPath = getEnvPath();
      if (envPath) {
        const envConfig = readEnvFile(envPath);
        const uiLanguage = envConfig.UI_LANGUAGE || 'en';
        settingsWindow.webContents.executeJavaScript(`
          document.cookie = "ui-language=${uiLanguage}; path=/; max-age=31536000";
          if (typeof settingsI18n !== 'undefined') {
            settingsI18n.setLanguage('${uiLanguage}');
          }
        `);
      }
    });
    // Context menu with standard edit actions for mouse operations
    extendedContextMenu({
      window: settingsWindow,
      showUndo: true,
      showRedo: true,
      showCut: true,
      showCopy: true,
      showPaste: true,
      showSelectAll: true
    });

    settingsWindow.on('close', (event) => {
      // Ask renderer if it wants to save before closing
      event.preventDefault();
      settingsWindow.webContents.send('attempt-close-settings');
      // Fallback: force hide if renderer does not respond within 3s
      if (pendingCloseTimers.settings) clearTimeout(pendingCloseTimers.settings);
      pendingCloseTimers.settings = setTimeout(() => {
        try {
          if (settingsWindow && !settingsWindow.isDestroyed()) {
            console.warn('[Main] Forcing hide of Settings (renderer unresponsive)');
            settingsWindow.hide();
          }
        } catch (_) {}
      }, 3000);
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

// Toggle Selenium enabled state and persist to env file
function toggleSeleniumEnabled() {
  try {
    const envPath = getEnvPath();
    if (!envPath) {
      console.error('Failed to get env path');
      return false;
    }

    // Toggle the state
    seleniumEnabled = !seleniumEnabled;

    // Save to env file
    let envConfig = readEnvFile(envPath);
    envConfig.SELENIUM_ENABLED = seleniumEnabled ? 'true' : 'false';
    writeEnvFile(envPath, envConfig);

    // Show dialog to inform user
    const messageKey = seleniumEnabled
      ? 'dialogs.seleniumWillStartOnNextLaunch'
      : 'dialogs.seleniumWillNotStartOnNextLaunch';

    dialog.showMessageBox(mainWindow, {
      type: 'info',
      title: i18n.t('dialogs.info'),
      message: i18n.t(messageKey),
      buttons: [i18n.t('dialogs.ok')]
    });

    return true;
  } catch (error) {
    console.error('Failed to toggle Selenium enabled state:', error);
    return false;
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

    if (!envConfig.EMBEDDING_MODEL) {
        envConfig.EMBEDDING_MODEL = 'text-embedding-3-large';
    }

    // Load default models from system_defaults.json if not already specified
    const systemDefaultsPath = app.isPackaged
  ? path.join(process.resourcesPath, 'app', 'docker', 'services', 'ruby', 'config', 'system_defaults.json')
  : path.join(__dirname, '..', 'docker', 'services', 'ruby', 'config', 'system_defaults.json');
    try {
        const systemDefaults = JSON.parse(fs.readFileSync(systemDefaultsPath, 'utf8'));
        const providerDefaults = systemDefaults.provider_defaults || {};
        
        // Map of environment variable names to provider keys in system_defaults.json
        const providerMap = {
            'OPENAI_DEFAULT_MODEL': 'openai',
            'ANTHROPIC_DEFAULT_MODEL': 'anthropic',
            'COHERE_DEFAULT_MODEL': 'cohere',
            'GEMINI_DEFAULT_MODEL': 'gemini',
            'MISTRAL_DEFAULT_MODEL': 'mistral',
            'GROK_DEFAULT_MODEL': 'xai',
            'PERPLEXITY_DEFAULT_MODEL': 'perplexity',
            'DEEPSEEK_DEFAULT_MODEL': 'deepseek'
        };
        
        // Set defaults from system_defaults.json if not already specified in env
        for (const [envVar, providerKey] of Object.entries(providerMap)) {
            if (!envConfig[envVar] && providerDefaults[providerKey]) {
                envConfig[envVar] = providerDefaults[providerKey].model;
            }
        }
    } catch (error) {
        console.error('Warning: Could not load system_defaults.json:', error.message);
        // Fallback to minimal defaults if file is missing or invalid
        if (!envConfig.OPENAI_DEFAULT_MODEL) envConfig.OPENAI_DEFAULT_MODEL = 'gpt-4.1-mini';
        if (!envConfig.ANTHROPIC_DEFAULT_MODEL) envConfig.ANTHROPIC_DEFAULT_MODEL = 'claude-sonnet-4-20250514';
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

// Handle immediate UI language change
ipcMain.on('change-ui-language', (_event, language) => {
  // Apply UI language change immediately
  i18n.setLanguage(language);
  updateApplicationMenu();
  
  // Update tray menu if it exists
  if (tray) {
    updateTrayMenu();
  }
  
  // Notify all windows about the language change
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('ui-language-changed', { language });
  }
  
  // Also notify the internal browser if it exists
  if (internalBrowser && !internalBrowser.isDestroyed()) {
    internalBrowser.webContents.send('ui-language-changed', { language });
  }
  if (installOptionsWindow && !installOptionsWindow.isDestroyed()) {
    installOptionsWindow.webContents.send('ui-language-changed', { language });
  }
});

// Handle settings save from settings window
ipcMain.on('save-settings', (_event, data) => {
  // Check if interface language has changed
  const envPath = getEnvPath();
  const oldConfig = envPath ? readEnvFile(envPath) : {};
  const uiLanguage = data.UI_LANGUAGE;
  const oldUiLanguage = oldConfig.UI_LANGUAGE;
  const languageChanged = uiLanguage && uiLanguage !== oldUiLanguage;
  
  saveSettings(data);
  
  // Apply UI language change
  if (uiLanguage) {
    i18n.setLanguage(uiLanguage);
    updateApplicationMenu();
    // Also update tray menu if it exists
    if (tray) {
      updateTrayMenu();
    }
    
    // If language changed, clear messages and show initial message in new language
    if (languageChanged && mainWindow && !mainWindow.isDestroyed()) {
      // Clear the messages area
      mainWindow.webContents.send('clear-messages');
      
      // Re-send the initial message in the new language
      const isServerMode = dockerManager.isServerMode();
      let openingText;
      if (isServerMode) {
        openingText = `
          [HTML]: 
          <p><b>${i18n.t('messages.serverModeTitle')}</b></p>
          <p><i class="fa-solid fa-server" style="color:#DC4C64;"></i> ${i18n.t('messages.serverModeDesc')}</p>
          <p><i class="fa-solid fa-shield-halved" style="color:#FFC107;"></i> <strong>${i18n.t('dialogs.warning')}:</strong> ${i18n.t('menu.jupyterDisabledMessage')}</p>
          <p>${i18n.t('messages.pressStartButton')}</p>
          <hr />`;
      } else {
        openingText = `
          [HTML]: 
          <p><b>${i18n.t('messages.standaloneModeTitle')}</b></p>
          <p><i class="fa-solid fa-laptop" style="color:#4CACDC;"></i> ${i18n.t('messages.standaloneModeDesc')}</p>
          <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> ${i18n.t('messages.standaloneModeTip')}</p>
          <p>${i18n.t('messages.pressStartButton')}</p>
          <hr />`;
      }
      writeToScreen(openingText);
      
      // Re-send update check result if available
      if (lastUpdateCheckResult) {
        // Regenerate the message with the new language
        const currentVersion = app.getVersion();
        if (lastUpdateCheckResult.includes('fa-circle-check')) {
          // Using latest version
          lastUpdateCheckResult = formatMessage('success', 'messages.usingLatestVersion', { version: currentVersion });
        } else if (lastUpdateCheckResult.includes('fa-circle-exclamation')) {
          // New version available - extract version from the message
          const versionMatch = lastUpdateCheckResult.match(/v([0-9.\\-a-z]+)/i);
          if (versionMatch) {
            lastUpdateCheckResult = formatMessage('warning', 'messages.newVersionAvailable', { version: versionMatch[1], current: currentVersion });
          }
        } else if (lastUpdateCheckResult.includes('fa-circle-info')) {
          // Failed to retrieve version
          lastUpdateCheckResult = formatMessage('info', 'messages.failedToRetrieveVersion');
        }
        writeToScreen(lastUpdateCheckResult);
      }
      
      // Update the status indicator with translated text
      updateStatusIndicator(currentStatus);
    }
  }
  
  // Apply browser mode immediately without restart
  if (data.BROWSER_MODE) {
    browserMode = data.BROWSER_MODE;
    if (mainWindow && mainWindow.webContents) {
      mainWindow.webContents.send('update-browser-mode', { mode: browserMode });
    }
  }
  
  // If language changed, also update the web UI
  if (languageChanged && mainWindow && mainWindow.webContents) {
    // Update cookie for Web UI
    mainWindow.webContents.executeJavaScript(`
      document.cookie = "ui-language=${uiLanguage}; path=/; max-age=31536000";
    `);
    
    // Send language change event
    mainWindow.webContents.send('interface-language-changed', { 
      language: uiLanguage 
    });
  }
});

// This is the main entry point for app initialization
app.whenReady().then(() => {
  // Initialize i18n with saved UI language
  const envPath = getEnvPath();
  if (envPath) {
    // Migrate INTERFACE_LANGUAGE to UI_LANGUAGE if needed
    try {
      const content = fs.readFileSync(envPath, 'utf8');
      if (content.includes('INTERFACE_LANGUAGE=')) {
        const newContent = content.replace(/INTERFACE_LANGUAGE=/g, 'UI_LANGUAGE=');
        fs.writeFileSync(envPath, newContent, 'utf8');
      }
    } catch (error) {
      console.error('Error migrating env file:', error);
    }
    
    // Load and set UI language
    const envConfig = readEnvFile(envPath);
    if (envConfig.UI_LANGUAGE) {
      i18n.setLanguage(envConfig.UI_LANGUAGE);
    }
    // Initialize Selenium enabled state (default: true if not explicitly set to 'false')
    seleniumEnabled = envConfig.SELENIUM_ENABLED !== 'false';
  }
  
  // Setup update-related error handlers first
  process.on('uncaughtException', (error) => {
    console.error('Uncaught exception during update process:', error);
    // Close splash screen if it's open
    if (updateSplashWindow && !updateSplashWindow.isDestroyed()) {
      updateSplashWindow.close();
      updateSplashWindow = null;
    }
    // Don't automatically initialize the app here to avoid double initialization
  });
  
  // Check for pending updates before initializing the app
  const pendingUpdateState = readUpdateState();
  if (pendingUpdateState && pendingUpdateState.updateReady) {
    console.log('Found pending update to install:', pendingUpdateState);
    
    // Show splash screen while applying update
    showUpdateSplash();
    
    // Clear update state since we're now starting after an update
    clearUpdateState();
    
    // Proceed with normal initialization immediately
    // The splash screen is shown in parallel and doesn't block the update process
    initializeApp();
    
    // Close splash screen after a delay to ensure it's visible
    setTimeout(() => {
      if (updateSplashWindow && !updateSplashWindow.isDestroyed()) {
        updateSplashWindow.close();
        updateSplashWindow = null;
      }
      console.log('Update has been installed successfully');
    }, 2000); // Show splash for 2 seconds
  } else {
    // No pending updates, proceed with normal initialization
    initializeApp();
  }
});

// Removed duplicate app.on('window-all-closed') and app.on('activate')

ipcMain.on('close-settings', () => {
  // Treat as an attempt to close; renderer decides to confirm or stay
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.webContents.send('attempt-close-settings');
  }
});

ipcMain.on('confirm-close-settings', () => {
  if (pendingCloseTimers.settings) clearTimeout(pendingCloseTimers.settings);
  if (settingsWindow) settingsWindow.hide();
});

ipcMain.on('confirm-close-install-options', () => {
  if (pendingCloseTimers.installOptions) clearTimeout(pendingCloseTimers.installOptions);
  if (installOptionsWindow) installOptionsWindow.destroy();
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
// Zoom Reset: reset to default zoom factor
ipcMain.on('zoom-reset', () => {
  if (webviewWindow && !webviewWindow.isDestroyed()) {
    const wc = webviewWindow.webContents;
    const defaultFactor = 1.0;
    wc.setZoomFactor(defaultFactor);
    wc.send('zoom-changed', defaultFactor);
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
