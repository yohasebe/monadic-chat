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

// Initialize event listeners when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  addCopyToClipboardListener();
  addCommandListeners();

  // Update version
  window.electronAPI.onUpdateVersion((_event, version) => {
    document.getElementById('version').textContent = version;
  });

  // Update status indicator
  window.electronAPI.onUpdateStatusIndicator((_event, status) => {
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
    if (status === 'Port in use' || status === 'Starting' || status === 'Stopping' || status === 'Building' || status === 'Uninstalling' || status === 'Importing' || status === 'Exporting') {
      Object.values(buttons).forEach(button => button.disabled = true);
      buttons.folder.disabled = false;
      buttons.settings.disabled = false;
    } else if (status === 'Running') {
      statusElement.textContent = "Preparing . . .";
      buttons.start.disabled = true;
      buttons.stop.disabled = false;
      buttons.restart.disabled = false;
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
  });

  // ... (Other event listeners)
});

// Handle command output
window.electronAPI.onCommandOutput((_event, output) => {
  try {
    // Remove carriage return characters
    output = output.replace(/\r\n|\r|\n/g, '\n').trim();

    if (output.includes("[HTML]:")) {
      const message = output.replace("[HTML]:", "");
      htmlOutputElement.innerHTML += message + '\n';
      htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
    } else {
      logOutputElement.textContent += output + '\n';
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
});

// Update control buttons based on status
window.electronAPI.onUpdateControls((_event, { status, disableControls }) => {
  const buttons = {
    start: document.getElementById('start'),
    stop: document.getElementById('stop'),
    restart: document.getElementById('restart'),
    browser: document.getElementById('browser'),
    folder: document.getElementById('folder')
  };

  if (disableControls) {
    Object.values(buttons).forEach(button => button.disabled = true);
  } else {
    buttons.start.disabled = status !== 'Stopped';
    buttons.stop.disabled = status !== 'Running';
    buttons.restart.disabled = status !== 'Running';
    buttons.browser.disabled = status !== 'Running' && status !== 'Ready';
    buttons.folder.disabled = false; // Always enable folder button
  }
});

// Enable browser button when server is ready
window.electronAPI.onServerReady(() => {
  document.getElementById('browser').disabled = false;
});
