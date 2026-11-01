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

  test.each([
    ['#sidebar-footer button', '--btn-primary-bg'],
    ['.action-btn', '--btn-primary-bg'],
    ['#sidebar-footer #close-settings-btn', '--btn-secondary-bg'],
    ['.file-picker-row button', '--btn-secondary-bg'],
    ['.confirm-dialog-cancel', '--btn-secondary-bg']
  ])('%s takes its color from %s', (selector, variable) => {
    expect(ruleOf(selector)).toContain(`var(${variable}, `);
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
