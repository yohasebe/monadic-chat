// Get HTML elements
const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;
const htmlMaxMessages = 100; // Maximum number of messages to keep in HTML area
let htmlMessageCount = 0;

// Global variables
let currentStatus = 'Stopped';
let networkUrlDisplayed = false;
let serverStarted = false; // Flag to track if server has fully started
let updateInProgress = false; // True while an app update is downloading or staged for install

// Function to add copy functionality to code blocks
function addCopyToClipboardListener() {
  document.addEventListener('click', (event) => {
    // Check if the clicked element is a copy icon
    if (!event.target.classList.contains('fa-copy')) return;

    const codeElement = event.target.nextElementSibling;
    const text = codeElement.textContent;
    const icon = event.target;

    try {
      // Copy text to clipboard using document.execCommand
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';  // Fixed position to prevent scrolling on mobile
      textarea.style.opacity = 0;
      document.body.appendChild(textarea);
      textarea.select();
      
      const success = document.execCommand('copy');
      document.body.removeChild(textarea);
      
      if (!success) {
        throw new Error('execCommand copy failed');
      }
      
      // Show success indicator
      icon.classList.replace('fa-copy', 'fa-check');
      icon.style.color = '#DC4C64';
      setTimeout(() => {
        icon.classList.replace('fa-check', 'fa-copy');
        icon.style.color = '';
      }, 1000);
    } catch (err) {
      console.error("Failed to copy text: ", err);
      
      // Try fallback methods if execCommand fails
      try {
        if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
          window.electronAPI.writeClipboard(text);
          
          // Show success indicator
          icon.classList.replace('fa-copy', 'fa-check');
          icon.style.color = '#DC4C64';
          setTimeout(() => {
            icon.classList.replace('fa-check', 'fa-copy');
            icon.style.color = '';
          }, 1000);
        } else if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text)
            .then(() => {
              // Show success indicator
              icon.classList.replace('fa-copy', 'fa-check');
              icon.style.color = '#DC4C64';
              setTimeout(() => {
                icon.classList.replace('fa-check', 'fa-copy');
                icon.style.color = '';
              }, 1000);
            })
            .catch(() => {
              // Show error indicator
              icon.classList.replace('fa-copy', 'fa-xmark');
              icon.style.color = '#DC4C64';
              setTimeout(() => {
                icon.classList.replace('fa-xmark', 'fa-copy');
                icon.style.color = '';
              }, 1000);
            });
        } else {
          throw new Error('No clipboard API available');
        }
      } catch (fallbackErr) {
        console.error("All clipboard methods failed: ", fallbackErr);
        
        // Show error indicator
        icon.classList.replace('fa-copy', 'fa-xmark');
        icon.style.color = '#DC4C64';
        setTimeout(() => {
          icon.classList.replace('fa-xmark', 'fa-copy');
          icon.style.color = '';
        }, 1000);
      }
    }
  });
}

// Add event listeners for command buttons
function addCommandListeners() {
  ['start', 'stop', 'restart', 'browser', 'sharedfolder', 'settings', 'exit'].forEach(id => {
    document.getElementById(id).addEventListener('click', () => {
      window.electronAPI.sendCommand(id);
    });
  });
}

// Function to update UI based on Docker Desktop status
function updateDockerStatusUI(isRunning) {
  const dockerStatusElement = document.getElementById('dockerStatus');
  const dockerLabelElement = document.getElementById('dockerLabel');

  // Normal Docker mode
  if (dockerLabelElement) {
    dockerLabelElement.style.display = '';
    dockerLabelElement.innerHTML = ' <i class="fa-brands fa-docker"></i> Docker ';
  }
  
  if (dockerStatusElement) {
    dockerStatusElement.style.display = '';
    if (isRunning === 'not-installed') {
      dockerStatusElement.textContent = 'Not installed';
      dockerStatusElement.classList.remove('active');
      dockerStatusElement.classList.remove('blinking');
      dockerStatusElement.classList.add('inactive');
    } else if (isRunning) {
      dockerStatusElement.textContent = 'Running';
      dockerStatusElement.classList.remove('inactive');
      dockerStatusElement.classList.remove('blinking'); // Stop blinking when status is determined
      dockerStatusElement.classList.add('active');
    } else {
      dockerStatusElement.textContent = 'Stopped';
      dockerStatusElement.classList.remove('active');
      dockerStatusElement.classList.remove('blinking'); // Stop blinking when status is determined
      dockerStatusElement.classList.add('inactive');
    }
  }
}

