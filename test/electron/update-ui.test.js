/**
 * @jest-environment jsdom
 */

// Tests for app/update-ui.js — the renderer-side updater UI helpers:
//   - renderDownloadProgress: a single in-place line + <progress> bar
//   - attachUpdateButtonHandler: delegated click on .mc-update-now

const { renderDownloadProgress, attachUpdateButtonHandler, injectUpdateButton } = require('../../app/update-ui');

describe('renderDownloadProgress', () => {
  let host;
  beforeEach(() => {
    document.body.innerHTML = '<div id="host"></div>';
    host = document.getElementById('host');
  });

  it('no-ops without host or data', () => {
    expect(renderDownloadProgress(null, { percent: 50 })).toBeNull();
    expect(renderDownloadProgress(host, null)).toBeNull();
    expect(host.children.length).toBe(0);
  });

  it('creates one progress line with text and a <progress> bar', () => {
    renderDownloadProgress(host, { percent: 30, bytesPerSecond: 12.4 * 1024 * 1024 });
    const lines = host.querySelectorAll('#update-progress-line');
    expect(lines.length).toBe(1);
    expect(host.textContent).toContain('Downloading update: 30%');
    expect(host.textContent).toContain('12.4 MB/s');
    const bar = host.querySelector('progress.update-progress-bar');
    expect(bar).not.toBeNull();
    expect(bar.value).toBe(30);
    expect(bar.max).toBe(100);
  });

  it('updates the SAME line in place across ticks (no new lines)', () => {
    renderDownloadProgress(host, { percent: 30, bytesPerSecond: 1024 * 1024 });
    renderDownloadProgress(host, { percent: 60, bytesPerSecond: 1024 * 1024 });
    renderDownloadProgress(host, { percent: 100, bytesPerSecond: 1024 * 1024 });
    expect(host.querySelectorAll('#update-progress-line').length).toBe(1);
    expect(host.textContent).toContain('Downloading update: 100%');
    expect(host.querySelector('progress.update-progress-bar').value).toBe(100);
  });

  it('clamps and rounds percent, and omits speed when unknown', () => {
    renderDownloadProgress(host, { percent: 150 });
    expect(host.querySelector('progress').value).toBe(100);
    expect(host.textContent).toContain('Downloading update: 100%');
    expect(host.textContent).not.toContain('MB/s');

    renderDownloadProgress(host, { percent: -5 });
    expect(host.querySelector('progress').value).toBe(0);
  });
});

describe('attachUpdateButtonHandler', () => {
  let host;
  let api;
  beforeEach(() => {
    document.body.innerHTML = '<div id="host"></div>';
    host = document.getElementById('host');
    api = { startUpdateDownload: jest.fn(), checkForUpdates: jest.fn() };
  });

  it('starts the download directly (not a re-check) when a .mc-update-now button is clicked', () => {
    attachUpdateButtonHandler(host, api);
    host.innerHTML = '<p>Update available <button class="mc-update-now">Download</button></p>';
    host.querySelector('.mc-update-now').click();
    expect(api.startUpdateDownload).toHaveBeenCalledTimes(1);
    expect(api.checkForUpdates).not.toHaveBeenCalled();
  });

  it('falls back to checkForUpdates when startUpdateDownload is unavailable (older preload)', () => {
    const legacy = { checkForUpdates: jest.fn() };
    attachUpdateButtonHandler(host, legacy);
    host.innerHTML = '<button class="mc-update-now">x</button>';
    host.querySelector('.mc-update-now').click();
    expect(legacy.checkForUpdates).toHaveBeenCalledTimes(1);
  });

  it('ignores clicks elsewhere', () => {
    attachUpdateButtonHandler(host, api);
    host.innerHTML = '<p>other content</p>';
    host.querySelector('p').click();
    expect(api.startUpdateDownload).not.toHaveBeenCalled();
  });

  it('is idempotent — repeated attach does not stack handlers', () => {
    attachUpdateButtonHandler(host, api);
    attachUpdateButtonHandler(host, api);
    host.innerHTML = '<button class="mc-update-now">x</button>';
    host.querySelector('.mc-update-now').click();
    expect(api.startUpdateDownload).toHaveBeenCalledTimes(1);
  });
});

describe('injectUpdateButton', () => {
  it('inserts an .mc-update-now button INSIDE the message paragraph', () => {
    const base = '[HTML]: <p data-i18n-key="messages.newVersionAvailable">A new version is available.</p>';
    const out = injectUpdateButton(base, 'Download & Install');
    // Button sits before the closing </p> (inline beside the text), with the label.
    expect(out).toMatch(/<button class="mc-update-now"[^>]*>.*Download & Install<\/button><\/p>$/);
    expect(out).toContain('A new version is available.');
  });

  it('renders into the DOM as a single paragraph containing the button', () => {
    document.body.innerHTML = '';
    const host = document.createElement('div');
    document.body.appendChild(host);
    const base = '[HTML]: <p>msg</p>';
    // Strip the [HTML]: prefix the way the renderer does, then inject.
    host.innerHTML = injectUpdateButton(base.replace('[HTML]: ', ''), 'Update');
    expect(host.querySelectorAll('p').length).toBe(1);
    expect(host.querySelector('p .mc-update-now')).not.toBeNull();
  });

  it('appends safely when there is no closing </p>', () => {
    const out = injectUpdateButton('plain text', 'Go');
    expect(out).toContain('mc-update-now');
    expect(out.startsWith('plain text')).toBe(true);
  });
});
