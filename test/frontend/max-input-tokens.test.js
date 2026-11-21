/**
 * @jest-environment jsdom
 */
// The input limit the page sends with a message, read from the model catalog
// as it is.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const JS = path.join(__dirname, '../../docker/services/ruby/public/js/monadic');

function load() {
  const utilities = fs.readFileSync(path.join(JS, 'utilities.js'), 'utf8');
  const fn = utilities.match(/function maxInputTokensOf\(spec\) \{[\s\S]*?\n\}\n/);
  if (!fn) throw new Error('maxInputTokensOf not found in utilities.js');
  const context = { window: {}, module: { exports: {} }, console };
  vm.createContext(context);
  vm.runInContext(`${fs.readFileSync(path.join(JS, 'model_spec.js'), 'utf8')}\n;this.spec = modelSpec;`, context);
  vm.runInContext(`const DEFAULT_MAX_INPUT_TOKENS = 4000;\n${fn[0]}\nthis.maxInputTokensOf = maxInputTokensOf;`, context);
  return context;
}

describe('the input limit sent with a message', () => {
  const { spec, maxInputTokensOf } = load();

  test('is a number for every model of the catalog that has a context window', () => {
    const withWindow = Object.entries(spec).filter(([, model]) => model.context_window !== undefined);
    expect(withWindow.length).toBeGreaterThan(50);
    withWindow.forEach(([name, model]) => {
      const range = model.context_window;
      expect([name, maxInputTokensOf(model)]).toEqual([name, range[range.length - 1]]);
    });
  });

  test('reads a window written as one number, and one written as a range', () => {
    expect(maxInputTokensOf({ context_window: [1048576] })).toBe(1048576);
    expect(maxInputTokensOf({ context_window: [1, 200000] })).toBe(200000);
  });

  test('is the default for a model with no window', () => {
    [undefined, null, {}, { context_window: [] }, { context_window: ['x'] }].forEach((model) => {
      expect(maxInputTokensOf(model)).toBe(4000);
    });
  });
});
