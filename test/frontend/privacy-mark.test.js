/**
 * @jest-environment jsdom
 */
// Marking words for the Privacy Filter in the message box: the selection
// is wrapped in the syntax the server reads, and the button shows only
// while the Privacy Filter is on.
const fs = require('fs');
const path = require('path');

describe('privacy mark', () => {
  let mark;

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `
      <input type="checkbox" id="check-privacy-session">
      <div id="privacy-mark-group" style="display:none">
        <button id="privacy-mark"></button>
        <button type="button" data-privacy-mark-type="ORGANIZATION" id="org"></button>
      </div>
      <textarea id="message"></textarea>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (node, ev, fn) => node && node.addEventListener(ev, fn);
    global.setAlert = jest.fn();
    mark = require('../../docker/services/ruby/public/js/monadic/privacy-mark.js');
  });

  afterEach(() => {
    delete global.setAlert;
  });

  function select(text, start, end) {
    const box = document.getElementById('message');
    box.value = text;
    box.setSelectionRange(start, end);
    return box;
  }

  it('wraps the selection with its type', () => {
    expect(mark.markRange('I am Taro.', 5, 9, 'PERSON').text).toBe('I am ⟦Taro|person⟧.');
    // A "|" in the words stays part of them.
    expect(mark.markRange('x A|organization y', 2, 16, 'PERSON').text).toBe('x ⟦A|organization|person⟧ y');
    expect(mark.markRange('At Acme.', 3, 7, 'ORGANIZATION').text).toBe('At ⟦Acme|organization⟧.');
  });

  it('refuses an empty selection, one over lines, and one with a mark in it', () => {
    expect(mark.markRange('a b', 1, 2, 'PERSON').error).toBe('empty');
    expect(mark.markRange('a\nb', 0, 3, 'PERSON').error).toBe('line');
    expect(mark.markRange('⟦a⟧ b', 0, 5, 'PERSON').error).toBe('nested');
  });

  it('every type word it writes is one the server reads', () => {
    const marks = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/lib/monadic/utils/privacy/marks.rb'), 'utf8');
    Object.entries(mark.TYPE_WORDS).forEach(([type, word]) => {
      const line = marks.split('\n').find((l) => l.includes(`'${type}' => %w[`));
      expect(line).toBeDefined();
      expect(line.split('%w[')[1].split(/\s+/)).toContain(word);
    });
  });

  it('shows the button only while the Privacy Filter is on', () => {
    const toggle = document.getElementById('check-privacy-session');
    const group = document.getElementById('privacy-mark-group');
    expect(group.style.display).toBe('none');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change'));
    expect(group.style.display).toBe('');
    // Locked after the first message: still on, still shown.
    toggle.disabled = true;
    window.privacyToggleLocked = true;
    document.dispatchEvent(new CustomEvent('privacy:state-changed', { detail: { enabled: true } }));
    expect(group.style.display).toBe('');
    // Disabled without the lock: the app has no Privacy Filter.
    window.privacyToggleLocked = false;
    document.dispatchEvent(new CustomEvent('privacy:state-changed', { detail: { enabled: false } }));
    expect(group.style.display).toBe('none');
  });

  it('keeps the focus (and the selection) in the message box when the buttons are pressed', () => {
    const down = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    document.getElementById('org').dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
  });

  it('marks the selection from the button, the type menu and the shortcut', () => {
    document.getElementById('check-privacy-session').checked = true;
    let box = select('Hi Bob', 3, 6);
    document.getElementById('privacy-mark').click();
    expect(box.value).toBe('Hi ⟦Bob|person⟧');

    box = select('At Acme', 3, 7);
    document.getElementById('org').click();
    expect(box.value).toBe('At ⟦Acme|organization⟧');

    box = select('Hi Ann', 3, 6);
    box.dispatchEvent(new KeyboardEvent('keydown', { key: 'K', ctrlKey: true, shiftKey: true }));
    expect(box.value).toBe('Hi ⟦Ann|person⟧');
  });

  it('has its words in all seven languages', () => {
    const source = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/i18n/translations.js'), 'utf8');
    const blocks = source.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);
    expect(blocks).toHaveLength(7);
    blocks.forEach((block) => {
      expect(block.match(/\n {6}privacyMark: \{\n/g)).toHaveLength(1);
      ['button', 'hint', 'person', 'organization', 'selectFirst'].forEach((key) => {
        expect(block).toMatch(new RegExp('\\n {8}' + key + ': "'));
      });
    });
  });
});