// Function to update UI based on Monadic Chat status
function updateMonadicChatStatusUI(status) {
  const statusElement = document.getElementById('status');
  
  // Debug output to console to help diagnose status issues
  console.log(`Updating status UI: ${status}`);
  
  // (debug) originalStatus removed to avoid unused warnings
  
  
  // Special case: "Ready" shows Started only once the server is verified
  if (status === 'Ready') {
    if (serverStarted) {
      console.log("Server ready and serverStarted=true, showing Started");
      statusElement.textContent = "Started";
      statusElement.classList.remove('inactive');
      statusElement.classList.add('active');
      document.getElementById('browser').disabled = false;
    } else {
      console.log("Ready status but waiting for server verification, showing Finalizing");
      statusElement.textContent = "Finalizing";
      statusElement.classList.remove('active');
      statusElement.classList.add('inactive');
    }
  }
  
  // If status is changing to Stopped, reset the tracking flags
  if (status === 'Stopped') {
    networkUrlDisplayed = false;
    serverStarted = false;
  }
  
  // If status is changing to Starting, also reset the flags to ensure URL is shown
  if (status === 'Starting' || status === 'Restarting') {
    networkUrlDisplayed = false;
    serverStarted = false;
  }
  
  // Update current status globally so other functions can access it
  currentStatus = status;
  
  const buttons = {
    start: document.getElementById('start'),
    stop: document.getElementById('stop'),
    restart: document.getElementById('restart'),
    browser: document.getElementById('browser'),
    sharedfolder: document.getElementById('sharedfolder'),
    settings: document.getElementById('settings')
  };
  

  // Enable/disable buttons based on status
  if (status === 'Port in use'
    || status === 'Quitting'
    || status === 'Starting'
    || status === 'Restarting'
    || status === 'Stopping'
    || status === 'Building'
    || status === 'Uninstalling'
    || status === 'Importing' ||
    status === 'Exporting') {
    Object.values(buttons).forEach(button => button.disabled = true);
    statusElement.classList.remove('active');
    statusElement.classList.add('inactive');
    
    // Add blinking animation for Starting and Restarting
    if (status === 'Starting' || status === 'Restarting') {
      statusElement.classList.add('blinking');
    } else {
      statusElement.classList.remove('blinking');
    }
    
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
    statusElement.textContent = status;
  } else if (status === 'Running') {
    // For Running state, show "Starting" until server verification completes
    if (serverStarted) {
      // Only if serverStarted is true (should not happen normally with Running status)
      statusElement.textContent = "Started";
      statusElement.classList.remove('inactive');
      statusElement.classList.remove('blinking');
      statusElement.classList.add('active');
    } else {
      // Show "Starting" until server is verified
      statusElement.textContent = "Starting";
      statusElement.classList.remove('active');
      statusElement.classList.add('inactive');
      statusElement.classList.add('blinking'); // Keep blinking while starting
    }
    
    
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    buttons.browser.disabled = false;
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Ready') {
    // Status already handled in the special case above
    // No additional processing needed here - avoid redundancy
    
    
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    buttons.browser.disabled = false;
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Stopped') {
    statusElement.textContent = status;
    statusElement.classList.remove('active');
    statusElement.classList.remove('blinking');
    statusElement.classList.add('inactive');
    
    buttons.start.disabled = false;
    buttons.stop.disabled = true;
    buttons.restart.disabled = true;
    buttons.browser.disabled = true;
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
  } else {
    statusElement.textContent = status;
    statusElement.classList.remove('blinking');
    Object.values(buttons).forEach(button => button.disabled = true);
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
  }

  // While an app update is downloading or staged for install, keep Start and
  // Restart disabled so the user can't spin up the server underneath the
  // imminent relaunch.
  if (updateInProgress) {
    buttons.start.disabled = true;
    buttons.restart.disabled = true;
  }
}

