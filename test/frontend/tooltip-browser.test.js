// MonadicTip (tooltip.js) in a real browser with the real stylesheets:
// where the bubble goes at the screen's edges, moving onto it, the
// keyboard's focus, scrolling in a box, and the control taken off the page
// while shown. Driven by support/tooltip-browser.mjs in a child process; a
// run that does not finish is a failure.
const path = require('path');
const { spawnSync } = require('child_process');

const rgb = (color) => color.match(/[\d.]+/g).slice(0, 3).map(Number);
const luminance = (color) => {
  const [r, g, b] = rgb(color).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

describe('Tooltips in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/tooltip-browser.mjs')], { encoding: 'utf8', timeout: 90000 });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  const inside = (s) => {
    const { bubble, view } = s;
    expect(bubble.left).toBeGreaterThanOrEqual(0);
    expect(bubble.top).toBeGreaterThanOrEqual(0);
    expect(bubble.right).toBeLessThanOrEqual(view.width);
    expect(bubble.bottom).toBeLessThanOrEqual(view.height);
  };

  test('with no room above, it goes below; at the right edge it stays inside the window', () => {
    expect(r.top.shown).toBe(true);
    expect(r.top.bubble.top).toBeGreaterThanOrEqual(r.top.target.bottom);
    inside(r.top);
    expect(r.right.shown).toBe(true);
    inside(r.right);
  });

  test('it describes the control shown, readable on its face', () => {
    expect(r.top.describedBy).toBe('monadic-tip');
    const [hi, lo] = [luminance(r.top.fg), luminance(r.top.bg)].sort((a, b) => b - a);
    expect((hi + 0.05) / (lo + 0.05)).toBeGreaterThanOrEqual(4.5);
  });

  test('the pointer may move onto it to read it; leaving both hides it', () => {
    expect(r.onBubble.shown).toBe(true);
    expect(r.afterLeaving.shown).toBe(false);
  });

  test('the keyboard\'s focus shows it; a click\'s does not', () => {
    expect(r.tabbed.shown).toBe(true);
    expect(r.tabbed.text).toBe('Second');
    expect(r.clicked.shown).toBe(false);
  });

  test('in a box that scrolls it follows its control, and hides when the control is out of view', () => {
    expect(r.scrolled).toEqual({ followed: true, shown: true });
    expect(r.scrolledAway.shown).toBe(false);
  });

  test('a control taken off the page while shown takes it away, with nothing else happening', () => {
    expect(r.goneBefore.shown).toBe(true);
    expect(r.goneAfter.shown).toBe(false);
  });
});
