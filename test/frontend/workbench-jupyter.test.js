/**
 * @jest-environment jsdom
 */
// A notebook opens in JupyterLab only when the user asks: a link to it in
// the conversation, or the work screen's button. The page sends only the
// notebook's path, and opens the address the server answers with, for the
// request it made.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('Opening a notebook in JupyterLab', () => {
  let sent;
  let opened;
  let added;
  let addListener;

  const asked = () => sent.filter((p) => p.message === 'JUPYTER_OPEN');

  function click(el, extra = {}) {
    el.dispatchEvent(new MouseEvent('click', Object.assign({ bubbles: true, cancelable: true, button: 0 }, extra)));
  }

  // The shared setup stands URL in for blob addresses only; links are read
  // with the real one here.
  let stubbedURL;

  afterEach(() => {
    global.URL = stubbedURL;
    window.URL = stubbedURL;
    added.forEach(([type, fn, opts]) => document.removeEventListener(type, fn, opts));
    document.addEventListener = addListener;
    delete window.electronAPI;
  });

  beforeEach(() => {
    stubbedURL = global.URL;
    global.URL = require('url').URL;
    window.URL = global.URL;
    added = [];
    addListener = document.addEventListener;
    document.addEventListener = function (type, fn, opts) {
      added.push([type, fn, opts]);
      return addListener.call(this, type, fn, opts);
    };
    jest.resetModules();
    document.body.innerHTML = `
      <div id="discourse"></div>
      <div id="workbench-status"></div>
      <div id="workbench-drafts" hidden></div>
      <div id="workbench-items" hidden></div>
      <div id="work-screen-browser"></div>
      <div id="workbench-view" hidden></div>`;
    sent = [];
    opened = [];
    window.safeWsSend = (payload) => sent.push(payload);
    window.setAlert = jest.fn();
    window.open = jest.fn((url) => {
      const tab = { url, closed: false, location: { href: url }, close: jest.fn(function () { this.closed = true; }) };
      opened.push(tab);
      return tab;
    });
    window.LayoutController = { isMenuHidden: () => false, setMenuHidden: jest.fn(), selectedPane: () => 'work', setPane: jest.fn() };
    window.WorkScreen = { refresh: jest.fn() };
    global.fetch = jest.fn(() => new Promise(() => {}));
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench.js'));
  });

  test('takes JupyterLab links on this machine to a notebook, and only the path', () => {
    const W = window.Workbench;
    expect(W.jupyterPath('http://127.0.0.1:8889/lab/tree/work/my%20analysis.ipynb')).toBe('work/my analysis.ipynb');
    expect(W.jupyterPath('http://localhost:8889/lab/tree/a.IPYNB')).toBe('a.IPYNB');
    [
      'https://example.com/lab/tree/a.ipynb', 'http://localhost.example/lab/tree/a.ipynb',
      'http://user:pw@127.0.0.1:8889/lab/tree/a.ipynb', 'http://127.0.0.1:8889/api/contents/a.ipynb',
      'http://127.0.0.1:8889/lab/tree/a.py', 'https://127.0.0.1:8889/lab/tree/a.ipynb',
      'http://127.0.0.1:8889/lab/tree/%E0%A4%A.ipynb', 'javascript:alert(1)'
    ].forEach((href) => expect(W.jupyterPath(href)).toBeNull());
  });

  test('a link in the conversation asks the server to open it, in a tab opened at the click', () => {
    document.getElementById('discourse').innerHTML =
      '<p><a href="http://127.0.0.1:8889/lab/tree/nb.ipynb" target="_blank">nb.ipynb</a> <a href="https://example.com/">site</a></p>';
    const [nb, site] = document.querySelectorAll('#discourse a');
    click(site);
    expect(asked()).toHaveLength(0);
    click(nb);
    expect(asked()).toEqual([expect.objectContaining({ path: 'nb.ipynb', request: expect.any(String) })]);
    expect(opened).toHaveLength(1);
    expect(opened[0].url).toBe('about:blank');

    // Only the answer to this request is taken.
    window.Workbench.onJupyterOpened({ request: 'another', success: true, url: 'http://127.0.0.1:8889/lab/tree/x.ipynb' });
    expect(opened[0].location.href).toBe('about:blank');
    window.Workbench.onJupyterOpened({ request: asked()[0].request, success: true, url: 'http://127.0.0.1:8889/lab/tree/nb.ipynb' });
    expect(opened[0].location.href).toBe('http://127.0.0.1:8889/lab/tree/nb.ipynb');
  });

  test('closes the tab and says why when JupyterLab could not be started', () => {
    window.Workbench.openInJupyter('nb.ipynb');
    window.Workbench.onJupyterOpened({ request: asked()[0].request, success: false, error: 'not_started' });
    expect(opened[0].close).toHaveBeenCalled();
    expect(window.setAlert).toHaveBeenLastCalledWith('JupyterLab could not be started.', 'error');
  });

  test('in the desktop app, opens the address once it comes (in the system browser)', () => {
    window.electronAPI = {};
    window.Workbench.openInJupyter('nb.ipynb');
    expect(opened).toHaveLength(0);
    window.Workbench.onJupyterOpened({ request: asked()[0].request, success: true, url: 'http://127.0.0.1:8889/lab/tree/nb.ipynb' });
    expect(window.open).toHaveBeenCalledWith('http://127.0.0.1:8889/lab/tree/nb.ipynb', '_blank');
  });

  test('leaves a click with a modifier or another button, and a link outside the conversation, to the browser', () => {
    document.getElementById('discourse').innerHTML = '<a href="http://127.0.0.1:8889/lab/tree/nb.ipynb">nb</a>';
    document.body.insertAdjacentHTML('beforeend', '<a id="outside" href="http://127.0.0.1:8889/lab/tree/nb.ipynb">x</a>');
    click(document.querySelector('#discourse a'), { button: 1 });
    click(document.getElementById('outside'));
    expect(asked()).toHaveLength(0);
  });

  test('a notebook on the work screen has a button that opens it in JupyterLab', () => {
    const item = { id: 'i_nb', kind: 'file', preview: 'text', actor: 'agent', name: 'nb.ipynb', path: 'work/nb.ipynb',
                   sha256: 'a'.repeat(64), version: 'a'.repeat(64), status: 'ok' };
    window.Workbench.onView({
      board: { board_id: 'b1', chat_id: 'c_1', revision: 1, items: [item] },
      approvals: { i_nb: 'tok' }, assets: { i_nb: '/workbench/asset/i_nb' }, selected: 'i_nb'
    });
    const openButton = Array.from(document.querySelectorAll('#workbench-view button')).find((b) => b.textContent === 'Open in JupyterLab');
    expect(openButton).toBeDefined();
    openButton.click();
    expect(asked()).toEqual([expect.objectContaining({ path: 'work/nb.ipynb' })]);
  });
});
