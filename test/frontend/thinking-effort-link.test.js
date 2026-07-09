/**
 * @jest-environment jsdom
 */

/**
 * Show Thinking ⇄ Reasoning Effort link
 * (docker/services/ruby/public/js/monadic/thinking-effort-link.js).
 *
 * Models whose reasoning_effort enumeration includes "none" (OpenAI gpt-5.x
 * family) produce no reasoning while effort is "none", so turning Show
 * Thinking ON in that state would silently display nothing. The link bumps
 * the effort to the model's lowest thinking level exactly then — and only
 * then. Turning the toggle OFF must never touch the effort (reasoning
 * affects answer quality, not just display).
 */

const path = require('path');
const MODULE_PATH = path.resolve(
  __dirname,
  '../../docker/services/ruby/public/js/monadic/thinking-effort-link.js'
);

describe('effortBumpForThinking (pure decision)', () => {
  let mod;

  beforeEach(() => {
    jest.resetModules();
    delete window.ThinkingEffortLink;
    mod = require(MODULE_PATH);
  });

  it('bumps "none" to the first non-none option of the model spec', () => {
    const spec = { reasoning_effort: [['none', 'low', 'medium', 'high'], 'none'] };
    expect(mod.effortBumpForThinking(spec, 'none')).toBe('low');
  });

  it('respects the spec order (e.g. ["none","high"] bumps to "high")', () => {
    const spec = { reasoning_effort: [['none', 'high'], 'none'] };
    expect(mod.effortBumpForThinking(spec, 'none')).toBe('high');
  });

  it('returns null when the current effort is already a thinking level', () => {
    const spec = { reasoning_effort: [['none', 'low', 'high'], 'none'] };
    expect(mod.effortBumpForThinking(spec, 'medium')).toBeNull();
  });

  it('returns null when the enumeration has no "none" (model always thinks)', () => {
    const spec = { reasoning_effort: [['low', 'medium', 'high'], 'low'] };
    expect(mod.effortBumpForThinking(spec, 'low')).toBeNull();
  });

  it('returns null for models without reasoning_effort', () => {
    expect(mod.effortBumpForThinking({ supports_thinking: true }, 'none')).toBeNull();
    expect(mod.effortBumpForThinking(undefined, 'none')).toBeNull();
  });
});

