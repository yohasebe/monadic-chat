/**
 * @jest-environment jsdom
 *
 * Regression test: TTS marker sanitization must NOT collapse indentation inside
 * fenced code blocks.
 *
 * Background (2026-06-02): MarkdownRenderer.render() runs
 * TtsTagSanitizer.sanitizeForDisplay() at the top to strip provider TTS markers
 * for the on-screen transcript. That sanitizer also collapses runs of spaces
 * (`/[ \t]{2,}/ -> " "`) to tidy whitespace left by removed markers. When the
 * active provider was TTS-tag-aware, this collapsed the 2/4/6-space indentation
 * of a Mermaid `mindmap` block down to a single space — flattening the hierarchy
 * so Mermaid threw "There can be only one root" and rendered the error bomb.
 *
 * render() now placeholder-protects fenced code blocks across the sanitize call.
 * These tests pin that indentation survives when sanitizeForDisplay is active.
 */

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

describeFn('MarkdownRenderer preserves code-fence indentation under TTS sanitization', () => {
  let MarkdownRenderer;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;

    const markdownit = require('../../docker/services/ruby/public/vendor/js/markdown-it.min.js');
    window.markdownit = markdownit.default || markdownit;
    window.katex = require('../../docker/services/ruby/public/vendor/js/katex.min.js');

    // Simulate a TTS-tag-aware provider so render() actually calls
    // sanitizeForDisplay (the collapse step that previously broke mindmaps).
    // Mirror the real collapse so the test fails if fences are left unprotected.
    window.TtsTagSanitizer = {
      tagAware: function() { return true; },
      sanitizeForDisplay: function(text) {
        return String(text)
          .replace(/[ \t]{2,}/g, " ")
          .replace(/\s+([,.!?;:])/g, "$1");
      }
    };

    require('../../docker/services/ruby/public/js/monadic/markdown-renderer.js');
    MarkdownRenderer = window.MarkdownRenderer;
    MarkdownRenderer._initMarkdownIt();
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
    delete window.markdownit;
    delete window.katex;
    delete window.TtsTagSanitizer;
  });

  function preText(html) {
    const div = document.createElement('div');
    div.innerHTML = html;
    const pre = div.querySelector('.mermaid-code pre');
    return pre ? pre.textContent : null;
  }

  test('Mermaid mindmap keeps 2/4/6-space indentation (no "one root" collapse)', () => {
    const code = [
      '```mermaid',
      'mindmap',
      '  root((化学))',
      '    物理化学',
      '      熱力学',
      '    無機化学',
      '      元素',
      '```'
    ].join('\n');

    const out = preText(MarkdownRenderer.render(code, { appName: 'mermaid_grapher' }));

    expect(out).toContain('  root((化学))');     // 2-space
    expect(out).toContain('    物理化学');         // 4-space
    expect(out).toContain('      熱力学');         // 6-space
    // The bug signature was every line collapsing to a single leading space.
    expect(out).not.toContain('\n root((化学))');
    expect(out).not.toContain('\n 物理化学');
  });

  test('prose outside code fences is still space-collapsed by the sanitizer', () => {
    const text = 'Hello    world\n\n```mermaid\nmindmap\n  root((A))\n    B\n```';
    const html = MarkdownRenderer.render(text, { appName: 'mermaid_grapher' });
    // Prose double spaces collapse (sanitizer still runs outside fences)...
    expect(html).toContain('Hello world');
    // ...while the fenced indentation is preserved.
    const out = preText(html);
    expect(out).toContain('  root((A))');
    expect(out).toContain('    B');
  });
});
