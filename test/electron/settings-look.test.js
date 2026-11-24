// The settings window keeps its grey surfaces and layout, takes the Web UI's
// button colors and title style, and follows the one theme setting through
// the theme class rather than the system's color scheme.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const page = fs.readFileSync(path.join(ROOT, 'app', 'settings.html'), 'utf8');
const main = fs.readFileSync(path.join(ROOT, 'app', 'main.js'), 'utf8');
const style = page.slice(page.indexOf('<style>'), page.indexOf('</style>'));
const script = page.slice(page.lastIndexOf('<script>'));
const ruleOf = (selector) => {
  const at = style.indexOf(selector + ' {');
  return at < 0 ? '' : style.slice(at, style.indexOf('}', at));
};

describe('the settings window', () => {
  test('follows the theme class, not the system color scheme', () => {
    expect(style).not.toContain('prefers-color-scheme');
    expect(style).toMatch(/\.dark-theme \{ color-scheme: dark; \}/);
  });

  test('uses the Web UI blue only, never the old blues', () => {
    for (const old of ['#0d6efd', '#0b5ed7', '#0071e3', '#0062cc', '#0a84ff', '#0077e6']) expect(page).not.toContain(old);
  });

  test('every button is a shared one (buttons.css), by its meaning, with no colors of its own', () => {
    const kinds = Array.from(page.matchAll(/<button\b[^>]*>/g), (m) => m[0]);
    expect(kinds.length).toBeGreaterThan(0);
    kinds.forEach((tag) => {
      if (/class="category-button"/.test(tag)) return; // the categories are the window's navigation
      expect(tag).toMatch(/class="btn btn-v2 btn-sm btn-(primary|secondary|tool)\b/);
    });
    const kindOf = (id) => (page.match(new RegExp(`<button[^>]*id="${id}"[^>]*>`)) || [''])[0];
    ['save-settings-btn', 'action-import-db', 'action-export-db', 'actionConfirmOk', 'unsavedSave'].forEach((id) => expect(kindOf(id)).toContain('btn-primary'));
    ['close-settings-btn', 'action-start', 'action-build', 'action-open-jupyter', 'select-tts-dict', 'check-for-updates-btn', 'actionConfirmCancel', 'unsavedDiscard']
      .forEach((id) => expect(kindOf(id)).toContain('btn-secondary'));
    expect(script).toContain("button.className = 'btn btn-v2 btn-sm btn-secondary key-check-btn';");
    ['#sidebar-footer button', '#sidebar-footer #close-settings-btn', '.action-btn', '.file-picker-row button', '.confirm-dialog-cancel', '.confirm-dialog-ok', '.key-check-btn']
      .forEach((selector) => expect(ruleOf(selector)).not.toMatch(/background|color/));
  });

  test('the show-key buttons are named and say whether the key shows', () => {
    expect(page.match(/btn-tool btn-icon toggle-api-key-visibility" aria-pressed="false"/g)).toHaveLength(9);
    expect(script).toContain("button.setAttribute('aria-label', settingsI18n.t('settings.buttons.showApiKeys')");
    expect(script).toContain("button.setAttribute('aria-pressed', String(show));");
  });

  test('a saved or failed save keeps its color under the pointer', () => {
    expect(style).toContain('#sidebar-footer #save-settings-btn.saved:hover');
    expect(style).toContain('#sidebar-footer #save-settings-btn.save-failed:hover');
  });

  test('the title is a Web UI modal title with the category icon', () => {
    const title = ruleOf('#content-title');
    expect(title).toContain('font-size: 14.63px');
    expect(title).toContain('var(--modal-title-color, ');
    expect(page).toContain('<h1 id="content-title"><i id="content-title-icon"');
    expect(script).not.toContain("getElementById('content-title').textContent");
    expect((script.match(/setContentTitle\(/g) || []).length).toBeGreaterThanOrEqual(4);
  });

  test('the confirm dialogs and About carry no colors of their own', () => {
    const inline = [...page.matchAll(/style="([^"]*)"/g)].map((m) => m[1]);
    const colored = inline.filter((s) => /(^|[\s;])(color|background-color|background)\s*:/.test(s) && !/rgba\(0,0,0,0\.5\)/.test(s));
    expect(colored).toEqual([]);
    // Nor a fixed color on a line or anywhere else in an inline style.
    expect(inline.filter((s) => /#[0-9a-f]{3,8}\b/i.test(s))).toEqual([]);
  });

  test('dark surfaces and text come from the shared variables with dark fallbacks', () => {
    for (const selector of ['.dark-theme body', '.dark-theme #settings-content', '.dark-theme .confirm-dialog-box', '.dark-theme .about-link']) {
      expect(ruleOf(selector)).toMatch(/var\(--[a-z-]+, #[0-9a-f]{3,6}\)/i);
    }
  });

  test("the window's own background is its page's body color, light and dark", () => {
    const tokens = fs.readFileSync(path.join(ROOT, 'docker', 'services', 'ruby', 'public', 'css', 'tokens.css'), 'utf8');
    const bgPanel = tokens.slice(tokens.indexOf('.dark-theme {')).match(/--bg-panel:\s*(#[0-9a-fA-F]+)/)[1];
    expect(main).toContain(`nativeTheme.shouldUseDarkColors ? '${bgPanel}' : '#f5f5f7'`);
    expect(ruleOf('.dark-theme body')).toContain(`var(--bg-panel, ${bgPanel})`);
    expect(style).toMatch(/body \{[^}]*background-color: #f5f5f7;/);
    expect(main).toContain('backgroundColor: settingsBackground()');
    expect(main).toContain('settingsWindow.setBackgroundColor(settingsBackground())');
  });
});
