// Get HTML elements
const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

// Global variables
let currentStatus = 'Stopped';
let networkUrlDisplayed = false;
let serverStarted = false; // サーバーが完全に起動したかどうかのフラグ

// Function to add copy functionality to code blocks
function addCopyToClipboardListener() {
  document.addEventListener('click', (event) => {
    // Check if the clicked element is a copy icon
    if (!event.target.classList.contains('fa-copy')) return;

    const codeElement = event.target.nextElementSibling;
    navigator.clipboard.writeText(codeElement.textContent)
      .then(() => {
        const icon = event.target;
        icon.classList.replace('fa-copy', 'fa-check');
        icon.style.color = '#DC4C64';
        setTimeout(() => {
          icon.classList.replace('fa-check', 'fa-copy');
          icon.style.color = '';
        }, 1000);
      })
      .catch(err => console.error('Failed to copy text: ', err));
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

// Function to write to the screen
function writeToScreen(text) {
  try {
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
    
    // Remove carriage return characters
    text = text.replace(/\r\n|\r|\n/g, '\n').trim();

    // HTML tagged content - can appear on multiple lines
    if (text.includes("[HTML]:")) {
      // Extract all HTML content by replacing the tag and preserving the rest
      // This regex handles both inline and multiline [HTML]: tags
      const parts = text.split(/\[HTML\]:/g);
      
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
    } else if (text.includes("[ERROR]:")) {
      // Error content
      const message = text.replace("[ERROR]:", "").trim();
      htmlOutputElement.innerHTML += '<p style="color: red;">' + message + '</p>\n';
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
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
    
    const modeStatusElement = document.getElementById('modeStatus');
    if (modeStatusElement) {
      modeStatusElement.textContent = mode === 'server' ? 'Server' : 'Standalone';
      
      // Set colors based on mode - using a unified color palette
      if (mode === 'server') {
        modeStatusElement.style.color = '#ff9966'; // Soft orange-red for server mode
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
      const networkUrl = `http://${data.localIP}:4567`;
      writeToScreen(`[HTML]: <p><i class="fa-solid fa-network-wired" style="color:#66ccff;"></i> System available at: <span class="network-url" onclick="navigator.clipboard.writeText('${networkUrl}').then(() => { this.innerHTML = '✓ Copied!'; setTimeout(() => { this.innerHTML = '${networkUrl}'; }, 1000); })" style="cursor:pointer; text-decoration:underline; color:#66ccff;">${networkUrl}</span></p>`);
      networkUrlDisplayed = true;
      
      // Mark server as fully started when network URL is displayed
      serverStarted = true;
      
      // Update status indicator if status is Ready or Finalizing (for both modes)
      const statusElement = document.getElementById('status');
      if (statusElement && (statusElement.textContent === "Finalizing" || currentStatus === 'Ready' || statusElement.textContent === "Starting")) {
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

