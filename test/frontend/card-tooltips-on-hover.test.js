/**
 * @jest-environment jsdom
 */

/**
 * The tooltips of a card header's controls (ui-utilities.js,
 * showCardTooltipsOnHover), with the real Bootstrap.
 */

const path = require('path');
const fs = require('fs');

const RUBY = path.resolve(__dirname, '../../docker/services/ruby/public');

describe('showCardTooltipsOnHover', () => {
  let uiUtils;
  let discourse;

  beforeAll(() => {
    const source = fs.readFileSync(path.join(RUBY, 'vendor/js/bootstrap.bundle.min.js'), 'utf8');
    // eslint-disable-next-line no-new-func
    new Function('window', 'document', `${source}\n;window.bootstrap = this.bootstrap || window.bootstrap;`)
      .call(window, window, document);
    global.bootstrap = window.bootstrap;
    document.body.innerHTML = '<div id="discourse"></div>';
    uiUtils = require(path.join(RUBY, 'js/monadic/ui-utilities'));
    discourse = document.getElementById('discourse');
    uiUtils.showCardTooltipsOnHover(discourse);
  });

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

  test('makes the tooltip of a control when the pointer comes to it, also to what is inside it', () => {
    const control = addCard('Copy');
    expect(bootstrap.Tooltip.getInstance(control)).toBeNull();
    hover(control.querySelector('.icon'));
    expect(bootstrap.Tooltip.getInstance(control)).not.toBeNull();
    expect(document.body.querySelector('.tooltip').textContent).toBe('Copy');
  });

  test('makes it again after every tooltip was removed, for an earlier card and a later one', () => {
    const earlier = addCard('Copy');
    hover(earlier);
    const later = addCard('Delete');
    hover(later);

    document.querySelectorAll('[data-bs-original-title]').forEach((el) => {
      const tip = bootstrap.Tooltip.getInstance(el);
      if (tip) tip.dispose();
    });
    expect(bootstrap.Tooltip.getInstance(earlier)).toBeNull();
    expect(bootstrap.Tooltip.getInstance(later)).toBeNull();

    hover(earlier);
    hover(later);
    expect(bootstrap.Tooltip.getInstance(earlier)).not.toBeNull();
    expect(bootstrap.Tooltip.getInstance(later)).not.toBeNull();
  });

  test('leaves what is outside a card header', () => {
    const body = document.createElement('span');
    body.title = 'In the text';
    discourse.appendChild(body);
    hover(body);
    expect(bootstrap.Tooltip.getInstance(body)).toBeNull();
  });
});
