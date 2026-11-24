/**
 * @jest-environment jsdom
 *
 * The buttons that remove an attachment show only an icon: each has a name,
 * from the page's translations, for screen readers and as a tooltip. Loads
 * the real scripts rather than copies.
 */
const fs = require('fs');
const path = require('path');

const JS_DIR = path.join(__dirname, '../../docker/services/ruby/public/js');
const load = (name) => {
  (0, eval)(fs.readFileSync(path.join(JS_DIR, name), 'utf8'));
};

describe('the remove buttons of attachments', () => {
  beforeAll(() => {
    document.body.innerHTML = '<button id="image-file"></button><div id="image-used"></div>';
    global.bootstrap = { Modal: { getOrCreateInstance: () => ({ hide() {}, show() {} }) } };
    load('monadic/dom-helpers.js');
    load('monadic/text-utils.js');
    load('monadic/select_image.js');
  });

  afterEach(() => { delete global.webUIi18n; });

  test.each([
    ['image/png', 'data:image/png;base64,AAAA'],
    ['application/pdf', 'data:application/pdf;base64,AAAA'],
    ['text/csv', 'data:text/csv;base64,AAAA']
  ])('a %s attachment\'s remove button is named in the page\'s language', (type, data) => {
    global.webUIi18n = { t: (key) => (key === 'ui.removeAttachment' ? 'この添付を外す' : key) };
    updateFileDisplay([{ title: 'a', type, data }]);
    const button = document.querySelector('#image-used .remove-file');
    expect(button.getAttribute('aria-label')).toBe('この添付を外す');
    expect(button.getAttribute('title')).toBe('この添付を外す');
  });

  test('without the translations, the English name', () => {
    updateFileDisplay([{ title: 'a', type: 'image/png', data: 'data:image/png;base64,AAAA' }]);
    expect(document.querySelector('#image-used .remove-file').getAttribute('aria-label')).toBe('Remove this attachment');
  });

  test('every language has the name', () => {
    // The file declares its table as a script-level const: read it in the
    // same evaluation.
    const table = (0, eval)(`${fs.readFileSync(path.join(JS_DIR, 'i18n/translations.js'), 'utf8')}\n;webUITranslations`);
    const languages = Object.keys(table);
    expect(languages.length).toBeGreaterThan(1);
    languages.forEach((lang) => expect(typeof table[lang].ui.removeAttachment).toBe('string'));
  });
});
