/**
 * @jest-environment jsdom
 *
 * Tests for vocabulary substitution token (${TOKEN}) protection in
 * MarkdownRenderer.render().
 *
 * Unlike markdown-renderer.test.js (which deliberately runs without
 * markdown-it/katex to test pure helpers), this suite loads real
 * markdown-it and katex so the full placeholder pipeline is exercised.
 */

// Vendored UMD bundles (markdown-it, katex) are gitignored, so they are
// absent in CI. Skip these full-render suites when the bundles are missing;
// they run in full locally where the vendor files exist.
function vendorBundlesPresent() {
  try {
    require.resolve("../../docker/services/ruby/public/vendor/js/markdown-it.min.js");
    require.resolve("../../docker/services/ruby/public/vendor/js/katex.min.js");
    return true;
  } catch (e) {
    return false;
  }
}
const describeFn = vendorBundlesPresent() ? describe : describe.skip;

describeFn('MarkdownRenderer vocabulary token protection (${TOKEN})', () => {
  let MarkdownRenderer;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;

    // Provide real markdown-it and katex so render()/renderMarkdown() take
    // the full rendering path (placeholder extraction + restoration), not the
    // plain-text fallback. These libraries are vendored as browser UMD bundles
    // (not npm deps), so we require them by path; the UMD wrapper returns the
    // module export under jest's CommonJS context.
    const markdownit = require('../../docker/services/ruby/public/vendor/js/markdown-it.min.js');
    window.markdownit = markdownit.default || markdownit;
    window.katex = require('../../docker/services/ruby/public/vendor/js/katex.min.js');

    require('../../docker/services/ruby/public/js/monadic/markdown-renderer.js');
    MarkdownRenderer = window.MarkdownRenderer;

    // Force markdown-it initialization now so no test can silently pass via the
    // plain-text fallback path (which would skip the placeholder pipeline).
    MarkdownRenderer._initMarkdownIt();
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
    delete window.markdownit;
    delete window.katex;
  });

  test('sanity: markdown-it + katex are loaded (full render path, not fallback)', () => {
    const result = MarkdownRenderer.render('The formula $a+b$ here');
    // markdown-it wraps prose in <p>; the fallback path would not.
    expect(result).toContain('<p>');
    // Real inline math renders via katex.
    expect(result).toContain('katex');
  });

  test('${TODAY} in prose is preserved literally and not rendered as math', () => {
    const result = MarkdownRenderer.render('The date is ${TODAY} today.');
    expect(result).toContain('${TODAY}');
    expect(result).not.toContain('katex');
  });

  test('keeps ${TODAY} literal AND renders $a+b$ as math in the same message', () => {
    const result = MarkdownRenderer.render('The date is ${TODAY} and the formula $a+b$');
    expect(result).toContain('${TODAY}');
    expect(result).toContain('katex');
  });

  test('${SHARED} inside backticks stays literal in a <code> element', () => {
    const result = MarkdownRenderer.render('Use `${SHARED}` here.');
    expect(result).toContain('<code>');
    expect(result).toContain('${SHARED}');
    expect(result).not.toContain('katex');
  });

  test('two tokens in one sentence are both preserved with no math span between them', () => {
    const result = MarkdownRenderer.render('path ${SHARED} on ${TODAY}');
    expect(result).toContain('${SHARED}');
    expect(result).toContain('${TODAY}');
    expect(result).not.toContain('katex');
    // The literal sentence must be intact — the text between the two tokens
    // must not be consumed/garbled as math.
    expect(result).toContain('path ${SHARED} on ${TODAY}');
  });

  test('unknown ${FOO} token also renders as literal text, never as broken math', () => {
    const result = MarkdownRenderer.render('Value ${FOO} and ${BAR_BAZ} here.');
    expect(result).toContain('${FOO}');
    expect(result).toContain('${BAR_BAZ}');
    expect(result).not.toContain('katex');
  });

  test('display math $$...$$ is unaffected while a token in the same message stays literal', () => {
    const result = MarkdownRenderer.render('Block: $$x + y$$ and token ${TODAY}');
    expect(result).toContain('${TODAY}');
    expect(result).toContain('katex');
  });

  test('${TOKEN} inside a fenced code block stays literal', () => {
    const result = MarkdownRenderer.render('```\necho ${SHARED}\n```');
    expect(result).toContain('${SHARED}');
    expect(result).not.toContain('katex');
  });

  test('lowercase ${today} is NOT treated as a token (regex requires UPPER_CASE)', () => {
    // It also must not become math; since there is only one $ pair candidate
    // around "{today}", katex would try to render it. The token regex does not
    // match, but this documents that lowercase is out of scope for protection.
    const result = MarkdownRenderer.render('lower ${today} here');
    // The literal text should survive in some form; we only assert the
    // uppercase-protected behavior elsewhere. Here just ensure no crash and
    // the word "today" is present.
    expect(result).toContain('today');
  });
});

describeFn('WsContentRenderer.renderKatexInHTML vocabulary token protection', () => {
  let renderKatexInHTML;

  beforeEach(() => {
    jest.resetModules();
    delete window.WsContentRenderer;
    window.katex = require('../../docker/services/ruby/public/vendor/js/katex.min.js');

    const ns = require('../../docker/services/ruby/public/js/monadic/ws-content-renderer.js');
    // renderKatexInHTML is not exported on the namespace; exercise it through
    // applyMath on a DOM element, which calls renderKatexInHTML on innerHTML.
    renderKatexInHTML = function(html) {
      const el = document.createElement('div');
      el.innerHTML = html;
      ns.applyMath(el);
      return el.innerHTML;
    };
  });

  afterEach(() => {
    delete window.WsContentRenderer;
    delete window.katex;
  });

  test('preserves ${TODAY} literally and does not render it as math', () => {
    const result = renderKatexInHTML('<p>The date is ${TODAY} today.</p>');
    expect(result).toContain('${TODAY}');
    expect(result).not.toContain('katex');
  });

  test('keeps ${TODAY} literal AND renders $a+b$ as math in the same fragment', () => {
    const result = renderKatexInHTML('<p>The date is ${TODAY} and $a+b$</p>');
    expect(result).toContain('${TODAY}');
    expect(result).toContain('katex');
  });

  test('two tokens preserved with no math span consuming the text between them', () => {
    const result = renderKatexInHTML('<p>path ${SHARED} on ${TODAY}</p>');
    expect(result).toContain('${SHARED}');
    expect(result).toContain('${TODAY}');
    expect(result).not.toContain('katex');
  });
});
