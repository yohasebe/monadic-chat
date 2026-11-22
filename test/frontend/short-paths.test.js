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

  it('adds as many folders as it takes to tell files of one name apart', () => {
    const a = 'conversations/c1/artifacts/report.txt';
    const b = 'conversations/c2/artifacts/report.txt';
    discourse.innerHTML = `<p><code>${a}</code> <code>${b}</code></p>`;
    window.ShortPaths.apply(discourse);
    expect(marks().map((m) => m.textContent)).toEqual(['c1/artifacts/report.txt', 'c2/artifacts/report.txt']);
  });

  it('leaves a URL, or another path, that has conversations/ inside it', () => {
    discourse.innerHTML = '<p>See https://example.com/conversations/c1/file.txt and C:\\x\\conversations/c1/file.txt and a/conversations/c1/file.txt</p>' +
      '<p><a href="https://example.com/conversations/c1/file.txt">https://example.com/conversations/c1/file.txt</a></p>';
    const before = discourse.innerHTML;
    window.ShortPaths.apply(discourse);
    expect(marks()).toEqual([]);
    expect(discourse.innerHTML).toBe(before);
  });

  it('gives the whole paths back in a copy of what the page shows (read out, copied by a card)', () => {
    discourse.innerHTML = `<div class="card-text"><p>At ${P1} and <code>${P2}</code></p></div>`;
    window.ShortPaths.apply(discourse);
    const card = discourse.querySelector('.card-text');
    expect(window.ShortPaths.textOf(card)).toBe(`At ${P1} and ${P2}`);
    // The page itself still shows the file names.
    expect(card.textContent).toBe('At 20260101-000100_image_1.jpg and photo.jpg');
  });

  it('shows a path that holds a hidden word whole, and puts back one that comes to hold it', () => {
    let hidden = [];
    window.WordTable = { showsWordIn: (text) => hidden.some((w) => text.includes(w)) };
    try {
      discourse.innerHTML = `<p>At ${P1}</p><p><code>${P2}</code></p>`;
      window.ShortPaths.apply(discourse);
      expect(marks()).toHaveLength(2);
      hidden = ['photo'];
      document.dispatchEvent(new CustomEvent('wordtable:changed'));
      expect(marks().map((m) => m.dataset.fullPath)).toEqual([P1]);
      expect(discourse.querySelector('code').textContent).toBe(P2);
      expect(discourse.querySelector('code').hasAttribute('title')).toBe(false);
    } finally {
      delete window.WordTable;
    }
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

  function copySelecting(node, start, end) {
    const range = document.createRange();
    range.setStart(node, start);
    range.setEnd(node, end);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
    const data = {};
    const e = new Event('copy', { bubbles: true, cancelable: true });
    e.clipboardData = { setData: (type, value) => { data[type] = value; } };
    document.dispatchEvent(e);
    return data['text/plain'];
  }

  it('copies the whole path when only the file name, or a part of it, is selected', () => {
    discourse.innerHTML = `<p>See <code>${P1}</code> now</p>`;
    window.ShortPaths.apply(discourse);
    const name = marks()[0].firstChild;
    expect(copySelecting(name, 0, name.nodeValue.length)).toBe(P1);
    expect(copySelecting(name, 3, 8)).toBe(P1);
  });

  it('copies the whole path when the selection starts inside the file name', () => {
    discourse.innerHTML = `<p id="line">See <code>${P1}</code> now</p>`;
    window.ShortPaths.apply(discourse);
    const name = marks()[0].firstChild;
    const range = document.createRange();
    range.setStart(name, 4);
    range.setEnd(document.getElementById('line').lastChild, 4);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
    const data = {};
    const e = new Event('copy', { bubbles: true, cancelable: true });
    e.clipboardData = { setData: (type, value) => { data[type] = value; } };
    document.dispatchEvent(e);
    expect(data['text/plain']).toBe(`${P1} now`);
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

describe('ShortPaths with the hidden words marked', () => {
  const PATH = 'conversations/c1/artifacts/report-for-Alice.txt';

  beforeEach(() => {
    jest.resetModules();
    jest.useFakeTimers();
    document.body.innerHTML = `<button id="anonymize"></button><div id="word-table-panel" style="display:none"></div>
      <textarea id="message"></textarea><div id="discourse"></div>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (el, event, fn) => { if (el) el.addEventListener(event, fn); };
    global.setAlert = jest.fn();
    window.safeWsSend = () => ({ sent: true });
  });

  afterEach(() => {
    jest.useRealTimers();
    delete window.WordTable;
    delete window.ShortPaths;
  });

  async function settle() {
    for (let i = 0; i < 6; i += 1) {
      await Promise.resolve();
      jest.advanceTimersByTime(200);
    }
  }

  const table = (active) => ({ chat: 'c1', marked: false, active, kept: [] });
  const card = () => document.querySelector('#discourse .card-text');

  it.each([['the words first', true], ['the paths first', false]])('keeps the path and the hidden word, %s', async (_name, wordsFirst) => {
    const wt = require('../../docker/services/ruby/public/js/monadic/word-table.js');
    if (wordsFirst) wt.handleTable(table([{ word: 'Alice', type: 'person', placeholder: '<<PERSON_1>>' }]));
    require('../../docker/services/ruby/public/js/monadic/short-paths.js');
    document.getElementById('discourse').innerHTML = `<div class="card-text"><p>Saved at ${PATH}</p></div>`;
    await settle();
    if (!wordsFirst) {
      wt.handleTable(table([{ word: 'Alice', type: 'person', placeholder: '<<PERSON_1>>' }]));
      await settle();
    }
    // The path is shown whole, with the hidden word marked in it.
    expect(card().textContent).toBe(`Saved at ${PATH}`);
    expect(card().querySelectorAll('.short-path')).toHaveLength(0);
    expect(Array.from(card().querySelectorAll('.word-table-shown')).map((m) => m.textContent)).toEqual(['Alice']);

    // Once the word is no longer hidden, the path is shortened again.
    wt.handleTable(table([]));
    await settle();
    expect(card().querySelector('.short-path').dataset.fullPath).toBe(PATH);
    expect(card().querySelectorAll('.word-table-shown')).toHaveLength(0);
  });
});
