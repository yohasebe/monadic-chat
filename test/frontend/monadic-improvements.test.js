/**
 * @jest-environment jsdom
 */

// The JSON trees kept in cards of earlier versions: an empty object does
// not open, and "no value" is marked. Only what is added to the page is
// looked at, since a reply that streams adds nodes many times a second.
describe('monadic-improvements', () => {
  const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

  function tree(content) {
    const item = document.createElement('div');
    item.className = 'json-item';
    item.innerHTML = `<div class="json-header"><span>key</span></div><div class="json-content">${content}</div>`;
    return item;
  }

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = '<div id="discourse"></div>';
    require('../../docker/services/ruby/public/js/monadic-improvements.js');
    document.dispatchEvent(new Event('DOMContentLoaded'));
  });

  test('marks an empty object of a tree added later, and its "no value"', async () => {
    const card = document.createElement('div');
    card.appendChild(tree('{}'));
    const filled = tree('<span>no value</span>');
    card.appendChild(filled);
    document.getElementById('discourse').appendChild(card);
    await settle();

    const [empty] = card.querySelectorAll('.json-item');
    expect(empty.classList.contains('empty-object')).toBe(true);
    expect(empty.querySelector('.json-content').style.display).toBe('none');
    expect(filled.classList.contains('empty-object')).toBe(false);
    expect(filled.querySelector('.json-content span').classList.contains('no-value')).toBe(true);
  });

  test('does not search the whole page when what is added holds no tree', async () => {
    const whole = jest.spyOn(document, 'querySelectorAll');
    const span = document.createElement('span');
    span.textContent = 'a streamed fragment';
    document.getElementById('discourse').appendChild(span);
    await settle();

    expect(whole).not.toHaveBeenCalled();
    whole.mockRestore();
  });
});
