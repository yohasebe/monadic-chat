// Moving entries of the shared folder to the trash from the shared folder
// page: the same checks as showing one, and only what the server says may go,
// for the kind of entry this computer sees. Run against a real folder.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ROOT_ID_FILE, MAX_TRASH, createTrashHandler } = require('../../app/shared_folder_reveal');

const ROOT_ID = 'b'.repeat(32);
const appContents = {};
const fromApp = { sender: appContents, senderFrame: { url: 'http://localhost:4567/' } };
const fromSharedFile = { sender: appContents, senderFrame: { url: 'http://localhost:4567/data/page.html' } };

describe('shared folder trash', () => {
  let root;
  let shell;
  let answers;
  let trash;
  let confirm;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-trash-'));
    fs.writeFileSync(path.join(root, ROOT_ID_FILE), ROOT_ID);
    fs.writeFileSync(path.join(root, 'old.png'), 'x');
    fs.mkdirSync(path.join(root, 'monadic-test-1-dir'));
    fs.mkdirSync(path.join(root, 'scripts'));
    fs.symlinkSync(os.tmpdir(), path.join(root, 'elsewhere'));
    answers = {
      'old.png': { kind: 'file', capabilities: { trash: true } },
      'monadic-test-1-dir': { kind: 'folder', capabilities: { trash: true } },
      scripts: { kind: 'folder', capabilities: { trash: false } }
    };
    shell = { trashItem: jest.fn(async () => undefined) };
    confirm = jest.fn(async () => true);
    trash = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => answers[relative] || null,
      confirm,
      shell,
      fs,
      platform: 'darwin'
    });
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('moves what the server says may go', async () => {
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['old.png', 'monadic-test-1-dir'] });
    expect(result.ok).toBe(true);
    expect(shell.trashItem).toHaveBeenCalledWith(path.join(root, 'old.png'));
    expect(shell.trashItem).toHaveBeenCalledWith(path.join(root, 'monadic-test-1-dir'));
  });

  it('leaves what the server keeps, and says so for that entry only', async () => {
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['scripts', 'old.png'] });
    expect(result.ok).toBe(false);
    expect(result.results).toEqual([
      { path: 'scripts', ok: false, error: 'not to be removed' },
      { path: 'old.png', ok: true }
    ]);
    expect(shell.trashItem).toHaveBeenCalledTimes(1);
  });

  it('leaves an entry the server does not know, or knows as another kind', async () => {
    answers['old.png'] = { kind: 'folder', capabilities: { trash: true } };
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['old.png', 'unknown.txt'] });
    expect(result.results.map((r) => r.ok)).toEqual([false, false]);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('never goes through a link', async () => {
    answers.elsewhere = { kind: 'folder', capabilities: { trash: true } };
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['elsewhere', 'elsewhere/x'] });
    expect(result.results.every((r) => !r.ok)).toBe(true);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('leaves an entry named in another case than the folder spells it', async () => {
    answers['OLD.png'] = { kind: 'file', capabilities: { trash: true } };
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['OLD.png'] });
    expect(result.ok).toBe(false);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('leaves the entry when the shared folder is swapped for a link while the server is asked', async () => {
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-trash-outside-'));
    fs.writeFileSync(path.join(outside, ROOT_ID_FILE), ROOT_ID);
    fs.writeFileSync(path.join(outside, 'old.png'), 'y');
    const moved = `${root}-moved`;
    const swapping = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => {
        fs.renameSync(root, moved);
        fs.symlinkSync(outside, root);
        return answers[relative];
      },
      confirm,
      shell,
      fs,
      platform: 'darwin'
    });
    try {
      const result = await swapping(fromApp, { rootId: ROOT_ID, paths: ['old.png'] });
      expect(result.results[0]).toEqual({ path: 'old.png', ok: false, error: 'the shared folder changed' });
      expect(shell.trashItem).not.toHaveBeenCalled();
    } finally {
      fs.unlinkSync(root);
      fs.renameSync(moved, root);
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });

  it('leaves the entry when it is replaced by another of the same kind while the server is asked', async () => {
    const replacing = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => {
        fs.renameSync(path.join(root, 'old.png'), path.join(root, 'kept.png'));
        fs.writeFileSync(path.join(root, 'old.png'), 'z');
        return answers[relative];
      },
      confirm,
      shell,
      fs,
      platform: 'darwin'
    });
    const result = await replacing(fromApp, { rootId: ROOT_ID, paths: ['old.png'] });
    expect(result.results[0]).toEqual({ path: 'old.png', ok: false, error: 'the entry changed' });
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('moves nothing unless the dialog of the desktop app is agreed to, and names what it asks about', async () => {
    confirm.mockResolvedValueOnce(false);
    const result = await trash(fromApp, { rootId: ROOT_ID, paths: ['old.png', 'monadic-test-1-dir'] });
    expect(result).toEqual({ ok: false, cancelled: true, error: 'cancelled' });
    expect(confirm).toHaveBeenCalledWith(['old.png', 'monadic-test-1-dir']);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('moves nothing without a dialog to ask', async () => {
    const asking = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => answers[relative] || null,
      shell,
      fs,
      platform: 'darwin'
    });
    expect((await asking(fromApp, { rootId: ROOT_ID, paths: ['old.png'] })).ok).toBe(false);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('refuses a file of the shared folder shown at the app\'s address', async () => {
    const result = await trash(fromSharedFile, { rootId: ROOT_ID, paths: ['old.png'] });
    expect(result).toEqual({ ok: false, error: 'not from the app' });
    expect(confirm).not.toHaveBeenCalled();
    expect(shell.trashItem).not.toHaveBeenCalled();
  });

  it('refuses another page, another folder, and paths it cannot read as written', async () => {
    expect((await trash({ senderFrame: { url: 'http://evil.example/' } }, { rootId: ROOT_ID, paths: ['old.png'] })).ok).toBe(false);
    expect((await trash(fromApp, { rootId: 'c'.repeat(32), paths: ['old.png'] })).ok).toBe(false);
    expect((await trash(fromApp, { rootId: ROOT_ID, paths: ['../old.png'] })).ok).toBe(false);
    expect((await trash(fromApp, { rootId: ROOT_ID, paths: ['/etc/hosts'] })).ok).toBe(false);
    expect((await trash(fromApp, { rootId: ROOT_ID, paths: [] })).ok).toBe(false);
    expect((await trash(fromApp, { rootId: ROOT_ID, paths: new Array(MAX_TRASH + 1).fill('old.png') })).ok).toBe(false);
    expect(shell.trashItem).not.toHaveBeenCalled();
  });
});
