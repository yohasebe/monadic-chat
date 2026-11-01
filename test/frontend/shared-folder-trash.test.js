// Moving entries of the shared folder to the trash from the shared folder
// page: the same checks as showing one, and only what the server says may go,
// for the kind of entry this computer sees. Run against a real folder.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ROOT_ID_FILE, MAX_TRASH, NO_ANSWER, createTrashHandler } = require('../../app/shared_folder_reveal');

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

  it('does not list the folder twice for every entry of a long run', async () => {
    for (let i = 0; i < 30; i += 1) {
      fs.writeFileSync(path.join(root, `monadic-test-${i}.txt`), 'x');
      answers[`monadic-test-${i}.txt`] = { kind: 'file', capabilities: { trash: true } };
    }
    let reads = 0;
    const counted = Object.assign({}, fs, { readdirSync: (...args) => { reads += 1; return fs.readdirSync(...args); } });
    const moving = { trashItem: jest.fn(async (target) => fs.rmSync(target)) };
    const run = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => answers[relative] || null,
      confirm,
      shell: moving,
      fs: counted,
      platform: 'darwin'
    });
    const paths = Array.from({ length: 30 }, (_, i) => `monadic-test-${i}.txt`);
    const result = await run(fromApp, { rootId: ROOT_ID, paths });
    expect(result.ok).toBe(true);
    expect(moving.trashItem).toHaveBeenCalledTimes(30);
    expect(reads).toBeLessThan(5); // the spelling comes from realpath here, not from listing the folder
  });

  it('still sees an entry renamed by someone else during the run', async () => {
    fs.writeFileSync(path.join(root, 'a.txt'), 'x');
    answers['a.txt'] = { kind: 'file', capabilities: { trash: true } };
    answers['b.txt'] = { kind: 'file', capabilities: { trash: true } };
    fs.writeFileSync(path.join(root, 'b.txt'), 'x');
    const run = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => {
        if (relative === 'a.txt') fs.renameSync(path.join(root, 'b.txt'), path.join(root, 'B.txt')); // only the case differs
        return answers[relative] || null;
      },
      confirm,
      shell,
      fs,
      platform: process.platform
    });
    const result = await run(fromApp, { rootId: ROOT_ID, paths: ['a.txt', 'b.txt'] });
    expect(result.results[1]).toEqual({ path: 'b.txt', ok: false, error: 'the entry is not there' });
  });

  it('checks the spelling by listing the folders where realpath does not give it', async () => {
    fs.writeFileSync(path.join(root, 'Notes.txt'), 'x');
    answers['notes.txt'] = { kind: 'file', capabilities: { trash: true } };
    answers['Notes.txt'] = { kind: 'file', capabilities: { trash: true } };
    let reads = 0;
    const counted = Object.assign({}, fs, { readdirSync: (...args) => { reads += 1; return fs.readdirSync(...args); } });
    const run = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => answers[relative] || null,
      confirm,
      shell,
      fs: counted,
      platform: 'linux'
    });
    const result = await run(fromApp, { rootId: ROOT_ID, paths: ['notes.txt', 'Notes.txt'] });
    expect(result.results[0]).toEqual({ path: 'notes.txt', ok: false, error: 'the entry is not there' });
    expect(result.results[1]).toEqual({ path: 'Notes.txt', ok: true });
    expect(reads).toBeGreaterThan(0);
  });

  function handlerWith(overrides) {
    return createTrashHandler(Object.assign({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => answers[relative] || null,
      confirm,
      shell,
      fs,
      platform: process.platform
    }, overrides));
  }

  it('leaves a path whose folder on the way is spelled in another case', async () => {
    fs.mkdirSync(path.join(root, 'Sub'));
    fs.writeFileSync(path.join(root, 'Sub', 'Notes.txt'), 'x');
    answers['sub/Notes.txt'] = { kind: 'file', capabilities: { trash: true } };
    answers['Sub/Notes.txt'] = { kind: 'file', capabilities: { trash: true } };
    for (const platform of [process.platform, 'linux']) {
      shell.trashItem.mockClear();
      const listed = [];
      const counted = Object.assign({}, fs, { readdirSync: (dir, ...rest) => { listed.push(path.relative(root, dir)); return fs.readdirSync(dir, ...rest); } });
      const result = await handlerWith({ fs: counted, platform })(fromApp, { rootId: ROOT_ID, paths: ['sub/Notes.txt', 'Sub/Notes.txt'] });
      expect(result.results).toEqual([
        { path: 'sub/Notes.txt', ok: false, error: 'the entry is not there' },
        { path: 'Sub/Notes.txt', ok: true }
      ]);
      if (platform === 'linux') expect(listed).toEqual(expect.arrayContaining(['', 'Sub']));
    }
  });

  it('leaves a name written in another Unicode form than the folder holds', async () => {
    const composed = 'Caf\u00e9.txt';
    const decomposed = 'Cafe\u0301.txt';
    fs.writeFileSync(path.join(root, composed), 'x');
    answers[composed] = { kind: 'file', capabilities: { trash: true } };
    answers[decomposed] = { kind: 'file', capabilities: { trash: true } };
    const result = await handlerWith({})(fromApp, { rootId: ROOT_ID, paths: [decomposed, composed] });
    expect(result.results[0]).toEqual({ path: decomposed, ok: false, error: 'the entry is not there' });
    expect(result.results[1]).toEqual({ path: composed, ok: true });
  });

  it('reaches the shared folder through a link above it', async () => {
    const alias = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-alias-'));
    try {
      fs.symlinkSync(path.dirname(root), path.join(alias, 'up'));
      const viaLink = path.join(alias, 'up', path.basename(root));
      const result = await handlerWith({ resolveRoot: () => viaLink })(fromApp, { rootId: ROOT_ID, paths: ['old.png'] });
      expect(result.results).toEqual([{ path: 'old.png', ok: true }]);
    } finally {
      fs.rmSync(alias, { recursive: true, force: true });
    }
  });

  it('stops when the server cannot be reached, and says what was not tried', async () => {
    const asked = [];
    const silent = createTrashHandler({
      resolveRoot: () => root,
      isAppUrl: (url) => url.startsWith('http://localhost:4567/'),
      isAppSender: (event) => event.sender === appContents,
      askEntry: async (relative) => { asked.push(relative); return relative === 'old.png' ? answers[relative] : NO_ANSWER; },
      confirm,
      shell,
      fs,
      platform: 'darwin'
    });
    const result = await silent(fromApp, { rootId: ROOT_ID, paths: ['old.png', 'monadic-test-1-dir', 'scripts'] });
    expect(result.results).toEqual([
      { path: 'old.png', ok: true },
      { path: 'monadic-test-1-dir', ok: false, no_answer: true, error: 'the server did not answer' },
      { path: 'scripts', ok: false, not_tried: true, error: 'not tried' }
    ]);
    expect(asked).toEqual(['old.png', 'monadic-test-1-dir']);
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
    expect((await trash(fromApp, { rootId: ROOT_ID, paths: ['old.png', 'old.png'] })).ok).toBe(false);
    // As many as the server lists from one folder, so choosing all of a folder needs one dialog.
    const serverSide = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/lib/monadic/workspace/shared_folder.rb'), 'utf8');
    expect(MAX_TRASH).toBe(Number(serverSide.match(/MAX_NAMES = ([\d_]+)/)[1].replace(/_/g, '')));
    expect(shell.trashItem).not.toHaveBeenCalled();
  });
});
