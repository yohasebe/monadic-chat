// Get HTML elements
const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

// Function to add copy functionality to code blocks
function copyToClipboard() {
  document.removeEventListener('click', handleCopyClick);
  document.addEventListener('click', handleCopyClick);
}

// Handle click events for copying code
function handleCopyClick(event) {
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
}

// Add event listeners for command buttons
function addCommandListener(id, command) {
  document.getElementById(id).addEventListener('click', () => {
    window.electron.sendCommand(command);
  });
}

// Initialize event listeners when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  copyToClipboard();

  ['start', 'stop', 'restart', 'browser', 'folder', 'settings', 'exit'].forEach(id => {
    addCommandListener(id, id);
  });
});

// Handle command output
window.electron.receiveCommandOutput((output) => {
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
window.electron.updateControls(({ status, disableControls }) => {
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
    buttons.folder.disabled = status !== 'Running';
  }
});

// Enable browser button when server is ready
window.electron.onServerReady(() => {
  document.getElementById('browser').disabled = false;
});
