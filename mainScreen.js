// Get HTML elements
const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

// Global variables
let currentStatus = 'Stopped';
let networkUrlDisplayed = false;
let serverStarted = false; // Flag to track if server has fully started
let lastMode = null; // Track the last set mode

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

// Function to update system label based on mode
function updateSystemLabelForMode(mode) {
  const systemLabelElement = document.getElementById('systemLabel');
  if (systemLabelElement) {
    if (mode === 'server') {
      systemLabelElement.innerHTML = ' <i class="fa-solid fa-server"></i> Server ';
    } else {
      systemLabelElement.innerHTML = ' <i class="fa-solid fa-cube"></i> System ';
    }
  }
}

// Function to update UI based on Docker Desktop status and operational mode
function updateDockerStatusUI(isRunning) {
  const dockerStatusElement = document.getElementById('dockerStatus');
  const dockerLabelElement = document.getElementById('dockerLabel');
  const modeStatusElement = document.getElementById('modeStatus');
  const modeLabelElement = document.getElementById('modeLabel');
  
  // Update mode display if elements exist
  if (modeStatusElement && modeLabelElement) {
    // Initialize with "Checking" during startup
    if (modeStatusElement.textContent === "") {
      modeStatusElement.textContent = 'Checking';
      modeStatusElement.classList.remove('active');
      modeStatusElement.classList.add('inactive');
    }
    
    // NOTE: We no longer update the mode here - this is handled by the dedicated 
    // onUpdateDistributedMode event listener to avoid race conditions
    modeStatusElement.classList.remove('inactive');
    modeStatusElement.classList.add('active');
  }
  
  // Normal Docker mode
  if (dockerLabelElement) {
    dockerLabelElement.style.display = '';
    dockerLabelElement.innerHTML = ' <i class="fa-brands fa-docker"></i> Docker ';
  }
  
  if (dockerStatusElement) {
    dockerStatusElement.style.display = '';
    if (isRunning) {
      dockerStatusElement.textContent = 'Running';
      dockerStatusElement.classList.remove('inactive');
      dockerStatusElement.classList.add('active');
    } else {
      dockerStatusElement.textContent = 'Stopped';
      dockerStatusElement.classList.remove('active');
      dockerStatusElement.classList.add('inactive');
    }
  }
}

