const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

function copyToClipboard() {
  document.removeEventListener('click', handleCopyClick);
  document.addEventListener('click', handleCopyClick);
}

function handleCopyClick(event) {
  if (event.target.classList.contains('fa-copy')) {
    const codeElement = event.target.nextElementSibling;
    const code = codeElement.textContent;
    navigator.clipboard.writeText(code).then(() => {
      event.target.classList.remove('fa-copy');
      event.target.classList.add('fa-check');
      event.target.style.color = '#DC4C64';
      setTimeout(() => {
        event.target.classList.remove('fa-check');
        event.target.classList.add('fa-copy');
        event.target.style.color = '';
      }, 1000);
    }).catch(err => {
      console.error('Failed to copy text: ', err);
    });
  }
}

document.addEventListener('DOMContentLoaded', () => {
  copyToClipboard();
});

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
  }
});

document.getElementById('start').addEventListener('click', () => {
  window.electron.sendCommand('start');
});

document.getElementById('stop').addEventListener('click', () => {
  window.electron.sendCommand('stop');
});

document.getElementById('restart').addEventListener('click', () => {
  window.electron.sendCommand('restart');
});

document.getElementById('browser').addEventListener('click', () => {
  window.electron.sendCommand('browser');
});

document.getElementById('folder').addEventListener('click', () => {
  window.electron.sendCommand('folder');
});

document.getElementById('settings').addEventListener('click', () => {
  window.electron.sendCommand('settings');
});

document.getElementById('exit').addEventListener('click', () => {
  window.electron.sendCommand('exit');
});

window.electron.updateControls(({ status, disableControls }) => {
  const startButton = document.getElementById('start');
  const stopButton = document.getElementById('stop');
  const restartButton = document.getElementById('restart');
  const browserButton = document.getElementById('browser');
  const folderButton = document.getElementById('folder');

  if (disableControls) {
    startButton.disabled = true;
    stopButton.disabled = true;
    restartButton.disabled = true;
    browserButton.disabled = true;
    folderButton.disabled = true;
  } else {
    startButton.disabled = status !== 'Stopped';
    stopButton.disabled = status !== 'Running';
    restartButton.disabled = status !== 'Running';
    browserButton.disabled = status !== 'Running' && status !== 'Ready';
    folderButton.disabled = status !== 'Running';
  }
});

// Listen for the serverReady event to enable the browser button immediately
window.electron.onServerReady(() => {
  document.getElementById('browser').disabled = false;
});


