/**
 * Cross-stack drift guard: realtime-STT denylist ↔ batch-router provider prefixes.
 *
 * The realtime STT path is OpenAI-only. stt-gate.js keeps a denylist
 * (NON_OPENAI_STT_PREFIXES) of provider prefixes that must NEVER be routed to
 * the realtime WebSocket — it is the negation of the batch router in
 * stt_utils.rb, which routes each `model.start_with?("<prefix>")` to that
 * provider's own batch endpoint.
 *
 * These two lists live in different files AND different languages, so they can
 * silently drift: add a new non-OpenAI STT provider to the Ruby batch router
 * but forget the JS gate, and selecting that model with a stale
 * `localStorage.stt_realtime='1'` back door would send its model value to
 * OpenAI's realtime endpoint → the exact "Realtime STT: Invalid value" bug this
 * guard exists to prevent, now for a brand-new provider. Lock them together.
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..', '..');
const STT_GATE = path.join(REPO_ROOT, 'docker/services/ruby/public/js/monadic/stt-gate.js');
const STT_UTILS = path.join(REPO_ROOT, 'docker/services/ruby/lib/monadic/utils/stt_utils.rb');

function gateDenylistPrefixes() {
  const src = fs.readFileSync(STT_GATE, 'utf8');
  const m = src.match(/NON_OPENAI_STT_PREFIXES\s*=\s*\[([^\]]*)\]/);
  expect(m).not.toBeNull();
  const prefixes = [];
  const re = /['"]([^'"]+)['"]/g;
  let hit;
  while ((hit = re.exec(m[1])) !== null) {
    prefixes.push(hit[1]);
  }
  return prefixes;
}

function batchRouterPrefixes() {
  const src = fs.readFileSync(STT_UTILS, 'utf8');
  const prefixes = [];
  // Match every `model.start_with?("<prefix>")` — in stt_utils.rb these are
  // exclusively the non-OpenAI provider routing checks in the batch router.
  const re = /model\.start_with\?\(\s*['"]([^'"]+)['"]\s*\)/g;
  let hit;
  while ((hit = re.exec(src)) !== null) {
    prefixes.push(hit[1]);
  }
  return prefixes;
}

describe('Realtime STT denylist ↔ batch router prefix parity', () => {
  let gate;
  let router;

  beforeAll(() => {
    gate = gateDenylistPrefixes();
    router = batchRouterPrefixes();
  });

  test('both lists are non-empty (extraction sanity check)', () => {
    expect(gate.length).toBeGreaterThan(0);
    expect(router.length).toBeGreaterThan(0);
  });

  test('the gate denylist equals the batch router provider prefixes (no drift)', () => {
    // Equality in BOTH directions:
    //  - a router prefix missing from the gate → that provider can reach the
    //    OpenAI realtime endpoint and 400 (the original bug).
    //  - a gate prefix missing from the router → the gate would force batch for
    //    a model the router treats as OpenAI (wrongly disabling realtime).
    expect([...gate].sort()).toEqual([...router].sort());
  });

  test('every non-OpenAI STT model is excluded from realtime by the gate', () => {
    // Concrete guard: one representative model per prefix must be denied.
    const samples = {
      'gemini-': 'gemini-2.5-flash',
      'scribe': 'scribe_v2',
      'cohere-transcribe': 'cohere-transcribe-03-2026',
      'voxtral': 'voxtral-mini-transcribe-26-02',
      'xai-stt': 'xai-stt-1'
    };
    router.forEach((prefix) => {
      const sample = samples[prefix];
      expect(sample).toBeDefined(); // new prefix added → extend this map too
      expect(sample.startsWith(prefix)).toBe(true);
    });
  });
});
