// In monadic.css the layers are base, components, dark-theme. For !important
// declarations an earlier layer wins, so a dark-theme rule marked !important
// for a selector that base or components also marks !important never applies:
// the status line kept its light background in dark this way.
const fs = require('fs');
const path = require('path');

const CSS = path.join(__dirname, '../../docker/services/ruby/public/css/monadic.css');

function layerText(css, name) {
  let text = '';
  const re = new RegExp(`@layer\\s+${name}\\s*\\{`, 'g');
  let m;
  while ((m = re.exec(css))) {
    let i = re.lastIndex; let depth = 1;
    while (depth) { depth += css[i] === '{' ? 1 : css[i] === '}' ? -1 : 0; i += 1; }
    text += css.slice(re.lastIndex, i - 1);
  }
  return text;
}

function importantDeclarations(text) {
  const out = new Set();
  for (const m of text.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selectors = m[1].split(',').map((s) => s.trim()).filter(Boolean);
    for (const d of m[2].split(';')) {
      if (!d.includes('!important') || !d.includes(':')) continue;
      const prop = d.split(':')[0].trim();
      selectors.forEach((s) => out.add(`${s}|${prop}`));
    }
  }
  return out;
}

describe('dark theme !important across layers', () => {
  const css = fs.readFileSync(CSS, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const light = new Set([...importantDeclarations(layerText(css, 'base')), ...importantDeclarations(layerText(css, 'components'))]);
  const dark = importantDeclarations(layerText(css, 'dark-theme'));

  test('the layers are found', () => {
    expect(light.size).toBeGreaterThan(10);
    expect(dark.size).toBeGreaterThan(10);
  });

  test('no dark-theme !important is beaten by the same selector in an earlier layer', () => {
    const beaten = [...dark].filter((key) => {
      const [selector, prop] = key.split('|');
      return light.has(`${selector.replace(/^(?:html|body)?\.dark-theme\s+/, '')}|${prop}`);
    });
    expect(beaten).toEqual([]);
  });
});
