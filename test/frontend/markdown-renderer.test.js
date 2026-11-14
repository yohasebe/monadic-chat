/**
 * @jest-environment jsdom
 */

describe('MarkdownRenderer Module', () => {
  let MarkdownRenderer;

  beforeEach(() => {
    jest.resetModules();
    delete window.MarkdownRenderer;

    // MarkdownRenderer needs window.markdownit for full rendering
    // We only test pure functions here (no markdown-it dependency)
    require('../../docker/services/ruby/public/js/monadic/markdown-renderer.js');
    MarkdownRenderer = window.MarkdownRenderer;
  });

  afterEach(() => {
    delete window.MarkdownRenderer;
  });

  describe('render', () => {
    it('returns empty string for empty input', () => {
      expect(MarkdownRenderer.render('')).toBe('');
      expect(MarkdownRenderer.render(null)).toBe('');
    });

    it('renders a reply written in JSON as text', () => {
      const result = MarkdownRenderer.render('{"message": "Hello", "context": {"topic": "x"}}');
      expect(result).toContain('message');
      expect(result).not.toContain('json-item');
    });

    it('returns plain text with HTML escaping when markdown-it is not loaded', () => {
      // markdown-it is not loaded in test env, so falls back to plain text
      const result = MarkdownRenderer.renderMarkdown('Hello <b>world</b>');
      expect(result).toContain('&lt;b&gt;');
      expect(result).not.toContain('<b>');
    });
  });

  describe('DrawIO raw XML detection regex (step 5b)', () => {
    // The regex used in renderMarkdown step 5b — extracted for direct testing
    const drawioRawRegex = /(<\?xml[^>]*\?>\s*\n)?<mxfile\b[\s\S]*?<diagram\b[\s\S]*?<\/mxfile>/g;

    it('matches valid DrawIO XML with diagram element', () => {
      const xml = '<mxfile><diagram id="test" name="Page-1"><mxGraphModel><root></root></mxGraphModel></diagram></mxfile>';
      expect(xml.match(drawioRawRegex)).not.toBeNull();
    });

    it('matches DrawIO XML with XML declaration prefix', () => {
      const xml = '<?xml version="1.0" encoding="UTF-8"?>\n<mxfile><diagram id="test"><mxGraphModel></mxGraphModel></diagram></mxfile>';
      expect(xml.match(drawioRawRegex)).not.toBeNull();
    });

    it('matches multi-line DrawIO XML', () => {
      const xml = [
        '<mxfile host="app.diagrams.net">',
        '  <diagram id="test" name="Page-1">',
        '    <mxGraphModel><root><mxCell id="0"/></root></mxGraphModel>',
        '  </diagram>',
        '</mxfile>'
      ].join('\n');
      expect(xml.match(drawioRawRegex)).not.toBeNull();
    });

    it('does not match mxfile without diagram element (prose mention)', () => {
      const text = 'The <mxfile> tag is used in DrawIO format</mxfile>';
      expect(text.match(drawioRawRegex)).toBeNull();
    });

    it('does not match incomplete mxfile reference in prose', () => {
      const text = 'DrawIO uses <mxfile> as the root element.';
      expect(text.match(drawioRawRegex)).toBeNull();
    });

    it('does not match mxfilename (word boundary check)', () => {
      const text = '<mxfilename>test</mxfilename>';
      expect(text.match(drawioRawRegex)).toBeNull();
    });
  });
});
