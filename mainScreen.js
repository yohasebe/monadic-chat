const htmlOutputElement = document.getElementById('messages');
const logOutputElement = document.getElementById('output');
const logMaxLines = 256;
let logLines = 0;

window.electron.receiveCommandOutput((output) => {
  // Remove carriage return characters
  output = output.replace(/\r/g, '').trim();

  if (output.startsWith("[HTML]:")) {
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

