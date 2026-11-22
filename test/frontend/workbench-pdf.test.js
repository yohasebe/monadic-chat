/**
 * @jest-environment jsdom
 */
// A PDF in the work screen: pdf.js (a fake here, recording what it is
// asked, in the shape of the pinned one: getDocument returns a loading task
// with its promise and destroy, and the document has no destroy) draws one
// page at a time with its text layer, nothing in the PDF acts, and a
// document no longer shown is let go through its loading task.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);
const flush = async () => { for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0)); };

function fakeLibrary({ pages = 3, width = 600, height = 800, fails = false, failPage = null, held = {}, heldText = {},
  heldDoc = null, destroyFails = null } = {}) {
  const lib = {
    calls: { documents: [], renders: [], layers: [], destroyed: 0 },
    GlobalWorkerOptions: {},
    AnnotationMode: { DISABLE: 0, ENABLE: 1 },
    // Writes "PAGE n" into its container; a page whose text is held
    // (heldText[n] === null) writes when the test lets it go.
    TextLayer: class {
      constructor(options) {
        this.options = options;
        lib.calls.layers.push(options);
      }
      render() {
        const n = this.options.textContentSource.page;
        const write = () => {
          const span = document.createElement('span');
          span.textContent = heldText[n] === undefined ? `PAGE ${n}` : `OLD PAGE ${n}`;
          this.options.container.appendChild(span);
        };
        if (heldText[n] !== null) {
          write();
          return Promise.resolve();
        }
        return new Promise((resolve) => { heldText[n] = () => { write(); resolve(); }; });
      }
      cancel() { lib.calls.cancelled = (lib.calls.cancelled || 0) + 1; }
    },
    getDocument(options) {
      lib.calls.documents.push(options);
      // destroy: 'reject' returns a rejected promise, 'throw' throws.
      const destroy = () => {
        lib.calls.destroyed += 1;
        if (destroyFails === 'throw') throw new Error('destroy failed');
        return destroyFails === 'reject' ? Promise.reject(new Error('destroy failed')) : Promise.resolve();
      };
      if (fails) return { promise: Promise.reject(new Error('Invalid PDF')), destroy };
      const doc = {
        numPages: pages,
        getPage: (n) => Promise.resolve({
          number: n,
          getViewport: ({ scale }) => ({ width: width * scale, height: height * scale, scale }),
          render: (params) => {
            lib.calls.renders.push(Object.assign({ page: n }, params));
            if (n === failPage) return { promise: Promise.reject(new Error('bad page')), cancel: () => {} };
            // A page held is drawn when the test lets it go (held[n]()).
            if (held[n] === null) return { promise: new Promise((resolve, reject) => { held[n] = { resolve, reject }; }), cancel: () => {} };
            return { promise: Promise.resolve(), cancel: () => {} };
          },
          streamTextContent: () => ({ page: n })
        })
      };
      // A document held arrives when the test lets it go (heldDoc.arrive()).
      if (heldDoc) return { promise: new Promise((resolve) => { heldDoc.arrive = () => resolve(doc); }), destroy };
      return { promise: Promise.resolve(doc), destroy };
    }
  };
  return lib;
}

