// The shared buttons (buttons.css) in a real browser, with the stylesheets
// each page has in the app: the Web UI's message tools row, the settings
// window's buttons, and the console's row. One small size for the row and for the footer, the
// meaning's colors readable in both themes, the states, long labels wrapping
// at a narrow width, and a window that could not read the shared sheets still
// showing its buttons. Driven by support/buttons-browser.mjs in a child
// process; a run that does not finish is a failure.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const TOKENS = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/css/tokens.css'), 'utf8');
const token = (name) => TOKENS.match(new RegExp(`${name}:\\s*([^;]+);`))[1].trim();
const SMALL = parseFloat(token('--btn-h-sm'));
const MEDIUM = parseFloat(token('--btn-h-md'));
const RADIUS = token('--btn-radius');
const DISABLED = token('--opacity-disabled');

const rgb = (color) => color.match(/[\d.]+/g).slice(0, 3).map(Number);
const luminance = (color) => {
  const [r, g, b] = rgb(color).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

const TOOLS = ['anonymize', 'voice'];
const FOOTER = ['save-settings-btn', 'close-settings-btn'];
const RUNNING = ['start', 'stop', 'restart', 'browser'];
const OTHERS = ['sharedfolder', 'settings', 'exit'];

describe('The shared buttons in a browser', () => {
  let r;

  beforeAll(() => {
    const run = spawnSync(process.execPath, [path.join(__dirname, 'support/buttons-browser.mjs')], {
      encoding: 'utf8', timeout: 90000
    });
    if (run.error || run.signal || run.status !== 0) {
      throw new Error(`the browser run did not end well (${run.error || run.signal || run.status}): ${(run.stderr || '').slice(-2000)}`);
    }
    const line = (run.stdout || '').split('\n').find((l) => l.startsWith('RESULT '));
    if (!line) throw new Error(`the browser run gave no result: ${(run.stderr || '').slice(-2000)}`);
    r = JSON.parse(line.slice('RESULT '.length));
  }, 120000);

  const near = (a, b, within = 0.5) => expect(Math.abs(a - b)).toBeLessThanOrEqual(within);

  const PARTS = JSON.parse(fs.readFileSync(path.join(__dirname, '../fixtures/button-parts.json'), 'utf8'));

  test.each(['wide', 'narrow', 'dark'])('every shared button in the view (%s) is its size, shows its whole label, and has a readable meaning color or is a tool on a panel', (name) => {
    const { buttons, unseen } = r.view[name];
    expect(unseen).toEqual([]);
    expect(buttons.length).toBeGreaterThan(50);
    buttons.forEach((b) => {
      const label = `${b.id}`;
      // A link is as tall as its line.
      if (!b.link) expect({ label, at: b.height >= (b.small ? SMALL : MEDIUM) - 0.5 }).toEqual({ label, at: true });
      if (b.icon) near(b.width, b.small ? SMALL : MEDIUM);
      expect({ label, cut: b.cut }).toEqual({ label, cut: 0 });
      // A meaning color, or a tool on its group's panel.
      const part = b.classes.some((c) => PARTS[c]);
      expect({ label, kind: !!b.meaning || (b.tool && !!b.panel) || b.link || part }).toEqual({ label, kind: true });
      const face = b.bg === 'rgba(0, 0, 0, 0)' ? b.behind : b.bg;
      expect({ label, readable: contrast(b.fg, face) >= 4.5 }).toEqual({ label, readable: true });
    });
  });

  test('the top bar\'s status label is as tall as the small buttons beside it, on one line with them', () => {
    const [status, ...buttons] = r.view.wide.bar;
    near(status.height, SMALL);
    buttons.forEach((b) => {
      near(b.height, SMALL);
      near(b.middle, status.middle);
    });
  });

  test('the floating buttons over the Web UI are two groups of small square tools, without colors of their own', () => {
    expect(r.floating.map((g) => g.map((b) => b.label))).toEqual([
      ['Zoom In', 'Zoom Out', 'Reset Zoom'], ['Reset All', 'Monadic Chat Console']
    ]);
    r.floating.flat().forEach((b) => {
      near(b.width, SMALL);
      near(b.height, SMALL);
      expect(b.bg).toBe('rgba(0, 0, 0, 0)');
      expect(contrast(b.fg, b.panel)).toBeGreaterThanOrEqual(4.5);
    });
  });

  test('Live Conversation\'s button is a small shared button in its own violet, red while live, readable in both themes', () => {
    ['light', 'dark'].forEach((theme) => {
      const { rest, live } = r.live[theme];
      [rest, live].forEach((look) => {
        near(look.height, SMALL);
        expect(contrast(look.fg, look.bg)).toBeGreaterThanOrEqual(4.5);
      });
      expect(live.bg).not.toBe(rest.bg);
      // Violet: more blue than green in it.
      const [, green, blue] = rgb(rest.bg);
      expect(blue).toBeGreaterThan(green);
    });
  });

  test('the exceptions in the table differ only as listed, in both themes', () => {
    const table = JSON.parse(fs.readFileSync(path.join(__dirname, '../fixtures/button-exceptions.json'), 'utf8'));
    const live = table.find((entry) => entry.element === '#lc-toggle');
    expect(live).toBeDefined();
    ['light', 'dark'].forEach((theme) => {
      const { rest, tokens } = r.live[theme];
      Object.entries(live.expect).forEach(([property, token]) => {
        expect(property).toBe('background-color');
        expect(rest.bg).toBe(tokens[token]);
      });
      // Its size is the shared one.
      near(rest.height, SMALL);
    });
  });

  test('after a start the page puts the focus on Live Conversation\'s button, and Enter presses it', () => {
    expect(r.live.light.focused).toBe(true);
    expect(r.live.dark.focused).toBe(true);
    expect(r.liveEnter).toEqual({ focused: 'lc-toggle', pressed: 1 });
  });

  test('a choice of one keeps its radios: the checked one\'s label is the chosen tool, the arrows move it, the keyboard\'s ring shows', () => {
    const filled = (l) => l.bg !== 'rgba(0, 0, 0, 0)';
    expect(r.choice.start.map((l) => [l.checked, filled(l)])).toEqual([[false, false], [true, true]]);
    expect(r.choice.arrowed.map((l) => [l.checked, filled(l), l.outline])).toEqual([[true, true, 'solid'], [false, false, 'none']]);
    expect(r.choice.clicked.map((l) => [l.checked, filled(l)])).toEqual([[false, false], [true, true]]);
    r.choice.start.forEach((l) => near(l.height, SMALL));
  });

  test('the message tools are one row of small buttons, one height and one look', () => {
    TOOLS.forEach((id) => {
      const b = r.web[id];
      near(b.height, SMALL);
      near(b.top, r.web[TOOLS[0]].top);
      expect(b.radius).toBe(RADIUS);
      expect(b.bg).toBe(r.web[TOOLS[0]].bg);
      expect(b.cut).toBe(0);
    });
  });

  test('their yellow is readable in both themes, and darker under the pointer', () => {
    [r.web, r.webDark].forEach((theme) => {
      TOOLS.forEach((id) => expect(contrast(theme[id].fg, theme[id].bg)).toBeGreaterThanOrEqual(4.5));
    });
    expect(r.webHover).not.toBe(r.webDark.anonymize.bg);
    expect(luminance(r.webHover)).toBeLessThan(luminance(r.webDark.anonymize.bg));
  });

  test('the keyboard focus shows a ring, and a disabled button is made lighter once', () => {
    expect(r.webFocus).toEqual({ outline: 'solid', matches: true });
    expect(r.webDisabled).toBe(DISABLED);
  });

  test('at a narrow width long labels wrap and make the buttons taller, nothing sticks out', () => {
    expect(r.webNarrow.out).toEqual([]);
    TOOLS.forEach((id) => {
      expect(r.webNarrowButtons[id].height).toBeGreaterThan(SMALL);
      expect(r.webNarrowButtons[id].cut).toBe(0);
    });
  });

  test('the settings window\'s Save and Close are the same small buttons, blue and grey, readable in both themes', () => {
    [r.settings, r.settingsDark].forEach((theme) => {
      FOOTER.forEach((id) => {
        near(theme[id].height, SMALL);
        expect(theme[id].radius).toBe(RADIUS);
        expect(contrast(theme[id].fg, theme[id].bg)).toBeGreaterThanOrEqual(4.5);
      });
      near(theme[FOOTER[0]].top, theme[FOOTER[1]].top);
      expect(theme[FOOTER[0]].bg).not.toBe(theme[FOOTER[1]].bg);
      // Save is the blue: more blue than red in it.
      const [red, , blue] = rgb(theme[FOOTER[0]].bg);
      expect(blue).toBeGreaterThan(red);
    });
  });

  test('the console\'s buttons are one row of small buttons: yellow for running the app, grey for the rest, readable in both themes', () => {
    [r.console, r.consoleDark].forEach((theme) => {
      [...RUNNING, ...OTHERS].forEach((id) => {
        near(theme[id].height, SMALL);
        near(theme[id].top, theme.start.top);
        expect(contrast(theme[id].fg, theme[id].bg)).toBeGreaterThanOrEqual(4.5);
      });
      RUNNING.forEach((id) => expect(theme[id].bg).toBe(theme.start.bg));
      OTHERS.forEach((id) => expect(theme[id].bg).toBe(theme.exit.bg));
      expect(theme.start.bg).not.toBe(theme.exit.bg);
      // Stop, Restart and Open Browser start disabled.
      ['stop', 'restart', 'browser'].forEach((id) => expect(theme[id].opacity).toBe(DISABLED));
    });
  });

  test('in a narrow console the row wraps and stays inside the window', () => {
    expect(r.consoleNarrow.exit.top).toBeGreaterThan(r.consoleNarrow.start.top);
    expect(r.consoleNarrowBottom.row).toBeLessThanOrEqual(r.consoleNarrowBottom.window);
  });

  test('the settings panels\' buttons are the same small buttons: blue to take in or write out, grey for the rest', () => {
    Object.values(r.panels).forEach((panel) => Object.values(panel).forEach((b) => near(b.height, SMALL)));
    const actions = r.panels['panel-actions'];
    expect(actions['action-import-db'].bg).toBe(r.settings[FOOTER[0]].bg);
    expect(actions['action-export-db'].bg).toBe(r.settings[FOOTER[0]].bg);
    ['action-start', 'action-build', 'action-open-jupyter'].forEach((id) => expect(actions[id].bg).toBe(r.settings[FOOTER[1]].bg));
    expect(r.panels['panel-about']['check-for-updates-btn'].bg).toBe(r.settings[FOOTER[1]].bg);
    expect(r.panels['panel-voice']['select-tts-dict'].bg).toBe(r.settings[FOOTER[1]].bg);
    // Before the app has started, the container actions are disabled.
    Object.values(actions).forEach((b) => expect(b.opacity).toBe(DISABLED));
  });

  test('the show-key button is a small square inside its field, which leaves room for it', () => {
    expect(r.keyField.inside).toBe(true);
    expect(r.keyField.room).toBe(true);
    near(r.keyField.width, SMALL);
    near(r.keyField.height, SMALL);
  });

  test('a settings window that could not read the shared sheets still shows Save and Close', () => {
    FOOTER.forEach((id) => {
      expect(r.settingsAlone[id].width).toBeGreaterThan(0);
      expect(r.settingsAlone[id].height).toBeGreaterThan(0);
      expect(r.settingsAlone[id].cut).toBe(0);
    });
  });
});
