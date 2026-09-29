const { execFileSync } = require('child_process');
const path = require('path');

const STAGED_DUMP = 'build/app-payload/docker/services/ruby/help_data/help_db.json';

function stagedDumpPath(payloadRoot) {
    return path.join(payloadRoot, STAGED_DUMP);
}

// electron-builder copies build/app-payload/docker straight into the app via
// extraResources, so `npm run build:mac-arm64` and its siblings never run
// stage_docker_payload.rb. Without a check here, a payload staged before the
// shipping rules existed -- or left behind by an earlier internal build -- gets
// packaged unchecked. Verify the dump that is actually about to ship, not the
// one in the source tree.
//
// A missing dump is a failure, not a skip: app-builder-lib's copyFiles only
// logs `file source doesn't exist` and carries on, so an unstaged payload
// produces an installer with no help database rather than an error.
function verifyStagedHelpDump(payloadRoot, repoRoot = payloadRoot) {
    const staged = stagedDumpPath(payloadRoot);
    try {
        return execFileSync(
            'ruby', [path.join(repoRoot, 'scripts/help_dump_guard.rb'), staged, repoRoot],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }
        );
    } catch (err) {
        const detail = (err.stderr || err.stdout || err.message || '').toString().trim();
        throw new Error(
            `[before_pack] refusing to package the staged help dump.\n${detail}\n` +
            '  Stage the payload first: ruby scripts/stage_docker_payload.rb'
        );
    }
}

// The app itself (app.asar) is packed from app/ and icons/ in the working tree,
// and electron-builder does not read .gitignore: an untracked or ignored file
// there ships to every platform. Only tracked files may be in those trees when
// packaging starts.
const APP_TREES = ['app', 'icons'];

// Files electron-builder drops on its own (.DS_Store, __pycache__, *.pyc and
// the like) never ship, so they must not stop a build either: Finder writes
// .DS_Store into any folder it opens. The list is read from app-builder-lib
// itself rather than copied, so it follows the version that packages the app.
function droppedByElectronBuilder(relPath) {
    const { excludedNames, excludedExts } = require('app-builder-lib/out/fileMatcher');
    const names = new Set(excludedNames.split(',').map(n => n.toLowerCase()));
    const exts = new Set(excludedExts.split(','));
    const segments = relPath.split('/');
    if (segments.some(seg => names.has(seg.toLowerCase()))) return true;
    const base = segments[segments.length - 1];
    const dot = base.lastIndexOf('.');
    return dot > 0 && exts.has(base.slice(dot + 1));
}

function untrackedAppFiles(repoRoot) {
    const out = execFileSync('git', ['-C', repoRoot, 'ls-files', '--others', '-z', '--', ...APP_TREES],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return out.split('\0').filter(Boolean).filter(p => !droppedByElectronBuilder(p));
}

function verifyAppTreesTracked(repoRoot) {
    const extra = untrackedAppFiles(repoRoot);
    if (extra.length > 0) {
        throw new Error(
            `[before_pack] ${extra.length} file(s) in ${APP_TREES.join('/ and ')}/ are not tracked by git and would ship inside the app:\n  ` +
            extra.slice(0, 15).join('\n  ') +
            '\n  Commit them if they belong in the app, or move them out of these directories.'
        );
    }
    return `[before_pack] ${APP_TREES.join('/, ')}/ hold only tracked files\n`;
}

// The docker/ and bin/ payload is copied from build/app-payload as it stands.
// A payload staged by an earlier build ships old contents, or files deleted
// since, unless it is compared with the current sources first.
function verifyStagedPayloadCurrent(repoRoot) {
    try {
        return execFileSync('ruby', [path.join(repoRoot, 'scripts/stage_docker_payload.rb'), '--check'],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (err) {
        const detail = (err.stderr || err.stdout || err.message || '').toString().trim();
        throw new Error(`[before_pack] refusing to package the staged payload.\n${detail}`);
    }
}

exports.default = async function beforePack() {
    const root = path.resolve(__dirname, '..');
    process.stdout.write(verifyAppTreesTracked(root));
    process.stdout.write(verifyStagedPayloadCurrent(root));
    process.stdout.write(verifyStagedHelpDump(root));
};

exports.verifyAppTreesTracked = verifyAppTreesTracked;
exports.verifyStagedPayloadCurrent = verifyStagedPayloadCurrent;

exports.verifyStagedHelpDump = verifyStagedHelpDump;
exports.stagedDumpPath = stagedDumpPath;
