// Get HTML elements
const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

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
  ['start', 'stop', 'restart', 'browser', 'folder', 'settings', 'exit'].forEach(id => {
    document.getElementById(id).addEventListener('click', () => {
      window.electronAPI.sendCommand(id);
    });
  });
}

// Function to update UI based on Docker Desktop status
function updateDockerStatusUI(isRunning) {
  const dockerStatusElement = document.getElementById('dockerStatus');
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

// Function to update UI based on Monadic Chat status
function updateMonadicChatStatusUI(status) {
  const statusElement = document.getElementById('status');
  statusElement.textContent = status;

  const buttons = {
    start: document.getElementById('start'),
    stop: document.getElementById('stop'),
    restart: document.getElementById('restart'),
    browser: document.getElementById('browser'),
    folder: document.getElementById('folder'),
    settings: document.getElementById('settings')
  };

  // Enable/disable buttons based on status
  if (status === 'Port in use'
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
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Running') {
    statusElement.textContent = "Preparing . . .";
    statusElement.classList.add('inactive');
    buttons.start.disabled = true;
    buttons.stop.disabled = true;
    buttons.restart.disabled = true;
    buttons.browser.disabled = true;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Ready') {
    statusElement.textContent = "Ready";
    statusElement.classList.remove('inactive');
    statusElement.classList.add('active');
    buttons.start.disabled = true;
    buttons.stop.disabled = false;
    buttons.restart.disabled = false;
    buttons.browser.disabled = false;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else if (status === 'Stopped') {
    statusElement.classList.remove('active');
    statusElement.classList.add('inactive');
    buttons.start.disabled = false;
    buttons.stop.disabled = true;
    buttons.restart.disabled = true;
    buttons.browser.disabled = true;
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  } else {
    Object.values(buttons).forEach(button => button.disabled = true);
    buttons.folder.disabled = false;
    buttons.settings.disabled = false;
  }
}

// Function to write to the screen
function writeToScreen(text) {
  try {
    // Remove carriage return characters
    text = text.replace(/\r\n|\r|\n/g, '\n').trim();

    if (text.includes("[HTML]:")) {
      const message = text.replace("[HTML]:", "");
      htmlOutputElement.innerHTML += message + '\n';
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
    }  else if (text.includes("[ERROR]:")) {
      const message = text.replace("[ERROR]:", "");
      htmlOutputElement.innerHTML += '<p style="color: red;">' + message + '</p>\n';
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
    } else {
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
  dockerStatusElement.textContent = 'Checking...';

  // Update version
  window.electronAPI.onUpdateVersion((_event, ver) => {
    const versionElement = document.getElementById('version');
    versionElement.textContent = ver;
  });

  // Update docker status
  window.electronAPI.onUpdateDockerStatusIndicator((_event, isRunning) => {
    updateDockerStatusUI(isRunning); 
  });

  // Update Monadic Chat status 
  window.electronAPI.onUpdateStatusIndicator((_event, status) => {
    updateMonadicChatStatusUI(status);
  });

  // Enable browser button when server is ready
  window.electronAPI.onServerReady(() => {
    document.getElementById('browser').disabled = false;
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

// Update docker status
window.electronAPI.onUpdateDockerStatusIndicator((_event, isRunning) => {
  updateDockerStatusUI(isRunning); 
});
