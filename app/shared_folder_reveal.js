// Showing an entry of the shared folder for the shared folder page. The page
// gives the entry's path relative to the shared folder, never an absolute
// one, and the id the server keeps in that folder. The entry is shown only
// when the folder this computer has is the one the page listed (the id file
// matches), and only along a path with no link at any level. Every entry,
// a folder too, is shown in its parent folder, never opened: code a model
// runs can make a folder that the system opens as an app (Name.app on
// macOS), and opening that would run it.
const path = require('path');
const { URL } = require('url');

const ROOT_ID_FILE = '.monadic-shared-root';
// The app's page that holds the Shared Folder panel. The same address also
// serves files of the shared folder (/data/...), which a model's code can
// write, so the origin alone does not tell the app's page from such a file.
const APP_PAGE_PATH = '/';
const WINDOWS_RESERVED_NAME = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$/i;

// The parts of a relative path, or null when it could name something
// outside the folder or a different entry than it reads as.
function sharedPathParts(relative, platform) {
  if (typeof relative !== 'string' || relative === '') return null;
  if (relative.startsWith('/') || relative.includes('\\') || relative.includes('\0')) return null;
  const parts = relative.split('/');
  for (const part of parts) {
    if (part === '' || part === '.' || part === '..') return null;
    if (platform === 'win32' &&
        (part.includes(':') || /[. ]$/.test(part) || WINDOWS_RESERVED_NAME.test(part))) return null;
  }
  return parts;
}

// The checks shared by every request about an entry: from the app's own
// window, a relative path the platform reads as written, this computer's
// shared folder being the one listed (rootId), and no link at any level.
// Returns { root, target, stat } or { error }.
// deps: { resolveRoot, isAppUrl, isAppSender, fs, platform }
// isAppSender: the request comes from the window the app opened for its
// pages (not only from a page at the app's address).
function checkSender(event, deps) {
  const sender = event && event.senderFrame && event.senderFrame.url;
  if (!sender || !deps.isAppUrl(sender)) return false;
  try {
    if (new URL(sender).pathname !== APP_PAGE_PATH) return false;
  } catch (_) {
    return false;
  }
  if (deps.isAppSender && !deps.isAppSender(event)) return false;
  return true;
}

function sharedRoot(rootId, deps) {
  if (typeof rootId !== 'string' || !/^[0-9a-f]{32}$/.test(rootId)) return { error: 'invalid request' };
  const root = deps.resolveRoot();
  const rootStat = deps.fs.statSync(root);
  if (!rootStat.isDirectory()) return { error: 'the shared folder is not a folder' };
  const idPath = path.join(root, ROOT_ID_FILE);
  if (!deps.fs.lstatSync(idPath).isFile() || deps.fs.readFileSync(idPath, 'utf8').trim() !== rootId) {
    return { error: "this computer's shared folder is not the one listed" };
  }
  return { root, rootStat };
}

function sameEntry(a, b) {
  return a.dev === b.dev && a.ino === b.ino;
}

// Each part must be spelled as the folder spells it: a folder that ignores
// case would otherwise find "Apps" for "apps", which the server keeps (the
// server checks the spelling again). On macOS the real path the system
// gives (fs.realpathSync.native) is spelled as the folders spell every part,
// so when it is the shared folder's real path with the parts as asked, no
// folder needs listing. When it is not, or cannot be had, and on other
// systems, each folder on the way is listed and must hold the part as it
// is written.
const REALPATH_SPELLS = new Set(['darwin']);

function spelledByRealpath(root, target, parts, deps) {
  if (!REALPATH_SPELLS.has(deps.platform) || !deps.fs.realpathSync || typeof deps.fs.realpathSync.native !== 'function') return false;
  try {
    return deps.fs.realpathSync.native(target) === path.join(deps.fs.realpathSync.native(root), ...parts);
  } catch (_) {
    return false;
  }
}

function spelledByListing(root, parts, deps) {
  let dir = root;
  for (const part of parts) {
    if (!deps.fs.readdirSync(dir).includes(part)) return false;
    dir = path.join(dir, part);
  }
  return true;
}

function entryAt(root, relative, deps) {
  const parts = sharedPathParts(relative, deps.platform);
  if (!parts) return { error: 'invalid request' };
  let target = root;
  let stat = null;
  for (const part of parts) {
    target = path.join(target, part);
    try {
      stat = deps.fs.lstatSync(target);
    } catch (err) {
      if (err && (err.code === 'ENOENT' || err.code === 'ENOTDIR')) return { error: 'the entry is not there' };
      throw err;
    }
    if (stat.isSymbolicLink()) return { error: 'the path goes through a link' };
  }
  if (!spelledByRealpath(root, target, parts, deps) && !spelledByListing(root, parts, deps)) {
    return { error: 'the entry is not there' };
  }
  if (!stat.isDirectory() && !stat.isFile()) return { error: 'not a file or folder' };
  return { target, stat, kind: stat.isDirectory() ? 'folder' : 'file' };
}

