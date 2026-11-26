/**
 * @jest-environment jsdom
 *
 * Formulas in a message are set aside while Markdown is rendered and put
 * back afterwards: each one in its own place, however many there are.
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

describeFn('MarkdownRenderer puts formulas back in their places', () => {
  let MarkdownRenderer;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;
    const markdownit = require('../../docker/services/ruby/public/vendor/js/markdown-it.min.js');
    window.markdownit = markdownit.default || markdownit;
    window.katex = require('../../docker/services/ruby/public/vendor/js/katex.min.js');
    require('../../docker/services/ruby/public/js/monadic/markdown-renderer.js');
    MarkdownRenderer = window.MarkdownRenderer;
    MarkdownRenderer._initMarkdownIt();
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
    delete window.markdownit;
    delete window.katex;
  });

  // The TeX source of each formula drawn, in the order of the page.
  function sources(html) {
    const div = document.createElement('div');
    div.innerHTML = html;
    return Array.from(div.querySelectorAll('annotation')).map((a) => a.textContent);
  }

  it('draws the eleventh inline formula as itself, not as the second followed by 0', () => {
    const formulas = Array.from({ length: 12 }, (_, i) => `v_{${i}} = ${i}`);
    const html = MarkdownRenderer.render(formulas.map((f) => `- $${f}$`).join('\n'));

    expect(sources(html)).toEqual(formulas);
    expect(html).not.toContain('PLACEHOLDER');
  });

  it('draws the eleventh block formula as itself', () => {
    const formulas = Array.from({ length: 12 }, (_, i) => `w_{${i}} = ${i}`);
    const html = MarkdownRenderer.render(formulas.map((f) => `$$${f}$$`).join('\n\n'));

    expect(sources(html)).toEqual(formulas);
  });

  it('draws a boxed formula', () => {
    const html = MarkdownRenderer.render('$$\\boxed{x = 2,\\ 3}$$');

    expect(sources(html)).toEqual(['\\boxed{x = 2,\\ 3}']);
    expect(html).not.toContain('katex-error');
  });
});

describe('MarkdownRenderer.extractMath takes what is math and leaves the rest', () => {
  let extractMath;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;
    require('../../docker/services/ruby/public/js/monadic/markdown-renderer.js');
    extractMath = window.MarkdownRenderer.extractMath;
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
  });

  it.each([
    'It costs $5 and $10.',
    'From $5-$10.',
    'price $5, total $10',
    'US$5 only',
    '$ x $ is not math',
    'An escaped \\$5 stays',
  ])('leaves dollar signs that are not math: %s', (text) => {
    const result = extractMath(text);
    expect(result.text).toBe(text);
    expect(result.blocks).toEqual([]);
    expect(result.inlines).toEqual([]);
  });

  it('takes $...$, \\(...\\), $$...$$ and \\[...\\]', () => {
    const result = extractMath('a $x^2$ b \\(y\\) c $$z$$ d \\[w\\]');
    expect(result.inlines).toEqual(['x^2', 'y']);
    expect(result.blocks).toEqual(['z', 'w']);
    expect(result.text).toBe('a MATH_INLINE_PLACEHOLDER_0 b MATH_INLINE_PLACEHOLDER_1 c MATH_BLOCK_PLACEHOLDER_0 d MATH_BLOCK_PLACEHOLDER_1');
  });

  it('takes a formula beside a price', () => {
    const result = extractMath('$5 for $x+1$');
    expect(result.inlines).toEqual(['x+1']);
  });

  it.each([
    ['a code span', 'run `echo $HOME and $PATH` now'],
    ['a fenced block', '```\nx = $a$\n```'],
    ['a fenced block with ~', '~~~abc\nK:$C$\n~~~'],
    ['an unclosed fence', '```\n$a$ to the end'],
  ])('leaves the math-like text of %s', (_what, text) => {
    const result = extractMath(text);
    expect(result.text).toBe(text);
    expect(result.inlines).toEqual([]);
  });

  it('takes the math after a code block', () => {
    const result = extractMath('```\n$a$\n```\nthen $b$');
    expect(result.inlines).toEqual(['b']);
    expect(result.text).toBe('```\n$a$\n```\nthen MATH_INLINE_PLACEHOLDER_0');
  });
});
