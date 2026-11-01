// Files the app writes or reads in the shared folder, where code a model runs
// can leave a link, a FIFO or another file in a file's place, or swap a file
// while the app works on it.
//
// Writing goes to a new file in a staging folder beside the shared folder
// (~/monadic/.staging, which no container mounts), and only a write that
// finished without an error is renamed over the target: a rename replaces a
// link or FIFO there instead of following it, and nothing in the shared
// folder can change the file before it is in place.
// Reading opens only the regular file that lstat saw: without blocking, and
// checked again after the open (the same file, not one swapped in).
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const NOFOLLOW = fs.constants.O_NOFOLLOW || 0;
const NONBLOCK = fs.constants.O_NONBLOCK || 0;

function notARegularFile(p, code) {
  const err = new Error(`Not a regular file: ${p}`);
  err.code = code;
  return err;
}

// The staging folder for a target directly in the shared folder: beside
// the shared folder, so that a rename stays on one file system.
function stagingDirFor(target) {
  return path.join(path.dirname(path.dirname(target)), '.staging');
}

// A write stream to a new file in the staging folder. When done writing,
// call stream.commit(): it ends the stream and, once the file is closed,
// renames it over target only if every byte was written without an error
// (a Promise). stream.discard()
// drops the file.
function writeStreamNoFollow(target, options = {}, fsImpl = fs) {
  const dir = options.stagingDir || stagingDirFor(target);
  fsImpl.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const dirStat = fsImpl.lstatSync(dir);
  if (!dirStat.isDirectory() || dirStat.isSymbolicLink()) throw notARegularFile(dir, 'ENOTDIR');

  const part = path.join(dir, `${path.basename(target)}.${crypto.randomBytes(8).toString('hex')}.part`);
  // Created here, at once and exclusively: this file is ours from now on.
  const fd = fsImpl.openSync(part, 'wx', 0o600);
  const stream = fsImpl.createWriteStream(null, { fd });

  let failed = null;
  let finished = false; // every byte written and flushed: not just ended or destroyed
  stream.on('error', (err) => { failed = failed || err; });
  stream.on('finish', () => { finished = true; });

  stream.discard = () => {
    try { fsImpl.unlinkSync(part); } catch (_) { /* already gone */ }
  };
  stream.commit = () => new Promise((resolve, reject) => {
    const finish = () => {
      if (failed || !finished) {
        stream.discard();
        reject(failed || new Error(`Not written to the end: ${target}`));
        return;
      }
      try {
        fsImpl.renameSync(part, target);
        resolve();
      } catch (err) {
        stream.discard();
        reject(err);
      }
    };
    // Only once the file is closed: a destroyed stream may not be yet.
    if (stream.closed) {
      finish();
    } else {
      stream.once('close', finish);
      if (!stream.destroyed && !stream.writableEnded) stream.end();
    }
  });
  return stream;
}

function openReadNoFollow(p, fsImpl = fs) {
  const before = fsImpl.lstatSync(p);
  if (!before.isFile()) throw notARegularFile(p, before.isSymbolicLink() ? 'ELOOP' : 'EINVAL');
  const fd = fsImpl.openSync(p, fs.constants.O_RDONLY | NOFOLLOW | NONBLOCK);
  let after;
  try {
    after = fsImpl.fstatSync(fd);
  } catch (err) {
    fsImpl.closeSync(fd);
    throw err;
  }
  if (!after.isFile() || after.ino !== before.ino || after.dev !== before.dev) {
    fsImpl.closeSync(fd);
    throw notARegularFile(p, 'ESTALE');
  }
  return fd;
}

function readStreamNoFollow(p, options = {}, fsImpl = fs) {
  const fd = openReadNoFollow(p, fsImpl);
  return fsImpl.createReadStream(null, { ...options, fd });
}

module.exports = { writeStreamNoFollow, readStreamNoFollow, openReadNoFollow, stagingDirFor };