describe('wireShowThinkingEffortLink (DOM behavior)', () => {
  let mod;

  beforeEach(() => {
    document.body.innerHTML = `
      <input type="checkbox" id="show-thinking">
      <select id="model">
        <option value="gpt-5.4" selected>gpt-5.4</option>
      </select>
      <select id="reasoning-effort">
        <option value="none" selected>none</option>
        <option value="low">low</option>
        <option value="high">high</option>
      </select>
    `;
    window.modelSpec = {
      'gpt-5.4': { reasoning_effort: [['none', 'low', 'medium', 'high', 'xhigh'], 'none'] }
    };
    jest.resetModules();
    delete window.ThinkingEffortLink;
    mod = require(MODULE_PATH);
    mod.wireShowThinkingEffortLink();
  });

  afterEach(() => {
    document.body.innerHTML = '';
    delete window.modelSpec;
    delete window.ThinkingEffortLink;
  });

  function toggleShowThinking(checked) {
    const cb = document.getElementById('show-thinking');
    cb.checked = checked;
    cb.dispatchEvent(new Event('change', { bubbles: true }));
  }

  it('bumps effort none→low when Show Thinking turns ON', () => {
    toggleShowThinking(true);
    expect(document.getElementById('reasoning-effort').value).toBe('low');
  });

  it('fires a change event on the effort select so params update downstream', () => {
    const handler = jest.fn();
    document.getElementById('reasoning-effort').addEventListener('change', handler);
    toggleShowThinking(true);
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('leaves a non-none effort untouched when turning ON', () => {
    document.getElementById('reasoning-effort').value = 'high';
    toggleShowThinking(true);
    expect(document.getElementById('reasoning-effort').value).toBe('high');
  });

  it('never touches the effort when turning OFF', () => {
    document.getElementById('reasoning-effort').value = 'none';
    toggleShowThinking(false);
    expect(document.getElementById('reasoning-effort').value).toBe('none');
  });

  it('is a no-op for models whose enumeration lacks "none"', () => {
    window.modelSpec['gpt-5.4'] = { reasoning_effort: [['low', 'medium', 'high'], 'low'] };
    document.getElementById('reasoning-effort').value = 'low';
    toggleShowThinking(true);
    expect(document.getElementById('reasoning-effort').value).toBe('low');
  });

  it('wiring is idempotent (no double bump-dispatch)', () => {
    mod.wireShowThinkingEffortLink();
    const handler = jest.fn();
    document.getElementById('reasoning-effort').addEventListener('change', handler);
    toggleShowThinking(true);
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('unchecks Show Thinking when the effort is set to "none" (reverse link)', () => {
    const cb = document.getElementById('show-thinking');
    cb.checked = true;
    const effortEl = document.getElementById('reasoning-effort');
    effortEl.value = 'none';
    effortEl.dispatchEvent(new Event('change', { bubbles: true }));
    expect(cb.checked).toBe(false);
  });

  it('does not re-check the toggle when effort is raised manually (display pref preserved)', () => {
    const cb = document.getElementById('show-thinking');
    cb.checked = false;
    const effortEl = document.getElementById('reasoning-effort');
    effortEl.value = 'high';
    effortEl.dispatchEvent(new Event('change', { bubbles: true }));
    expect(cb.checked).toBe(false);
  });

  it('no bump→uncheck loop: turning ON bumps effort and the toggle STAYS on', () => {
    toggleShowThinking(true);
    expect(document.getElementById('reasoning-effort').value).toBe('low');
    expect(document.getElementById('show-thinking').checked).toBe(true);
  });
});

describe('syncShowThinkingToEffort (initial/model-selection coherence)', () => {
  let mod;

  beforeEach(() => {
    document.body.innerHTML = `
      <input type="checkbox" id="show-thinking" checked>
      <select id="model"><option value="gpt-5.4" selected>gpt-5.4</option></select>
      <select id="reasoning-effort">
        <option value="none" selected>none</option>
        <option value="low">low</option>
      </select>
    `;
    window.modelSpec = {
      'gpt-5.4': { reasoning_effort: [['none', 'low', 'medium', 'high'], 'none'] }
    };
    jest.resetModules();
    delete window.ThinkingEffortLink;
    mod = require(MODULE_PATH);
  });

  afterEach(() => {
    document.body.innerHTML = '';
    delete window.modelSpec;
    delete window.ThinkingEffortLink;
  });

  it('unchecks a checked toggle when the current effort is "none"', () => {
    mod.syncShowThinkingToEffort();
    expect(document.getElementById('show-thinking').checked).toBe(false);
  });

  it('leaves the toggle checked when the effort is a thinking level', () => {
    document.getElementById('reasoning-effort').value = 'low';
    mod.syncShowThinkingToEffort();
    expect(document.getElementById('show-thinking').checked).toBe(true);
  });

  it('leaves the toggle alone for always-thinking models (no "none" in enum)', () => {
    window.modelSpec['gpt-5.4'] = { reasoning_effort: [['low', 'medium', 'high'], 'low'] };
    mod.syncShowThinkingToEffort();
    expect(document.getElementById('show-thinking').checked).toBe(true);
  });

  it('never force-checks an unchecked toggle (sync only removes contradictions)', () => {
    document.getElementById('show-thinking').checked = false;
    document.getElementById('reasoning-effort').value = 'low';
    mod.syncShowThinkingToEffort();
    expect(document.getElementById('show-thinking').checked).toBe(false);
  });
});
