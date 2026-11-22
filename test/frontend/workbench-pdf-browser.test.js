// A PDF in the work screen, in a real browser with the pinned pdf.js: one
// PDF is shown and let go, and the next is drawn (also when the first is let
// go while it loads). The browser is driven by support/workbench-pdf-browser.mjs
// in a child process. pdf.js is fetched into public/vendor when the image is
// built; without it this test does not run (and says so). With it, a run
// that does not finish is a failure.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const VENDOR = path.join(__dirname, '../../docker/services/ruby/public/vendor/pdfjs');
const hasPdfjs = fs.existsSync(path.join(VENDOR, 'pdf.min.mjs')) && fs.existsSync(path.join(VENDOR, 'pdf.worker.min.mjs'));

(hasPdfjs ? describe : describe.skip)('WorkbenchPdf with the pinned pdf.js in a browser', () => {
  let result;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/workbench-pdf-browser.mjs')], {
      encoding: 'utf8', timeout: 90000
    });
    // The run counts only when the child itself ended well (its browser and
    // server closed too), not on its result line alone.
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    result = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  test('draws the next PDF after the one before was drawn and let go', () => {
    const r = result.afterDrawn;
    expect(r.failed).toBeUndefined();
    expect(r.errors).toEqual([]);
    expect(r.rejections).toEqual([]);
    expect(r.shown).toMatchObject({ status: 'ready', page: 1, pages: 3 });
    expect(r.canvas[0]).toBeGreaterThan(0);
    expect(r.text).toContain('Page 1 of 3');
  });

  test('draws the next PDF when the one before is let go while it loads', () => {
    const r = result.whileLoading;
    expect(r.failed).toBeUndefined();
    expect(r.errors).toEqual([]);
    expect(r.rejections).toEqual([]);
    expect(r.shown).toMatchObject({ status: 'ready', page: 1, pages: 4 });
    expect(r.text).toContain('Page 1 of 4');
  });
});
