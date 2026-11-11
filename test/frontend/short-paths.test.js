/**
 * @jest-environment jsdom
 */
// Shared folder paths shown by their file name: the whole path is in the
// title and in what is copied, code blocks are left as written, and two
// files of one name are told apart by their folder.
const P1 = 'conversations/20260101-000000_image-generator_x/artifacts/20260101-000100_image_1.jpg';
const P2 = 'conversations/20260101-000000_image-generator_x/inputs/photo.jpg';
const P3 = 'conversations/20260101-000000_image-generator_x/artifacts/photo.jpg';

describe('ShortPaths', () => {
  let discourse;

  function load() {
    jest.resetModules();
    require('../../docker/services/ruby/public/js/monadic/dom-helpers.js');
    require('../../docker/services/ruby/public/js/monadic/short-paths.js');
  }

  beforeEach(() => {
    document.body.innerHTML = '<div id="discourse"></div>';
    discourse = document.getElementById('discourse');
    load();
  });

  afterEach(() => { delete window.ShortPaths; });

  const marks = () => Array.from(discourse.querySelectorAll('.short-path'));

  it('shows a path in a code span or a link by its file name, with the whole path in the title', () => {
    discourse.innerHTML = `<div class="card-text"><p>Saved: <code>${P1}</code></p><a href="/data/${P1}">${P1}</a></div>`;
    window.ShortPaths.apply(discourse);
    expect(marks().map((m) => m.textContent)).toEqual(['20260101-000100_image_1.jpg', '20260101-000100_image_1.jpg']);
    expect(marks().every((m) => m.title === P1 && m.dataset.fullPath === P1)).toBe(true);
    // The link still goes to the file.
    expect(discourse.querySelector('a').getAttribute('href')).toBe(`/data/${P1}`);
  });

  it('shortens a path in running text and leaves the words around it', () => {
    discourse.innerHTML = `<p>The image is at ${P1}. Open it.</p>`;
    window.ShortPaths.apply(discourse);
    expect(discourse.textContent).toBe('The image is at 20260101-000100_image_1.jpg. Open it.');
    expect(marks()[0].dataset.fullPath).toBe(P1);
  });

  it('can be reached by the keyboard and read out as the whole path', () => {
    discourse.innerHTML = `<p><code>${P1}</code></p>`;
    window.ShortPaths.apply(discourse);
    expect(marks()[0].tabIndex).toBe(0);
    expect(marks()[0].getAttribute('aria-label')).toBe(P1);
  });

  it('shortens /monadic/data paths too', () => {
    discourse.innerHTML = '<p><code>/monadic/data/report.pdf</code></p>';
    window.ShortPaths.apply(discourse);
    expect(marks()[0].textContent).toBe('report.pdf');
  });

  it('leaves code blocks and other text as written', () => {
    discourse.innerHTML = `<pre><code>cat ${P1}</code></pre><pre><code>${P1}</code></pre><pre>${P1}</pre><p><code>conversations</code> and a/b/c.txt</p>`;
    window.ShortPaths.apply(discourse);
    expect(marks()).toEqual([]);
    expect(discourse.querySelector('pre').textContent).toBe(`cat ${P1}`);
  });

  it('tells two files of one name apart by their folder', () => {
    discourse.innerHTML = `<p><code>${P2}</code> <code>${P3}</code></p>`;
    window.ShortPaths.apply(discourse);
    expect(marks().map((m) => m.textContent)).toEqual(['inputs/photo.jpg', 'artifacts/photo.jpg']);
  });

  it('is the same when applied again', () => {
    discourse.innerHTML = `<p>At ${P1} and <code>${P1}</code></p>`;
    window.ShortPaths.apply(discourse);
    const once = discourse.innerHTML;
    window.ShortPaths.apply(discourse);
    expect(discourse.innerHTML).toBe(once);
  });

  it('copies the whole paths', () => {
    discourse.innerHTML = `<p id="line">See <code>${P1}</code> now</p>`;
    window.ShortPaths.apply(discourse);
    const range = document.createRange();
    range.selectNodeContents(document.getElementById('line'));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    const data = {};
    const e = new Event('copy', { bubbles: true, cancelable: true });
    e.clipboardData = { setData: (type, value) => { data[type] = value; } };
    document.dispatchEvent(e);
    expect(data['text/plain']).toBe(`See ${P1} now`);
    expect(e.defaultPrevented).toBe(true);
  });

  it('leaves a copy without a shortened path to the browser', () => {
    discourse.innerHTML = '<p id="line">Plain words</p>';
    const range = document.createRange();
    range.selectNodeContents(document.getElementById('line'));
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
    const e = new Event('copy', { bubbles: true, cancelable: true });
    e.clipboardData = { setData: jest.fn() };
    document.dispatchEvent(e);
    expect(e.clipboardData.setData).not.toHaveBeenCalled();
    expect(e.defaultPrevented).toBe(false);
  });

  it('shortens what comes into the conversation later', async () => {
    jest.useFakeTimers();
    try {
      const card = document.createElement('div');
      card.innerHTML = `<p><code>${P1}</code></p>`;
      discourse.appendChild(card);
      await Promise.resolve();
      jest.advanceTimersByTime(200);
      expect(marks().map((m) => m.textContent)).toEqual(['20260101-000100_image_1.jpg']);
    } finally {
      jest.useRealTimers();
    }
  });
});
