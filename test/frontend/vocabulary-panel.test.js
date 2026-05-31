/**
 * @jest-environment jsdom
 */
const path = require('path');

// Load the IIFE module; it assigns window.VocabularyPanel and module.exports.
const VocabularyPanel = require(
  path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic/vocabulary-panel.js')
);

// Minimal DOM mirroring views/index.erb: the section wrapper, the collapsible
// heading toggle (with caret) and the list host (collapsed by default).
function setupDom() {
  document.body.innerHTML = `
    <div id="available-variables" style="display:none;">
      <h5 id="available-variables-toggle" class="sidebar-collapse-toggle py-2 mb-0" role="button" aria-expanded="false" aria-controls="available-variables-list">
        <span class="text"><i class="fas fa-dollar-sign"></i> Available Variables</span><i id="available-variables-caret" class="fas fa-chevron-down sidebar-collapse-icon"></i>
      </h5>
      <div id="available-variables-list" class="mt-2" style="display:none;"></div>
    </div>`;
}

describe('VocabularyPanel.render', () => {
  beforeEach(() => {
    setupDom();
  });

  test('renders one row per backend entry with token, description and value', () => {
    const entries = [
      { token: 'SHARED', description: 'The shared data folder', display: 'decorate', value: '/monadic/data' },
      { token: 'TODAY', description: "Today's date", display: 'expand', value: '2026-05-31' },
      { token: 'MODEL', description: 'The AI model', display: 'expand', value: 'gpt-5.4' }
    ];

    VocabularyPanel.render(entries);

    const section = document.getElementById('available-variables');
    const rows = document.querySelectorAll('#available-variables-list .vocab-row');

    expect(section.style.display).toBe('');
    expect(rows.length).toBe(3);

    // First row content is driven entirely by the backend array.
    const firstToken = rows[0].querySelector('.vocab-name');
    expect(firstToken.textContent).toBe('${SHARED}');
    expect(rows[0].querySelector('.vocab-desc').textContent).toBe('The shared data folder');
    expect(rows[0].querySelector('.vocab-value').textContent).toBe('/monadic/data');
  });

  test('panel chips use .vocab-name (NOT clickable .vocab-token)', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: 'The shared data folder', display: 'decorate', value: '/monadic/data' }
    ]);
    // No clickable .vocab-token chips are created in the panel.
    expect(document.querySelectorAll('#available-variables .vocab-token').length).toBe(0);
    const chip = document.querySelector('#available-variables .vocab-name');
    expect(chip).not.toBeNull();
    expect(chip.textContent).toBe('${SHARED}');
    // Reference-only: none of the handler-target attributes are present, so the
    // delegated reveal/clipboard handler (matching .vocab-token) never fires.
    expect(chip.getAttribute('role')).toBeNull();
    expect(chip.getAttribute('tabindex')).toBeNull();
    expect(chip.getAttribute('data-vocab-path')).toBeNull();
  });

  test('lists a token with a null value with a hidden, empty resolved element', () => {
    VocabularyPanel.render([
      { token: 'MODEL', description: 'The AI model', display: 'expand', value: null }
    ]);

    const rows = document.querySelectorAll('#available-variables-list .vocab-row');
    expect(rows.length).toBe(1);
    expect(rows[0].querySelector('.vocab-name').textContent).toBe('${MODEL}');
    // The resolved container is always created so updateValues() can fill it
    // in later — but for a value-less entry it is hidden and the value empty.
    const resolved = rows[0].querySelector('.vocab-resolved');
    const val = rows[0].querySelector('.vocab-value');
    expect(resolved).not.toBeNull();
    expect(resolved.style.display).toBe('none');
    expect(val).not.toBeNull();
    expect(val.textContent).toBe('');
  });

  test('every row carries a data-vocab-token attribute', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: 'x', display: 'decorate', value: '/d' },
      { token: 'MODEL', description: 'y', display: 'expand', value: null }
    ]);
    const rows = document.querySelectorAll('#available-variables-list .vocab-row');
    expect(rows[0].getAttribute('data-vocab-token')).toBe('SHARED');
    expect(rows[1].getAttribute('data-vocab-token')).toBe('MODEL');
  });

  test('section body is collapsed by default (list hidden, aria-expanded=false)', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: 'x', display: 'decorate', value: '/d' }
    ]);
    const section = document.getElementById('available-variables');
    const list = document.getElementById('available-variables-list');
    const toggle = document.getElementById('available-variables-toggle');
    // Section is shown (has vocabulary) but the body stays collapsed.
    expect(section.style.display).toBe('');
    expect(list.style.display).toBe('none');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  test('clicking the heading expands then collapses the list body', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: 'x', display: 'decorate', value: '/d' }
    ]);
    const list = document.getElementById('available-variables-list');
    const toggle = document.getElementById('available-variables-toggle');

    // Expand
    toggle.click();
    expect(list.style.display).toBe('');
    expect(toggle.getAttribute('aria-expanded')).toBe('true');

    // Collapse again
    toggle.click();
    expect(list.style.display).toBe('none');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  test('re-render (app switch) resets to collapsed even after expanding', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: 'x', display: 'decorate', value: '/d' }
    ]);
    const toggle = document.getElementById('available-variables-toggle');
    const list = document.getElementById('available-variables-list');
    toggle.click();
    expect(list.style.display).toBe(''); // expanded

    // App switch -> re-render collapses again.
    VocabularyPanel.render([
      { token: 'NOTEBOOK', description: 'notebook', display: 'decorate', value: '/nb' }
    ]);
    expect(list.style.display).toBe('none');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  test('hides the whole section when given an empty array', () => {
    // First populate, then clear, to confirm it toggles off.
    VocabularyPanel.render([
      { token: 'SHARED', description: 'x', display: 'decorate', value: '/d' }
    ]);
    expect(document.getElementById('available-variables').style.display).toBe('');

    VocabularyPanel.render([]);
    const section = document.getElementById('available-variables');
    expect(section.style.display).toBe('none');
    expect(document.querySelectorAll('#available-variables-list .vocab-row').length).toBe(0);
  });

  test('treats non-array input as empty and hides the section', () => {
    VocabularyPanel.render(undefined);
    expect(document.getElementById('available-variables').style.display).toBe('none');
    VocabularyPanel.render(null);
    expect(document.getElementById('available-variables').style.display).toBe('none');
  });

  test('does not inject markup from token/description/value (XSS-safe)', () => {
    VocabularyPanel.render([
      { token: 'SHARED', description: '<img src=x onerror=alert(1)>', display: 'decorate', value: '<b>v</b>' }
    ]);
    const row = document.querySelector('#available-variables-list .vocab-row');
    // textContent assignment means the markup is rendered as literal text.
    expect(row.querySelector('.vocab-desc').textContent).toBe('<img src=x onerror=alert(1)>');
    expect(row.querySelector('.vocab-desc').querySelector('img')).toBeNull();
    expect(row.querySelector('.vocab-value').textContent).toBe('<b>v</b>');
    expect(row.querySelector('.vocab-value').querySelector('b')).toBeNull();
  });
});

