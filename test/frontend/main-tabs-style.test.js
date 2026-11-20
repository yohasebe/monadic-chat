/**
 * @jest-environment jsdom
 */
const fs = require('fs');
const path = require('path');

// The tabs over the main column and the side column share one look.
describe('main column and side column tabs', () => {
  beforeAll(() => {
    const css = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/css/monadic.css'), 'utf8');
    const style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
  });

  const PROPERTIES = ['backgroundColor', 'borderTopStyle', 'paddingLeft', 'marginLeft', 'whiteSpace', 'fontWeight'];

  function look(className, selected) {
    document.body.innerHTML = `<button type="button" class="${className}" role="tab" aria-selected="${selected}">Tab</button>`;
    const computed = getComputedStyle(document.querySelector('button'));
    return Object.fromEntries(PROPERTIES.map((name) => [name, computed[name]]));
  }

  test.each([['selected', 'true'], ['not selected', 'false']])('a %s tab looks the same in both columns', (_label, selected) => {
    expect(look('summary-tab', selected)).toEqual(look('side-pane-tab', selected));
  });
});
