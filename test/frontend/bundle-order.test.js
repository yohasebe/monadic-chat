/**
 * Bundle order invariants.
 *
 * scripts/build_js_bundle.mjs concatenates frontend JS files in a fixed
 * order; that order is the only thing keeping `window.safeWsSend` /
 * `window.monadicFetch` defined by the time their consumers are
 * parsed. Without this test, a future re-ordering of the FILES array
 * could silently move the helpers below their callers — most callers
 * happen inside event handlers (so the breakage would only surface
 * on first user click), and the failure mode would be a confusing
 * "TypeError: window.safeWsSend is not a function" with no obvious
 * cause.
 *
 * Strategy: parse the FILES array out of build_js_bundle.mjs and
 * assert that every known consumer file appears strictly after its
 * helper.
 */

const fs = require('fs');
const path = require('path');

function loadBundleFiles() {
  const buildScriptPath = path.join(__dirname, '..', '..', 'scripts', 'build_js_bundle.mjs');
  const text = fs.readFileSync(buildScriptPath, 'utf8');
  const filesMatch = text.match(/const FILES = \[([\s\S]*?)\];/);
  if (!filesMatch) {
    throw new Error('Could not parse FILES array from build_js_bundle.mjs');
  }
  return filesMatch[1]
    .split('\n')
    .map(line => {
      const m = line.match(/["']([^"']+\.js)["']/);
      return m ? m[1] : null;
    })
    .filter(Boolean);
}

describe('bundle order invariants', () => {
  let files;

  beforeAll(() => {
    files = loadBundleFiles();
  });

  test('FILES array is non-empty and parseable', () => {
    expect(files.length).toBeGreaterThan(20);
  });

  test('monadic-ws.js precedes every file that calls window.safeWsSend', () => {
    const helperIdx = files.indexOf('js/monadic/monadic-ws.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    // Files that were migrated in H7.2-H7.8 and now reference safeWsSend.
    // If a new consumer is added, list it here so the load-order
    // invariant covers it.
    const consumers = [
      'js/monadic/cards.js',
      'js/monadic/alert-manager.js',
      'js/monadic/utilities.js',
      'js/monadic/library-panel.js',
      'js/monadic/ws-ping.js',
      'js/monadic/ws-tool-handler.js',
      'js/monadic/ws-visibility-handler.js',
      'js/monadic/ws-privacy-handler.js',
      'js/monadic/websocket.js',
      'js/monadic/tts.js',
      'js/monadic/recording.js'
    ];

    consumers.forEach(consumer => {
      const consumerIdx = files.indexOf(consumer);
      expect(consumerIdx).toBeGreaterThan(-1);
      expect(consumerIdx).toBeGreaterThan(helperIdx);
    });
  });

  test('monadic-fetch.js precedes every file that calls window.monadicFetch', () => {
    const helperIdx = files.indexOf('js/monadic/monadic-fetch.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    // monadic-fetch consumers established in H3 and earlier sweeps.
    const consumers = [
      'js/monadic/cards.js',
      'js/monadic/utilities.js',
      'js/monadic/shims.js'
    ];

    consumers.forEach(consumer => {
      const consumerIdx = files.indexOf(consumer);
      expect(consumerIdx).toBeGreaterThan(-1);
      expect(consumerIdx).toBeGreaterThan(helperIdx);
    });
  });

  test('debug-config.js stays at index 0 (loaded first for early flag access)', () => {
    expect(files[0]).toBe('js/debug-config.js');
  });
});
