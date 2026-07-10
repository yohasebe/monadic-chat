/**
 * Source-level guards for the dynamic-skills UI wiring and the OpenAI
 * model-selector fixes (real source, not a test-local reimplementation).
 */

const fs = require('fs');
const path = require('path');

const read = (rel) => fs.readFileSync(path.resolve(__dirname, '../..', rel), 'utf8');
const UTIL = read('docker/services/ruby/public/js/monadic/utilities.js');
const VIEWER = read('docker/services/ruby/public/js/monadic/workflow-viewer.js');
const WS = read('docker/services/ruby/public/js/monadic/websocket.js');

describe('OpenAI model selector (utilities.js listModels)', () => {
  // The REAL pattern from the source, extracted so the assertions test the
  // shipped regex rather than a copy.
  const m = UTIL.match(/const gpt5ModelPatterns = \[(\/.*?\/)\];/);
  const pattern = m && eval(m[1]); // eslint-disable-line no-eval

  it('groups the GPT-5.6 named tiers (sol/terra/luna) under GPT-5', () => {
    expect(pattern).toBeTruthy();
    ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.4-mini', 'gpt-5'].forEach((id) => {
      expect(pattern.test(id)).toBe(true);
    });
  });

  it('does not swallow non-chat model ids into the GPT-5 group', () => {
    ['gpt-realtime-whisper', 'gpt-image-2', 'gpt-4o-mini-tts-2025-12-15'].forEach((id) => {
      expect(pattern.test(id)).toBe(false);
    });
  });

  it('filters speech models (STT/TTS/realtime) out of the chat selector', () => {
    const fn = UTIL.match(/function listModels\([\s\S]{0,700}/)[0];
    expect(fn).toMatch(/stt_capability/);
    expect(fn).toMatch(/tts_capability/);
    expect(fn).toMatch(/supports_realtime_streaming/);
  });
});

describe('Workflow Viewer dynamic-skill reflection', () => {
  it('renders unlocked state (open lock + check) from data.unlocked_tools', () => {
    expect(VIEWER).toMatch(/unlockedSet = new Set\(data\.unlocked_tools/);
    expect(VIEWER).toMatch(/groupUnlocked \? '/);
    expect(VIEWER).toMatch(/unlockedSet\.has\(n\) \? '/);
  });

  it('exposes reloadCurrent (re-FETCH, not just re-render)', () => {
    expect(VIEWER).toMatch(/reloadCurrent: function \(\) \{[\s\S]{0,300}?currentApp = null;[\s\S]{0,120}?loadApp\(name\)/);
  });

  it('websocket.js reloads the viewer on the tool_unlocked event', () => {
    const block = WS.match(/case "tool_unlocked": \{[\s\S]{0,500}?\}/)[0];
    expect(block).toMatch(/WorkflowViewer\.reloadCurrent\(\)/);
  });
});