describe('WorkbenchPdf', () => {
  let box;

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = '<div id="box"></div>';
    box = document.getElementById('box');
    HTMLCanvasElement.prototype.getContext = () => ({});
    delete global.webUIi18n;
    require(js('monadic/workbench-pdf.js'));
  });

  function showWith(lib, bytes = new ArrayBuffer(8)) {
    window.WorkbenchPdf.loader = () => Promise.resolve(lib);
    return window.WorkbenchPdf.show(box, bytes);
  }

  test('draws the first page from the bundled pdf.js, with its text layer and nothing in the PDF acting', async () => {
    const lib = fakeLibrary();
    const handle = showWith(lib);
    await flush();
    expect(lib.GlobalWorkerOptions.workerSrc).toBe('/vendor/pdfjs/pdf.worker.min.mjs');
    expect(lib.calls.documents[0]).toMatchObject({
      cMapUrl: '/vendor/pdfjs/cmaps/', cMapPacked: true, standardFontDataUrl: '/vendor/pdfjs/standard_fonts/',
      wasmUrl: '/vendor/pdfjs/wasm/', iccUrl: '/vendor/pdfjs/iccs/', enableXfa: false, enableScripting: false, isEvalSupported: false
    });
    expect(lib.calls.documents[0].data).toBeInstanceOf(Uint8Array);
    expect(lib.calls.renders).toHaveLength(1);
    expect(lib.calls.renders[0]).toMatchObject({ page: 1, annotationMode: lib.AnnotationMode.DISABLE });
    expect(lib.calls.layers[0].container).toBe(box.querySelector('.textLayer'));
    expect(box.querySelector('.textLayer').style.visibility).toBe('');
    expect(box.querySelector('.workbench-pdf-where').textContent).toBe('Page 1 of 3');
    expect(handle.state()).toMatchObject({ page: 1, pages: 3 });
  });

  test('moves between pages with its buttons and the arrow keys, and stops at the ends', async () => {
    const lib = fakeLibrary();
    const handle = showWith(lib);
    await flush();
    expect(box.querySelector('.workbench-pdf-prev').disabled).toBe(true);
    box.querySelector('.workbench-pdf-next').click();
    await flush();
    box.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    await flush();
    expect(handle.state().page).toBe(3);
    expect(box.querySelector('.workbench-pdf-next').disabled).toBe(true);
    box.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    await flush();
    expect(lib.calls.renders.map((r) => r.page)).toEqual([1, 2, 3]);
  });

  test('zooms within its limits, and keeps a canvas under its pixel limit', async () => {
    const lib = fakeLibrary({ width: 5000, height: 5000 });
    const handle = showWith(lib);
    await flush();
    const before = handle.state().scale;
    box.querySelector('.workbench-pdf-in').click();
    await flush();
    expect(handle.state().scale).toBeCloseTo(before * 1.25);
    for (let i = 0; i < 20; i += 1) box.querySelector('.workbench-pdf-in').click();
    await flush();
    expect(handle.state().scale).toBe(4);
    const canvas = box.querySelector('canvas');
    expect(canvas.width * canvas.height).toBeLessThanOrEqual(4096 * 4096);
  });

  describe('lets the document go when it is no longer shown', () => {
    test('before pdf.js is loaded: the document is never asked for', async () => {
      const lib = fakeLibrary();
      let arrive;
      window.WorkbenchPdf.loader = () => new Promise((resolve) => { arrive = () => resolve(lib); });
      const handle = window.WorkbenchPdf.show(box, new ArrayBuffer(8));
      handle.dispose();
      arrive();
      await flush();
      expect(lib.calls.documents).toHaveLength(0);
      expect(lib.calls.destroyed).toBe(0);
      expect(box.textContent).not.toContain('could not be shown');
    });

    test('while the document loads: its loading task goes, and what arrives later draws nothing', async () => {
      const heldDoc = {};
      const lib = fakeLibrary({ heldDoc: heldDoc });
      const handle = showWith(lib);
      await flush();
      handle.dispose();
      expect(lib.calls.destroyed).toBe(1);
      heldDoc.arrive();
      await flush();
      expect(lib.calls.renders).toHaveLength(0);
      expect(box.textContent).not.toContain('could not be shown');
    });

    test('while a page draws: the drawing stops, and its end changes nothing', async () => {
      const held = { 1: null };
      const lib = fakeLibrary({ held: held });
      const changes = [];
      window.WorkbenchPdf.loader = () => Promise.resolve(lib);
      const handle = window.WorkbenchPdf.show(box, new ArrayBuffer(8), (shown) => changes.push(shown.status));
      await flush();
      handle.dispose();
      expect(lib.calls.destroyed).toBe(1);
      held[1].resolve();
      await flush();
      expect(changes).toEqual(['drawing']);
      expect(box.querySelector('.textLayer')).toBeNull();
    });

    test('once, however often it is asked', async () => {
      const lib = fakeLibrary();
      const handle = showWith(lib);
      await flush();
      handle.dispose();
      handle.dispose();
      expect(lib.calls.destroyed).toBe(1);
    });

    test.each(['reject', 'throw'])('when letting it go fails (%s), the next PDF is still drawn', async (how) => {
      // pdf.js is loaded once for the page: the next PDF uses the same one.
      const lib = fakeLibrary({ destroyFails: how });
      const handle = showWith(lib);
      await flush();
      expect(() => handle.dispose()).not.toThrow();
      const next = showWith(lib);
      await flush();
      expect(lib.calls.documents).toHaveLength(2);
      expect(next.shown()).toMatchObject({ status: 'ready', page: 1, pages: 3 });
    });
  });

  test('says what is drawn only once a page and its text layer are drawn', async () => {
    const changes = [];
    const lib = fakeLibrary();
    window.WorkbenchPdf.loader = () => Promise.resolve(lib);
    const handle = window.WorkbenchPdf.show(box, new ArrayBuffer(8), (shown) => changes.push(shown.status));
    expect(handle.shown()).toEqual({ status: 'loading' });
    await flush();
    const first = handle.shown();
    expect(first).toEqual({ status: 'ready', page: 1, pages: 3, scale: 1, drawing: expect.any(Number) });
    expect(handle.canvas()).toBe(box.querySelector('canvas'));
    expect(handle.textLayer()).toBe(box.querySelector('.textLayer'));
    box.querySelector('.workbench-pdf-next').click();
    expect(handle.state().page).toBe(2);
    expect(handle.shown()).toEqual({ status: 'drawing' });
    await flush();
    expect(handle.shown()).toMatchObject({ status: 'ready', page: 2 });
    expect(handle.shown().drawing).toBeGreaterThan(first.drawing);
    expect(changes).toEqual(['drawing', 'ready', 'drawing', 'ready']);
  });

  test('does not say a page failed for a drawing a newer one replaced', async () => {
    const held = { 2: null };
    const lib = fakeLibrary({ held: held });
    const handle = showWith(lib);
    await flush();
    box.querySelector('.workbench-pdf-next').click();
    await flush();
    box.querySelector('.workbench-pdf-next').click();
    await flush();
    expect(handle.shown()).toMatchObject({ status: 'ready', page: 3 });
    held[2].reject(new Error('late failure'));
    await flush();
    expect(handle.shown()).toMatchObject({ status: 'ready', page: 3 });
  });

  test('shows only the text of the page drawn last, and stops the text of the page before', async () => {
    const heldText = { 1: null };
    const lib = fakeLibrary({ heldText: heldText });
    const handle = showWith(lib);
    await flush();
    box.querySelector('.workbench-pdf-next').click();
    await flush();
    expect(handle.shown()).toMatchObject({ status: 'ready', page: 2 });
    heldText[1]();
    await flush();
    const shownText = Array.from(box.querySelectorAll('.textLayer')).map((layer) => layer.textContent);
    expect(shownText).toEqual(['PAGE 2']);
    expect(lib.calls.cancelled).toBe(1);
  });

  test('says a page failed', async () => {
    const other = showWith(fakeLibrary({ failPage: 2 }));
    await flush();
    box.querySelector('.workbench-pdf-next').click();
    await flush();
    expect(other.shown()).toEqual({ status: 'failed' });
  });

  test('says so when the PDF cannot be read', async () => {
    showWith(fakeLibrary({ fails: true }));
    await flush();
    expect(box.textContent).toContain('could not be shown');
  });

  describe('following the pane\'s width', () => {
    let watched;
    let width;
    beforeEach(() => {
      watched = [];
      width = 600;
      Object.defineProperty(box, 'clientWidth', { configurable: true, get: () => width });
      global.ResizeObserver = class {
        constructor(callback) { this.callback = callback; watched.push(this); }
        observe() {}
        disconnect() { this.gone = true; }
      };
      jest.resetModules();
      require(js('monadic/workbench-pdf.js'));
    });
    afterEach(() => {
      delete global.ResizeObserver;
      jest.useRealTimers();
    });
    const resized = (to) => { width = to; watched.forEach((w) => w.callback([])); };
    const settleTimers = async (ms) => { jest.advanceTimersByTime(ms); jest.useRealTimers(); await flush(); };

    test('fits the page shown to the new width once it stays, keeping the page', async () => {
      const lib = fakeLibrary({ width: 600 });
      const handle = showWith(lib);
      await flush();
      expect(handle.state().scale).toBe(1);
      box.querySelector('.workbench-pdf-next').click();
      await flush();
      jest.useFakeTimers();
      resized(400);
      resized(300);
      jest.advanceTimersByTime(100);
      expect(lib.calls.renders).toHaveLength(2);
      await settleTimers(100);
      expect(lib.calls.renders).toHaveLength(3);
      expect(handle.state()).toMatchObject({ page: 2, scale: 0.5 });
    });

    test('keeps the scale the user zoomed to', async () => {
      const lib = fakeLibrary({ width: 600 });
      const handle = showWith(lib);
      await flush();
      box.querySelector('.workbench-pdf-in').click();
      await flush();
      const zoomed = handle.state().scale;
      jest.useFakeTimers();
      resized(300);
      await settleTimers(500);
      expect(handle.state().scale).toBe(zoomed);
      expect(lib.calls.renders).toHaveLength(2);
    });

    test('fits nothing when the pane is hidden before the wait is over', async () => {
      const lib = fakeLibrary({ width: 600 });
      showWith(lib);
      await flush();
      jest.useFakeTimers();
      resized(300);
      jest.advanceTimersByTime(50);
      resized(0);
      await settleTimers(500);
      expect(lib.calls.renders).toHaveLength(1);
    });

    test('changes nothing for a hidden pane, and stops watching once let go', async () => {
      const lib = fakeLibrary({ width: 600 });
      const handle = showWith(lib);
      await flush();
      jest.useFakeTimers();
      resized(0);
      await settleTimers(500);
      expect(lib.calls.renders).toHaveLength(1);
      handle.dispose();
      expect(watched[0].gone).toBe(true);
      jest.useFakeTimers();
      resized(300);
      await settleTimers(500);
      expect(lib.calls.renders).toHaveLength(1);
    });
  });
});

