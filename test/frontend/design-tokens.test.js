// The Web UI's CSS variables live in tokens.css. The page must load it after
// vendor-layers.css (whose first @layer statement fixes the layer order) and
// before monadic.css (which uses the variables), and monadic.css must not
// define them again.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

describe('design tokens', () => {
  const page = read('docker/services/ruby/views/index.erb');
  const tokens = read('docker/services/ruby/public/css/tokens.css');
  const monadic = read('docker/services/ruby/public/css/monadic.css');

  it('is loaded after vendor-layers.css and before monadic.css', () => {
    const at = (name) => page.indexOf(`css/${name}?`);
    expect(at('vendor-layers.css')).toBeGreaterThan(-1);
    expect(at('tokens.css')).toBeGreaterThan(at('vendor-layers.css'));
    expect(at('monadic.css')).toBeGreaterThan(at('tokens.css'));
  });

  it('defines the light and dark values, and monadic.css does not define them again', () => {
    const defined = (css) => new Set([...css.matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]));
    const inTokens = defined(tokens);
    expect(inTokens.size).toBeGreaterThan(100);
    expect(tokens).toMatch(/@layer base \{[\s\S]*:root \{[\s\S]*\.dark-theme \{/);
    const again = [...defined(monadic)].filter((v) => inTokens.has(v));
    expect(again).toEqual([]);
  });

  // Bootstrap's .text-muted, .form-text and .text-body-secondary take
  // --bs-secondary-color with !important, so a dark .text-muted rule in
  // monadic.css never wins; the variable itself has to change in dark.
  it("gives Bootstrap's secondary text a dark value in dark mode", () => {
    const dark = tokens.slice(tokens.indexOf('.dark-theme {'));
    expect(dark).toMatch(/--bs-secondary-color:\s*var\(--text-muted\);/);
    expect(tokens.slice(0, tokens.indexOf('.dark-theme {'))).not.toContain('--bs-secondary-color');
    expect(monadic).not.toMatch(/\.dark-theme [^{,]*\.text-muted\s*[,{]/);
  });
});
