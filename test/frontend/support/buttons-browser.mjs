// Measures the shared buttons (buttons.css) in a headless browser, on the
// pages that use them, with the stylesheets each page has in the app: the
// Web UI's message tools row (vendor-layers.css with Bootstrap, tokens.css,
// buttons.css, monadic.css), the console's row (index.html) and the
// settings window's Save and Close (settings.html as it is), each with
// tokens.css and buttons.css put in as the Electron window gets them.
// Run by buttons-browser.test.js as a child process (puppeteer is an ES
// module); prints what it measured as one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(here, '../../..');
const PUBLIC = path.join(ROOT, 'docker/services/ruby/public');
const APP = path.join(ROOT, 'app');

const VIEW = fs.readFileSync(path.join(ROOT, 'docker/services/ruby/views/index.erb'), 'utf8');
const between = (from, to) => {
  const start = VIEW.indexOf(from);
  return VIEW.slice(start, VIEW.indexOf(to, start)).replace(/<%#[\s\S]*?%>/g, '');
};
// The row as the view has it, and the Send and Clear row (not moved yet)
// for the buttons next to it.
const TOOLS = `${between('<div class="d-flex align-items-center flex-wrap message-tools">', '</div>\n                </div>')}</div>`;
const SEND = between('<button id="send"', '<button id="clear"') + between('<button id="clear"', '</button>') + '</button>';

const WEB = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/vendor/css/montserrat.css">
<link rel="stylesheet" href="/css/vendor-layers.css">
<link rel="stylesheet" href="/css/tokens.css">
<link rel="stylesheet" href="/css/buttons.css">
<link rel="stylesheet" href="/css/monadic.css">
<link rel="stylesheet" href="/vendor/css/all.min.css">
</head><body><div id="main"><div id="user-panel"><div id="tools-holder">${TOOLS}</div>
<div class="d-flex">${SEND}</div></div></div></body></html>`;

// The settings window as Electron loads it, with the shared sheets put in
// (or, for the window that cannot read them, left out).
const SETTINGS = fs.readFileSync(path.join(APP, 'settings.html'), 'utf8');
const CONSOLE = fs.readFileSync(path.join(APP, 'index.html'), 'utf8');
const consolePage = () => CONSOLE.replace('<head>', '<head><base href="/app/"><link rel="stylesheet" href="/css/tokens.css"><link rel="stylesheet" href="/css/buttons.css">');
const settingsPage = (shared) => SETTINGS.replace('<head>', `<head><base href="/app/">${shared
  ? '<link rel="stylesheet" href="/css/tokens.css"><link rel="stylesheet" href="/css/buttons.css">'
  : ''}`);

// The whole view, its ERB and scripts left out: every shared button in it,
// measured where it shows (the page, each modal opened, the holders the app
// shows by script opened one at a time).
const VIEW_PAGE = VIEW.replace(/<%#[\s\S]*?%>/g, '').replace(/<%=[\s\S]*?%>/g, '').replace(/<%[\s\S]*?%>/g, '')
  .replace(/<script\b[\s\S]*?<\/script>/g, '');

// The buttons the app's main process puts over the Web UI (main.js), run
// as it runs them.
const MAIN = fs.readFileSync(path.join(APP, 'main.js'), 'utf8');
const FLOATING = MAIN.match(/const injectButtonJS = `([\s\S]*?)`;/)[1];

const TYPES = { '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    const pages = { '/view': VIEW_PAGE, '/console': consolePage(), '/web': WEB, '/settings': settingsPage(true), '/settings-alone': settingsPage(false) };
    if (pages[url]) {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(pages[url]);
      return;
    }
    const base = url.startsWith('/app/') ? APP : PUBLIC;
    const file = path.join(base, url.startsWith('/app/') ? url.slice(5) : url);
    if (!file.startsWith(base) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// Each button's box and look; hidden ones are left out.
const measure = (ids) => {
  const out = {};
  ids.forEach((id) => {
    const el = document.getElementById(id);
    if (!el) { out[id] = null; return; }
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    out[id] = {
      width: r.width, height: r.height, top: r.top,
      bg: cs.backgroundColor, fg: cs.color, radius: cs.borderTopLeftRadius,
      minHeight: cs.minHeight, whiteSpace: cs.whiteSpace, opacity: cs.opacity, outline: cs.outlineStyle,
      cut: el.scrollWidth - el.clientWidth
    };
  });
  return out;
};

// Past the buttons' color transition.
const settled = () => new Promise((resolve) => { setTimeout(resolve, 300); });

// Every btn: its size class and what it measures, and the ones never
// shown (none expected).
const everyButton = () => {
  const seen = new Map();
  const take = () => document.querySelectorAll('.btn').forEach((b) => {
    const r = b.getBoundingClientRect();
    if (!r.width || seen.has(b)) return;
    const cs = getComputedStyle(b);
    seen.set(b, {
      id: b.id || b.className, classes: Array.from(b.classList), small: b.classList.contains('btn-sm'), icon: b.classList.contains('btn-icon'), link: b.classList.contains('btn-link'),
      height: r.height, width: r.width, cut: b.scrollWidth - b.clientWidth,
      meaning: ['btn-primary', 'btn-secondary', 'btn-danger', 'btn-warning'].find((k) => b.classList.contains(k)) || null,
      tool: b.classList.contains('btn-tool'),
      // A tool sits on its group's panel (or on the top bar); clear, it
      // shows that color.
      panel: b.closest('.btn-panel, .navbar') ? getComputedStyle(b.closest('.btn-panel, .navbar')).backgroundColor : null,
      // What shows behind a clear button: the nearest filled box around it.
      behind: (() => {
        for (let el = b.parentElement; el; el = el.parentElement) {
          const color = getComputedStyle(el).backgroundColor;
          if (color !== 'rgba(0, 0, 0, 0)') return color;
        }
        return 'rgb(255, 255, 255)';
      })(),
      bg: cs.backgroundColor, fg: cs.color
    });
  });
  take();
  document.querySelectorAll('.modal').forEach((m) => {
    m.classList.add('show'); m.style.display = 'block';
    take();
    m.classList.remove('show'); m.style.display = '';
  });
  Array.from(document.querySelectorAll('.btn')).filter((b) => !seen.has(b)).forEach((b) => {
    const undo = [];
    const chain = [];
    for (let el = b; el && el !== document.body; el = el.parentElement) chain.unshift(el);
    chain.forEach((el) => {
      if (el.hidden) { el.hidden = false; undo.push(() => { el.hidden = true; }); }
      if (getComputedStyle(el).display === 'none') {
        const was = el.style.getPropertyValue('display');
        el.style.setProperty('display', 'block', 'important');
        undo.push(() => { el.style.setProperty('display', was); });
      }
    });
    take();
    undo.reverse().forEach((f) => f());
  });
  return { buttons: Array.from(seen.values()), unseen: Array.from(document.querySelectorAll('.btn')).filter((b) => !seen.has(b)).map((b) => b.id || b.className) };
};

const TOOL_IDS = ['anonymize', 'voice'];
const SETTINGS_IDS = ['save-settings-btn', 'close-settings-btn'];
const PANELS = {
  'panel-actions': ['action-start', 'action-build', 'action-open-jupyter', 'action-import-db', 'action-export-db'],
  'panel-about': ['check-for-updates-btn'],
  'panel-voice': ['select-tts-dict']
};
const CONSOLE_IDS = ['start', 'stop', 'restart', 'browser', 'sharedfolder', 'settings', 'exit'];

async function look(page, url, ids, { dark = false, width = 1280 } = {}) {
  await page.setViewport({ width, height: 800 });
  await page.goto(url);
  await page.evaluate(() => document.fonts.ready);
  if (dark) await page.evaluate(() => document.documentElement.classList.add('dark-theme'));
  await settled();
  return page.evaluate(measure, ids);
}

async function main() {
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    page.on('pageerror', () => {}); // settings.html's script needs the window's preload; its look does not
    const out = {};
    out.view = {};
    for (const [name, options] of Object.entries({ wide: {}, narrow: { width: 390 }, dark: { dark: true } })) {
      await look(page, `${base}/view`, [], options);
      out.view[name] = await page.evaluate(everyButton);
      // The top bar: the status label beside its buttons.
      out.view[name].bar = await page.evaluate(() => ['status-message', 'cancel_query', 'toggle-menu'].map((id) => {
        const el = document.getElementById(id);
        if (el.style.display === 'none') el.style.removeProperty('display');
        const r = el.getBoundingClientRect();
        return { id, height: r.height, middle: r.top + r.height / 2 };
      }));
    }
    // The floating groups at the bottom right.
    await look(page, `${base}/view`, []);
    out.floating = await page.evaluate((script) => {
      window.electronAPI = {};
      (0, eval)(script);
      const groups = Array.from(document.querySelectorAll('body > div > .btn-panel.btn-fab'));
      return groups.map((g) => {
        const panel = getComputedStyle(g).backgroundColor;
        return Array.from(g.querySelectorAll('button')).map((b) => {
          const r = b.getBoundingClientRect();
          const cs = getComputedStyle(b);
          return { label: b.getAttribute('aria-label'), width: r.width, height: r.height, fg: cs.color, bg: cs.backgroundColor, panel };
        });
      });
    }, FLOATING);
    // Live Conversation: its button where the page focuses after a start,
    // Enter pressing it; its colors, at rest and live, in both themes.
    out.live = {};
    for (const dark of [false, true]) {
      await look(page, `${base}/web`, [], { dark });
      const scripts = ['js/monadic/dom-helpers.js', 'js/monadic/utilities.js'].map((f) => fs.readFileSync(path.join(PUBLIC, f), 'utf8'));
      out.live[dark ? 'dark' : 'light'] = await page.evaluate((sources) => {
        sources.forEach((src) => { try { (0, eval)(src); } catch (_) { /* what the page does not need here */ } });
        const button = document.createElement('button');
        button.id = 'lc-toggle';
        button.type = 'button';
        button.className = 'btn btn-sm btn-lc';
        button.textContent = 'Start live conversation';
        window.livePressed = 0;
        button.addEventListener('click', () => { window.livePressed += 1; });
        document.getElementById('user-panel').prepend(button);
        setInputFocus();
        const focused = document.activeElement === button;
        const look = () => {
          const cs = getComputedStyle(button);
          return { bg: cs.backgroundColor, fg: cs.color, height: button.getBoundingClientRect().height };
        };
        const rest = look();
        // The table's tokens, as colors in this theme.
        const probe = document.createElement('div');
        document.body.append(probe);
        const tokens = {};
        ['--btn-live-bg'].forEach((name) => {
          probe.style.backgroundColor = `var(${name})`;
          tokens[name] = getComputedStyle(probe).backgroundColor;
        });
        probe.remove();
        button.classList.add('btn-lc-live');
        return new Promise((resolve) => setTimeout(() => {
          const live = look();
          button.classList.remove('btn-lc-live');
          resolve({ focused, rest, live, tokens });
        }, 300));
      }, scripts);
    }
    await page.keyboard.press('Enter');
    out.liveEnter = await page.evaluate(() => ({ focused: document.activeElement && document.activeElement.id, pressed: window.livePressed }));
    // A choice of one (the reasoning switch): the checked radio's label is
    // the chosen tool; the arrows move the choice; the keyboard's ring shows
    // on the label.
    await look(page, `${base}/web`, []);
    const reasoning = fs.readFileSync(path.join(PUBLIC, 'js/monadic/reasoning-ui-manager.js'), 'utf8')
      .match(/deepseekUI\.innerHTML = `([\s\S]*?)`;/)[1];
    await page.evaluate((html) => {
      const box = document.createElement('div');
      box.id = 'choice-box';
      box.innerHTML = html;
      document.body.prepend(box);
    }, reasoning);
    const labels = () => page.evaluate(() => ['reasoning-off', 'reasoning-on'].map((id) => {
      const l = document.querySelector(`label[for="${id}"]`);
      const cs = getComputedStyle(l);
      return { checked: document.getElementById(id).checked, bg: cs.backgroundColor, outline: cs.outlineStyle, height: l.getBoundingClientRect().height };
    }));
    out.choice = { start: await labels() };
    await page.focus('#reasoning-on');
    await page.keyboard.press('ArrowLeft');
    await settled();
    out.choice.arrowed = await labels();
    await page.click('label[for="reasoning-on"]');
    await settled();
    out.choice.clicked = await labels();
    out.web = await look(page, `${base}/web`, [...TOOL_IDS, 'send']);
    out.webDark = await look(page, `${base}/web`, TOOL_IDS, { dark: true });
    // Hover, then the keyboard's focus ring.
    await page.hover('#anonymize');
    await settled();
    out.webHover = await page.evaluate(() => getComputedStyle(document.getElementById('anonymize')).backgroundColor);
    await page.mouse.move(0, 0);
    await page.focus('#anonymize');
    await page.keyboard.press('Shift');
    out.webFocus = await page.evaluate(() => {
      const el = document.getElementById('anonymize');
      el.blur();
      el.focus({ focusVisible: true });
      return { outline: getComputedStyle(el).outlineStyle, matches: el.matches(':focus-visible') };
    });
    out.webDisabled = await page.evaluate(() => {
      const el = document.getElementById('anonymize');
      el.disabled = true;
      return getComputedStyle(el).opacity;
    });
    // A narrow row with long labels: the buttons wrap their text, nothing
    // is cut or sticks out of the row.
    await look(page, `${base}/web`, TOOL_IDS, { width: 320 });
    out.webNarrow = await page.evaluate((ids) => {
      ids.forEach((id) => { document.getElementById(id).lastChild.textContent = ' A label much longer than the button can hold on one line'; });
      const right = document.documentElement.clientWidth;
      return { out: ids.filter((id) => document.getElementById(id).getBoundingClientRect().right > right + 0.5) };
    }, TOOL_IDS);
    out.webNarrowButtons = await page.evaluate(measure, TOOL_IDS);
    out.settings = await look(page, `${base}/settings`, SETTINGS_IDS);
    out.settingsDark = await look(page, `${base}/settings`, SETTINGS_IDS, { dark: true });
    out.settingsAlone = await look(page, `${base}/settings-alone`, SETTINGS_IDS);

    // The settings panels with buttons, shown one by one as a category does.
    out.panels = {};
    for (const [panel, ids] of Object.entries(PANELS)) {
      await look(page, `${base}/settings`, []);
      out.panels[panel] = await page.evaluate((name, list) => {
        document.querySelectorAll('.settings-panel').forEach((p) => p.classList.toggle('active', p.id === name));
        return list;
      }, panel, ids).then((list) => page.evaluate(measure, list));
    }
    // The show-key button inside its field: within the field's box, and
    // not over the field's text end (the field leaves room for it).
    out.keyField = await page.evaluate(() => {
      document.querySelectorAll('.settings-panel').forEach((p) => p.classList.toggle('active', p.id === 'panel-api-keys'));
      const button = document.querySelector('.toggle-api-key-visibility');
      const input = document.getElementById(button.getAttribute('data-target'));
      const b = button.getBoundingClientRect();
      const i = input.getBoundingClientRect();
      return {
        inside: b.left >= i.left && b.right <= i.right && b.top >= i.top - 0.5 && b.bottom <= i.bottom + 0.5,
        room: parseFloat(getComputedStyle(input).paddingRight) >= b.width - 2,
        width: b.width, height: b.height, inputHeight: i.height
      };
    });

    out.console = await look(page, `${base}/console`, CONSOLE_IDS);
    out.consoleDark = await look(page, `${base}/console`, CONSOLE_IDS, { dark: true });
    // A narrow console: the row wraps, and stays inside the window.
    out.consoleNarrow = await look(page, `${base}/console`, CONSOLE_IDS, { width: 360 });
    out.consoleNarrowBottom = await page.evaluate(() => ({
      row: document.querySelector('.button-group').getBoundingClientRect().bottom,
      window: window.innerHeight
    }));
    process.stdout.write(`RESULT ${JSON.stringify(out)}\n`);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack}\n`);
  process.exit(1);
});
