/**
 * @jest-environment jsdom
 */
// The tabs over the main column, on the page's own markup: before a session
// "Current settings" is only a name; a chat that can be continued is offered
// by "Session" as by the button under the settings; in a session the tabs and
// that button switch between the settings and the conversation, which comes
// back where it was scrolled to.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../docker/services/ruby');
const PAGE = fs.readFileSync(path.join(ROOT, 'views/index.erb'), 'utf8');
const TRANSLATIONS = fs.readFileSync(path.join(ROOT, 'public/js/i18n/translations.js'), 'utf8');

function cut(from, to) {
  const start = PAGE.indexOf(from);
  const end = PAGE.indexOf(to, start);
  if (start < 0 || end < 0) throw new Error('markup not found: ' + from);
  return PAGE.slice(start, end);
}

describe('main column tab words', () => {
  it('are in every language with the same keys', () => {
    const blocks = TRANSLATIONS.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);
    expect(blocks.map((b) => b.slice(0, 2))).toEqual(['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de']);
    blocks.forEach((b) => {
      expect(b).toMatch(/\n {6}mainTabs: \{ label: "[^"]+", session: "[^"]+" \},/);
    });
    (PAGE.match(/ui\.mainTabs\.(\w+)/g) || []).forEach((k) => {
      expect(['ui.mainTabs.label', 'ui.mainTabs.session']).toContain(k);
    });
  });
});

describe('main column tabs', () => {
  const settingsShown = () => document.getElementById('config-body').style.display !== 'none';
  let started;
  const actions = () => document.getElementById('config-actions');
  const tab = (name) => document.getElementById('summary-tab-' + name);
  const column = () => document.getElementById('main');
  const panel = () => document.getElementById('main-panel');

  beforeEach(() => {
    document.body.innerHTML = '<div id="main">' +
      cut('<div class="column-bar">', '<div id="config-wrapper">') +
      '<div id="config-body"></div>' +
      '<div id="config-actions"><button id="start"></button></div>' +
      '<div id="main-panel" class="d-none"></div></div>';
    started = 0;
    document.getElementById('start').addEventListener('click', () => { started += 1; });
    jest.resetModules();
    require('../../docker/services/ruby/public/js/monadic/dom-helpers.js');
    require('../../docker/services/ruby/public/js/monadic/main-tabs.js');
  });

  afterEach(() => { delete window.MainTabs; });

  function startSession() {
    panel().classList.remove('d-none');
    window.MainTabs.setMode('active');
    window.MainTabs.show('session');
  }

  it('before a session, has only "Current settings", which does nothing', () => {
    expect(tab('session').hidden).toBe(true);
    expect(tab('settings').tabIndex).toBe(-1);
    tab('settings').click();
    expect(window.MainTabs.locked()).toBe(true);
    expect(settingsShown()).toBe(true);
  });

  it('from the start of a session, offers both tabs and shows the conversation', () => {
    startSession();
    expect(tab('session').hidden).toBe(false);
    expect(tab('session').getAttribute('aria-selected')).toBe('true');
    expect(tab('session').tabIndex).toBe(0);
    expect(tab('settings').getAttribute('aria-selected')).toBe('false');
    expect(settingsShown()).toBe(false);
    expect(panel().style.display).not.toBe('none');
  });

  it('shows one of the settings and the conversation at a time', () => {
    startSession();
    tab('settings').click();
    expect(settingsShown()).toBe(true);
    expect(panel().style.display).toBe('none');
    expect(tab('settings').getAttribute('aria-selected')).toBe('true');
    expect(tab('settings').tabIndex).toBe(0);
    expect(tab('session').tabIndex).toBe(-1);
    tab('session').click();
    expect(settingsShown()).toBe(false);
    expect(panel().style.display).not.toBe('none');
  });

  it('brings the conversation back where it was scrolled to', () => {
    startSession();
    column().scrollTop = 420;
    tab('settings').click();
    expect(column().scrollTop).toBe(0);
    tab('session').click();
    expect(column().scrollTop).toBe(420);
  });

  it('starts the next session\'s conversation at the top', () => {
    startSession();
    column().scrollTop = 420;
    tab('settings').click();
    window.MainTabs.setMode('none');
    startSession();
    expect(column().scrollTop).toBe(0);
  });

  it('switches with the arrow keys, which the page\'s shortcuts do not see', () => {
    startSession();
    const seen = jest.fn();
    document.addEventListener('keydown', seen);
    tab('session').focus();
    tab('session').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
    expect(window.MainTabs.current()).toBe('settings');
    expect(document.activeElement).toBe(tab('settings'));
    // → on the settings tab goes to the conversation, and does not start voice input.
    tab('settings').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    expect(window.MainTabs.current()).toBe('session');
    expect(seen).not.toHaveBeenCalled();
    document.removeEventListener('keydown', seen);
  });

  it('shows the tab chosen last when tabs are chosen quickly', () => {
    startSession();
    tab('settings').click();
    tab('session').click();
    tab('settings').click();
    expect(window.MainTabs.current()).toBe('settings');
    expect(settingsShown()).toBe(true);
    expect(panel().style.display).toBe('none');
  });

  it('offers a chat opened from the history by "Session", which continues it', () => {
    window.MainTabs.setMode('ready');
    expect(tab('session').hidden).toBe(false);
    expect(tab('settings').getAttribute('aria-selected')).toBe('true');
    expect(tab('session').tabIndex).toBe(0);
    tab('session').click();
    expect(started).toBe(1);
    // The settings stay until the session has started.
    expect(settingsShown()).toBe(true);
  });

  it('does not continue a chat by "Session" while the button under the settings cannot', () => {
    window.MainTabs.setMode('ready');
    document.getElementById('start').disabled = true;
    tab('session').click();
    expect(started).toBe(0);
  });

  it('in a session, shows the button under the settings with the settings only', () => {
    startSession();
    expect(actions().style.display).toBe('none');
    tab('settings').click();
    expect(actions().style.display).not.toBe('none');
    tab('session').click();
    expect(actions().style.display).toBe('none');
  });

  it('locks again on reset, with the settings shown and no Session tab', () => {
    startSession();
    window.MainTabs.setMode('none');
    window.MainTabs.show('settings');
    expect(tab('session').hidden).toBe(true);
    expect(tab('settings').tabIndex).toBe(-1);
    tab('session').click();
    expect(window.MainTabs.current()).toBe('settings');
  });
});
