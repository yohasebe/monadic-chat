/**
 * @jest-environment jsdom
 */
// The kinds of content the page draws, from the table the server gives it,
// and the diagrams of the chat's cards: drawn once per placeholder, again
// only for a new source, and let go when the placeholder leaves the page.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '../..');
const js = (f) => path.join(root, 'docker/services/ruby/public/js', f);
// jsdom has no TextEncoder; browsers do.
global.TextEncoder = global.TextEncoder || require('util').TextEncoder;
// test/setup.js replaces btoa with a stub; this file needs the real one.
const realBtoa = (binary) => Buffer.from(binary, 'binary').toString('base64');
const TABLE = fs.readFileSync(path.join(root, 'docker/services/ruby/lib/monadic/render_formats.json'), 'utf8');

describe('Renderers', () => {
  let R;
  let draws;

  function card(source) {
    const el = document.createElement('div');
    el.className = 'card-text';
    el.innerHTML = '<div class="mermaid-code"><pre></pre></div>';
    el.querySelector('pre').textContent = source;
    document.body.appendChild(el);
    return el;
  }

  const settle = () => new Promise((r) => setTimeout(r, 0));

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `<script type="application/json" id="render-formats">${TABLE}</script>`;
    draws = [];
    window.WorkbenchRender = {
      KINDS: ['markdown', 'diagram', 'table', 'svg', 'html', 'vega_lite'],
      draw: jest.fn((box, kind, text) => {
        const handle = { kind, text, dispose: jest.fn(), svg: () => `<svg>${text}</svg>`, done: Promise.resolve() };
        if (text.includes('broken')) {
          handle.done = Promise.reject(new Error('<b>Parse error</b> on line 2'));
          handle.done.catch(() => {});
        }
        if (text.includes('slow')) {
          handle.done = new Promise((resolve, reject) => { handle.finish = resolve; handle.fail = reject; });
          handle.done.catch(() => {});
        }
        box.textContent = `drawn ${kind}`;
        draws.push(handle);
        return handle;
      })
    };
    delete window.RenderFormatsTable;
    global.btoa = realBtoa;
    window.btoa = realBtoa;
    R = require(js('monadic/render-registry.js'));
  });

  afterEach(() => R._reset());

  describe('the table', () => {
    test('is the one the server gives the page', () => {
      expect(R.formats()).toEqual(JSON.parse(TABLE));
    });

    test('names the kind of a file as the server does, for the same cases', () => {
      const cases = JSON.parse(fs.readFileSync(path.join(root, 'test/fixtures/render_format_cases.json'), 'utf8'));
      cases.forEach((c) => expect([c.name, R.forName(c.name)]).toEqual([c.name, c.id]));
    });

    test('has a way to draw every kind it names, and the chat draws the fence markdown-renderer.js makes', () => {
      const real = require(js('monadic/workbench-render.js'));
      R.formats().forEach((f) => expect(real.KINDS).toContain(f.id));
      expect(R.forFence('mermaid')).toBe('diagram');
      expect(R.forFence(' Mermaid ')).toBe('diagram');
      expect(R.forFence('python')).toBeNull();
      const renderer = fs.readFileSync(js('monadic/markdown-renderer.js'), 'utf8');
      expect(renderer).toContain('<div class="mermaid-code"><pre>');
    });

    test('is given to the page before its scripts', () => {
      const page = fs.readFileSync(path.join(root, 'docker/services/ruby/views/index.erb'), 'utf8');
      const tag = page.indexOf('<script type="application/json" id="render-formats"><%= Monadic::RenderFormats::FORMATS_JSON %></script>');
      expect(tag).toBeGreaterThan(0);
      expect(tag).toBeLessThan(page.indexOf('monadic.bundle.min.js'));
    });
  });

  describe('diagrams in the chat', () => {
    test('are drawn from their source, made plain, beside the hidden source with a switch', async () => {
      const el = card('flowchart LR\n  A[“start”] --> B[マーク]');
      R.apply(el);
      await settle();
      expect(draws).toHaveLength(1);
      expect(draws[0].kind).toBe('diagram');
      expect(draws[0].text).toBe('flowchart LR\n  A["start"] --> B[マーク]');
      const placeholder = el.querySelector('.mermaid-code');
      expect(placeholder.style.display).toBe('none');
      const toggle = el.querySelector('.sourcecode-toggle');
      expect(toggle.textContent).toContain('Toggle Mermaid Diagram');
      toggle.click();
      expect(placeholder.style.display).toBe('');
      expect(el.querySelector('.render-wrap .diagram').textContent).toBe('drawn diagram');
      expect(el.querySelector('.render-actions button').textContent).toBe('Download SVG');
    });

    test('are drawn once however often the card is drawn again, and again only for a new source', async () => {
      const el = card('flowchart LR\nA-->B');
      R.apply(el);
      R.apply(el);
      R.apply(el);
      await settle();
      expect(draws).toHaveLength(1);
      expect(el.querySelectorAll('.render-wrap')).toHaveLength(1);
      expect(el.querySelectorAll('.sourcecode-toggle')).toHaveLength(1);
      el.querySelector('.mermaid-code pre').textContent = 'flowchart LR\nC-->D';
      R.apply(el);
      await settle();
      expect(draws).toHaveLength(2);
      expect(draws[0].dispose).toHaveBeenCalled();
      expect(el.querySelectorAll('.render-wrap')).toHaveLength(1);
      expect(el.querySelectorAll('.sourcecode-toggle')).toHaveLength(1);
    });

    test('are let go when their card leaves the page, or when the page is reset', async () => {
      const one = card('flowchart LR\nA-->B');
      const two = card('flowchart LR\nC-->D');
      R.apply(document.body);
      await settle();
      expect(draws).toHaveLength(2);
      one.remove();
      await settle();
      expect(draws[0].dispose).toHaveBeenCalled();
      expect(draws[1].dispose).not.toHaveBeenCalled();
      // A card whose text is drawn anew (an edit): its old placeholder goes.
      two.innerHTML = '<div class="mermaid-code"><pre>flowchart LR\nE-->F</pre></div>';
      await settle();
      expect(draws[1].dispose).toHaveBeenCalled();
      R.apply(two);
      await settle();
      expect(draws).toHaveLength(3);
      document.body.innerHTML = '';
      await settle();
      expect(draws[2].dispose).toHaveBeenCalled();
    });

    test('say why one cannot be drawn, as text, and offer no download', async () => {
      const el = card('flowchart LR\nbroken');
      R.apply(el);
      await settle();
      await settle();
      const alert = el.querySelector('.render-wrap .alert-danger');
      expect(alert.textContent).toContain('Mermaid Syntax Error:');
      expect(alert.textContent).toContain('<b>Parse error</b> on line 2');
      expect(alert.querySelector('b')).toBeNull();
      expect(Array.from(el.querySelectorAll('.render-actions button')).map((b) => b.textContent)).toEqual(['Try again']);
    });

    test('keep the switch and the drawing beside a placeholder moved alone, and stay put with a card moved whole', async () => {
      const a = card('flowchart LR\nA-->B');
      const b = document.createElement('div');
      document.body.appendChild(b);
      R.apply(a);
      await settle();
      const placeholder = a.querySelector('.mermaid-code');
      b.appendChild(placeholder);
      await settle();
      expect(a.querySelector('.render-wrap')).toBeNull();
      expect(placeholder.previousElementSibling.className).toContain('sourcecode-toggle');
      expect(placeholder.nextElementSibling.className).toContain('render-wrap');
      expect(draws[0].dispose).not.toHaveBeenCalled();
      const c = document.createElement('div');
      document.body.appendChild(c);
      c.appendChild(b);
      R.apply(c);
      await settle();
      expect(draws).toHaveLength(1);
      expect(c.querySelectorAll('.render-wrap')).toHaveLength(1);
    });

    test('draw a failed diagram again only when the user asks, letting the failed one go', async () => {
      const el = card('flowchart LR\nbroken');
      R.apply(el);
      await settle();
      await settle();
      R.apply(el);
      await settle();
      expect(draws).toHaveLength(1);
      const retry = el.querySelector('.render-actions button');
      expect(retry.textContent).toBe('Try again');
      retry.click();
      await settle();
      expect(draws).toHaveLength(2);
      expect(draws[0].dispose).toHaveBeenCalled();
      expect(el.querySelectorAll('.render-wrap')).toHaveLength(1);
    });

    test('take nothing from a drawing finished after its source changed', async () => {
      const el = card('flowchart LR\nslow');
      R.apply(el);
      await settle();
      el.querySelector('.mermaid-code pre').textContent = 'flowchart LR\nslow other';
      R.apply(el);
      await settle();
      draws[0].finish();
      await settle();
      expect(el.querySelectorAll('.render-actions button')).toHaveLength(0);
      draws[1].finish();
      await settle();
      expect(el.querySelectorAll('.render-actions button')).toHaveLength(1);
    });

    test('give a drawn diagram as a data: URL of its own, and nothing while drawing or for a placeholder not drawn', async () => {
      const el = card('flowchart LR\nA-->B \u7D42');
      R.apply(el);
      await settle();
      const src = R.selfContainedSrc(el.querySelector('.mermaid-code'));
      expect(src.startsWith('data:image/svg+xml;base64,')).toBe(true);
      const decoded = Buffer.from(src.split(',')[1], 'base64').toString('utf8');
      expect(decoded).toBe('<svg>flowchart LR\nA-->B \u7D42</svg>');
      expect(R.selfContainedSrc(document.createElement('div'))).toBeNull();
      const slow = card('flowchart LR\nslow');
      R.apply(slow);
      await settle();
      expect(R.selfContainedSrc(slow.querySelector('.mermaid-code'))).toBeNull();
    });

    test('download the SVG the drawing shows', async () => {
      const el = card('flowchart LR\nA-->B');
      R.apply(el);
      await settle();
      const parts = [];
      const RealBlob = global.Blob;
      global.Blob = function CapturedBlob(content, options) {
        parts.push({ content, options });
        return new RealBlob(content, options);
      };
      global.URL.createObjectURL = jest.fn(() => 'blob:x');
      global.URL.revokeObjectURL = jest.fn();
      const clicked = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
      el.querySelector('.render-actions button').click();
      global.Blob = RealBlob;
      expect(clicked).toHaveBeenCalled();
      expect(parts).toEqual([{ content: ['<svg>flowchart LR\nA-->B</svg>'], options: { type: 'image/svg+xml;charset=utf-8' } }]);
      expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:x');
      clicked.mockRestore();
    });

    test('leave nothing behind when the drawing part is not loaded', () => {
      delete window.WorkbenchRender;
      const el = card('flowchart LR\nA-->B');
      R.apply(el);
      expect(el.querySelector('.render-wrap')).toBeNull();
      expect(el.querySelector('.mermaid-code').style.display).toBe('');
    });
  });
});