// deps: { resolveRoot, isAppUrl, isAppSender, shell, fs, platform }
function createRevealHandler(deps) {
  return async function reveal(event, request) {
    try {
      if (!checkSender(event, deps)) return { ok: false, error: 'not from the app' };
      if (!sharedPathParts(request && request.path, deps.platform)) return { ok: false, error: 'invalid request' };
      const { root, error } = sharedRoot(request && request.rootId, deps);
      if (error) return { ok: false, error };
      const found = entryAt(root, request.path, deps);
      if (found.error) return { ok: false, error: found.error };
      deps.shell.showItemInFolder(found.target);
      return { ok: true };
    } catch (err) {
      return { ok: false, error: (err && err.code) || 'failed' };
    }
  };
}

// Entries in one request: as many as the server lists from one folder
// (SharedFolder::MAX_NAMES), so choosing every entry of a folder is moved
// after one dialog. Each one is still asked about on its own.
const MAX_TRASH = 20000;

// askEntry's answer when the server could not be reached at all (no reply
// in time, connection refused): the rest of the run is not tried.
const NO_ANSWER = Symbol('no answer');

// Moves entries of the shared folder to the system's trash. Each one must
// pass the checks above, and the server must say it may go (not protected,
// not in a chat open in a tab) for the same kind of entry this computer
// sees, and the person must agree in a dialog of the desktop app itself (not
// of the page), which names the count and the first entries. While the
// server is asked the folder could change, so just before
// the move the shared folder must still be the same folder with the same id
// file, and the entry the same entry, with no link on the way.
// deps: as for reveal, plus askEntry(relativePath) -> Promise<item|null>
// (the server's description of the entry), confirm(paths) -> Promise<bool>
// (the desktop app's dialog; nothing is moved without it) and shell.trashItem.
function createTrashHandler(deps) {
  return async function trash(event, request) {
    try {
      if (!checkSender(event, deps)) return { ok: false, error: 'not from the app' };
      const paths = request && request.paths;
      if (!Array.isArray(paths) || paths.length === 0 || paths.length > MAX_TRASH ||
          new Set(paths).size !== paths.length ||
          paths.some((p) => !sharedPathParts(p, deps.platform))) {
        return { ok: false, error: 'invalid request' };
      }
      const first = sharedRoot(request.rootId, deps);
      if (first.error) return { ok: false, error: first.error };
      if (typeof deps.confirm !== 'function' || (await deps.confirm(paths.slice())) !== true) {
        return { ok: false, cancelled: true, error: 'cancelled' };
      }

      const results = [];
      let silent = false;
      for (const relative of paths) {
        if (silent) {
          results.push({ path: relative, ok: false, not_tried: true, error: 'not tried' });
          continue;
        }
        const result = await trashOne(first, request.rootId, relative, deps);
        if (result.no_answer) silent = true;
        results.push(result);
      }
      return { ok: results.every((r) => r.ok), results };
    } catch (err) {
      return { ok: false, error: (err && err.code) || 'failed' };
    }
  };
}

async function trashOne(first, rootId, relative, deps) {
  const { root } = first;
  try {
    const found = entryAt(root, relative, deps);
    if (found.error) return { path: relative, ok: false, error: found.error };
    const item = await deps.askEntry(relative);
    if (item === NO_ANSWER) return { path: relative, ok: false, no_answer: true, error: 'the server did not answer' };
    if (!item || !item.capabilities || item.capabilities.trash !== true) {
      return { path: relative, ok: false, error: 'not to be removed' };
    }
    if (item.kind !== found.kind) return { path: relative, ok: false, error: 'the entry changed' };
    const now = sharedRoot(rootId, deps);
    if (now.error || !sameEntry(now.rootStat, first.rootStat)) {
      return { path: relative, ok: false, error: 'the shared folder changed' };
    }
    const again = entryAt(root, relative, deps);
    if (again.error || again.kind !== found.kind || !sameEntry(again.stat, found.stat)) {
      return { path: relative, ok: false, error: 'the entry changed' };
    }
    await deps.shell.trashItem(again.target);
    return { path: relative, ok: true };
  } catch (err) {
    return { path: relative, ok: false, error: (err && err.code) || 'failed' };
  }
}

// Shows an absolute path from the app's pages (the ${SHARED} token and the
// like). Only the shared folder itself, a real folder and not a link, is
// opened; anything else, a folder too, is shown in its parent, for the same
// reason as above. deps: { resolveRoot, fs, shell }
function showSharedPath(target, deps) {
  let root = null;
  try {
    const candidate = deps.resolveRoot();
    if (path.resolve(target) === path.resolve(candidate)) {
      const stat = deps.fs.lstatSync(candidate);
      if (stat.isDirectory() && !stat.isSymbolicLink()) root = candidate;
    }
  } catch (_) {
    root = null;
  }
  if (root) {
    // The folder checked, not the path given: "root/link/.." reads as the
    // root but the system would follow the link before the "..".
    deps.shell.openPath(root);
  } else {
    deps.shell.showItemInFolder(target);
  }
}

module.exports = { ROOT_ID_FILE, APP_PAGE_PATH, MAX_TRASH, NO_ANSWER, sharedPathParts, createRevealHandler, createTrashHandler, showSharedPath };
