// Builds the worker the work screen draws Vega-Lite charts in:
// docker/services/ruby/public/vendor/vega/vega-worker.mjs (one file, no
// imports) and the licenses of what it holds (LICENSES.txt), from the
// locked packages. Prints the size, hash and packages.
//
//   npm run build:vega
import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const out = join(root, 'docker/services/ruby/public/vendor/vega');
const outfile = join(out, 'vega-worker.mjs');
mkdirSync(out, { recursive: true });

const result = await build({
  entryPoints: [join(root, 'scripts/vega/vega_worker_entry.mjs')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  minify: true,
  legalComments: 'none',
  metafile: true,
  outfile
});

// The packages whose code is in the bundle, by the files esbuild took.
const packages = new Map();
Object.keys(result.metafile.inputs).forEach((input) => {
  const match = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)\//);
  if (!match || packages.has(match[1])) return;
  const dir = join(root, 'node_modules', match[1]);
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  packages.set(match[1], { name: pkg.name, version: pkg.version, license: pkg.license, dir });
});
const names = [...packages.keys()].sort();

const licenses = names.map((name) => {
  const { version, license, dir } = packages.get(name);
  const file = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'license'].map((f) => join(dir, f)).find(existsSync);
  const text = file ? readFileSync(file, 'utf8').trim() : `License: ${license}`;
  return `${name}@${version} (${license})\n\n${text}\n`;
});
writeFileSync(join(out, 'LICENSES.txt'), `${licenses.join('\n' + '-'.repeat(72) + '\n\n')}`);

const bytes = readFileSync(outfile);
const sha256 = createHash('sha256').update(bytes).digest('hex');
console.log(`vega-worker.mjs: ${bytes.length} bytes (${gzipSync(bytes).length} gzip), sha256 ${sha256}`);
console.log(names.map((name) => `  ${name}@${packages.get(name).version} (${packages.get(name).license})`).join('\n'));
