/**
 * @jest-environment jsdom
 *
 * File names come from the user's disk and may contain HTML. The attachment
 * list must show them as text. Loads the real scripts rather than copies.
 */
const fs = require('fs');
const path = require('path');

const JS_DIR = path.join(__dirname, '../../docker/services/ruby/public/js/monadic');
const load = (name) => {
  // Indirect eval runs the file as a classic script in the global scope
  (0, eval)(fs.readFileSync(path.join(JS_DIR, name), 'utf8'));
};

describe('attachment list escapes file names', () => {
  beforeAll(() => {
    document.body.innerHTML = '<button id="image-file"></button><div id="image-used"></div>';
    global.bootstrap = { Modal: { getOrCreateInstance: () => ({ hide() {}, show() {} }) } };
    load('dom-helpers.js');
    load('text-utils.js');
    load('select_image.js');
  });

  const hostile = [
    `<img src=x onerror="window.__pwned=1">.png`,
    `a' onmouseover='window.__pwned=1' x='.png`
  ];

  test.each([
    ['image/png', 'data:image/png;base64,AAAA'],
    ['application/pdf', 'data:application/pdf;base64,AAAA'],
    ['text/csv', 'data:text/csv;base64,AAAA']
  ])('renders %s names as text', (type, data) => {
    for (const title of hostile) {
      window.__pwned = undefined;
      updateFileDisplay([{ title, type, data }]);
      const used = document.getElementById('image-used');
      // No element or attribute was created from the name
      expect(used.querySelector('[onerror],[onmouseover]')).toBeNull();
      expect(used.querySelectorAll('img').length).toBe(type.startsWith('image/') ? 1 : 0);
      expect(used.textContent + (used.querySelector('img')?.getAttribute('alt') || '')).toContain(title);
      expect(window.__pwned).toBeUndefined();
    }
  });
});
