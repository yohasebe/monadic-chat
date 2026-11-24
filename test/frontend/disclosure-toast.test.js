/**
 * @jest-environment jsdom
 */

/**
 * The side column's panels open and close by their headings (disclosure.js),
 * by a press or by Enter or Space, without Bootstrap; the audio notice
 * (ws-auto-speech.js) shows and closes without it too.
 */
const fs = require('fs');
const path = require('path');

const PUBLIC = path.join(__dirname, '../../docker/services/ruby/public');
const VIEW = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/views/index.erb'), 'utf8');

describe('disclosures', () => {
  beforeAll(() => {
    (0, eval)(fs.readFileSync(path.join(PUBLIC, 'js/monadic/disclosure.js'), 'utf8'));
  });

  beforeEach(() => {
    document.body.innerHTML = `
      <h5 id="h" class="sidebar-collapse-toggle" role="button" tabindex="0" data-disclosure aria-controls="p" aria-expanded="true"><span id="label">Panel</span></h5>
      <div id="p" class="collapse show">Body</div>
      <h5 id="own" role="button" aria-controls="q" aria-expanded="false">Own</h5>
      <div id="q" style="display:none"></div>`;
  });

  const open = () => document.getElementById('p').classList.contains('show');
  const said = () => document.getElementById('h').getAttribute('aria-expanded');

  test('a press on the heading, or on what is in it, closes and opens its panel, the heading saying so', () => {
    document.getElementById('label').click();
    expect([open(), said()]).toEqual([false, 'false']);
    document.getElementById('h').click();
    expect([open(), said()]).toEqual([true, 'true']);
  });

  test.each(['Enter', ' '])('%j on the heading turns it over', (key) => {
    const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
    document.getElementById('h').dispatchEvent(event);
    expect([open(), said()]).toEqual([false, 'false']);
    expect(event.defaultPrevented).toBe(true);
  });

  test('a heading not marked data-disclosure is left to its own script', () => {
    document.getElementById('own').click();
    expect(document.getElementById('own').getAttribute('aria-expanded')).toBe('false');
  });

  test('in the view, every panel heading names its panel and is in the keyboard\'s order, without Bootstrap\'s collapse', () => {
    const headings = Array.from(VIEW.matchAll(/<h5\b[^>]*data-disclosure[^>]*>/g), (m) => m[0]);
    expect(headings.length).toBeGreaterThan(5);
    headings.forEach((h) => {
      expect(h).toMatch(/tabindex="0"/);
      const id = h.match(/aria-controls="([^"]+)"/)[1];
      expect(VIEW).toMatch(new RegExp(`id="${id}" class="collapse show`));
    });
    expect(VIEW).not.toMatch(/data-bs-toggle="collapse"/);
  });
});

describe('the audio notice', () => {
  beforeAll(() => {
    document.body.innerHTML = '';
    global.$id = (id) => document.getElementById(id);
    delete global.bootstrap;
    require(path.join(PUBLIC, 'js/monadic/ws-auto-speech.js'));
  });

  test('shows without Bootstrap and closes by its close button', () => {
    document.body.innerHTML = '<div id="tts-toast" class="toast"><button id="tts-toast-close" class="btn-close"></button><div id="tts-toast-body"></div></div>';
    window.showTtsNotice({ notice_type: 'partial', segments_total: 3, segments_played: 1 });
    const toast = document.getElementById('tts-toast');
    expect(toast.classList.contains('show')).toBe(true);
    expect(document.getElementById('tts-toast-body').textContent).not.toBe('');
    document.getElementById('tts-toast-close').click();
    expect(toast.classList.contains('show')).toBe(false);
  });

  test('in the view, the notice is closed by its own button, not Bootstrap\'s dismiss', () => {
    expect(VIEW).toMatch(/id="tts-toast-close"/);
    expect(VIEW).not.toMatch(/data-bs-dismiss="toast"/);
  });
});

describe('the scripts use neither Bootstrap\'s collapse nor its toast', () => {
  const DIR = path.join(PUBLIC, 'js');
  const files = ['monadic.js'].concat(fs.readdirSync(path.join(DIR, 'monadic')).filter((f) => f.endsWith('.js')).map((f) => `monadic/${f}`));
  test.each([/bootstrap\.Collapse/, /bootstrap\.Toast/])('%s', (pattern) => {
    expect(files.filter((f) => pattern.test(fs.readFileSync(path.join(DIR, f), 'utf8')))).toEqual([]);
  });
});
