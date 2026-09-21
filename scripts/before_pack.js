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

exports.default = async function beforePack() {
    const root = path.resolve(__dirname, '..');
    process.stdout.write(verifyStagedHelpDump(root));
};

exports.verifyStagedHelpDump = verifyStagedHelpDump;
exports.stagedDumpPath = stagedDumpPath;
