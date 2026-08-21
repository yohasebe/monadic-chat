/**
 * @jest-environment jsdom
 */

/**
 * Session-cumulative cost readout for speech-to-speech turns.
 *
 * The invariants worth pinning are about honesty rather than arithmetic:
 * the figure accumulates across turns (a single turn looks cheap), it never
 * renders a sub-cent charge as "$0.00" (which reads as free), and it comes
 * from the server's accounting rather than being recomputed here — the rate
 * constants must stay single-sourced in sts_stream_handler.rb.
 */

let Usage;

beforeEach(() => {
  jest.resetModules();

  const el = document.createElement('span');
  el.id = 'sts-usage-indicator';
  el.style.display = 'none';
  document.body.appendChild(el);

  window.escapeHtml = (s) => String(s);
  Usage = require('../../docker/services/ruby/public/js/monadic/ws-sts-usage');
});

afterEach(() => {
  const el = document.getElementById('sts-usage-indicator');
  if (el) el.remove();
  delete window.escapeHtml;
});

const indicator = () => document.getElementById('sts-usage-indicator');

describe('initial state', () => {
  it('stays hidden until a turn completes', () => {
    expect(indicator().style.display).toBe('none');
    expect(Usage.getSessionCostUsd()).toBe(0);
  });
});

describe('accumulation', () => {
  it('adds up the cost across turns', () => {
    Usage.record({ estimated_cost_usd: 0.02 });
    Usage.record({ estimated_cost_usd: 0.03 });

    expect(Usage.getSessionCostUsd()).toBeCloseTo(0.05, 6);
    expect(Usage.getTurnCount()).toBe(2);
  });

  it('becomes visible once there is something to report', () => {
    Usage.record({ estimated_cost_usd: 0.02 });

    expect(indicator().style.display).not.toBe('none');
    expect(indicator().innerHTML).toContain('$0.02');
  });

  it('counts a turn even when the server reported no cost', () => {
    Usage.record({ estimated_cost_usd: 0 });

    expect(Usage.getTurnCount()).toBe(1);
    expect(indicator().style.display).not.toBe('none');
  });

  // An unknown charge and a zero charge must not look the same — showing
  // "$0.00" for missing accounting would read as "this was free".
  it('shows an unknown amount as — rather than $0.00', () => {
    Usage.record({ audio_input_tokens: 97 }); // no estimated_cost_usd

    expect(indicator().innerHTML).toContain('—');
    expect(indicator().innerHTML).not.toContain('$0.00');
  });

  it('shows a genuine zero as $0.00', () => {
    Usage.record({ estimated_cost_usd: 0 });

    expect(indicator().innerHTML).toContain('$0.00');
  });

  it('keeps the navbar spacing class when rendering', () => {
    Usage.record({ estimated_cost_usd: 0.02 });

    expect(indicator().className).toContain('me-2');
    expect(indicator().className).toContain('sts-usage-indicator');
  });

  it('ignores a malformed cost rather than poisoning the total with NaN', () => {
    Usage.record({ estimated_cost_usd: 0.04 });
    Usage.record({ estimated_cost_usd: 'not a number' });

    expect(Usage.getSessionCostUsd()).toBeCloseTo(0.04, 6);
  });

  it('ignores a negative cost', () => {
    Usage.record({ estimated_cost_usd: 0.04 });
    Usage.record({ estimated_cost_usd: -5 });

    expect(Usage.getSessionCostUsd()).toBeCloseTo(0.04, 6);
  });

  it('does nothing when accounting is absent', () => {
    Usage.record(null);
    Usage.record(undefined);

    expect(Usage.getTurnCount()).toBe(0);
    expect(indicator().style.display).toBe('none');
  });
});

describe('formatting', () => {
  it('never shows a real charge as $0.00', () => {
    // A single turn is routinely sub-cent; rounding it to $0.00 would read
    // as free and defeat the point of showing the figure at all.
    expect(Usage.formatUsd(0.004)).toBe('<$0.01');
  });

  it('shows zero as zero', () => {
    expect(Usage.formatUsd(0)).toBe('$0.00');
  });

  it('formats normal amounts to two decimals', () => {
    expect(Usage.formatUsd(0.096)).toBe('$0.10');
    expect(Usage.formatUsd(5.76)).toBe('$5.76');
  });
});

describe('labelling', () => {
  it('marks the figure as an estimate', () => {
    Usage.record({ estimated_cost_usd: 0.5 });

    expect(indicator().innerHTML).toContain('est.');
  });

  it('explains in the tooltip that the figure is an upper bound', () => {
    Usage.record({ estimated_cost_usd: 0.5 });

    // The server prices cached audio input at the full rate, so the estimate
    // overstates on long sessions. Saying "upper bound" is what makes that
    // honest rather than merely approximate.
    expect(indicator().getAttribute('title')).toMatch(/upper bound/i);
  });
});

describe('message handling', () => {
  it('records the accounting carried by sts_audio_done', () => {
    Usage.handleStsAudioDone({
      type: 'sts_audio_done',
      turn_id: 't1',
      usage: { input_token_details: {} },
      accounting: { estimated_cost_usd: 0.012, audio_input_tokens: 97, audio_output_tokens: 291 }
    });

    expect(Usage.getSessionCostUsd()).toBeCloseTo(0.012, 6);
  });

  it('tolerates a done message with no accounting', () => {
    expect(() => Usage.handleStsAudioDone({ turn_id: 't1' })).not.toThrow();
    expect(Usage.getTurnCount()).toBe(0);
  });

  // The rate constants live in sts_stream_handler.rb. If this module ever
  // starts deriving cost from raw token counts, a price change would update
  // one side only.
  it('does not compute cost from raw token counts', () => {
    Usage.handleStsAudioDone({
      turn_id: 't1',
      usage: { input_token_details: { audio_tokens: 1000000 } },
      accounting: { estimated_cost_usd: 0.01 }
    });

    expect(Usage.getSessionCostUsd()).toBeCloseTo(0.01, 6);
  });
});

describe('reset', () => {
  it('clears the total and hides the indicator', () => {
    Usage.record({ estimated_cost_usd: 1.23 });

    Usage.reset();

    expect(Usage.getSessionCostUsd()).toBe(0);
    expect(Usage.getTurnCount()).toBe(0);
    expect(indicator().style.display).toBe('none');
  });
});
