/**
 * @jest-environment jsdom
 */

/**
 * The tooltips of a card header's controls (ui-utilities.js,
 * showCardTooltipsOnHover), with the real tooltip.js.
 */

const path = require('path');
const fs = require('fs');

const RUBY = path.resolve(__dirname, '../../docker/services/ruby/public');

describe('showCardTooltipsOnHover', () => {
  let uiUtils;
  let discourse;

  beforeAll(() => {
    (0, eval)(fs.readFileSync(path.join(RUBY, 'js/monadic/tooltip.js'), 'utf8'));
    document.body.innerHTML = '<div id="discourse"></div>';
    uiUtils = require(path.join(RUBY, 'js/monadic/ui-utilities'));
    discourse = document.getElementById('discourse');
    uiUtils.showCardTooltipsOnHover(discourse);
  });

  afterEach(() => window.MonadicTip.hideAll());

  function addCard(title) {
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `<div class="card-header"><span class="func-copy" title="${title}"><i class="icon"></i></span></div><div class="card-text"></div>`;
    discourse.appendChild(card);
    return card.querySelector('.func-copy');
  }

  function hover(el) {
    el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
  }

  const bubble = () => document.getElementById('monadic-tip');

  test('makes the tooltip of a control when the pointer first comes to it, also to what is inside it, and shows it then', () => {
    const control = addCard('Copy');
    expect(window.MonadicTip.get(control)).toBeNull();
    hover(control.querySelector('.icon'));
    expect(window.MonadicTip.get(control)).not.toBeNull();
    expect(bubble().hidden).toBe(false);
    expect(bubble().textContent).toBe('Copy');
    // The browser's own tooltip does not show too; the bubble describes it.
    expect(control.hasAttribute('title')).toBe(false);
    expect(control.getAttribute('aria-describedby')).toBe('monadic-tip');
  });

  test('makes it again for a card whose tooltips were let go, an earlier card and a later one', () => {
    const earlier = addCard('Copy');
    hover(earlier);
    const later = addCard('Delete');
    hover(later);

    window.MonadicTip.disposeWithin(discourse);
    expect(window.MonadicTip.get(earlier)).toBeNull();
    expect(window.MonadicTip.get(later)).toBeNull();
    // The title is back on each control.
    expect(earlier.getAttribute('title')).toBe('Copy');

    hover(earlier);
    hover(later);
    expect(window.MonadicTip.get(earlier)).not.toBeNull();
    expect(window.MonadicTip.get(later)).not.toBeNull();
    expect(bubble().textContent).toBe('Delete');
  });

  test('leaves what is outside a card header', () => {
    const body = document.createElement('span');
    body.title = 'In the text';
    discourse.appendChild(body);
    hover(body);
    expect(window.MonadicTip.get(body)).toBeNull();
    expect(body.getAttribute('title')).toBe('In the text');
  });
});
