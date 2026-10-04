// With no Docker installed the status used to stay "Checking" (blinking) for
// as long as the app was open: the status could only be running or stopped.
// mainScreen.js is a plain browser script whose top level sets up the whole
// console page, so only the status function is taken from the real file and
// evaluated into the page.
const fs = require('fs');
const path = require('path');

function loadMainScreen() {
  document.body.innerHTML = `
    <span id="modeLabel"></span><span id="modeStatus"></span>
    <span id="dockerLabel"></span><span id="dockerStatus" class="inactive blinking">Checking</span>`;
  const source = fs.readFileSync(path.join(__dirname, '../../app/mainScreen.js'), 'utf8');
  const fn = source.match(/function updateDockerStatusUI\(isRunning\) \{[\s\S]*?\n\}\n/);
  if (!fn) throw new Error('updateDockerStatusUI not found in mainScreen.js');
  window.eval(fn[0]);
  return document.getElementById('dockerStatus');
}

describe('Docker status in the console', () => {
  test('shows "Not installed" and stops blinking when Docker is missing', () => {
    const status = loadMainScreen();
    window.updateDockerStatusUI('not-installed');
    expect(status.textContent).toBe('Not installed');
    expect(status.classList.contains('blinking')).toBe(false);
    expect(status.classList.contains('inactive')).toBe(true);
  });

  test('still shows Running and Stopped for the boolean states', () => {
    const status = loadMainScreen();
    window.updateDockerStatusUI(true);
    expect(status.textContent).toBe('Running');
    window.updateDockerStatusUI(false);
    expect(status.textContent).toBe('Stopped');
  });
});
