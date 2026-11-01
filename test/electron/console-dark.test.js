// The console has a dark look: its own colors, and the message colors that
// would not read on a dark background, are classes with a light and a dark
// value. (Accent icon colors stay inline; they read on both.)
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const read = (f) => fs.readFileSync(path.join(ROOT, 'app', f), 'utf8');
const page = read('index.html');
const main = read('main.js');
const screen = read('mainScreen.js');
const style = page.slice(page.indexOf('<style>'), page.indexOf('</style>'));

const MESSAGE_CLASSES = ['msg-version-app', 'msg-version-container', 'msg-update-done', 'msg-checking', 'msg-stopped', 'icon-ollama'];

describe('the console in dark', () => {
  test.each(MESSAGE_CLASSES)('%s has a light color and a dark one', (cls) => {
    expect(style).toMatch(new RegExp(`(^|\\n)\\s*(i)?\\.${cls}\\s*\\{[^}]*(color|background)`));
    expect(style).toMatch(new RegExp(`\\.dark-theme (i)?\\.${cls}[\\s,{]`));
  });

  test.each(['msg-version-app', 'msg-version-container', 'msg-update-done', 'msg-checking', 'icon-ollama'])('the main process sends %s instead of a color', (cls) => {
    expect(main).toContain(cls);
  });

  test('the stop line is a class, not a color', () => {
    expect(screen).toContain('<p class="msg-stopped"');
    expect(screen).not.toMatch(/<p style="color: #999;"><i class="fa-solid fa-circle-stop">/);
  });

  test.each([
    'background: #e8f4fc', 'background: #f0e8fc', 'background-color: #e8f5e9',
    'style="color: #666; font-size: 12px;"', 'fa-horse" style="color:#333333;"'
  ])('no message carries %s', (inline) => {
    expect(main).not.toContain(inline);
  });

  test('the page, the panels and the links take dark colors from the shared variables', () => {
    for (const rule of ['.dark-theme body', '.dark-theme #messages', '.dark-theme #output', '.dark-theme a']) {
      const at = style.indexOf(rule + ' ');
      expect(at).toBeGreaterThan(-1);
      expect(style.slice(at, style.indexOf('}', at))).toMatch(/var\(--[a-z-]+, #[0-9a-f]{3,6}\)/i);
    }
  });

  test('the yellow buttons keep their black text in dark', () => {
    expect(style).not.toMatch(/\.dark-theme button\s*\{/);
  });

  test('a disabled button is light gray on dark gray, the ones with their own text color too', () => {
    const at = style.indexOf('.dark-theme button:disabled,');
    const rule = style.slice(at, style.indexOf('}', at));
    // button#start and button#browser set black text by id, which a plain
    // :disabled rule cannot beat.
    expect(rule).toContain('.dark-theme button#start:disabled');
    expect(rule).toContain('.dark-theme button#browser:disabled');
    expect(rule).toMatch(/color: #b8b8b8/);
  });

  test("the window's dark background is the page's dark body", () => {
    const tokens = fs.readFileSync(path.join(ROOT, 'docker', 'services', 'ruby', 'public', 'css', 'tokens.css'), 'utf8');
    const dark = tokens.slice(tokens.indexOf('.dark-theme {'));
    const bgBody = dark.match(/--bg-body:\s*(#[0-9a-fA-F]+)/)[1];
    expect(main).toContain(`nativeTheme.shouldUseDarkColors ? '${bgBody}'`);
    expect(style).toContain(`var(--bg-body, ${bgBody})`);
  });

  test("the window's own background follows the theme", () => {
    expect(main).toContain('backgroundColor: consoleBackground()');
    expect(main).toMatch(/nativeTheme\.on\('updated', \(\) => \{\s*if \(mainWindow && !mainWindow\.isDestroyed\(\)\) mainWindow\.setBackgroundColor\(consoleBackground\(\)\);/);
  });
});
