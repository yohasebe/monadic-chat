// What the work screen draws of a text file, in a real browser with the
// pinned Mermaid and the built Vega worker: nothing a drawn file names
// reaches the network (each address points at the test server, which
// counts what arrives), scripts in a page do not run, and diagrams and
// charts of the kinds taken are drawn while the others are refused. Each
// layer of a page (the sanitizer, the policy, the frame) is also run alone.
// Driven by support/workbench-render-browser.mjs in a child process.
const path = require('path');
const { spawnSync } = require('child_process');

describe('WorkbenchRender in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/workbench-render-browser.mjs')], {
      encoding: 'utf8', timeout: 120000
    });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 150000);

  test('nothing a drawn file names reaches the network', () => {
    expect(r.probes).toEqual([]);
  });

  test('a page is shown in a frame with no permission, with no address left, and its scripts do not run', () => {
    expect(r.frames.page).toEqual({ sandbox: '', hasHref: false });
    expect(r.frames.pageReadable).toBe(false);
    expect(r.title).toBe('');
  });

  test('draws the diagrams taken, in Japanese too, and refuses settings inside one', () => {
    ['diagramFlow', 'diagramSequence', 'diagramClass', 'diagramSankey'].forEach((name) => {
      expect(r.drawn[name]).toEqual({ width: expect.any(Number), height: expect.any(Number) });
      expect(r.drawn[name].width).toBeGreaterThan(0);
    });
    expect(r.refused.diagramSettings).toMatch(/^refused/);
    // Which kinds there are is Mermaid's to say.
    expect(r.drawn.diagramSankey.width).toBeGreaterThan(0);
    expect(r.drawn.diagramGit.width).toBeGreaterThan(0);
    expect(r.refused.diagramUnknown).toMatch(/^refused: .*[Nn]o diagram type/);
  });

  test('draws charts from inline values, and refuses addresses, images, a second fold, too many views, signals and other functions', () => {
    expect(r.drawn.chartBar.width).toBeGreaterThan(0);
    expect(r.drawn.chartLine.width).toBeGreaterThan(0);
    expect(r.refused.chartUrl).toMatch(/^refused/);
    expect(r.refused.chartImage).toMatch(/^refused/);
    expect(r.refused.chartFold).toMatch(/fold may be used once/);
    expect(r.refused.chartFacet13).toMatch(/only filter/);
    expect(r.refused.chartRowColumn).toMatch(/16 views/);
    expect(r.refused.chartRepeatLayer).toMatch(/15 views/);
    expect(r.refused.chartFunction).toMatch(/"sequence" is not taken/);
    expect(r.refused.chartJson).toMatch(/not JSON/);
    expect(r.refused.chartSignal).toMatch(/"signal" is not taken/);
    expect(r.refused.chartNestedExpr).toMatch(/"sequence" is not taken/);
    expect(r.refused.chartBracketFacet).toMatch(/a field of the values as it is/);
    ['filterEqualExpr', 'filterRange', 'filterNested'].forEach((name) => expect(r.refused[name]).toMatch(/"sequence" is not taken/));
    ['filterEqualSignal', 'filterOneOf'].forEach((name) => expect(r.refused[name]).toMatch(/"signal" is not taken/));
    expect(r.drawn.filterPlain.width).toBeGreaterThan(0);
  });

  test('draws Markdown (its Mermaid block as a diagram) and SVG, and lets an image made for a drawing go with it', () => {
    expect(r.drawn.markdown.width).toBeGreaterThan(0);
    expect(r.drawn.svg.width).toBeGreaterThan(0);
    expect(r.releasedAfterDispose).toBe(true);
  });

  test('draws the diagrams of a chat card once, as images, and lets them go with the card', () => {
    expect(r.chat.wraps).toBe(2);
    expect(r.chat.images).toHaveLength(2);
    r.chat.images.forEach((width) => expect(width).toBeGreaterThan(0));
    expect(r.chat.downloads).toBe(2);
    expect(r.chat.releasedWithCard).toBe(true);
    // An image of its own (the PDF export's) still draws once the card is gone.
    expect(r.chat.ownImageWidth).toBeGreaterThan(0);
  });

  test('leaves no error on the page', () => {
    expect(r.errors).toEqual([]);
  });
});
