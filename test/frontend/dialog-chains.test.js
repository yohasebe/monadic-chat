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
      <dialog id="libraryBrowseModal"><button id="row-a" data-conversation-id="a">Open</button></dialog>
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

  test('from Browse: Browse closes, then the Viewer opens; closing the Viewer opens Browse again, back on the row', async () => {
    const browse = window.MonadicDialog.of(document.getElementById('libraryBrowseModal'));
    browse.open();
    document.getElementById('row-a').focus();
    log.length = 0;
    lib.openViewerModal('a');
    await flush();
    expect(log).toEqual(['close libraryBrowseModal button', 'open libraryViewerModal']);
    log.length = 0;
    await window.MonadicDialog.of(document.getElementById('libraryViewerModal')).close('esc');
    await flush();
    expect(log).toEqual(['close libraryViewerModal esc', 'open libraryBrowseModal from row-a']);
  });

  test('on its own, the Viewer opens, and closing it opens nothing', async () => {
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
