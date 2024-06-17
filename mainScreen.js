window.electron.receiveCommandOutput((output) => {
  // Remove carriage return characters
  output = output.replace(/\r/g, '').trim();

  let outputElement;
  if (output.startsWith("[HTML]:")) {
    const message = output.replace("[HTML]:", "");
    outputElement = document.getElementById('messages');
    outputElement.innerHTML += message + '\n';
  } else {
    outputElement = document.getElementById('output');
    outputElement.textContent += output + '\n';
  }
  outputElement.scrollTop = outputElement.scrollHeight;
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