// Track if we're in startup phase
let inStartupPhase = false;

// Function to write to the screen
function writeToScreen(text) {
  try {
    // Mark startup phase when we see the preparing message
    if (text.includes("Monadic Chat preparing")) {
      inStartupPhase = true;
      return; // Don't show the preparing message
    }
    
    // End startup phase when we see success
    if (text.includes("Connecting to server: success")) {
      inStartupPhase = false;
      return; // Don't show the success message
    }
    
    // Check the current interface language
    const interfaceLanguage = getCookie('interface-language') || 'en';
    
    // Don't show connection attempts during startup (English only)
    if (interfaceLanguage === 'en' && inStartupPhase && text.includes("Connecting to server: attempt")) {
      return;
    }
    
    // Don't show retry messages during startup (English only)
    if (interfaceLanguage === 'en' && inStartupPhase && text.includes("Retrying in")) {
      return;
    }
    
    // Don't show the emoji status messages
    if (text.includes("🚀 Starting Docker containers") || 
        text.includes("📦 Loading application modules") || 
        text.includes("⏳ Almost ready")) {
      return;
    }
    
    // Handle update check messages - replace the checking message
    // Check for update result messages by looking for specific icons instead of text
    const hasUpdateResult = text.includes('fa-circle-check') || // Success (latest version)
                           text.includes('fa-circle-exclamation') || // Warning (new version) or Error
                           text.includes('fa-circle-info'); // Info (failed to retrieve)
    
    if (hasUpdateResult) {
      // Find and remove the "Checking for updates..." message with spinner
      const paragraphs = htmlOutputElement.querySelectorAll('p');
      paragraphs.forEach(p => {
        if (p.querySelector('i.fa-sync.fa-spin')) {
          p.remove();
        }
      });
    }
    
    
  // Remove carriage return characters and trim
  text = text.replace(/\r\n|\r|\n/g, '\n').trim();

  // Removed plain-text fallback rendering to keep #messages strict.

    // Handle server start/stop events
    if (text === "[SERVER STOPPED]") {
      try { window.silentReconnectMode = true; } catch {}
      // Reset URL display flag on stop so restart shows it again
      networkUrlDisplayed = false;
      serverStarted = false;
      inStartupPhase = false;
      // Clear console output
      logOutputElement.textContent = '';
      logLines = 0;
      // Add stop message to messages area with timestamp
      const timestamp = new Date().toLocaleTimeString();
      const stopMessageKey = 'messages.systemStopped';
      
      // Get translated stop message
      let stopMessage = stopMessageKey;
      if (window.i18n && window.i18n.t) {
        stopMessage = window.i18n.t(stopMessageKey, { time: timestamp });
      } else {
        // Fallback to English if i18n not available
        stopMessage = `System stopped at ${timestamp}`;
      }
      
      htmlOutputElement.innerHTML += `<p style="color: #999;"><i class="fa-solid fa-circle-stop"></i> ${stopMessage}</p>\n`;
      htmlMessageCount++;
      
      // Limit HTML messages to prevent memory issues
      if (htmlMessageCount > htmlMaxMessages) {
        const messages = htmlOutputElement.children;
        const messagesToRemove = htmlMessageCount - htmlMaxMessages;
        for (let j = 0; j < messagesToRemove && messages.length > 0; j++) {
          messages[0].remove();
        }
        htmlMessageCount = htmlMaxMessages;
      }
      
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
      // Don't display [SERVER STOPPED] in console output
      return;
    }
    if (text === "[SERVER STARTED]") {
      // Clear console output when server starts fresh
      logOutputElement.textContent = '';
      logLines = 0;
      // Don't add any message - just clear and return
      return;
    }
    

    // HTML tagged content - can appear on multiple lines
    if (text.includes("[HTML]:")) {
      // Check if [SERVER STARTED] is included in the HTML content
      let serverStartedFound = false;
      if (text.includes("[SERVER STARTED]")) {
        serverStartedFound = true;
        // Remove [SERVER STARTED] from the HTML text for processing
        text = text.replace(/\[SERVER STARTED\]/g, '').trim();
      }
      
      // Extract all HTML content by replacing the tag and preserving the rest
      // This regex handles both inline and multiline [HTML]: tags
      const parts = text.split(/\[HTML\]:\s*/g);
      
      // The first part (before any [HTML]: tag) goes to the log output if it exists
      if (parts[0].trim() !== '') {
        logOutputElement.textContent += parts[0].trim() + '\n';
        logLines += parts[0].split('\n').length;
        if (logLines > logMaxLines) {
          const lines = logOutputElement.textContent.split('\n');
          logOutputElement.textContent = lines.slice(-logMaxLines).join('\n');
          logLines = logMaxLines;
        }
        logOutputElement.scrollTop = logOutputElement.scrollHeight;
      }
      
      // All subsequent parts are HTML content (parts[1] and onwards)
      for (let i = 1; i < parts.length; i++) {
        if (parts[i].trim() !== '') {
          htmlOutputElement.innerHTML += parts[i].trim() + '\n';
          htmlMessageCount++;
          
          // Limit HTML messages to prevent memory issues
          if (htmlMessageCount > htmlMaxMessages) {
            const messages = htmlOutputElement.children;
            // Remove oldest messages, keeping the last htmlMaxMessages
            const messagesToRemove = htmlMessageCount - htmlMaxMessages;
            for (let j = 0; j < messagesToRemove && messages.length > 0; j++) {
              messages[0].remove();
            }
            htmlMessageCount = htmlMaxMessages;
          }
          
          htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
        }
      }
      
      // If [SERVER STARTED] was found, just clear the console
      if (serverStartedFound) {
        logOutputElement.textContent = '';
        logLines = 0;
      }
      
      return; // Don't process this as regular text
    } else if (text.includes("[ERROR]:")) {
      // Error content
      const message = text.replace("[ERROR]:", "").trim();
      htmlOutputElement.innerHTML += '<p><i class="fa-solid fa-circle-exclamation" style="color:#DC4C64;"></i> ' + message + '</p>\n';
      htmlMessageCount++;
      
      // Limit HTML messages to prevent memory issues
      if (htmlMessageCount > htmlMaxMessages) {
        const messages = htmlOutputElement.children;
        const messagesToRemove = htmlMessageCount - htmlMaxMessages;
        for (let j = 0; j < messagesToRemove && messages.length > 0; j++) {
          messages[0].remove();
        }
        htmlMessageCount = htmlMaxMessages;
      }
      
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
      return; // Don't process this as regular text
    } else {
      // Regular output to the console log area
      logOutputElement.textContent += text + '\n';
      logLines++;
      if (logLines > logMaxLines) {
        const lines = logOutputElement.textContent.split('\n');
        logOutputElement.textContent = lines.slice(-logMaxLines).join('\n');
        logLines = logMaxLines;
      }
      logOutputElement.scrollTop = logOutputElement.scrollHeight;
    }
  } catch (error) {
    console.error('Error processing command output:', error);
    // Notify user if an error occurs with more specific message
    const errorMessage = error.message || 'Unknown error';
    htmlOutputElement.innerHTML += `<p><i class="fa-solid fa-circle-exclamation" style="color:#DC4C64;"></i> Error: ${errorMessage}</p>\n`;
    htmlMessageCount++;
    
    // Limit HTML messages to prevent memory issues
    if (htmlMessageCount > htmlMaxMessages) {
      const messages = htmlOutputElement.children;
      const messagesToRemove = htmlMessageCount - htmlMaxMessages;
      for (let j = 0; j < messagesToRemove && messages.length > 0; j++) {
        messages[0].remove();
      }
      htmlMessageCount = htmlMaxMessages;
    }
    
    htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
  }
}

