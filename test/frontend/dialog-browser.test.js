// MonadicDialog (dialog.js) in a real browser, with the view's delete
// confirmation and the real stylesheets and scripts: opening (its name, its
// first control, the page's mark), every way of closing ending once (Esc,
// the backdrop but not a drag out of the panel, its buttons, close()
// refused), opening again while it closes, the focus going back, Easy
// Submit leaving Enter to it, a tooltip in it closed by the first Esc, and a
// dialog that only its buttons close. Driven by support/dialog-browser.mjs
// in a child process; a run that does not finish is a failure.
const path = require('path');
const { spawnSync } = require('child_process');

describe('Dialogs in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/dialog-browser.mjs')], { encoding: 'utf8', timeout: 90000 });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  test('closed, it is not shown and the page is not marked', () => {
    expect(r.closedAtStart.open).toBe(false);
    expect(r.closedAtStart.marked).toBe(false);
    expect(r.closedAtStart.panel.width).toBe(0);
  });

  test('opened, it is named by its title, its Cancel is focused, the page is marked, a panel of its width on its face over a backdrop', () => {
    const o = r.opened;
    expect(o.open).toBe(true);
    expect(o.marked).toBe(true);
    expect(o.named).toBe('Delete Message');
    expect(o.focused).toBe('Cancel');
    expect(o.log).toEqual(['deleteConfirmation mdialog:shown ']);
    expect(o.panel.width).toBeLessThanOrEqual(500);
    expect(o.panel.left).toBeGreaterThan(0);
    expect(o.panel.right).toBeLessThan(o.view.width);
    expect(o.face).not.toBe('rgba(0, 0, 0, 0)');
    expect(o.backdrop).not.toBe('rgba(0, 0, 0, 0)');
  });

  test('Enter goes to the dialog (its focused Cancel), not to the chat', () => {
    expect(r.enterInside.sent).toBe(0);
    expect(r.enterInside.open).toBe(false);
  });

  test('Esc closes it once, the focus going back to what opened it; then Enter is the chat\'s again', () => {
    expect(r.escaped.open).toBe(false);
    expect(r.escaped.marked).toBe(false);
    expect(r.escaped.focused).toBe('opener');
    expect(r.escaped.log.filter((l) => l.includes('hidden'))).toEqual(['deleteConfirmation mdialog:hidden esc']);
    expect(r.enterAfter.sent).toBe(1);
  });

  test('a press on the backdrop closes it; a drag from the panel out does not', () => {
    expect(r.dragged.open).toBe(true);
    expect(r.backdrop.open).toBe(false);
    expect(r.backdrop.log).toEqual(['deleteConfirmation mdialog:hide backdrop', 'deleteConfirmation mdialog:hidden backdrop']);
  });

  test('a closing refused leaves it open, without a hidden; its Cancel closes it', () => {
    expect(r.refused).toEqual({ closed: false, open: true });
    expect(r.refusedLook.log.some((l) => l.includes('hidden'))).toBe(false);
    expect(r.cancelled.open).toBe(false);
    expect(r.cancelled.focused).toBe('opener');
  });

  test('opened again while it closes, it opens once it has closed', () => {
    expect(r.reopened).toEqual({ closed: true, open: true });
    expect(r.reopenedLog.slice(0, 4)).toEqual([
      'deleteConfirmation mdialog:shown ', 'deleteConfirmation mdialog:hide button',
      'deleteConfirmation mdialog:hidden button', 'deleteConfirmation mdialog:shown '
    ]);
  });

  test('a tooltip in it is shown in it, and the first Esc closes only the tooltip', () => {
    expect(r.tooltip.inDialog).toBe('deleteConfirmation');
    expect(r.firstEsc).toEqual({ tip: false, open: true });
    expect(r.secondEsc).toEqual({ open: false });
  });

  test('a dialog only its buttons close stays open on Esc and the backdrop', () => {
    expect(r.staticKept.open).toBe(true);
    expect(r.staticClosed).toEqual({ open: false, marked: false });
  });
});
