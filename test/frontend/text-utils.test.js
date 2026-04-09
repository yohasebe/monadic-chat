/**
 * Tests for text-utils.js
 *
 * Pure string manipulation utilities extracted from utilities.js.
 */

const { removeCode, removeMarkdown, removeEmojis, convertString } = require('../../docker/services/ruby/public/js/monadic/text-utils');

describe('text-utils', () => {
  describe('removeCode', () => {
    it('removes fenced code blocks', () => {
      const text = 'Some text ```code here``` and more text';
      expect(removeCode(text)).toBe('Some text   and more text');
    });

    it('removes script and style tags', () => {
      const text = 'Text with <script>alert("hi")</script> and <style>.foo{}</style>';
      expect(removeCode(text)).toBe('Text with   and  ');
    });

    it('removes img tags', () => {
      const text = 'Text with <img src="photo.jpg" /> in the middle';
      expect(removeCode(text)).toBe('Text with   in the middle');
    });

    it('handles multiline code blocks', () => {
      const text = 'Before\n```\nline1\nline2\n```\nAfter';
      expect(removeCode(text)).toBe('Before\n \nAfter');
    });

    it('returns text unchanged when no code blocks', () => {
      const text = 'Just plain text with no code';
      expect(removeCode(text)).toBe('Just plain text with no code');
    });
  });

  describe('removeMarkdown', () => {
    it('removes bold, italic, and code formatting', () => {
      const text = '**bold** *italic* `code` _emphasis_';
      expect(removeMarkdown(text)).toBe('bold italic code emphasis');
    });

    it('removes mixed markdown in a sentence', () => {
      const text = 'This is a **bold** statement with *italic* words and `code blocks` mixed in.';
      expect(removeMarkdown(text)).toBe('This is a bold statement with italic words and code blocks mixed in.');
    });

    it('handles double underscores', () => {
      const text = '__Bold__ and *italic*';
      expect(removeMarkdown(text)).toBe('Bold and italic');
    });

    it('returns plain text unchanged', () => {
      expect(removeMarkdown('no formatting here')).toBe('no formatting here');
    });
  });

  describe('removeEmojis', () => {
    it('removes emoji characters', () => {
      const text = 'Hello 😀 world 🌍';
      expect(removeEmojis(text)).toBe('Hello  world ');
    });

    it('returns text unchanged when no emojis', () => {
      const text = 'No emojis here';
      expect(removeEmojis(text)).toBe('No emojis here');
    });

    it('preserves special non-emoji characters', () => {
      const text = 'Text with emojis 🎉 and special chars #@!';
      expect(removeEmojis(text)).toBe('Text with emojis  and special chars #@!');
    });
  });

  describe('convertString', () => {
    it('converts snake_case to Title Case', () => {
      expect(convertString('this_is_snake_case')).toBe('This Is Snake Case');
    });

    it('handles single word', () => {
      expect(convertString('word')).toBe('Word');
    });

    it('handles empty string', () => {
      expect(convertString('')).toBe('');
    });

    it('handles multiple underscores', () => {
      expect(convertString('multiple___underscores')).toBe('Multiple   Underscores');
    });

    it('handles already capitalized words', () => {
      expect(convertString('Already_Capitalized')).toBe('Already Capitalized');
    });
  });

  describe('exports', () => {
    it('exports all functions to window', () => {
      expect(window.removeCode).toBe(removeCode);
      expect(window.removeMarkdown).toBe(removeMarkdown);
      expect(window.removeEmojis).toBe(removeEmojis);
      expect(window.convertString).toBe(convertString);
    });

    it('exports all functions via module.exports', () => {
      expect(typeof removeCode).toBe('function');
      expect(typeof removeMarkdown).toBe('function');
      expect(typeof removeEmojis).toBe('function');
      expect(typeof convertString).toBe('function');
    });
  });
});