// Initialize event listeners when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  addCopyToClipboardListener();
  addCommandListeners();

  const dockerStatusElement = document.getElementById('dockerStatus');
  dockerStatusElement.classList.add('inactive');
  dockerStatusElement.classList.add('blinking'); // Add blinking for initial checking
  dockerStatusElement.textContent = 'Checking';
  
  // Update version
  window.electronAPI.onUpdateVersion((_event, ver) => {
    const versionElement = document.getElementById('version');
    versionElement.textContent = ver;
  });
  
  // Note: Update messages are now sent via 'command-output' and displayed in the main message area

  // Update docker status
  window.electronAPI.onUpdateDockerStatusIndicator((_event, isRunning) => {
    updateDockerStatusUI(isRunning); 
  });

  // Update Monadic Chat status 
  window.electronAPI.onUpdateStatusIndicator((_event, status, translatedStatus) => {
    // Use translated status if available, otherwise use original
    updateMonadicChatStatusUI(translatedStatus || status);
  });

  // Disable Start/Restart while an app update download/staging is in flight,
  // and restore the normal controls if the user defers ("Later").
  window.electronAPI.onUpdateBusy((_event, busy) => {
    updateInProgress = !!busy;
    // Re-apply the current status so the guard takes effect immediately.
    updateMonadicChatStatusUI(currentStatus);
    // Keep the inline "Download & Install" button in sync: disabled while a
    // download is in flight, re-enabled if it errors (busy=false) so the user
    // can retry.
    if (window.MonadicUpdateUI && typeof window.MonadicUpdateUI.setUpdateButtonsBusy === 'function') {
      window.MonadicUpdateUI.setUpdateButtonsBusy(htmlOutputElement, !!busy);
    }
  });

  // Handle controls update from main process
  window.electronAPI.onUpdateControls((_event, data) => {
    const { status, disableControls } = data;
    if (disableControls) {
      // Disable all controls during operations
      const buttons = {
        start: document.getElementById('start'),
        stop: document.getElementById('stop'),
        restart: document.getElementById('restart'),
        browser: document.getElementById('browser')
      };
      Object.values(buttons).forEach(button => button.disabled = true);
    } else {
      // Update controls based on status
      updateMonadicChatStatusUI(status);
    }
  });

  // Enable browser button when server is ready
  window.electronAPI.onServerReady(() => {
    document.getElementById('browser').disabled = false;
  });
  
  // Listen for network URL display command
  window.electronAPI.onDisplayNetworkUrl((_event, data) => {
    if (!networkUrlDisplayed && data && data.localIP) {
      // Don't hide startup animation here - let it complete naturally

      const networkUrl = `http://${data.localIP}:4567`;
      const urlMessage = `<p><i class="fa-solid fa-laptop" style="color:#66ccff;"></i> System available at: <span class="network-url" onclick="navigator.clipboard.writeText('${networkUrl}').then(() => { this.innerHTML = '✓ Copied!'; setTimeout(() => { this.innerHTML = '${networkUrl}'; }, 1000); })" style="cursor:pointer; text-decoration:underline; color:#66ccff;">${networkUrl}</span></p>`;

      // Write directly to HTML output instead of going through writeToScreen
      htmlOutputElement.innerHTML += urlMessage + '\n';
      htmlMessageCount++;
      
      // Limit HTML messages to prevent memory issues
      if (htmlMessageCount > htmlMaxMessages) {
        const messages = htmlOutputElement.children;
        const messagesToRemove = htmlMessageCount - htmlMaxMessages;
        for (let j = 0; j < messagesToRemove && messages.length > 0; j++) {
          messages[0].remove();
        }
        htmlMessageCount = htmlMaxMessages;
      }
      
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
      networkUrlDisplayed = true;
      
      // Mark server as fully started when network URL is displayed
      serverStarted = true;
      
      // Update status indicator if status is Ready or Finalizing
      const statusElement = document.getElementById('status');
      if (statusElement && (statusElement.textContent === "Finalizing" || currentStatus === 'Ready' || statusElement.textContent === "Starting" || statusElement.textContent === "Started")) {
        console.log("Network URL displayed - updating status to Started");
        statusElement.textContent = "Started";
        statusElement.classList.remove('inactive');
        statusElement.classList.remove('blinking'); // Stop blinking when started
        statusElement.classList.add('active');
      }
    }
  });

  window.electronAPI.onDisableUI(() => {
    const buttons = {
      start: document.getElementById('start'),
      stop: document.getElementById('stop'),
      restart: document.getElementById('restart'),
    };
    Object.values(buttons).forEach(button => button.disabled = true);
  });

  // Handle command output
  window.electronAPI.onCommandOutput((_event, output) => {
    writeToScreen(output);
  });

  // Auto-update download progress: update a SINGLE in-place line + bar (see
  // app/update-ui.js) instead of appending one line per milestone.
  if (window.electronAPI.onUpdateDownloadProgress && window.MonadicUpdateUI) {
    window.electronAPI.onUpdateDownloadProgress((_event, progress) => {
      window.MonadicUpdateUI.renderDownloadProgress(htmlOutputElement, progress);
    });
  }
  // Wire the "Download & Install" button embedded in the update-available
  // message to the existing check-for-updates flow.
  if (window.MonadicUpdateUI) {
    window.MonadicUpdateUI.attachUpdateButtonHandler(htmlOutputElement, window.electronAPI);
  }

  // Handle clear messages command
  window.electronAPI.onClearMessages((_event) => {
    // Clear both message areas
    htmlOutputElement.innerHTML = '';
    logOutputElement.textContent = '';
    logLines = 0;
    htmlMessageCount = 0;
  });
  
  // Handle reset display command
  window.electronAPI.onResetDisplay((_event, lastUpdateResult) => {
    // Clear both message areas
    htmlOutputElement.innerHTML = '';
    logOutputElement.textContent = '';
    logLines = 0;
    htmlMessageCount = 0; // Reset HTML message count
    
    // Reset flags
    networkUrlDisplayed = false;
    serverStarted = false;
    inStartupPhase = false;
    
    // Show the initial message. On Linux, Docker is often the Docker
    // Engine service, not Docker Desktop.
    const isLinux = window.electronAPI && window.electronAPI.platform === 'linux';
    const tipKey = isLinux ? 'messages.standaloneModeTipLinux' : 'messages.standaloneModeTip';
    const dockerTip = (window.i18n && window.i18n.t)
      ? window.i18n.t(tipKey)
      : (isLinux ? 'Please make sure Docker is running while using Monadic Chat.'
                 : 'Please make sure Docker Desktop is running while using Monadic Chat.');
    const pressStart = (window.i18n && window.i18n.t)
      ? window.i18n.t('messages.pressStartButton')
      : 'Press <b>start</b> button to initialize the server.';
    const initialMessage = `
        <p><b>Monadic Chat</b></p>
        <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> ${dockerTip}</p>
        <p>${pressStart}</p>
        <hr />`;
    
    htmlOutputElement.innerHTML = initialMessage;
    htmlMessageCount = 4; // Count initial messages (title, tip, start instruction, hr)
    
    // Show the last update check result if available
    if (lastUpdateResult) {
      // Remove [HTML]: prefix if present
      let updateMessage = lastUpdateResult;
      if (updateMessage.startsWith('[HTML]: ')) {
        updateMessage = updateMessage.substring(8);
      }
      htmlOutputElement.innerHTML += updateMessage;
      htmlMessageCount++; // Count the update message
    }
  });

  // Initialize Web UI translations if available
  if (window.webUIi18n) {
    // Try to get saved language from cookie first
    const cookieMatch = document.cookie.match(/ui-language=([^;]+)/);
    if (cookieMatch && cookieMatch[1]) {
      console.log('[MainScreen] Setting language from cookie:', cookieMatch[1]);
      window.webUIi18n.setLanguage(cookieMatch[1]);
    } else {
      // Set default language to English
      console.log('[MainScreen] No cookie found, setting default language to English');
      window.webUIi18n.setLanguage('en');
    }
  }
  
  // Listen for UI language changes
  window.electronAPI.onUILanguageChanged((_event, data) => {
    if (data.language) {
      // Save to cookie for persistence
      document.cookie = `ui-language=${data.language}; path=/; max-age=31536000`;
      
      // Update i18n instance
      if (window.i18n) {
        window.i18n.setLanguage(data.language);
      }
      
      // Update Web UI language if available
      if (window.webUIi18n) {
        window.webUIi18n.setLanguage(data.language);
      }
      
      // Re-translate all messages in #messages
      const messagesElement = document.getElementById('messages');
      if (messagesElement) {
        const htmlOutput = messagesElement.querySelector('.html-output');
        if (htmlOutput) {
          // Find all translatable messages
          const translatableMessages = htmlOutput.querySelectorAll('[data-i18n-key]');
          translatableMessages.forEach(msg => {
            const key = msg.getAttribute('data-i18n-key');
            const _type = msg.getAttribute('data-i18n-type');
            const paramsStr = msg.getAttribute('data-i18n-params');
            let params = {};
            try {
              params = JSON.parse(paramsStr || '{}');
            } catch {
              // Ignore parse errors
            }
            
            // Get translation using the renderer's i18n instance
            if (window.i18n && window.i18n.t) {
              const translatedText = window.i18n.t(key, params);
              
              // Preserve nested interactive children that carry their own
              // data-i18n-key (e.g. the inline "Download & Install" button in
              // the update-available message) — rebuilding innerHTML from the
              // translated text alone would wipe them. The same forEach visits
              // those children later and re-translates their own labels.
              const preserved = Array.from(msg.children).filter(function (c) {
                return c.nodeType === 1 && c.hasAttribute('data-i18n-key');
              });

              // Find the icon if exists
              const icon = msg.querySelector('i.fa-solid');
              if (icon) {
                // Update text while preserving icon
                const iconHTML = icon.outerHTML;
                msg.innerHTML = iconHTML + ' ' + translatedText;
              } else {
                msg.textContent = translatedText;
              }

              preserved.forEach(function (el) { msg.appendChild(el); });
            }
          });
        }
      }
    }
  });

});


