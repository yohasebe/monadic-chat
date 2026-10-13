// Showing an entry of the shared folder from the shared folder page: only
// from the app's own pages, only by a relative path, only in the folder the
// page listed, and never through a link. Run against a real folder.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ROOT_ID_FILE, sharedPathParts, createRevealHandler, showSharedPath } = require('../../app/shared_folder_reveal');

const ROOT_ID = 'a'.repeat(32);
const appContents = {};
const fromApp = { sender: appContents, senderFrame: { url: 'http://localhost:4567/' } };

describe('shared folder reveal', () => {
  let root;
  let shell;
  let reveal;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-reveal-'));
    fs.writeFileSync(path.join(root, ROOT_ID_FILE), ROOT_ID);
    fs.mkdirSync(path.join(root, 'conversations', 'chat'), { recursive: true });
    fs.writeFileSync(path.join(root, 'image.png'), 'x');
    fs.symlinkSync(os.tmpdir(), path.join(root, 'elsewhere'));
    shell = { openPath: jest.fn(async () => ''), showItemInFolder: jest.fn() };
    reveal = createRevealHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      shell,
      fs,
      platform: 'darwin'
    });
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('shows a folder or a file in its folder', async () => {
    await expect(reveal(fromApp, { rootId: ROOT_ID, path: 'conversations/chat' })).resolves.toEqual({ ok: true });
    expect(shell.showItemInFolder).toHaveBeenCalledWith(path.join(root, 'conversations', 'chat'));
    await expect(reveal(fromApp, { rootId: ROOT_ID, path: 'image.png' })).resolves.toEqual({ ok: true });
    expect(shell.showItemInFolder).toHaveBeenCalledWith(path.join(root, 'image.png'));
    expect(shell.openPath).not.toHaveBeenCalled();
  });

  // A folder shaped like a macOS app is opened (run) by the system: it is
  // only shown, like any other folder.
  it('never opens a folder, which could be an app', async () => {
    fs.mkdirSync(path.join(root, 'Tool.app', 'Contents', 'MacOS'), { recursive: true });
    await expect(reveal(fromApp, { rootId: ROOT_ID, path: 'Tool.app' })).resolves.toEqual({ ok: true });
    expect(shell.openPath).not.toHaveBeenCalled();
    expect(shell.showItemInFolder).toHaveBeenCalledWith(path.join(root, 'Tool.app'));
  });

  it('refuses a request from another page', async () => {
    const other = { senderFrame: { url: 'http://evil.example/' } };
    expect((await reveal(other, { rootId: ROOT_ID, path: 'image.png' })).ok).toBe(false);
    expect(shell.showItemInFolder).not.toHaveBeenCalled();
  });

  it("refuses a page at the app's address in another window", async () => {
    const otherWindow = { sender: {}, senderFrame: { url: 'http://localhost:4567/' } };
    expect((await reveal(otherWindow, { rootId: ROOT_ID, path: 'image.png' })).ok).toBe(false);
    expect(shell.showItemInFolder).not.toHaveBeenCalled();
  });

  it('refuses when the folder here is not the one listed', async () => {
    const result = await reveal(fromApp, { rootId: 'b'.repeat(32), path: 'image.png' });
    expect(result.ok).toBe(false);
    expect(shell.showItemInFolder).not.toHaveBeenCalled();
  });

  it('refuses a path through a link', async () => {
    expect((await reveal(fromApp, { rootId: ROOT_ID, path: 'elsewhere' })).ok).toBe(false);
    expect(shell.openPath).not.toHaveBeenCalled();
  });

  it('refuses paths that could leave the folder', async () => {
    for (const p of ['/etc', '..', 'a/../..', 'a//b', 'a\\b', 'a\0b', '', 'missing']) {
      expect((await reveal(fromApp, { rootId: ROOT_ID, path: p })).ok).toBe(false);
    }
    expect(shell.openPath).not.toHaveBeenCalled();
    expect(shell.showItemInFolder).not.toHaveBeenCalled();
  });

  it('refuses Windows names that resolve to something else', () => {
    for (const p of ['C:', 'file.txt:stream', 'trailing.', 'trailing ', 'CON', 'nul.txt', 'LPT1']) {
      expect(sharedPathParts(p, 'win32')).toBeNull();
    }
    expect(sharedPathParts('nul.txt', 'darwin')).toEqual(['nul.txt']);
  });
});

// The ${SHARED} token and other absolute paths from the app's pages.
describe('showing an absolute path', () => {
  let root;
  let shell;
  const show = (p) => showSharedPath(p, { resolveRoot: () => root, fs, shell });

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-show-'));
    fs.mkdirSync(path.join(root, 'Tool.app', 'Contents', 'MacOS'), { recursive: true });
    fs.mkdirSync(path.join(root, 'plain'));
    shell = { openPath: jest.fn(async () => ''), showItemInFolder: jest.fn() };
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('opens the shared folder itself', () => {
    show(root);
    expect(shell.openPath).toHaveBeenCalledWith(root);
  });

  it('only shows any other folder, which could be an app, or file', () => {
    for (const p of [path.join(root, 'Tool.app'), path.join(root, 'plain'), path.join(root, 'missing.txt'), os.tmpdir()]) show(p);
    expect(shell.openPath).not.toHaveBeenCalled();
    expect(shell.showItemInFolder).toHaveBeenCalledTimes(4);
  });

  it('opens the folder it checked, not a path that only reads as it', () => {
    fs.symlinkSync(path.join(root, 'Tool.app', 'Contents'), path.join(root, 'jump'));
    show(`${root}/jump/..`); // the system resolves the link first: Tool.app
    expect(shell.openPath).toHaveBeenCalledWith(root);
  });

  it('does not open the shared folder when it is a link', () => {
    const link = `${root}-link`;
    fs.symlinkSync(root, link);
    try {
      showSharedPath(link, { resolveRoot: () => link, fs, shell });
      expect(shell.openPath).not.toHaveBeenCalled();
    } finally {
      fs.unlinkSync(link);
    }
  });
});
