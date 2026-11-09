/**
 * @jest-environment jsdom
 */
// The PDF export prints a card's drawings (diagrams shown as images whose
// address belongs to the card) as images of their own, and a diagram not
// drawn (still drawing, or failed) as its source, shown: the print does not
// depend on the card staying on the page, and the card is not changed.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '../..');
const js = (f) => path.join(root, 'docker/services/ruby/public/js', f);

describe('PDF export of drawings', () => {
  let draws;

  function card(mid, sources) {
    const el = document.createElement('div');
    el.id = mid;
    el.innerHTML = '<div class="card-body"><div class="card-text"><p>Here:</p></div></div>';
    const text = el.querySelector('.card-text');
    sources.forEach((source) => {
      const placeholder = document.createElement('div');
      placeholder.className = 'mermaid-code';
      const pre = document.createElement('pre');
      pre.textContent = source;
      placeholder.appendChild(pre);
      text.appendChild(placeholder);
    });
    document.body.appendChild(el);
    return el;
  }

  // The print frame's document.
  function printed() {
    const frames = document.querySelectorAll('iframe');
    return frames[frames.length - 1].contentDocument;
  }

  // A pre that is shown: no hidden ancestor, not inside a placeholder.
  function shownSources(doc) {
    return Array.from(doc.querySelectorAll('pre')).filter((pre) => {
      for (let el = pre; el; el = el.parentElement) {
        if (el.style && el.style.display === 'none') return false;
        if (el.classList && el.classList.contains('mermaid-code')) return false;
      }
      return true;
    }).map((pre) => pre.textContent);
  }

  const settle = () => new Promise((r) => setTimeout(r, 0));

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `<script type="application/json" id="render-formats">${fs.readFileSync(
      path.join(root, 'docker/services/ruby/lib/monadic/render_formats.json'), 'utf8')}</script>`;
    global.TextEncoder = global.TextEncoder || require('util').TextEncoder;
    global.btoa = (binary) => Buffer.from(binary, 'binary').toString('base64');
    window.btoa = global.btoa;
    draws = [];
    // As the drawing part does: the image comes once the diagram is drawn;
    // a failure leaves none.
    window.WorkbenchRender = {
      draw: jest.fn((box, kind, text) => {
        const handle = { dispose: jest.fn(), svg: () => `<svg id="d">${text}</svg>` };
        if (text.includes('slow')) {
          handle.done = new Promise(() => {});
        } else if (text.includes('broken')) {
          handle.done = Promise.reject(new Error('Parse error'));
          handle.done.catch(() => {});
        } else {
          const img = document.createElement('img');
          img.className = 'workbench-svg';
          img.src = `blob:card-${draws.length}`;
          box.replaceChildren(img);
          handle.done = Promise.resolve();
        }
        draws.push(handle);
        return handle;
      })
    };
    window.SessionState = { getMessages: () => [{ mid: 'm1', role: 'assistant', text: 'x' }] };
    window.webUIi18n = undefined;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/text-utils.js'));
    require(js('monadic/render-registry.js'));
    require(js('monadic/pdf_export.js'));
  });

  afterEach(() => window.Renderers._reset());

  test('prints a drawn diagram as an image of its own, and one drawing or failed as its source, shown', async () => {
    const el = card('m1', ['flowchart LR\nA-->B', 'flowchart LR\nslow', 'flowchart LR\nbroken']);
    window.Renderers.apply(el);
    await settle();
    await settle();
    const before = el.querySelector('.card-text').innerHTML;
    window.exportConversationToPDF();
    const doc = printed();
    const imgs = doc.querySelectorAll('img');
    expect(imgs).toHaveLength(1);
    const src = imgs[0].getAttribute('src');
    expect(src.startsWith('data:image/svg+xml;base64,')).toBe(true);
    expect(Buffer.from(src.split(',')[1], 'base64').toString('utf8')).toBe('<svg id="d">flowchart LR\nA-->B</svg>');
    expect(shownSources(doc)).toEqual(['flowchart LR\nslow', 'flowchart LR\nbroken']);
    expect(doc.body.innerHTML).not.toContain('blob:card-');
    expect(doc.querySelectorAll('.mermaid-code, .render-wrap, .sourcecode-toggle, .alert-danger')).toHaveLength(0);
    // The card itself is as it was, and what was printed stays when it goes.
    expect(el.querySelector('.card-text').innerHTML).toBe(before);
    const html = doc.body.innerHTML;
    el.remove();
    await settle();
    expect(draws[0].dispose).toHaveBeenCalled();
    expect(printed().body.innerHTML).toBe(html);
  });

  test('prints a diagram not drawn at all (no drawing part) as its source, shown', () => {
    delete window.WorkbenchRender;
    card('m1', ['flowchart LR\nA-->B']);
    window.exportConversationToPDF();
    expect(shownSources(printed())).toEqual(['flowchart LR\nA-->B']);
  });
});