describe('a PDF item in the workbench', () => {
  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `
      <div id="workbench-status"></div>
      <div id="workbench-items" hidden></div>
      <div id="work-screen-browser"></div>
      <div id="workbench-view" hidden></div>`;
    window.LayoutController = { isMenuHidden: () => false, setMenuHidden: jest.fn(), selectedPane: () => 'work', setPane: jest.fn() };
    window.WorkScreen = { refresh: jest.fn() };
    window.safeWsSend = jest.fn();
    window.SessionState = { getMessages: () => [] };
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench.js'));
  });

  afterEach(() => {
    delete global.fetch;
    delete window.WorkbenchPdf;
  });

  test('takes the bytes from its address, and lets the document go when another item is shown', async () => {
    const shown = [];
    const disposed = [];
    window.WorkbenchPdf = {
      show: (box, bytes) => { shown.push(bytes.byteLength); return { dispose: () => disposed.push(true), state: () => ({}) }; }
    };
    global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(12) }));
    const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'paper.pdf', path: 'paper.pdf', preview: 'pdf',
      sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
    const notes = { id: 'i_t', kind: 'file', actor: 'user', name: 'a.txt', path: 'a.txt', preview: 'text',
      sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };
    const board = (revision) => ({ board_id: 'b1', chat_id: 'c_1', revision: revision, items: [paper, notes] });
    window.Workbench.onView({ board: board(1), approvals: {}, assets: { i_p: '/workbench/asset/p', i_t: '/workbench/asset/t' }, selected: 'i_p' });
    await flush();
    expect(global.fetch).toHaveBeenCalledWith('/workbench/asset/p', expect.anything());
    expect(shown).toEqual([12]);
    window.Workbench.select('i_t');
    await flush();
    expect(disposed).toHaveLength(1);
  });
});
