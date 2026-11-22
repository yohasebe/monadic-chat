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
