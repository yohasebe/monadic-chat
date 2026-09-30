const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
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
//
// When the effective configuration is given (context.packager.config, which
// includes -c.<key>=... overrides from the command line), staging also checks
// that the extra files it adds are the ones it recorded. The rule lives in
// stage_docker_payload.rb only; this passes it the configuration as JSON.
function verifyStagedPayloadCurrent(repoRoot, config) {
    const args = [path.join(repoRoot, 'scripts/stage_docker_payload.rb'), '--check'];
    let tmp = null;
    if (config) {
        tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'before-pack-'));
        const file = path.join(tmp, 'config.json');
        fs.writeFileSync(file, JSON.stringify(config));
        args.push('--config', file);
    }
    try {
        return execFileSync('ruby', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (err) {
        const detail = (err.stderr || err.stdout || err.message || '').toString().trim();
        throw new Error(`[before_pack] refusing to package the staged payload.\n${detail}`);
    } finally {
        if (tmp) fs.rmSync(tmp, { recursive: true, force: true });
    }
}

// The effective configuration is required: if a later electron-builder moved
// it, skipping the comparison would pass command-line overrides unnoticed.
function effectiveConfig(context) {
    const config = context && context.packager && context.packager.config;
    if (!config || typeof config !== 'object') {
        throw new Error(
            '[before_pack] electron-builder did not pass its configuration (context.packager.config);\n' +
            '  the extra files it adds cannot be compared with what staging recorded.'
        );
    }
    return config;
}

exports.default = async function beforePack(context) {
    const root = path.resolve(__dirname, '..');
    const config = effectiveConfig(context);
    process.stdout.write(verifyAppTreesTracked(root));
    process.stdout.write(verifyStagedPayloadCurrent(root, config));
    process.stdout.write(verifyStagedHelpDump(root));
};

exports.verifyAppTreesTracked = verifyAppTreesTracked;
exports.verifyStagedPayloadCurrent = verifyStagedPayloadCurrent;
exports.effectiveConfig = effectiveConfig;

exports.verifyStagedHelpDump = verifyStagedHelpDump;
exports.stagedDumpPath = stagedDumpPath;
