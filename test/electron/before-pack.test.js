// The beforePack hook is the one check every packaging entry point passes
// through. These cases pin the rule that only tracked files in app/ and
// icons/ may reach app.asar, while the files electron-builder drops on its
// own (Finder's .DS_Store, __pycache__) do not stop a build.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { verifyAppTreesTracked } = require('../../scripts/before_pack');

function withRepo(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'before-pack-'));
  const git = (...args) => execFileSync('git', ['-C', dir, '-c', 'core.hooksPath=/dev/null', ...args], { stdio: 'ignore' });
  try {
    git('init', '-q');
    fs.mkdirSync(path.join(dir, 'app'));
    fs.mkdirSync(path.join(dir, 'icons'));
    fs.writeFileSync(path.join(dir, 'app', 'main.js'), 'x');
    fs.writeFileSync(path.join(dir, 'icons', 'app.png'), 'x');
    git('add', '-A');
    fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

describe('beforePack: only tracked files in app/ and icons/', () => {
  it('passes when the trees hold only tracked files', () => {
    withRepo(dir => {
      expect(() => verifyAppTreesTracked(dir)).not.toThrow();
    });
  });

  it('stops on an untracked file in app/', () => {
    withRepo(dir => {
      fs.writeFileSync(path.join(dir, 'app', 'notes.txt'), 'private');
      expect(() => verifyAppTreesTracked(dir)).toThrow(/app\/notes\.txt/);
    });
  });

  it('stops on a git-ignored file too, since electron-builder does not read .gitignore', () => {
    withRepo(dir => {
      fs.writeFileSync(path.join(dir, '.gitignore'), '*.log\n');
      fs.writeFileSync(path.join(dir, 'icons', 'debug.log'), 'x');
      expect(() => verifyAppTreesTracked(dir)).toThrow(/icons\/debug\.log/);
    });
  });

  it('ignores files electron-builder drops on its own', () => {
    withRepo(dir => {
      fs.writeFileSync(path.join(dir, 'icons', '.DS_Store'), 'x');
      fs.mkdirSync(path.join(dir, 'app', '__pycache__'));
      fs.writeFileSync(path.join(dir, 'app', '__pycache__', 'm.pyc'), 'x');
      expect(() => verifyAppTreesTracked(dir)).not.toThrow();
    });
  });
});
