/**
 * @jest-environment jsdom
 *
 * Display-compat golden tests and XSS-stripping tests for the model-output
 * sanitization path (see tmp/memo/xss_display_compat_audit.md):
 *
 *   MarkdownRenderer.render()  ->  sanitizeModelHtml()  (what createCard applies)
 *
 * Runs the REAL pipeline: vendored markdown-it + KaTeX + DOMPurify, the
 * real MarkdownRenderer, and the real html-sanitizer wrapper. The golden
 * section pins that every piece of intentional HTML the app emits survives
 * sanitization; the malicious section pins that injected markup does not.
 *
 * Skipped automatically when vendor bundles are absent (mirrors the
 * markdown-renderer-tts-codefence.test.js pattern).
 */

const PURIFY_PATH = '../../docker/services/ruby/public/vendor/js/purify.min.js';
const MARKDOWN_IT_PATH = '../../docker/services/ruby/public/vendor/js/markdown-it.min.js';
const KATEX_PATH = '../../docker/services/ruby/public/vendor/js/katex.min.js';
const TEXT_UTILS_PATH = '../../docker/services/ruby/public/js/monadic/text-utils.js';
const SANITIZER_PATH = '../../docker/services/ruby/public/js/monadic/html-sanitizer.js';
const RENDERER_PATH = '../../docker/services/ruby/public/js/monadic/markdown-renderer.js';

function vendorBundlesPresent() {
  try {
    require.resolve(PURIFY_PATH);
    require.resolve(MARKDOWN_IT_PATH);
    require.resolve(KATEX_PATH);
    return true;
  } catch (e) {
    return false;
  }
}
const describeFn = vendorBundlesPresent() ? describe : describe.skip;

