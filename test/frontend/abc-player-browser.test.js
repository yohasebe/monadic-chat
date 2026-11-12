// Playing a tune in a real browser: the controls are made, and the sounds
// come from the ones Monadic Chat carries, for the instruments the tune is
// played with, and from nowhere else. Driven by support/abc-player-browser.mjs
// in a child process.
const path = require('path');
const { spawnSync } = require('child_process');

describe('AbcPlayer in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/abc-player-browser.mjs')], {
      encoding: 'utf8', timeout: 90000
    });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  test('makes the playing controls', () => {
    expect(r.controls).toBe(true);
  });

  test('loads the sounds of the instruments played, from the ones carried, and nothing from outside', () => {
    const sounds = r.requests.filter((u) => u.startsWith('/vendor/soundfont/'));
    expect(sounds.length).toBeGreaterThan(0);
    const instruments = new Set(sounds.map((u) => u.split('/')[4]));
    expect([...instruments].sort()).toEqual(['acoustic_grand_piano-mp3', 'string_ensemble_1-mp3']);
    expect(r.failed).toEqual([]);
    expect(r.outside).toEqual([]);
  });

  test('leaves no error on the page', () => {
    expect(r.errors).toEqual([]);
  });
});
