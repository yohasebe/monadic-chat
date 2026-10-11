// Showing an entry of the shared folder from the shared folder page: only
// from the app's own pages, only by a relative path, only in the folder the
// page listed, and never through a link. Run against a real folder.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ROOT_ID_FILE, sharedPathParts, createRevealHandler } = require('../../app/shared_folder_reveal');

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

  it('opens a folder and shows a file in its folder', async () => {
    await expect(reveal(fromApp, { rootId: ROOT_ID, path: 'conversations/chat' })).resolves.toEqual({ ok: true });
    expect(shell.openPath).toHaveBeenCalledWith(path.join(root, 'conversations', 'chat'));
    await expect(reveal(fromApp, { rootId: ROOT_ID, path: 'image.png' })).resolves.toEqual({ ok: true });
    expect(shell.showItemInFolder).toHaveBeenCalledWith(path.join(root, 'image.png'));
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
