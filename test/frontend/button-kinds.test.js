/**
 * @jest-environment jsdom
 */
// Buttons take one of the kinds of the Web UI, filled: blue (confirm),
// grey (act, move about, cancel), red (delete) and yellow (a standing action
// of the side column); in a toolbar or a switch, btn-tool (clear on its
// group's panel, the chosen one filled). A white button with only a border, or another
// colour, is used only where the border or the colour itself says
// something, listed here.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../docker/services/ruby');
const FILES = ['views/index.erb'].concat(
  fs.readdirSync(path.join(ROOT, 'public/js/monadic')).filter((f) => f.endsWith('.js')).map((f) => `public/js/monadic/${f}`),
  ['public/js/monadic.js']
);
const OTHER_KINDS = /\bbtn-(outline-[a-z]+|light|dark|success|info)\b/;
// Where another kind is meant, by what the line holds.
const EXCEPTIONS = [];

// Every shared button (.btn), in the Web UI and in the app's windows, has
// a meaning or a form, or is in the table of exceptions (each with what it
// may differ in and why), which the browser test reads too.
// Buttons that are parts of their own, not the shared buttons (what they
// are tells how they look), by a class each: the browser test reads it too.
const COMPONENTS = JSON.parse(fs.readFileSync(path.join(__dirname, '../fixtures/button-parts.json'), 'utf8'));

const TABLE = JSON.parse(fs.readFileSync(path.join(__dirname, '../fixtures/button-exceptions.json'), 'utf8'));
const KINDS = /\bbtn-(primary|secondary|danger|warning|tool|link)\b/;
const SHARED_FILES = FILES.map((file) => path.join(ROOT, file))
  .concat(['index.html', 'settings.html', 'main.js'].map((file) => path.join(__dirname, '../../app', file)));
const sharedButtons = () => SHARED_FILES.flatMap((file) => {
  const text = fs.readFileSync(file, 'utf8');
  // A button's whole class list as written (a list with its kind chosen
  // elsewhere, e.g. workbench.js's button(), is tested where it is chosen;
  // a part of its own may use Bootstrap's .btn for its box).
  return Array.from(text.matchAll(/["'`](btn\s[^"'`\n]*)["'`]/g), (m) => ({ file: path.basename(file), classes: m[1] }))
    .filter(({ classes }) => !classes.includes('${') && !/\s$/.test(classes) && !classes.split(/\s+/).some((c) => COMPONENTS[c]));
});

describe('button kinds', () => {
  test.each(FILES)('%s uses only the kinds of the Web UI, but where listed', (file) => {
    const odd = fs.readFileSync(path.join(ROOT, file), 'utf8').split('\n')
      .map((line, i) => [i + 1, line])
      .filter(([, line]) => OTHER_KINDS.test(line) && !EXCEPTIONS.some((rule) => rule.test(line)))
      .map(([n, line]) => `${file}:${n}: ${line.trim()}`);
    expect(odd).toEqual([]);
  });

  test('every shared button has a meaning or a form, or is in the table of exceptions', () => {
    const buttons = sharedButtons();
    expect(buttons.length).toBeGreaterThan(50);
    const odd = buttons.filter(({ classes }) => !KINDS.test(classes)
      && !TABLE.some((entry) => classes.split(/\s+/).includes(entry.class)));
    expect(odd).toEqual([]);
  });


  test('every button in the Web UI is a shared one or a part of its own', () => {
    const odd = FILES.flatMap((file) => {
      const text = fs.readFileSync(path.join(ROOT, file), 'utf8');
      const lists = Array.from(text.matchAll(/<button\b[^>]*?class=["']([^"']*)["']/g), (m) => m[1])
        .concat(Array.from(text.matchAll(/element\('button',\s*['`"]([^'`"]*)['`"]/g), (m) => m[1]));
      return lists.filter((list) => {
        // A template's ${...} ends a class name too.
        const classes = list.split(/[\s$]+/);
        if (classes.includes('btn') && !classes.some((c) => COMPONENTS[c])) return false;
        return !classes.some((c) => COMPONENTS[c] || TABLE.some((entry) => entry.class === c));
      }).map((list) => `${file}: ${list}`);
    });
    expect(odd).toEqual([]);
  });

  test('each entry of the table names a button that is there, what it may differ in, and why', () => {
    expect(TABLE.length).toBeGreaterThan(0);
    const all = SHARED_FILES.map((file) => fs.readFileSync(file, 'utf8')).join('\n');
    TABLE.forEach((entry) => {
      expect(Object.keys(entry).sort()).toEqual(['class', 'element', 'expect', 'reason', 'rule', 'screen', 'state']);
      expect(all).toContain(entry.class);
      expect(all).toContain(entry.element.replace(/^#/, 'id="'));
      // A reason the user would give, not the past or the looks.
      expect(entry.reason).not.toMatch(/as before|as it was|looks? (nicer|better)/i);
    });
  });

  test('each exception still names something there', () => {
    const all = FILES.map((file) => fs.readFileSync(path.join(ROOT, file), 'utf8')).join('\n');
    EXCEPTIONS.forEach((rule) => expect(all).toMatch(rule));
  });
});
