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
  // The label goes through the translation helpers defined before it.
  const helpers = source.match(/const desktopStrings = [\s\S]*?\nfunction relabelStatuses\(\) \{[\s\S]*?\n\}\n/);
  if (!helpers) throw new Error('status label helpers not found in mainScreen.js');
  // The engine's name, drawn in the label.
  const label = source.match(/let engineName = [\s\S]*?\nfunction drawEngineLabel\(element\) \{[\s\S]*?\n\}\n/);
  if (!label) throw new Error('engine label helpers not found in mainScreen.js');
  window.eval(helpers[0].replace('const desktopStrings', 'var desktopStrings') +
    label[0].replace('let engineName', 'var engineName') + fn[0]);
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

  test('names the engine in the label once it is known: Docker with its icon, another engine by its own name', () => {
    loadMainScreen();
    const label = document.getElementById('dockerLabel');
    window.updateDockerStatusUI(true);
    expect(label.textContent.trim()).toBe('');
    window.engineName = 'Docker';
    window.updateDockerStatusUI(true);
    expect(label.textContent.trim()).toBe('Docker');
    expect(label.querySelector('i').className).toContain('fa-docker');
    window.engineName = 'Podman';
    window.updateDockerStatusUI(true);
    expect(label.textContent.trim()).toBe('Podman');
    expect(label.querySelector('i').className).not.toContain('fa-docker');
  });

  test('still shows Running and Stopped for the boolean states', () => {
    const status = loadMainScreen();
    window.updateDockerStatusUI(true);
    expect(status.textContent).toBe('Running');
    window.updateDockerStatusUI(false);
    expect(status.textContent).toBe('Stopped');
  });
});
