// Showing an entry of the shared folder for the shared folder page. The page
// gives the entry's path relative to the shared folder, never an absolute
// one, and the id the server keeps in that folder. The entry is shown only
// when the folder this computer has is the one the page listed (the id file
// matches), and only along a path with no link at any level. Every entry,
// a folder too, is shown in its parent folder, never opened: code a model
// runs can make a folder that the system opens as an app (Name.app on
// macOS), and opening that would run it.
const path = require('path');

const ROOT_ID_FILE = '.monadic-shared-root';
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

// deps: { resolveRoot, isAppUrl, isAppSender, shell, fs, platform }
// isAppSender: the request comes from the window the app opened for its
// pages (not only from a page at the app's address).
function createRevealHandler(deps) {
  return async function reveal(event, request) {
    try {
      const sender = event && event.senderFrame && event.senderFrame.url;
      if (!sender || !deps.isAppUrl(sender)) return { ok: false, error: 'not from the app' };
      if (deps.isAppSender && !deps.isAppSender(event)) return { ok: false, error: 'not from the app' };

      const rootId = request && request.rootId;
      const parts = sharedPathParts(request && request.path, deps.platform);
      if (typeof rootId !== 'string' || !/^[0-9a-f]{32}$/.test(rootId) || !parts) {
        return { ok: false, error: 'invalid request' };
      }

      const root = deps.resolveRoot();
      const idPath = path.join(root, ROOT_ID_FILE);
      if (!deps.fs.lstatSync(idPath).isFile() || deps.fs.readFileSync(idPath, 'utf8').trim() !== rootId) {
        return { ok: false, error: "this computer's shared folder is not the one listed" };
      }

      let target = root;
      let stat = null;
      for (const part of parts) {
        target = path.join(target, part);
        stat = deps.fs.lstatSync(target);
        if (stat.isSymbolicLink()) return { ok: false, error: 'the path goes through a link' };
      }
      if (stat.isDirectory() || stat.isFile()) {
        deps.shell.showItemInFolder(target);
        return { ok: true };
      }
      return { ok: false, error: 'not a file or folder' };
    } catch (err) {
      return { ok: false, error: (err && err.code) || 'failed' };
    }
  };
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

module.exports = { ROOT_ID_FILE, sharedPathParts, createRevealHandler, showSharedPath };
