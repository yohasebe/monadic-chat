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

  test('text-utils.js (canonical escapeHtml) precedes every delegating consumer', () => {
    const helperIdx = files.indexOf('js/monadic/text-utils.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    // These modules delegate their escaping to window.escapeHtml, which
    // text-utils.js defines at load time.
    const consumers = [
      'js/monadic/html-sanitizer.js',
      'js/monadic/markdown-renderer.js',
      'js/monadic/card-renderer.js',
      'js/monadic/library-panel.js',
      'js/monadic/websocket-handlers.js',
      'js/monadic/ws-privacy-handler.js',
      'js/monadic/ws-message-renderer.js',
      'js/monadic/context-panel.js',
      'js/monadic/pdf_export.js'
    ];

    consumers.forEach(consumer => {
      const consumerIdx = files.indexOf(consumer);
      expect(consumerIdx).toBeGreaterThan(-1);
      expect(consumerIdx).toBeGreaterThan(helperIdx);
    });
  });

  // The assistant card label was previously inlined at three call sites, so an
  // "interrupted" marker added to one of them never reached the product. It
  // now lives in card-renderer.js, which makes the load order load-bearing:
  // the consumers call window.assistantBadge at render time and would throw if
  // it were not defined yet.
  test('card-renderer.js (window.assistantBadge) precedes its consumers', () => {
    const helperIdx = files.indexOf('js/monadic/card-renderer.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    const consumers = [
      'js/monadic/ws-html-handler.js',
      'js/monadic/websocket-handlers.js',
      'js/monadic.js'
    ];

    consumers.forEach(consumer => {
      const consumerIdx = files.indexOf(consumer);
      expect(consumerIdx).toBeGreaterThan(-1);
      expect(consumerIdx).toBeGreaterThan(helperIdx);
    });
  });

  // Dropdown call sites reference appOffersSpeechToSpeech (model_utils.js)
  // at render time; if a consumer ever moved above it, every dropdown would
  // throw on population.
  test('model_utils.js precedes the dropdown call sites', () => {
    const helperIdx = files.indexOf('js/monadic/model_utils.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    ['js/monadic/utilities.js', 'js/monadic/ws-app-data-handlers.js', 'js/monadic.js'].forEach(consumer => {
      const idx = files.indexOf(consumer);
      expect(idx).toBeGreaterThan(helperIdx);
    });
  });

  test('live-conversation.js precedes monadic.js (setAppMode is called on app change)', () => {
    const lcIdx = files.indexOf('js/monadic/live-conversation.js');
    const monadicIdx = files.indexOf('js/monadic.js');
    expect(lcIdx).toBeGreaterThanOrEqual(0);
    expect(monadicIdx).toBeGreaterThan(lcIdx);
  });

  test('ws-sts-playback.js precedes ws-sts-usage.js and both follow ws-audio-playback.js', () => {
    const playbackIdx = files.indexOf('js/monadic/ws-audio-playback.js');
    const stsIdx = files.indexOf('js/monadic/ws-sts-playback.js');
    const usageIdx = files.indexOf('js/monadic/ws-sts-usage.js');

    // ws-audio-playback's stopAllActiveAudio resolves window.WsStsPlayback at
    // call time, so it may load first; the STS modules must not precede it in
    // a way that inverts the documented relationship.
    expect(playbackIdx).toBeGreaterThanOrEqual(0);
    expect(stsIdx).toBeGreaterThan(playbackIdx);
    expect(usageIdx).toBeGreaterThan(stsIdx);
  });

  test('html-sanitizer.js (window.sanitizeModelHtml) precedes its innerHTML-sink consumers', () => {
    const helperIdx = files.indexOf('js/monadic/html-sanitizer.js');
    expect(helperIdx).toBeGreaterThanOrEqual(0);

    const consumers = [
      'js/monadic/card-renderer.js',
      'js/monadic/ws-message-renderer.js',
      'js/monadic/verify-render.js'
    ];

    consumers.forEach(consumer => {
      const consumerIdx = files.indexOf(consumer);
      expect(consumerIdx).toBeGreaterThan(-1);
      expect(consumerIdx).toBeGreaterThan(helperIdx);
    });
  });
});
