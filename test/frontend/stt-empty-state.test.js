/**
 * @jest-environment jsdom
 */

/**
 * STT select empty-state tests.
 *
 * Source of truth: docker/services/ruby/public/js/monadic/stt-gate.js
 * (updateSttEmptyState). Every #stt-model option ships disabled and is
 * enabled per verified API key; the placeholder option (value="") must
 * own the "no key present" state instead of a disabled model name, and
 * selection must move to a real enabled option once one appears.
 */

const path = require('path');
const STT_GATE_PATH = path.resolve(
  __dirname,
  '../../docker/services/ruby/public/js/monadic/stt-gate.js'
);

function buildSelect({ enabledIds = [], selectedValue = '' } = {}) {
  document.body.innerHTML = `
    <select id="stt-model">
      <option id="stt-model-placeholder" value="" disabled selected hidden>No STT models available (API key required)</option>
      <option id="openai-stt-4o-mini" value="gpt-4o-mini-transcribe-2025-12-15" disabled>GPT-4o Mini Transcribe</option>
      <option id="gemini-stt-flash" value="gemini-2.5-flash" disabled>Gemini 2.5 Flash</option>
      <option id="cohere-stt-transcribe" value="cohere-transcribe-03-2026" disabled>Cohere Transcribe</option>
    </select>
  `;
  enabledIds.forEach((id) => {
    document.getElementById(id).disabled = false;
  });
  const sel = document.getElementById('stt-model');
  if (selectedValue !== '') {
    sel.value = selectedValue;
  }
  return sel;
}

function loadSttGate() {
  jest.resetModules();
  return require(STT_GATE_PATH);
}

describe('updateSttEmptyState', () => {
  test('keeps the placeholder selected while every model is disabled', () => {
    const sel = buildSelect();
    const SttGate = loadSttGate();
    SttGate.updateSttEmptyState();
    expect(sel.value).toBe('');
    expect(sel.options[sel.selectedIndex].id).toBe('stt-model-placeholder');
  });

  test('moves off the placeholder to the first enabled model', () => {
    const sel = buildSelect({ enabledIds: ['gemini-stt-flash'] });
    const changed = jest.fn();
    sel.addEventListener('change', changed);
    // Loading the module auto-initializes the observer, which performs
    // the initial sync — exactly what the browser does
    loadSttGate();
    expect(sel.value).toBe('gemini-2.5-flash');
    expect(changed).toHaveBeenCalled();
  });

  test('replaces a disabled selection with the first enabled model', () => {
    const sel = buildSelect({
      enabledIds: ['cohere-stt-transcribe'],
      selectedValue: 'gpt-4o-mini-transcribe-2025-12-15'
    });
    const SttGate = loadSttGate();
    SttGate.updateSttEmptyState();
    expect(sel.value).toBe('cohere-transcribe-03-2026');
  });

  test('leaves a valid enabled selection untouched', () => {
    const sel = buildSelect({
      enabledIds: ['openai-stt-4o-mini', 'gemini-stt-flash'],
      selectedValue: 'gemini-2.5-flash'
    });
    const SttGate = loadSttGate();
    const changed = jest.fn();
    sel.addEventListener('change', changed);
    SttGate.updateSttEmptyState();
    expect(sel.value).toBe('gemini-2.5-flash');
    expect(changed).not.toHaveBeenCalled();
  });

  test('falls back to the placeholder when the only enabled model is disabled again', () => {
    const sel = buildSelect({ enabledIds: ['gemini-stt-flash'] });
    const SttGate = loadSttGate();
    SttGate.updateSttEmptyState();
    expect(sel.value).toBe('gemini-2.5-flash');
    document.getElementById('gemini-stt-flash').disabled = true;
    SttGate.updateSttEmptyState();
    expect(sel.value).toBe('');
  });

  test('leaves the selection alone when no placeholder option exists', () => {
    // A select without the placeholder (e.g. stale cached markup) must not
    // be set to value='' — that would blank the select (selectedIndex -1)
    document.body.innerHTML = `
      <select id="stt-model">
        <option id="openai-stt-4o-mini" value="gpt-4o-mini-transcribe-2025-12-15" disabled selected>GPT-4o Mini Transcribe</option>
        <option id="gemini-stt-flash" value="gemini-2.5-flash" disabled>Gemini 2.5 Flash</option>
      </select>
    `;
    const sel = document.getElementById('stt-model');
    const SttGate = loadSttGate();
    SttGate.updateSttEmptyState();
    expect(sel.selectedIndex).not.toBe(-1);
    expect(sel.value).toBe('gpt-4o-mini-transcribe-2025-12-15');
  });

  test('does not throw when #stt-model is absent', () => {
    document.body.innerHTML = '';
    const SttGate = loadSttGate();
    expect(() => SttGate.updateSttEmptyState()).not.toThrow();
  });

  test('observer reacts to option enablement without an explicit call', async () => {
    const sel = buildSelect();
    const SttGate = loadSttGate();
    SttGate.initSttEmptyStateObserver();
    expect(sel.value).toBe('');
    document.getElementById('gemini-stt-flash').disabled = false;
    // MutationObserver callbacks run as microtasks
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(sel.value).toBe('gemini-2.5-flash');
  });
});