describeFn('model-output sanitization pipeline (golden + XSS)', () => {
  let MarkdownRenderer;
  let sanitizeModelHtml;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;

    const markdownit = require(MARKDOWN_IT_PATH);
    window.markdownit = markdownit.default || markdownit;
    window.katex = require(KATEX_PATH);

    // Bind DOMPurify to the real jsdom window, not the setup.js mock.
    const createDOMPurify = require(PURIFY_PATH);
    window.DOMPurify = createDOMPurify(document.defaultView);

    require(TEXT_UTILS_PATH);
    sanitizeModelHtml = require(SANITIZER_PATH).sanitizeModelHtml;
    require(RENDERER_PATH);
    MarkdownRenderer = window.MarkdownRenderer;
    MarkdownRenderer._initMarkdownIt();
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
    delete window.markdownit;
    delete window.katex;
  });

  // Render markdown the way createCard does before innerHTML.
  function renderSanitized(text, options) {
    return sanitizeModelHtml(MarkdownRenderer.render(text, options));
  }

  function toDoc(html) {
    const div = document.createElement('div');
    div.innerHTML = html;
    return div;
  }

  // ── Golden: intentional HTML must survive ──────────────────────────

  describe('display compatibility (intentional HTML survives)', () => {
    test('plain markdown: paragraphs, emphasis, links', () => {
      const doc = toDoc(renderSanitized('Hello **world**, see [x](https://example.com).'));
      expect(doc.querySelector('p')).not.toBeNull();
      expect(doc.querySelector('strong').textContent).toBe('world');
      const a = doc.querySelector('a[href="https://example.com"]');
      expect(a).not.toBeNull();
      expect(a.getAttribute('target')).toBe('_blank');
      expect(a.getAttribute('rel')).toContain('noopener');
    });

    test('code block: pre > code.language-* survives', () => {
      const doc = toDoc(renderSanitized('```python\nprint("hi")\n```'));
      const code = doc.querySelector('pre > code.language-python');
      expect(code).not.toBeNull();
      expect(code.textContent).toContain('print("hi")');
    });

    test('KaTeX: span.katex + MathML annotation[encoding] survive', () => {
      const doc = toDoc(renderSanitized('Euler: $e^{i\\pi}+1=0$'));
      expect(doc.querySelector('span.katex')).not.toBeNull();
      const annotation = doc.querySelector('annotation[encoding="application/x-tex"]');
      expect(annotation).not.toBeNull();
      expect(annotation.textContent).toContain('e^{i\\pi}');
    });

    test('KaTeX display math ($$...$$) survives', () => {
      const doc = toDoc(renderSanitized('$$\\int_0^1 x^2 dx$$'));
      expect(doc.querySelector('span.katex-display')).not.toBeNull();
    });

    test('generated_image: div.generated_image > img with /data/ src survives', () => {
      const serverHtml = '<div class="generated_image"><img src="/data/abc123.png" /></div>' +
        '<div class="prompt"><b>Prompt</b>: a cat</div>';
      const doc = toDoc(sanitizeModelHtml(serverHtml));
      const img = doc.querySelector('div.generated_image > img');
      expect(img).not.toBeNull();
      expect(img.getAttribute('src')).toBe('/data/abc123.png');
      expect(doc.querySelector('div.prompt > b')).not.toBeNull();
    });

    test('generated image with inline style keeps the style attribute', () => {
      const serverHtml = '<img src="/data/x.png" style="max-width:100%; border-radius: 8px;">';
      const doc = toDoc(sanitizeModelHtml(serverHtml));
      const img = doc.querySelector('img');
      expect(img).not.toBeNull();
      expect(img.getAttribute('style')).toContain('max-width');
    });

    test('generated_video: video[controls] > source[src,type] survives', () => {
      const serverHtml = '<div class="generated_video">' +
        '<video controls width="600"><source src="/data/x.mp4" type="video/mp4" /></video></div>';
      const doc = toDoc(sanitizeModelHtml(serverHtml));
      const video = doc.querySelector('div.generated_video > video');
      expect(video).not.toBeNull();
      expect(video.hasAttribute('controls')).toBe(true);
      const source = video.querySelector('source');
      expect(source.getAttribute('src')).toBe('/data/x.mp4');
      expect(source.getAttribute('type')).toBe('video/mp4');
    });

    test('mc: citation link keeps href and data-mc-link', () => {
      const doc = toDoc(renderSanitized('[Conversation 42](mc:conv:abc-123)'));
      const a = doc.querySelector('a.mc-conv-link');
      expect(a).not.toBeNull();
      expect(a.getAttribute('href')).toBe('mc:conv:abc-123');
      expect(a.getAttribute('data-mc-link')).toBe('mc:conv:abc-123');
    });

    test('mermaid wrapper: div.mermaid-code > pre survives with source intact', () => {
      const doc = toDoc(renderSanitized('```mermaid\ngraph TD\n  A-->B\n```'));
      const pre = doc.querySelector('div.mermaid-code > pre');
      expect(pre).not.toBeNull();
      expect(pre.textContent).toContain('A-->B');
    });

    test('abc wrapper: div.abc-code > pre survives', () => {
      const doc = toDoc(renderSanitized('```abc\nX:1\nK:C\nC D E F|\n```'));
      expect(doc.querySelector('div.abc-code > pre')).not.toBeNull();
    });

    test('base64 image attachment (data:image URI) survives', () => {
      const doc = toDoc(sanitizeModelHtml(
        '<img class="base64-image mb-3" src="data:image/png;base64,iVBORw0KGgo=" alt="shot.png" style="max-width: 100%;">'
      ));
      const img = doc.querySelector('img.base64-image');
      expect(img).not.toBeNull();
      expect(img.getAttribute('src')).toMatch(/^data:image\/png;base64,/);
    });

    test('Monadic JSON tree markup survives (json-item/json-header/json-content)', () => {
      const html = MarkdownRenderer.render(
        JSON.stringify({ message: 'hi', context: { theme: 'cats' } }),
        { isMonadic: true }
      );
      const doc = toDoc(sanitizeModelHtml(html));
      expect(doc.querySelector('.json-item[data-key="context"]')).not.toBeNull();
      expect(doc.querySelector('.json-header')).not.toBeNull();
      expect(doc.querySelector('.json-content')).not.toBeNull();
      // Inline onclick must be gone; delegation (json-tree-toggle.js) handles clicks.
      expect(doc.querySelector('.json-header').hasAttribute('onclick')).toBe(false);
    });
  });

  // ── Malicious input must be neutralized ────────────────────────────

  describe('XSS stripping (malicious HTML does not survive)', () => {
    test('<script> tags are removed (raw HTML in markdown)', () => {
      const out = renderSanitized('text <script>alert(1)</script> more');
      expect(out).not.toContain('<script>');
      expect(out).not.toContain('alert(1)</script>');
    });

    test('img onerror handler is stripped', () => {
      const doc = toDoc(sanitizeModelHtml('<img src="/data/x.png" onerror="alert(1)">'));
      const img = doc.querySelector('img');
      expect(img).not.toBeNull();
      expect(img.hasAttribute('onerror')).toBe(false);
    });

    test('javascript: URIs are removed from links', () => {
      const doc = toDoc(sanitizeModelHtml('<a href="javascript:alert(1)">x</a>'));
      const a = doc.querySelector('a');
      if (a) {
        expect(a.getAttribute('href') || '').not.toMatch(/javascript:/i);
      }
    });

    test('KaTeX \\href with javascript: URI is neutralized (trust:true escape hatch)', () => {
      const out = renderSanitized('$\\href{javascript:alert(1)}{click}$');
      expect(out).not.toMatch(/href="javascript:/i);
    });

    test('<iframe>, <form>, <object>, <embed> are removed', () => {
      const out = sanitizeModelHtml(
        '<iframe src="https://evil.example"></iframe>' +
        '<form action="https://evil.example"><input name="q"></form>' +
        '<object data="x.swf"></object><embed src="x.swf">'
      );
      expect(out).not.toContain('<iframe');
      expect(out).not.toContain('<form');
      expect(out).not.toContain('<input');
      expect(out).not.toContain('<object');
      expect(out).not.toContain('<embed');
    });

    test('inline event handler attributes are stripped everywhere', () => {
      const doc = toDoc(sanitizeModelHtml(
        '<div onclick="alert(1)" onmouseover="alert(2)"><span onfocus="alert(3)" tabindex="0">t</span></div>'
      ));
      expect(doc.querySelector('[onclick]')).toBeNull();
      expect(doc.querySelector('[onmouseover]')).toBeNull();
      expect(doc.querySelector('[onfocus]')).toBeNull();
    });

    test('<script> inside SVG is removed', () => {
      const out = sanitizeModelHtml('<svg><script>alert(1)</script><circle r="10"/></svg>');
      expect(out).not.toContain('<script>');
    });

    test('attribute-injection via broken tag does not produce executable markup', () => {
      const out = sanitizeModelHtml('<img src="x" alt="\\"><script>alert(1)</script>">');
      expect(out).not.toContain('<script>');
    });
  });

  // ── Fail-closed fallback ───────────────────────────────────────────

  describe('DOMPurify-absent fallback', () => {
    test('falls back to full escaping and never passes unsanitized HTML', () => {
      const saved = window.DOMPurify;
      delete window.DOMPurify;
      try {
        const out = sanitizeModelHtml('<b>bold</b><script>alert(1)</script>');
        expect(out).not.toContain('<script>');
        expect(out).not.toContain('<b>');
        expect(out).toContain('&lt;b&gt;');
      } finally {
        window.DOMPurify = saved;
      }
    });
  });
});
