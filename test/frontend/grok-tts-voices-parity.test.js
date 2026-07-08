/**
 * Grok (xAI) TTS voice roster parity.
 *
 * The user-facing dropdown (views/index.erb → #grok-tts-voice) and the
 * SSOT capability list (model_spec.js → grok-tts.tts_voices) must list the
 * exact same voice_id set. The roster is authored statically from xAI's
 * authoritative GET /v1/tts/voices response; this guard fails the moment the
 * two copies drift, so adding/removing a voice must touch both places.
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..', '..');
const INDEX_ERB = path.join(REPO_ROOT, 'docker/services/ruby/views/index.erb');
const MODEL_SPEC = path.join(REPO_ROOT, 'docker/services/ruby/public/js/monadic/model_spec.js');

function grokOptionValuesFromErb() {
  const html = fs.readFileSync(INDEX_ERB, 'utf8');
  const selectStart = html.indexOf('id="grok-tts-voice"');
  expect(selectStart).toBeGreaterThan(-1);
  const selectEnd = html.indexOf('</select>', selectStart);
  expect(selectEnd).toBeGreaterThan(selectStart);
  const block = html.slice(selectStart, selectEnd);
  const values = [];
  const re = /<option\s+value="([^"]+)"/g;
  let m;
  while ((m = re.exec(block)) !== null) {
    values.push(m[1]);
  }
  return values;
}

describe('Grok TTS voice roster: index.erb ↔ model_spec.js parity', () => {
  let specVoices;
  let erbValues;

  beforeAll(() => {
    const modelSpec = require(MODEL_SPEC);
    specVoices = modelSpec['grok-tts'] && modelSpec['grok-tts'].tts_voices;
    erbValues = grokOptionValuesFromErb();
  });

  test('model_spec grok-tts declares a non-empty tts_voices array', () => {
    expect(Array.isArray(specVoices)).toBe(true);
    expect(specVoices.length).toBeGreaterThan(0);
  });

  test('the dropdown options and tts_voices are the same set (no drift)', () => {
    expect([...erbValues].sort()).toEqual([...specVoices].sort());
  });

  test('every voice_id is lowercase (the request sends voice_id.downcase)', () => {
    specVoices.forEach((v) => expect(v).toBe(v.toLowerCase()));
    erbValues.forEach((v) => expect(v).toBe(v.toLowerCase()));
  });

  test('there are no duplicate options in the dropdown', () => {
    expect(new Set(erbValues).size).toBe(erbValues.length);
  });

  test('the original five voices remain available (backward compatibility)', () => {
    ['eve', 'ara', 'rex', 'sal', 'leo'].forEach((v) => {
      expect(specVoices).toContain(v);
      expect(erbValues).toContain(v);
    });
  });

  test('eve (the xAI default) is marked selected in the dropdown', () => {
    const html = fs.readFileSync(INDEX_ERB, 'utf8');
    const start = html.indexOf('id="grok-tts-voice"');
    const block = html.slice(start, html.indexOf('</select>', start));
    expect(block).toMatch(/<option\s+value="eve"\s+selected>/);
  });
});
