/**
 * @jest-environment jsdom
 */

// Tests for renderVerifyConfidence (js/monadic/verify-render.js): the DOM
// rendering of a confidence-via-agreement verdict under an assistant card.
// MarkdownRenderer / getTranslation are intentionally absent so the function
// exercises its escaped/English fallbacks.

const { renderVerifyConfidence } = require('../../docker/services/ruby/public/js/monadic/verify-render.js');

function makeCard(mid) {
  document.body.innerHTML =
    `<div class="card" id="${mid}">` +
    `  <div class="card-header"><div class="card-title">Assistant</div></div>` +
    `  <div class="card-body"><div class="card-text">answer</div><div class="verify-bar"></div></div>` +
    `</div>`;
  return document.getElementById(mid);
}

describe('renderVerifyConfidence', () => {
  beforeEach(() => { document.body.innerHTML = ''; });

  it('does nothing when the card for mid is absent', () => {
    expect(() => renderVerifyConfidence({ mid: 'ghost', confidence: 'high' })).not.toThrow();
  });

  it('renders a pending spinner for data.pending', () => {
    makeCard('m1');
    renderVerifyConfidence({ mid: 'm1', pending: true });
    const panel = document.querySelector('#m1 .verify-result');
    expect(panel).not.toBeNull();
    expect(panel.className).toContain('verify-result--pending');
    expect(panel.querySelector('.fa-circle-notch')).not.toBeNull();
  });

  it('renders the confidence badge, recommendation, and a header chip', () => {
    makeCard('m2');
    renderVerifyConfidence({ mid: 'm2', confidence: 'high', score: 0.92, recommendation: 'trust' });
    const badge = document.querySelector('#m2 .verify-result .verify-badge--high');
    expect(badge.textContent).toContain('high');
    expect(badge.textContent).toContain('0.92');
    expect(document.querySelector('#m2 .verify-rec').textContent).toContain('trust');
    // At-a-glance chip in the header.
    expect(document.querySelector('#m2 .card-title .verify-chip.verify-badge--high')).not.toBeNull();
  });

  it('shows corroboration as its own badge', () => {
    makeCard('m3');
    renderVerifyConfidence({ mid: 'm3', confidence: 'high', score: 0.8, corroboration: 'disputed' });
    expect(document.querySelector('#m3 .verify-badge--disputed').textContent).toContain('disputed');
  });

  it('builds a panel legend (Response N -> provider/model) and a moderator line', () => {
    makeCard('m4');
    renderVerifyConfidence({
      mid: 'm4', confidence: 'medium', score: 0.6,
      cross_provider: true,
      responses: [
        { provider: 'anthropic', model: 'claude', success: true, text: '**bold**' },
        { provider: 'gemini', model: 'flash', success: true, text: 'plain' }
      ],
      moderator: { provider: 'openai', model: 'gpt' }
    });
    const items = document.querySelectorAll('#m4 .verify-panel-item');
    expect(items.length).toBe(2);
    expect(items[0].textContent).toContain('Response 1');
    expect(items[0].textContent).toContain('anthropic');
    // No MarkdownRenderer in this env -> falls back to escaped raw text.
    expect(items[0].querySelector('.verify-panel-raw').textContent).toContain('**bold**');
    expect(document.querySelector('#m4 .verify-body').textContent).toContain('openai');
  });

  it('flags a single-provider panel as a weak signal', () => {
    makeCard('m5');
    renderVerifyConfidence({
      mid: 'm5', confidence: 'high', score: 0.9, cross_provider: false,
      responses: [{ provider: 'openai', model: 'a', success: true, text: 'x' }]
    });
    expect(document.querySelector('#m5 .verify-weak')).not.toBeNull();
  });

  it('replaces a prior result on a second render (idempotent)', () => {
    makeCard('m6');
    renderVerifyConfidence({ mid: 'm6', confidence: 'low', score: 0.2 });
    renderVerifyConfidence({ mid: 'm6', confidence: 'high', score: 0.95 });
    expect(document.querySelectorAll('#m6 .verify-result').length).toBe(1);
    expect(document.querySelector('#m6 .verify-badge--high')).not.toBeNull();
  });
});
