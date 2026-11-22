// The page's two columns in a real browser, with the real stylesheets and
// layout-controller.js: the bars at the top of each column stay there while
// it scrolls, the border between the columns sets the side column's width
// (the same for its three panes, kept for the next load), and the columns
// take turns below 768 px. Driven by support/layout-browser.mjs in a child
// process; a run that does not finish is a failure.
const path = require('path');
const { spawnSync } = require('child_process');

describe('The columns in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/layout-browser.mjs')], {
      encoding: 'utf8', timeout: 90000
    });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  const near = (a, b, within = 1) => expect(Math.abs(a - b)).toBeLessThanOrEqual(within);

  test('starts with the side column at 40 % of the row, the border on the gap between the columns', () => {
    const row = r.before.main.width + r.before.menu.width;
    near(r.before.menu.width, row * 0.4, 2);
    expect(r.before.handle.shown).toBe(true);
    expect(r.before.handleOff).toBeLessThanOrEqual(1);
    expect(r.before.tabsCut).toEqual([0, 0, 0, 0]);
  });

  test('keeps the Files pane\'s controls right under the side column\'s bar while its list scrolls', () => {
    expect(r.filesScrolled.by).toBeGreaterThan(0);
    near(r.filesScrolled.headTop, r.filesScrolled.barBottom);
    // With room below its last control, which the list scrolls under, as
    // much as there is between the bar and its first control.
    expect(r.filesScrolled.spaceBelow).toBeGreaterThan(0);
    near(r.filesScrolled.spaceBelow, r.filesScrolled.barBottom - r.filesScrolled.tabsBottom);
    // The search box and the controls beside it are one height.
    expect(new Set(r.filesScrolled.findHeights).size).toBe(1);
    // The buttons of the row above are as tall as those of the search row.
    expect(r.filesScrolled.upHeight).toBe(r.filesScrolled.findHeights[0]);
    expect(r.filesScrolled.refreshHeight).toBe(r.filesScrolled.findHeights[0]);
    // The bar is its tabs at their set height, which the controls stay under.
    expect(r.filesScrolled.tabsHeight).toBeLessThanOrEqual(46.5);
  });

  test('keeps both bars at the top of their columns, side by side, while the columns scroll', () => {
    expect(r.scrolledBy).toEqual([1500, 1500]);
    near(r.scrolled.summary.top, r.before.summary.top);
    near(r.scrolled.tabs.top, r.before.tabs.top);
    near(r.scrolled.summary.top, r.scrolled.tabs.top);
    // Nothing that scrolls shows outside their rounded corners.
    expect(r.scrolled.corners.flat()).toEqual(Array(4).fill('column-bar'));
    // At the top edge of the column, with no space above them.
    near(r.scrolled.summary.top, r.scrolled.main.top);
    near(r.scrolled.tabs.top, r.scrolled.menu.top);
  });

  test('gives the main column\'s tabs the side column\'s height', () => {
    near(r.before.barHeights[0], r.before.barHeights[1]);
    near(r.before.selectedTabHeights[0], r.before.selectedTabHeights[1]);
  });

  test('lists the shared folder names from the start of their rows', () => {
    expect(r.files.nameIndent).toBeGreaterThanOrEqual(0);
    expect(r.files.nameIndent).toBeLessThanOrEqual(40);
  });

  test('keeps a long line from widening the conversation', () => {
    near(r.before.main.width + r.before.menu.width, r.before.main.width / 0.6, 3);
  });

  test('moves the border by dragging it, and keeps the width', () => {
    expect(r.dragging).toBe(true);
    near(r.dragged.menu.width - r.before.menu.width, 128, 2);
    expect(r.dragged.handleOff).toBeLessThanOrEqual(1);
    expect(Number(r.dragged.stored)).toBeCloseTo(r.dragged.width, 1);
  });

  test('gives the three panes one width', () => {
    expect(r.work.menu.width).toBe(r.dragged.menu.width);
    expect(r.files.menu.width).toBe(r.dragged.menu.width);
  });

  test('gives the conversation the whole row with the side column hidden, and the width back after', () => {
    expect(r.hidden.menu.shown).toBe(false);
    expect(r.hidden.handle.shown).toBe(false);
    near(r.hidden.main.width, r.dragged.main.width + r.dragged.menu.width);
    expect(r.back.menu.width).toBe(r.dragged.menu.width);
  });

  test('takes turns at full width below 768 px, with no border, and is side by side at 768', () => {
    expect(r.narrow.handle.shown).toBe(false);
    expect(r.narrow.main.shown !== r.narrow.menu.shown).toBe(true);
    expect(r.at768.handle.shown).toBe(true);
    expect(r.at768.main.shown && r.at768.menu.shown).toBe(true);
  });

  test('never makes the side column too narrow for its tabs, nor the conversation too narrow', () => {
    expect(r.narrowest.tabsCut).toEqual([0, 0, 0, 0]);
    expect(r.narrowest.handleOff).toBeLessThanOrEqual(1);
    // The side column at least 24rem, the conversation at least 22rem.
    expect(r.narrowest.menu.width).toBeGreaterThanOrEqual(24 * r.narrowest.rem - 1);
    expect(r.widest.main.width).toBeGreaterThanOrEqual(22 * r.widest.rem - 1);
    expect(r.widest.handleOff).toBeLessThanOrEqual(1);
  });

  test('fits the Files tab in the narrowest side column: its search row, its selection band, nothing sticking out', () => {
    expect(r.narrowest.findCut).toBe(0);
    expect(r.narrowest.paneCut).toBe(0);
  });

  test('opens a row\'s menu inside the window and over everything, also for the last row', () => {
    expect(r.menu.left).toBeGreaterThanOrEqual(0);
    expect(r.menu.right).toBeLessThanOrEqual(r.menu.w);
    expect(r.menu.top).toBeGreaterThanOrEqual(0);
    expect(r.menu.bottom).toBeLessThanOrEqual(r.menu.h);
    expect(r.menu.onTop).toBe(true);
    // As wide as its words need, with them at its left.
    expect(r.menu.spare).toBeLessThan(100);
    expect(r.menu.indent).toBeLessThan(40);
  });

  test('says the width as drawn, and moves from it with one key press', () => {
    expect(r.narrowest.said).toBe(r.narrowest.drawnPct);
    expect(r.afterKey.menu.width).toBeGreaterThan(r.narrowest.menu.width);
    expect(r.afterKey.said).toBe(r.afterKey.drawnPct);
  });

  test('uses the kept width when the page loads again', () => {
    expect(r.reloaded.menu.width).toBe(r.back.menu.width);
  });
});