// Adjust the heights on window resize
window.addEventListener('resize', function() {
  const currentRatio = document.getElementById('messages').offsetHeight / (document.getElementById('messages').offsetHeight + document.getElementById('output').offsetHeight);
  setInitialHeights(currentRatio);
});

// Function to set initial heights based on a ratio
function setInitialHeights(ratio) {
  const wrapperHeight = document.querySelector('.message-wrapper').clientHeight - divider.offsetHeight;
  const messagesHeight = wrapperHeight * ratio;
  const outputHeight = wrapperHeight - messagesHeight;
  document.getElementById('messages').style.height = `${messagesHeight}px`;
  output.style.height = `${outputHeight}px`;
}

// Set the initial ratio
setInitialHeights(0.75); // Adjust this value to your preferred starting ratio

// Add the draggable functionality
divider.addEventListener('mousedown', function(e) {
  isDragging = true;
  e.preventDefault(); // Prevent text selection during drag
});

document.addEventListener('mousemove', function(e) {
  if (!isDragging) return;
  const totalHeight = messageWrapper.clientHeight - divider.offsetHeight;
  const messagesHeight = e.clientY - messageWrapper.offsetTop - divider.offsetHeight / 2;
  const outputHeight = totalHeight - messagesHeight;
  messages.style.height = `${messagesHeight}px`;
  output.style.height = `${outputHeight}px`;
});

document.addEventListener('mouseup', function(_e) {
  isDragging = false;
});
