// The palette (tokens.css): five families, each one scale of the same steps,
// in light and in dark; the color tokens of buttons, tags, status, links and
// focus take their values from it rather than from colors of their own.
const fs = require('fs');
const path = require('path');

const TOKENS = fs.readFileSync(
  path.join(__dirname, '../../docker/services/ruby/public/css/tokens.css'), 'utf8');
const dark = TOKENS.indexOf('.dark-theme {');
const lightPart = TOKENS.slice(0, dark);
const darkPart = TOKENS.slice(dark);

const FAMILIES = ['accent', 'green', 'amber', 'red', 'grey'];
const STEPS = ['soft', 'line', 'mid', 'strong', 'strong-hover', 'text'];

const palette = (part) => Object.fromEntries(
  Array.from(part.matchAll(/--pal-([a-z-]+):\s*(#[0-9a-fA-F]{6});/g), (m) => [m[1], m[2]]));

describe('the palette', () => {
  test('has every step of every family, in light and in dark', () => {
    const names = FAMILIES.flatMap((f) => STEPS.map((s) => `${f}-${s}`)).sort();
    expect(Object.keys(palette(lightPart)).sort()).toEqual(names);
    expect(Object.keys(palette(darkPart)).sort()).toEqual(names);
  });

  test.each([
    'btn-primary-bg', 'btn-primary-hover-bg', 'btn-success-bg', 'btn-secondary-bg', 'btn-warning', 'btn-danger',
    'status-error', 'status-warning', 'status-info', 'status-success', 'color-link', 'text-link', 'focus-outline',
    'accent-blue', 'accent-green', 'accent-red', 'accent-amber',
    'bdg-blue-bg', 'bdg-green-fg', 'bdg-amber-bd', 'bdg-red-fg', 'bdg-grey-bg'
  ])('gives --%s from the palette', (name) => {
    const values = Array.from(TOKENS.matchAll(new RegExp(`--${name}:\\s*([^;]+);`, 'g')), (m) => m[1].trim());
    expect(values.length).toBeGreaterThan(0);
    values.forEach((value) => expect(value).toMatch(/^var\(--pal-[a-z-]+\)$/));
  });
});