describe('VocabularyPanel.renderForApp', () => {
  beforeEach(() => {
    setupDom();
    window.apps = {
      Chat: {
        vocabulary_info: [
          { token: 'APP', description: 'The app name', display: 'expand', value: 'Chat' }
        ]
      },
      OptOut: { vocabulary_info: [] }
    };
  });

  test('renders from the cached app vocabulary_info field', () => {
    VocabularyPanel.renderForApp('Chat');
    const rows = document.querySelectorAll('#available-variables-list .vocab-row');
    expect(rows.length).toBe(1);
    expect(rows[0].querySelector('.vocab-name').textContent).toBe('${APP}');
  });

  test('hides the section for an app that opted out (empty array)', () => {
    VocabularyPanel.renderForApp('OptOut');
    expect(document.getElementById('available-variables').style.display).toBe('none');
  });

  test('hides the section for an unknown app', () => {
    VocabularyPanel.renderForApp('Nope');
    expect(document.getElementById('available-variables').style.display).toBe('none');
  });
});

describe('VocabularyPanel.updateValues', () => {
  beforeEach(() => {
    setupDom();
    // Panel rendered with MODEL having no value yet (typical at app-load).
    VocabularyPanel.render([
      { token: 'SHARED', description: 'The shared data folder', display: 'decorate', value: '/monadic/data' },
      { token: 'MODEL', description: 'The AI model', display: 'expand', value: null }
    ]);
  });

  test('populates a previously value-less row and reveals its .vocab-resolved', () => {
    const row = document.querySelector('[data-vocab-token="MODEL"]');
    // Pre-condition: hidden and empty.
    expect(row.querySelector('.vocab-resolved').style.display).toBe('none');
    expect(row.querySelector('.vocab-value').textContent).toBe('');

    VocabularyPanel.updateValues({ MODEL: { value: 'gpt-x', display: 'expand' } });

    expect(row.querySelector('.vocab-value').textContent).toBe('gpt-x');
    expect(row.querySelector('.vocab-resolved').style.display).toBe('');
  });

  test('tolerates a plain-string map value', () => {
    VocabularyPanel.updateValues({ MODEL: 'gpt-string' });
    const row = document.querySelector('[data-vocab-token="MODEL"]');
    expect(row.querySelector('.vocab-value').textContent).toBe('gpt-string');
    expect(row.querySelector('.vocab-resolved').style.display).toBe('');
  });

  test('a null/empty value hides the row .vocab-resolved', () => {
    // First give SHARED a value via the panel, then clear it.
    const row = document.querySelector('[data-vocab-token="SHARED"]');
    expect(row.querySelector('.vocab-resolved').style.display).toBe('');

    VocabularyPanel.updateValues({ SHARED: { value: null, display: 'decorate' } });
    expect(row.querySelector('.vocab-value').textContent).toBe('');
    expect(row.querySelector('.vocab-resolved').style.display).toBe('none');

    VocabularyPanel.updateValues({ SHARED: '' });
    expect(row.querySelector('.vocab-resolved').style.display).toBe('none');
  });

  test('ignores tokens that are not in the panel (no new rows added)', () => {
    const before = document.querySelectorAll('#available-variables-list .vocab-row').length;
    VocabularyPanel.updateValues({ NOTEBOOK: { value: '/nb', display: 'decorate' } });
    const after = document.querySelectorAll('#available-variables-list .vocab-row').length;
    expect(after).toBe(before);
    expect(document.querySelector('[data-vocab-token="NOTEBOOK"]')).toBeNull();
  });

  test('does not change collapse/visibility state of the panel', () => {
    const list = document.getElementById('available-variables-list');
    const toggle = document.getElementById('available-variables-toggle');
    // Collapsed by default after render.
    expect(list.style.display).toBe('none');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');

    VocabularyPanel.updateValues({ MODEL: { value: 'gpt-x', display: 'expand' } });

    // Unchanged.
    expect(list.style.display).toBe('none');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
  });

  test('no-op for falsy / non-object maps', () => {
    expect(() => VocabularyPanel.updateValues(null)).not.toThrow();
    expect(() => VocabularyPanel.updateValues(undefined)).not.toThrow();
    expect(() => VocabularyPanel.updateValues('nope')).not.toThrow();
    // MODEL still has no value.
    const row = document.querySelector('[data-vocab-token="MODEL"]');
    expect(row.querySelector('.vocab-value').textContent).toBe('');
  });

  test('XSS-safe: map value is set via textContent', () => {
    VocabularyPanel.updateValues({ MODEL: { value: '<b>x</b>', display: 'expand' } });
    const val = document.querySelector('[data-vocab-token="MODEL"] .vocab-value');
    expect(val.textContent).toBe('<b>x</b>');
    expect(val.querySelector('b')).toBeNull();
  });
});
