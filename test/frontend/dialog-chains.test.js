/**
 * @jest-environment jsdom
 */

/**
 * Dialogs that open one after another (MonadicDialog): the Library's
 * Viewer opens once Browse has closed and Browse opens again when the
 * Viewer closes (back on the row's button); opened on its own, the Viewer
 * opens nothing after it. Reset's "save to the Knowledge Base" opens the
 * save dialog once the reset dialog has closed, and not when that closing
 * was refused. A fake MonadicDialog keeps the order of what happened.
 */
const path = require('path');

const JS = path.join(__dirname, '../../docker/services/ruby/public/js/monadic');

function fakeDialogs(log, { refuse = () => false } = {}) {
  const made = new Map();
  window.MonadicDialog = {
    of(el) {
      if (!made.has(el)) {
        const d = {
          isOpen: false,
          open(opener) {
            log.push(`open ${el.id}${opener ? ` from ${opener.id || opener.className}` : ''}`);
            d.isOpen = true;
            return true;
          },
          close(reason) {
            if (refuse(el)) { log.push(`refused ${el.id}`); return Promise.resolve(false); }
            log.push(`close ${el.id} ${reason}`);
            d.isOpen = false;
            return Promise.resolve(true).then((closed) => {
              el.dispatchEvent(new CustomEvent('mdialog:hidden', { detail: { reason } }));
              return closed;
            });
          }
        };
        made.set(el, d);
      }
      return made.get(el);
    }
  };
  return made;
}

const flush = () => new Promise((r) => setTimeout(r, 0));

describe('the Library\'s Browse and Viewer', () => {
  let log;
  let lib;

  beforeEach(() => {
    jest.resetModules();
    log = [];
    document.body.innerHTML = `
      <dialog id="libraryViewerModal"></dialog>`;
    window.safeWsSend = () => ({ sent: true });
    fakeDialogs(log);
    require(path.join(JS, 'library-panel.js'));
    lib = window.libraryPanel;
    lib.init();
  });

  afterEach(() => {
    delete window.MonadicDialog;
    delete window.libraryPanel;
    delete window.safeWsSend;
  });

  test('the Viewer opens on its own (the list is a tab of the side column), and closing it opens nothing', async () => {
    lib.openViewerModal('a');
    await flush();
    expect(log).toEqual(['open libraryViewerModal']);
    log.length = 0;
    await window.MonadicDialog.of(document.getElementById('libraryViewerModal')).close('button');
    await flush();
    expect(log).toEqual(['close libraryViewerModal button']);
  });
});

describe('Reset and saving to the Knowledge Base', () => {
  const SOURCE = require('fs').readFileSync(path.join(JS, 'utilities.js'), 'utf8');

  const setUp = (refuse) => {
    const log = [];
    document.body.innerHTML = `
      <dialog id="resetConfirmation"><button id="resetSaveAndConfirm">Save</button><button id="resetConfirmed">Confirm</button></dialog>
      <div id="main-panel"></div>`;
    global.$id = (id) => document.getElementById(id);
    window.audioInit = () => {};
    window.messages = [{ role: 'user', text: 'hello' }];
    fakeDialogs(log, { refuse });
    window.libraryPanel = {
      isCurrentAppKbSaveEligible: () => true,
      openSaveModal: () => log.push('open librarySaveModal')
    };
    (0, eval)(SOURCE);
    return log;
  };

  afterEach(() => {
    delete window.MonadicDialog;
    delete window.libraryPanel;
    delete window.messages;
  });

  test('the save dialog opens once the reset dialog has closed', async () => {
    const log = setUp(() => false);
    window.resetEvent(null, false);
    expect(log).toEqual(['open resetConfirmation']);
    log.length = 0;
    document.getElementById('resetSaveAndConfirm').click();
    await flush();
    expect(log).toEqual(['close resetConfirmation button', 'open librarySaveModal']);
  });

  test('when the reset dialog\'s closing is refused, the save dialog does not open', async () => {
    const log = setUp((el) => el.id === 'resetConfirmation');
    window.resetEvent(null, false);
    log.length = 0;
    document.getElementById('resetSaveAndConfirm').click();
    await flush();
    expect(log).toEqual(['refused resetConfirmation']);
  });
});

describe('the scripts and the view use MonadicDialog only', () => {
  const fs = require('fs');
  const DIR = path.join(__dirname, '../../docker/services/ruby/public/js');
  const VIEW = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/views/index.erb'), 'utf8');
  const files = ['monadic.js'].concat(fs.readdirSync(path.join(DIR, 'monadic')).filter((f) => f.endsWith('.js')).map((f) => `monadic/${f}`));
  const read = (f) => fs.readFileSync(path.join(DIR, f), 'utf8');

  test.each([
    ['Bootstrap\'s modal', /bootstrap\.Modal/],
    ['its events', /\.bs\.modal/],
    ['its close attribute', /data-bs-dismiss="modal"/],
    ['its marks of an open modal', /modal-open|\.modal\.show/]
  ])('no script uses %s', (_name, pattern) => {
    expect(files.filter((f) => pattern.test(read(f)))).toEqual([]);
  });

  test('the view\'s dialogs are <dialog> elements, closed by their own attribute', () => {
    expect(VIEW).not.toMatch(/class="modal fade/);
    expect(VIEW).not.toMatch(/data-bs-dismiss="modal"|data-bs-backdrop|data-bs-keyboard/);
    expect((VIEW.match(/<dialog class="mdialog/g) || []).length).toBeGreaterThan(9);
  });
});
