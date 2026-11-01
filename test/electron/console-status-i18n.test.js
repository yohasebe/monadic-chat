// The console page in a language other than English. main sends each status
// in English and translated; the page used the translated word in its
// checks, so no check matched and every button stayed disabled. Its own
// translations (the Web UI's) also lacked the desktop app's messages, so the
// stop line showed its key and a language change translated nothing.
const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..', '..', 'app');
const table = (lang) => JSON.parse(fs.readFileSync(path.join(APP, 'translations', `${lang}.json`), 'utf8'));

async function openConsole() {
  const html = fs.readFileSync(path.join(APP, 'index.html'), 'utf8')
    .replace(/<script[\s\S]*?<\/script>/g, '').replace(/<link[^>]*>/g, '');
  // A fresh frame per test: the page script declares top-level constants.
  const frame = document.createElement('iframe');
  document.body.appendChild(frame);
  const w = frame.contentWindow;
  w.document.open(); w.document.write(html); w.document.close();
  const on = {};
  w.electronAPI = new Proxy({ platform: 'darwin', getTranslations: async (lang) => table(lang) }, {
    get: (t, k) => (k in t ? t[k] : (String(k).startsWith('on') ? (cb) => { on[k] = cb; } : () => Promise.resolve()))
  });
  w.console.log = () => {};
  for (const f of ['webUITranslations.js', 'update-ui.js', 'mainScreen.js']) w.eval(fs.readFileSync(path.join(APP, f), 'utf8'));
  w.document.dispatchEvent(new w.Event('DOMContentLoaded'));
  await new Promise((r) => setTimeout(r, 20));
  const enabled = () => ['start', 'stop', 'restart'].filter((id) => !w.document.getElementById(id).disabled);
  const setStatus = (status, lang) => on.onUpdateStatusIndicator({}, status, table(lang).status[status.toLowerCase()]);
  return { w, on, enabled, setStatus, label: () => w.document.getElementById('status').textContent };
}

describe('console status in another language', () => {
  test('the buttons follow the status, and the label is translated', async () => {
    const c = await openConsole();
    await c.on.onUILanguageChanged({}, { language: 'ja' });
    const ja = table('ja').status;
    c.setStatus('Stopped', 'ja');
    expect([c.enabled(), c.label()]).toEqual([['start'], ja.stopped]);
    c.setStatus('Running', 'ja');
    expect([c.enabled(), c.label()]).toEqual([['stop', 'restart'], ja.starting]);
    c.setStatus('Ready', 'ja');
    expect([c.enabled(), c.label()]).toEqual([['stop', 'restart'], ja.finalizing]);
  });

  test('the stop line is translated, and again when the language changes', async () => {
    const c = await openConsole();
    await c.on.onUILanguageChanged({}, { language: 'ja' });
    c.setStatus('Stopped', 'ja');
    c.on.onCommandOutput({}, '[SERVER STOPPED]');
    const line = () => c.w.document.querySelector('.msg-stopped').textContent.trim();
    const time = JSON.parse(c.w.document.querySelector('.msg-stopped').dataset.i18nParams).time;
    expect(line()).toBe(table('ja').messages.systemStopped.replace('{{time}}', time));
    await c.on.onUILanguageChanged({}, { language: 'de' });
    expect(line()).toBe(table('de').messages.systemStopped.replace('{{time}}', time));
    expect(c.label()).toBe(table('de').status.stopped);
  });
});