// Function to update UI based on Monadic Chat status
function updateMonadicChatStatusUI(status) {
  const statusElement = document.getElementById('status');
  
  // Debug output to console to help diagnose status issues
  console.log(`Updating status UI: ${status}, distributed mode: ${window.electronAPI.getDistributedMode()}`);
  
  // Save original status for debugging
  const originalStatus = status;
  
  
  // Special case: if we receive "Ready" status, handle differently based on mode
  if (status === 'Ready') {
    // Both Standalone and Server mode now wait for server to be fully ready
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
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
    statusElement.textContent = status;
  } else if (status === 'Running') {
    // For Running state, show "Starting" for both modes until server verification completes
    if (serverStarted) {
      // Only if serverStarted is true (should not happen normally with Running status)
      statusElement.textContent = "Started";
      statusElement.classList.remove('inactive');
      statusElement.classList.add('active');
    } else {
      // In both modes, show "Starting" until server is verified
      statusElement.textContent = "Starting";
      statusElement.classList.remove('active');
      statusElement.classList.add('inactive');
    }
    
    
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    // Browser enabled in Standalone mode, disabled in Server mode
    buttons.browser.disabled = window.electronAPI.getDistributedMode() === 'server';
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
    statusElement.classList.add('inactive');
    
    buttons.start.disabled = false;
    buttons.stop.disabled = true;
    buttons.restart.disabled = true;
    buttons.browser.disabled = true;
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
  } else {
    statusElement.textContent = status;
    Object.values(buttons).forEach(button => button.disabled = true);
    buttons.sharedfolder.disabled = false;
    buttons.settings.disabled = false;
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
    
    // Don't show connection attempts during startup
    if (inStartupPhase && text.includes("Connecting to server: attempt")) {
      return;
    }
    
    // Don't show retry messages during startup
    if (inStartupPhase && text.includes("Retrying in")) {
      return;
    }
    
    // Don't show the emoji status messages
    if (text.includes("🚀 Starting Docker containers") || 
        text.includes("📦 Loading application modules") || 
        text.includes("⏳ Almost ready")) {
      return;
    }
    
    // Handle connection-related status updates for Server mode
    if (window.electronAPI.getDistributedMode() === 'server') {
      // Server is still in connecting stage - failed attempts
      if (text.includes("Connecting to server: attempt") && text.includes("failed")) {
        const statusElement = document.getElementById('status');
        if (statusElement && statusElement.textContent !== "Finalizing") {
          console.log("Server connection attempt failed - ensuring status shows Finalizing");
          statusElement.textContent = "Finalizing";
          statusElement.classList.remove('active');
          statusElement.classList.add('inactive');
        }
      }
      
      // Connection succeeded but still need to display network URL
      else if (text.includes("Connecting to server: success")) {
        console.log("Server connection success detected - waiting for network URL");
        const statusElement = document.getElementById('status');
        if (statusElement && !serverStarted) {
          statusElement.textContent = "Finalizing";
          statusElement.classList.remove('active');
          statusElement.classList.add('inactive');
        }
      }
      
      // Server verification complete but still waiting for network URL
      else if (text.includes("Server verification complete")) {
        console.log("Server verification complete - waiting for network URL");
        const statusElement = document.getElementById('status');
        if (statusElement && !serverStarted) {
          statusElement.textContent = "Finalizing";
          statusElement.classList.remove('active');
          statusElement.classList.add('inactive');
        }
      }
    }
    
    // Handle update check messages - replace the checking message
    if (text.includes("You are using the latest version") || 
        text.includes("A new version") || 
        text.includes("Failed to retrieve the latest version")) {
      // Find and remove the "Checking for updates..." message
      const paragraphs = htmlOutputElement.querySelectorAll('p');
      paragraphs.forEach(p => {
        if (p.querySelector('i.fa-sync')) {
          p.remove();
        }
      });
    }
    
    
    // Remove carriage return characters and trim
    text = text.replace(/\r\n|\r|\n/g, '\n').trim();

    // Handle server start/stop events
    if (text === "[SERVER STOPPED]") {
      // Reset URL display flag on stop so restart shows it again
      networkUrlDisplayed = false;
      serverStarted = false;
      inStartupPhase = false;
      // Clear console output
      logOutputElement.textContent = '';
      logLines = 0;
      // Add stop message to messages area with timestamp
      const timestamp = new Date().toLocaleTimeString();
      const stopMessage = window.electronAPI.getDistributedMode() === 'server' 
        ? 'Server stopped' 
        : 'System stopped';
      htmlOutputElement.innerHTML += `<p style="color: #999;"><i class="fa-solid fa-circle-stop"></i> ${stopMessage} at ${timestamp}</p>\n`;
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
      htmlOutputElement.innerHTML += '<p style="color: red;">' + message + '</p>\n';
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
    // Notify user if an error occurs
    htmlOutputElement.innerHTML += '<p style="color: red;">An error occurred. Please check the console for details.</p>\n';
    htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
  }
}

// Initialize event listeners when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  addCopyToClipboardListener();
  addCommandListeners();

  const dockerStatusElement = document.getElementById('dockerStatus');
  dockerStatusElement.classList.add('inactive');
  dockerStatusElement.textContent = 'Checking';
  
  // Set initial system label based on current mode
  const initialMode = window.electronAPI.getDistributedMode();
  updateSystemLabelForMode(initialMode);

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
  window.electronAPI.onUpdateStatusIndicator((_event, status) => {
    updateMonadicChatStatusUI(status);
  });
  
  // Listen for distributed mode updates from the main process
  window.electronAPI.onUpdateDistributedMode((_event, data) => {
    // Support both old format (string) and new format (object)
    const mode = typeof data === 'string' ? data : data.mode;
    const localIP = typeof data === 'object' && data.localIP ? data.localIP : null;
    
    // Update system label icon based on mode
    updateSystemLabelForMode(mode === 'server' ? 'server' : 'off');
    
    const modeStatusElement = document.getElementById('modeStatus');
    if (modeStatusElement) {
      modeStatusElement.textContent = mode === 'server' ? 'Server' : 'Standalone';
      
      // Set colors based on mode - using a unified color palette
      if (mode === 'server') {
        modeStatusElement.style.color = '#ff6666'; // More distinct red for server mode
        modeStatusElement.classList.remove('active');
        modeStatusElement.classList.add('inactive');
      } else {
        modeStatusElement.style.color = '#66ccff'; // Soft blue for standalone mode
        modeStatusElement.classList.remove('inactive');
        modeStatusElement.classList.add('active');
        
        // Reset flags when switching to standalone mode
        networkUrlDisplayed = false;
        serverStarted = false;
      }
      
      // If the mode has changed, clear the messages area and display new mode info
      if (lastMode !== null && lastMode !== mode) {
        // Clear messages area
        htmlOutputElement.innerHTML = '';
        
        // Add new mode information message
        const modeInfo = mode === 'server' ? 
          `<p><i class="fa-solid fa-info-circle" style="color:#ff6666;"></i> <b>Server Mode</b>: System is now in Server Mode. Please start the service and access via browser from other devices on your network.</p>` : 
          `<p><i class="fa-solid fa-info-circle" style="color:#66ccff;"></i> <b>Standalone Mode</b>: System is now in Standalone Mode for local use.</p>`;
        
        htmlOutputElement.innerHTML = modeInfo;
      }
      
      // Update last mode
      lastMode = mode;
      
      // Force a cookie update to ensure consistency
      document.cookie = `distributed-mode=${mode}; path=/; max-age=31536000`;
      console.log(`Mode updated to: ${mode}`);
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
      const mode = window.electronAPI.getDistributedMode();
      const urlMessage = mode === 'server' 
        ? `<p><i class="fa-solid fa-network-wired" style="color:#66ccff;"></i> System available at: <span class="network-url" onclick="navigator.clipboard.writeText('${networkUrl}').then(() => { this.innerHTML = '✓ Copied!'; setTimeout(() => { this.innerHTML = '${networkUrl}'; }, 1000); })" style="cursor:pointer; text-decoration:underline; color:#66ccff;">${networkUrl}</span></p>`
        : `<p><i class="fa-solid fa-laptop" style="color:#66ccff;"></i> System available at: <span class="network-url" onclick="navigator.clipboard.writeText('${networkUrl}').then(() => { this.innerHTML = '✓ Copied!'; setTimeout(() => { this.innerHTML = '${networkUrl}'; }, 1000); })" style="cursor:pointer; text-decoration:underline; color:#66ccff;">${networkUrl}</span></p>`;
      
      // Write directly to HTML output instead of going through writeToScreen
      htmlOutputElement.innerHTML += urlMessage + '\n';
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
      networkUrlDisplayed = true;
      
      // Mark server as fully started when network URL is displayed
      serverStarted = true;
      
      // Update status indicator if status is Ready or Finalizing (for both modes)
      const statusElement = document.getElementById('status');
      if (statusElement && (statusElement.textContent === "Finalizing" || currentStatus === 'Ready' || statusElement.textContent === "Starting" || statusElement.textContent === "Started")) {
        console.log("Network URL displayed - updating status to Started");
        statusElement.textContent = "Started";
        statusElement.classList.remove('inactive');
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
  
  // Handle reset display command
  window.electronAPI.onResetDisplay((_event, lastUpdateResult) => {
    // Clear both message areas
    htmlOutputElement.innerHTML = '';
    logOutputElement.textContent = '';
    logLines = 0;
    
    // Reset flags
    networkUrlDisplayed = false;
    serverStarted = false;
    inStartupPhase = false;
    
    // Get the current mode and show initial message
    const mode = window.electronAPI.getDistributedMode();
    let initialMessage = '';
    
    if (mode === 'server') {
      initialMessage = `
        <p><b>Monadic Chat: <span style="color: #DC4C64; font-weight: bold;">Server Mode</span></b></p>
        <p><i class="fa-solid fa-server" style="color:#DC4C64;"></i> Running in server mode. Services will be accessible from external devices.</p>
        <p><i class="fa-solid fa-shield-halved" style="color:#FFC107;"></i> <strong>Security notice:</strong> Jupyter features are disabled in Server Mode for security.</p>
        <p>Press <b>start</b> button to initialize the server.</p>
        <hr />`;
    } else {
      initialMessage = `
        <p><b>Monadic Chat: <span style="color: #4CACDC; font-weight: bold;">Standalone Mode</span></b></p>
        <p><i class="fa-solid fa-laptop" style="color:#4CACDC;"></i> Running in standalone mode. Services are accessible locally only.</p>
        <p><i class="fa-solid fa-circle-info" style="color:#61b0ff;"></i> Please make sure Docker Desktop is running while using Monadic Chat.</p>
        <p>Press <b>start</b> button to initialize the server.</p>
        <hr />`;
    }
    
    htmlOutputElement.innerHTML = initialMessage;
    
    // Show the last update check result if available
    if (lastUpdateResult) {
      // Remove [HTML]: prefix if present
      let updateMessage = lastUpdateResult;
      if (updateMessage.startsWith('[HTML]: ')) {
        updateMessage = updateMessage.substring(8);
      }
      htmlOutputElement.innerHTML += updateMessage;
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

