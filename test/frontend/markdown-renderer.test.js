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

  describe('snakeToCapitalized', () => {
    it('converts snake_case to Capitalized Words', () => {
      expect(MarkdownRenderer.snakeToCapitalized('hello_world')).toBe('Hello World');
    });

    it('handles single word', () => {
      expect(MarkdownRenderer.snakeToCapitalized('hello')).toBe('Hello');
    });

    it('handles multiple underscores', () => {
      expect(MarkdownRenderer.snakeToCapitalized('one_two_three')).toBe('One Two Three');
    });

    it('handles empty string', () => {
      expect(MarkdownRenderer.snakeToCapitalized('')).toBe('');
    });
  });

  describe('isMonadicJson', () => {
    it('returns false for null/empty input', () => {
      expect(MarkdownRenderer.isMonadicJson(null)).toBe(false);
      expect(MarkdownRenderer.isMonadicJson('')).toBe(false);
      expect(MarkdownRenderer.isMonadicJson(undefined)).toBe(false);
    });

    it('detects valid Monadic JSON with message key', () => {
      const json = JSON.stringify({ message: 'hello', context: {} });
      expect(MarkdownRenderer.isMonadicJson(json)).toBe(true);
    });

    it('detects valid Monadic JSON with context key', () => {
      const json = JSON.stringify({ context: { topic: 'test' } });
      expect(MarkdownRenderer.isMonadicJson(json)).toBe(true);
    });

    it('rejects regular JSON without message/context keys', () => {
      const json = JSON.stringify({ name: 'test', value: 123 });
      expect(MarkdownRenderer.isMonadicJson(json)).toBe(false);
    });

    it('rejects plain text', () => {
      expect(MarkdownRenderer.isMonadicJson('just some text')).toBe(false);
    });

    it('detects JSON inside markdown code block', () => {
      const text = '```json\n{"message": "hello"}\n```';
      expect(MarkdownRenderer.isMonadicJson(text)).toBe(true);
    });
  });

  describe('_sanitizeJsonString', () => {
    it('returns input as-is for null/non-string', () => {
      expect(MarkdownRenderer._sanitizeJsonString(null)).toBeNull();
      expect(MarkdownRenderer._sanitizeJsonString(123)).toBe(123);
    });

    it('escapes raw newlines inside JSON string values', () => {
      // A JSON string with a raw newline inside a value
      const raw = '{"key": "line1\nline2"}';
      const sanitized = MarkdownRenderer._sanitizeJsonString(raw);
      expect(sanitized).toBe('{"key": "line1\\nline2"}');
    });

    it('escapes raw tabs inside JSON string values', () => {
      const raw = '{"key": "col1\tcol2"}';
      const sanitized = MarkdownRenderer._sanitizeJsonString(raw);
      expect(sanitized).toBe('{"key": "col1\\tcol2"}');
    });

    it('preserves already-escaped sequences', () => {
      const raw = '{"key": "line1\\nline2"}';
      const sanitized = MarkdownRenderer._sanitizeJsonString(raw);
      expect(sanitized).toBe('{"key": "line1\\nline2"}');
    });

    it('preserves whitespace outside strings', () => {
      const raw = '{\n  "key": "value"\n}';
      const sanitized = MarkdownRenderer._sanitizeJsonString(raw);
      expect(sanitized).toBe('{\n  "key": "value"\n}');
    });
  });

  describe('_extractMonadicJson', () => {
    it('returns null for null/non-string input', () => {
      expect(MarkdownRenderer._extractMonadicJson(null)).toBeNull();
      expect(MarkdownRenderer._extractMonadicJson(123)).toBeNull();
    });

    it('extracts pure JSON with message key', () => {
      const json = '{"message": "hello", "context": {}}';
      const result = MarkdownRenderer._extractMonadicJson(json);
      expect(result).toEqual({ message: 'hello', context: {} });
    });

    it('extracts JSON from markdown code block', () => {
      const text = 'Some text\n```json\n{"message": "hello"}\n```\nMore text';
      const result = MarkdownRenderer._extractMonadicJson(text);
      expect(result).toEqual({ message: 'hello' });
    });

    it('extracts JSON from bare code block', () => {
      const text = '```\n{"context": {"topic": "test"}}\n```';
      const result = MarkdownRenderer._extractMonadicJson(text);
      expect(result).toEqual({ context: { topic: 'test' } });
    });

    it('extracts embedded JSON from surrounding text', () => {
      const text = 'Here is the result: {"message": "found it"} and more text';
      const result = MarkdownRenderer._extractMonadicJson(text);
      expect(result).toEqual({ message: 'found it' });
    });

    it('returns null for non-Monadic JSON', () => {
      const json = '{"name": "test"}';
      expect(MarkdownRenderer._extractMonadicJson(json)).toBeNull();
    });

    it('handles BOM prefix', () => {
      const json = '\uFEFF{"message": "hello"}';
      const result = MarkdownRenderer._extractMonadicJson(json);
      expect(result).toEqual({ message: 'hello' });
    });

    it('handles raw newlines in string values via sanitization', () => {
      const json = '{"message": "line1\nline2"}';
      const result = MarkdownRenderer._extractMonadicJson(json);
      expect(result).toEqual({ message: 'line1\nline2' });
    });
  });

  describe('render', () => {
    it('returns empty string for empty input', () => {
      expect(MarkdownRenderer.render('')).toBe('');
      expect(MarkdownRenderer.render(null)).toBe('');
    });

    it('returns plain text with HTML escaping when markdown-it is not loaded', () => {
      // markdown-it is not loaded in test env, so falls back to plain text
      const result = MarkdownRenderer.renderMarkdown('Hello <b>world</b>');
      expect(result).toContain('&lt;b&gt;');
      expect(result).not.toContain('<b>');
    });
  });

  describe('renderField', () => {
    it('renders empty values with "no value" italic text', () => {
      const html = MarkdownRenderer.renderField('test_key', null, 1, {});
      expect(html).toContain('Test Key');
      expect(html).toContain('no value');
    });

    it('renders empty array with "no value"', () => {
      const html = MarkdownRenderer.renderField('items', [], 1, {});
      expect(html).toContain('Items');
      expect(html).toContain('no value');
    });

    it('renders simple string value', () => {
      const html = MarkdownRenderer.renderSimpleField('Name', 'Alice', 'name', 1);
      expect(html).toContain('Name');
      expect(html).toContain('Alice');
    });
  });

  describe('jsonToHtml', () => {
    it('returns string representation for non-objects', () => {
      expect(MarkdownRenderer.jsonToHtml(null, { iteration: 0 })).toBe('null');
      expect(MarkdownRenderer.jsonToHtml('hello', { iteration: 0 })).toBe('hello');
    });

    it('renders message field with hr separator', () => {
      const html = MarkdownRenderer.jsonToHtml({ message: 'Hello' }, { iteration: 0 });
      expect(html).toContain('<hr />');
    });
  });
});
