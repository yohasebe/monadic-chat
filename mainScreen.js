const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

window.electron.receiveCommandOutput((output) => {
  // Remove carriage return characters
  output = output.replace(/\r/g, '').trim();

  if (output.includes("[HTML]:")) {
    const message = output.replace("[HTML]:", "");
    htmlOutputElement.innerHTML += message + '\n';
    htmlOutputElement.scrollTop = htmlOutputElement.scrollHeight;
  } else {
    logOutputElement.textContent += output + '\n';
    logLines++;
    if (logLines > logMaxLines) {
      logOutputElement.textContent = logOutputElement.textContent.split('\n').slice(1).join('\n');
    }
    logOutputElement.scrollTop = logOutputElement.scrollHeight;
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
    browserButton.disabled = status !== 'Running' && status !== 'BrowserReady';
    folderButton.disabled = status !== 'Running';
  }
});

// Listen for the serverReady event to enable the browser button immediately
window.electron.onServerReady(() => {
  document.getElementById('browser').disabled = false;
});

