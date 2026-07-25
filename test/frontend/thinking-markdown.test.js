/**
 * @jest-environment jsdom
 */

/**
 * Thinking trace Markdown rendering
 * (websocket-handlers.js → renderThinkingMarkdown / renderThinkingBlock).
 *
 * Reasoning traces are markdown-ish text; the panel used to show the raw
 * markers (**bold**, "- " lists) as literal strings. They now render through
 * markdown-it (html:false → raw HTML stays escaped) with an escaped-text
 * fallback when markdown-it is absent.
 */

const path = require('path');
const MARKDOWN_IT_PATH = path.resolve(
  __dirname,
  '../../docker/services/ruby/public/vendor/js/markdown-it.min.js'
);
const HANDLERS_PATH = path.resolve(
  __dirname,
  '../../docker/services/ruby/public/js/monadic/websocket-handlers.js'
);

function loadHandlers({ withMarkdownIt }) {
  jest.resetModules();
  delete window.wsHandlers;
  if (withMarkdownIt) {
    // The real shipped renderer (UMD exposes a factory via module.exports).
    global.markdownit = require(MARKDOWN_IT_PATH);
  } else {
    delete global.markdownit;
  }
  return require(HANDLERS_PATH);
}

afterEach(() => {
  delete global.markdownit;
  delete window.wsHandlers;
});

describe('renderThinkingMarkdown with markdown-it available', () => {
  let handlers;
  beforeEach(() => { handlers = loadHandlers({ withMarkdownIt: true }); });

  it('renders emphasis and lists instead of literal markers', () => {
    const html = handlers.renderThinkingMarkdown('**Plan:**\n\n- step one\n- step two');
    expect(html).toContain('<strong>Plan:</strong>');
    expect(html).toContain('<li>step one</li>');
    expect(html).not.toContain('**');
  });

  it('keeps raw HTML in the trace escaped (html:false)', () => {
    const html = handlers.renderThinkingMarkdown('try <script>alert(1)</script> now');
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
  });

  it('turns single newlines into line breaks (breaks:true)', () => {
    const html = handlers.renderThinkingMarkdown('line one\nline two');
    expect(html).toContain('<br>');
  });

  it('renders inside the full thinking block card', () => {
    const block = handlers.renderThinkingBlock('**bold** thought', 'Thinking Process');
    expect(block).toContain('<strong>bold</strong>');
    expect(block).toContain('thinking-block-inner');
  });
});

describe('renderThinkingMarkdown fallback without markdown-it', () => {
  let handlers;
  beforeEach(() => { handlers = loadHandlers({ withMarkdownIt: false }); });

  it('falls back to escaped text with <br> line breaks', () => {
    const html = handlers.renderThinkingMarkdown('a <b>bold</b> claim\nnext line');
    expect(html).toContain('&lt;b&gt;bold&lt;/b&gt;');
    expect(html).toContain('<br>');
    expect(html).not.toContain('<b>bold</b>');
  });

  it('handles null/undefined without throwing', () => {
    expect(handlers.renderThinkingMarkdown(null)).toBe('');
    expect(handlers.renderThinkingMarkdown(undefined)).toBe('');
  });
});

// Thinking-block headers carry no inline onclick (DOMPurify strips inline
// handlers from sanitized card HTML); expansion is driven by the delegated
// click listener websocket-handlers.js installs at load time.
describe('thinking block header delegation', () => {
  let handlers;
  beforeEach(() => { handlers = loadHandlers({ withMarkdownIt: false }); });

  it('renderThinkingBlock emits no inline onclick handler', () => {
    const block = handlers.renderThinkingBlock('content', 'Thinking Process');
    expect(block).not.toContain('onclick');
    expect(block).toContain('thinking-block-header');
  });

  it('clicking the header toggles .expanded on the block', () => {
    document.body.innerHTML = handlers.renderThinkingBlock('content', 'Thinking Process');
    const block = document.querySelector('.thinking-block');
    const header = document.querySelector('.thinking-block-header');

    expect(block.classList.contains('expanded')).toBe(false);
    header.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(block.classList.contains('expanded')).toBe(true);
    header.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(block.classList.contains('expanded')).toBe(false);
  });

  it('clicking a child element inside the header also toggles', () => {
    document.body.innerHTML = handlers.renderThinkingBlock('content', 'Thinking Process');
    const block = document.querySelector('.thinking-block');
    const icon = document.querySelector('.thinking-block-header .fa-brain');

    icon.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(block.classList.contains('expanded')).toBe(true);
  });
});
