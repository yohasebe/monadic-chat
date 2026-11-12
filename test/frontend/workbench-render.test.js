/**
 * @jest-environment jsdom
 */
// What the work screen draws of a text file, apart from the browser:
// tables are read with quotes and quoted line ends and cut at their limits;
// a page keeps listed tags and attributes only, under a policy set first;
// Markdown keeps data: images and outside links only; a diagram's own
// settings are refused before Mermaid sees them.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public', f);

describe('WorkbenchRender', () => {
  let R;

  beforeAll(() => {
    window.DOMPurify = require(js('vendor/js/purify.min.js'));
    window.markdownit = require(js('vendor/js/markdown-it.min.js'));
    window.hljs = require(js('vendor/js/highlight.min.js'));
    require(js('js/monadic/text-utils.js'));
  });

  beforeEach(() => {
    jest.resetModules();
    R = require(js('js/monadic/workbench-render.js'));
  });

  describe('a table', () => {
    test('reads quotes, doubled quotes and line ends inside quotes', () => {
      const { rows, cut } = R.parseTable('a,"b,c","say ""hi"""\r\n1,"two\nlines",3\n', ',');
      expect(rows).toEqual([['a', 'b,c', 'say "hi"'], ['1', 'two\nlines', '3']]);
      expect(cut).toBe(false);
    });

    test('stops at 2000 records and 50 fields, and says so', () => {
      const wide = Array.from({ length: 60 }, (_, i) => `c${i}`).join('\t');
      const { rows, cut } = R.parseTable(`${wide}\n${'x\n'.repeat(2500)}`, '\t');
      expect(rows).toHaveLength(2000);
      expect(rows[0]).toHaveLength(50);
      expect(cut).toBe(true);
    });

    test('is drawn with text only, the first row as the header', async () => {
      const box = document.createElement('div');
      await R.draw(box, 'table', 'name,<b>x</b>\nAda,<img src=x onerror=alert(1)>\n', { name: 't.csv' }).done;
      expect(Array.from(box.querySelectorAll('th')).map((c) => c.textContent)).toEqual(['name', '<b>x</b>']);
      expect(box.querySelector('td + td').textContent).toBe('<img src=x onerror=alert(1)>');
      expect(box.querySelector('img, b')).toBeNull();
    });
  });

  describe('a page', () => {
    const page = (html) => {
      const out = R.pageDocument(html);
      const doc = new DOMParser().parseFromString(out, 'text/html');
      return { out, doc };
    };

    test('puts the policy first in a head it makes, and keeps no way to load or move', () => {
      const { out, doc } = page('<html><head><base href="https://x.invalid/"><meta http-equiv="refresh" content="0;url=https://x.invalid/">' +
        '<link rel="stylesheet" href="https://x.invalid/s.css"><style>p{color:red}</style></head><body>' +
        '<p>hi <a href="https://x.invalid/a">link</a></p><map><area href="https://x.invalid/m"></map>' +
        '<svg><a xlink:href="https://x.invalid/s"><text>t</text></a></svg><math><mi>x</mi></math>' +
        '<form action="https://x.invalid/f"><input name="q"><button formaction="https://x.invalid/b">go</button></form>' +
        '<iframe src="https://x.invalid/i"></iframe><object data="https://x.invalid/o"></object>' +
        '<video poster="https://x.invalid/p"></video><table background="https://x.invalid/t"><tr><td>c</td></tr></table>' +
        '<script>fetch("https://x.invalid/js")</script><p onclick="alert(1)" style="color:blue">s</p></body></html>');
      expect(out.startsWith('<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy"')).toBe(true);
      expect(doc.head.querySelectorAll('meta')).toHaveLength(2);
      expect(doc.querySelector('meta[http-equiv="Content-Security-Policy"]').content)
        .toBe("default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; base-uri 'none'; form-action 'none'");
      expect(doc.querySelectorAll('base, link, a, area, map, svg, math, form, input, button, iframe, object, video, script')).toHaveLength(0);
      expect(out).not.toMatch(/x\.invalid/);
      expect(out).not.toMatch(/onclick|href|formaction|poster|background=/i);
      expect(doc.body.textContent).toContain('hi link');
      expect(doc.querySelector('style').textContent).toBe('p{color:red}');
      expect(doc.querySelector('p[style]').getAttribute('style')).toBe('color:blue');
    });

    test('drops CSS that could load something, in any spelling it could take', () => {
      const { out, doc } = page('<style>p{background:url(https://x.invalid/a)}</style><style>@import "https://x.invalid/b";</style>' +
        '<style>p{background:\\75rl(https://x.invalid/c)}</style><style>q{color:green}</style>' +
        '<p style="background-image:image-set(\'https://x.invalid/d\' 1x)">a</p><p style="background:URL(https://x.invalid/e)">b</p>');
      expect(out).not.toMatch(/x\.invalid/);
      expect(Array.from(doc.querySelectorAll('style')).map((s) => s.textContent)).toEqual(['q{color:green}']);
      expect(doc.querySelectorAll('p[style]')).toHaveLength(0);
    });

    test('keeps images only as data: images of image types, and their text otherwise', () => {
      const png = 'data:image/png;base64,iVBORw0KGgo=';
      const { doc } = page(`<img src="${png}" alt="ok"><img src="https://x.invalid/i.png" alt="far">` +
        '<img src="data:image/svg+xml;base64,PHN2Zy8+" alt="svg"><img src="/workbench/asset/t" alt="here">' +
        `<img src="${png}" srcset="https://x.invalid/s.png 2x" alt="set">`);
      const imgs = doc.querySelectorAll('img');
      expect(Array.from(imgs).map((i) => i.getAttribute('alt'))).toEqual(['ok', 'set']);
      expect(imgs[1].hasAttribute('srcset')).toBe(false);
      expect(doc.body.textContent).toContain('far');
      expect(doc.body.textContent).toContain('here');
    });

    test('is shown in a frame with no permission, given as a property', async () => {
      const box = document.createElement('div');
      await R.draw(box, 'html', '<p>hi</p>').done;
      const frame = box.querySelector('iframe');
      expect(frame.getAttribute('sandbox')).toBe('');
      expect(frame.srcdoc).toContain('<p>hi</p>');
      expect(frame.getAttribute('referrerpolicy')).toBe('no-referrer');
    });
  });

  describe('Markdown', () => {
    test('keeps outside links (opened without a referrer) and data: images, and no raw HTML', async () => {
      const box = document.createElement('div');
      const png = 'data:image/png;base64,iVBORw0KGgo=';
      await R.draw(box, 'markdown', `# T\n\n<b onclick="x()">raw</b> [out](https://example.com) [js](javascript:alert(1)) ` +
        `[rel](notes.md)\n\n![a](${png}) ![b](https://x.invalid/b.png)`).done;
      expect(box.querySelector('h1').textContent).toBe('T');
      expect(box.querySelector('b')).toBeNull();
      const links = box.querySelectorAll('a');
      expect(Array.from(links).map((a) => a.getAttribute('href'))).toEqual(['https://example.com']);
      expect(links[0].getAttribute('rel')).toBe('noopener noreferrer');
      expect(links[0].getAttribute('referrerpolicy')).toBe('no-referrer');
      expect(Array.from(box.querySelectorAll('img')).map((i) => i.getAttribute('src'))).toEqual([png]);
      expect(box.textContent).toContain('[image: b]');
      // Raw HTML and refused links stay as text; no element carries them.
      expect(box.textContent).toContain('<b onclick');
      expect(box.querySelectorAll('[onclick], [href^="javascript"], [src*="x.invalid"]')).toHaveLength(0);
    });

    test('leaves the chat\'s sanitizer as it was', async () => {
      const before = window.DOMPurify.sanitize('<a href="https://example.com" style="color:red">x</a>');
      await R.draw(document.createElement('div'), 'markdown', '[x](https://example.com)').done;
      expect(window.DOMPurify.sanitize('<a href="https://example.com" style="color:red">x</a>')).toBe(before);
    });
  });

  describe('code', () => {
    test('is highlighted by its extension, each line standing alone', () => {
      expect(R.codeLanguage('scripts/run.py')).toBe('py');
      expect(R.codeLanguage('notes.txt')).toBeNull();
      expect(R.codeLanguage('data.csv')).toBeNull();
      const text = 'def f():\n    """two\n    lines"""\n    return 1';
      const lines = R.highlightedLines(text, 'py');
      expect(lines).toHaveLength(4);
      // Each line is whole: every span it opens is closed, and its text is the line's.
      lines.forEach((html, i) => {
        const li = document.createElement('li');
        li.innerHTML = html;
        expect(li.textContent).toBe(text.split('\n')[i]);
        expect((html.match(/<span/g) || []).length).toBe((html.match(/<\/span>/g) || []).length);
      });
      expect(lines[0]).toContain('hljs-keyword');
      // The string that runs over lines is a string on both.
      expect(lines[1]).toContain('hljs-string');
      expect(lines[2]).toContain('hljs-string');
    });

    test('escapes what it shows and leaves text it cannot highlight alone', () => {
      const lines = R.highlightedLines('x = "<img src=x onerror=alert(1)>"', 'py');
      const li = document.createElement('li');
      li.innerHTML = lines[0];
      expect(li.querySelector('img')).toBeNull();
      expect(R.highlightedLines('text', null)).toBeNull();
      expect(R.highlightedLines('text', 'no-such-language')).toBeNull();
    });
  });

  describe('a Jupyter notebook', () => {
    const PNG = 'iVBORw0KGgo=';
    const notebook = (cells) => JSON.stringify({ nbformat: 4, nbformat_minor: 5, metadata: {}, cells });
    const draw = async (cells) => {
      const box = document.createElement('div');
      await R.draw(box, 'notebook', typeof cells === 'string' ? cells : notebook(cells), { name: 'n.ipynb' }).done;
      return box;
    };

    test('shows its cells in order: Markdown drawn, code with its run number, and what each run showed', async () => {
      const box = await draw([
        { cell_type: 'markdown', source: ['# Title\n', 'Some **words**'] },
        { cell_type: 'code', execution_count: 3, source: 'print("hi")', outputs: [
          { output_type: 'stream', name: 'stdout', text: ['hi\n'] },
          { output_type: 'display_data', data: { 'image/png': PNG, 'text/plain': '<Figure>' } },
          { output_type: 'execute_result', data: { 'text/plain': ['42'] } }
        ] },
        { cell_type: 'raw', source: 'raw text' }
      ]);
      const cells = box.querySelectorAll('.workbench-nb-cell');
      expect(cells).toHaveLength(3);
      expect(cells[0].querySelector('h1').textContent).toBe('Title');
      expect(cells[0].querySelector('strong').textContent).toBe('words');
      expect(cells[1].querySelector('.workbench-nb-prompt').textContent).toBe('[3]');
      expect(cells[1].querySelector('.workbench-nb-source').textContent).toBe('print("hi")');
      expect(cells[1].querySelector('.workbench-nb-source .hljs-built_in, .workbench-nb-source .hljs-string')).not.toBeNull();
      const outputs = Array.from(cells[1].querySelectorAll('.workbench-nb-stream'), (o) => o.textContent);
      expect(outputs).toEqual(['hi\n', '42']);
      // The image is shown, not its text form.
      expect(cells[1].querySelector('img.workbench-nb-image').getAttribute('src')).toBe(`data:image/png;base64,${PNG}`);
      expect(cells[1].textContent).not.toContain('<Figure>');
      expect(cells[2].textContent).toBe('raw text');
    });

    test('runs nothing: HTML outputs are made safe, and one that is only a script is said to be interactive', async () => {
      const box = await draw([{ cell_type: 'code', execution_count: 1, source: 'df', outputs: [
        { output_type: 'execute_result', data: { 'text/html': '<table><tr><td onclick="x()">1</td></tr></table><script>alert(1)</script>' } },
        { output_type: 'display_data', data: { 'text/html': '<div id="plot"></div><script>Plotly.newPlot("plot")</script>',
                                                'application/vnd.plotly.v1+json': {} } },
        { output_type: 'display_data', data: { 'application/vnd.jupyter.widget-view+json': {} } }
      ] }]);
      expect(box.querySelector('script')).toBeNull();
      expect(box.querySelector('td').textContent).toBe('1');
      expect(box.querySelector('td').hasAttribute('onclick')).toBe(false);
      const notes = Array.from(box.querySelectorAll('.workbench-nb-note'), (n) => n.textContent);
      expect(notes).toEqual(['An interactive output (not shown here).', 'An interactive output (not shown here).']);
    });

    test('shows an error\'s traceback without terminal colors', async () => {
      const box = await draw([{ cell_type: 'code', execution_count: 2, source: '1/0', outputs: [
        { output_type: 'error', ename: 'ZeroDivisionError', evalue: 'division by zero',
          traceback: ['\u001b[0;31mZeroDivisionError\u001b[0m: division by zero'] }
      ] }]);
      const error = box.querySelector('.workbench-nb-stderr');
      expect(error.textContent).toBe('ZeroDivisionError: division by zero');
    });

    test('says when a file is not a notebook it can read', async () => {
      for (const text of ['{ not json', JSON.stringify({ cells: 'no' })]) {
        const box = document.createElement('div');
        const handle = R.draw(box, 'notebook', text, { name: 'n.ipynb' });
        await expect(handle.done).rejects.toThrow('This notebook could not be read.');
      }
    });

    test('keeps an image that is not a data image of an image type out', async () => {
      const box = await draw([{ cell_type: 'markdown', source: '![x](https://example.com/x.png)' },
        { cell_type: 'code', execution_count: 1, source: '', outputs: [
          { output_type: 'display_data', data: { 'image/png': 'not base64 !' } }] }]);
      expect(box.querySelector('img')).toBeNull();
    });
  });

  describe('a diagram', () => {
    test('takes no settings of its own, and is not too long', () => {
      expect(R.diagramChecked('flowchart LR\nA-->B')).toBe('flowchart LR\nA-->B');
      expect(R.diagramChecked('%% note\nsequenceDiagram\nA->>B: hi')).toContain('sequenceDiagram');
      expect(() => R.diagramChecked('%%{init: {"securityLevel": "loose"}}%%\nflowchart LR\nA-->B')).toThrow(R.Refused);
      expect(() => R.diagramChecked('---\nconfig:\n  theme: dark\n---\nflowchart LR\nA-->B')).toThrow(R.Refused);
      expect(() => R.diagramChecked(`flowchart LR\n${'A-->B\n'.repeat(10000)}`)).toThrow(R.Refused);
    });
  });

  describe('a diagram\'s frame', () => {
    afterEach(() => {
      jest.useRealTimers();
      delete global.fetch;
      R._dropFrames();
    });

    test('that never says it is ready ends the drawing in time, and the next diagram makes a new frame', async () => {
      jest.useFakeTimers();
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, text: () => Promise.resolve('/* mermaid */') }));
      const flush = async () => { for (let i = 0; i < 10; i += 1) await Promise.resolve(); };
      const first = R.draw(document.createElement('div'), 'diagram', 'flowchart LR\nA-->B');
      await flush();
      const frames = () => document.querySelectorAll('iframe.workbench-diagram-frame');
      expect(frames()).toHaveLength(1);
      expect(frames()[0].getAttribute('sandbox')).toBe('allow-scripts');
      jest.advanceTimersByTime(15000);
      await expect(first.done).rejects.toThrow(/too long/);
      expect(frames()).toHaveLength(0);
      R.draw(document.createElement('div'), 'diagram', 'flowchart LR\nC-->D');
      await flush();
      expect(frames()).toHaveLength(1);
    });

    test('ends the drawing in time when Mermaid itself is not read', async () => {
      jest.useFakeTimers();
      const signals = [];
      global.fetch = jest.fn((url, options) => {
        signals.push(options.signal);
        return new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(new Error('aborted'))));
      });
      const handle = R.draw(document.createElement('div'), 'diagram', 'flowchart LR\nA-->B');
      for (let i = 0; i < 10; i += 1) await Promise.resolve();
      jest.advanceTimersByTime(15000);
      await expect(handle.done).rejects.toThrow(/too long/);
      // The read was ended, and the next diagram reads Mermaid again.
      expect(signals[0].aborted).toBe(true);
      R.draw(document.createElement('div'), 'diagram', 'flowchart LR\nC-->D');
      for (let i = 0; i < 10; i += 1) await Promise.resolve();
      expect(global.fetch).toHaveBeenCalledTimes(2);
    });
  });

  describe('a chart', () => {
    let workers;

    beforeEach(() => {
      workers = [];
      global.URL.createObjectURL = jest.fn(() => 'blob:chart');
      global.URL.revokeObjectURL = jest.fn();
      global.Worker = jest.fn(function FakeWorker(url, options) {
        this.url = url;
        this.options = options;
        this.listeners = {};
        this.posted = [];
        this.terminate = jest.fn();
        this.addEventListener = (type, fn) => { this.listeners[type] = fn; };
        this.removeEventListener = (type) => { delete this.listeners[type]; };
        this.postMessage = (data) => this.posted.push(data);
        workers.push(this);
      });
    });

    afterEach(() => {
      jest.useRealTimers();
      delete global.Worker;
    });

    test('is made in the module worker the server serves, and ends with it when it takes too long', async () => {
      jest.useFakeTimers();
      const first = R.draw(document.createElement('div'), 'vega_lite', '{}');
      await Promise.resolve();
      await Promise.resolve();
      expect(workers).toHaveLength(1);
      expect(workers[0].url).toBe('/vendor/vega/vega-worker.mjs');
      expect(workers[0].options).toEqual({ type: 'module' });
      expect(workers[0].posted).toEqual([{ id: expect.any(Number), text: '{}' }]);
      jest.advanceTimersByTime(10000);
      await expect(first.done).rejects.toThrow(/too long/);
      expect(workers[0].terminate).toHaveBeenCalled();
      // The next chart has a new worker.
      R.draw(document.createElement('div'), 'vega_lite', '{"a":1}');
      for (let i = 0; i < 5; i += 1) await Promise.resolve();
      expect(workers).toHaveLength(2);
    });

    test('takes only the answer to the chart asked, and says what the worker refused', async () => {
      const box = document.createElement('div');
      const handle = R.draw(box, 'vega_lite', '{}');
      for (let i = 0; i < 5; i += 1) await Promise.resolve();
      const worker = workers[0];
      const id = worker.posted[0].id;
      worker.listeners.message({ data: { id: id + 1, svg: '<svg/>' } });
      worker.listeners.message({ data: { id: id, error: '"url" is not taken', refused: true } });
      await expect(handle.done).rejects.toThrow(R.Refused);
      await expect(handle.done).rejects.toThrow('"url" is not taken');
      expect(box.querySelector('img')).toBeNull();
    });
  });

  test('refuses a kind it does not draw', async () => {
    await expect(R.draw(document.createElement('div'), 'pdf', 'x').done).rejects.toThrow(R.Refused);
  });
});
