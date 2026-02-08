// Usage: node scripts/generate_workflow_svgs.mjs [--server http://localhost:4567]
import puppeteer from 'puppeteer';
import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const OUTPUT_DIR = join(ROOT, 'docs', 'assets', 'images', 'workflows');
const SERVER = process.argv.includes('--server')
  ? process.argv[process.argv.indexOf('--server') + 1]
  : 'http://localhost:4567';

function slugify(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

async function main() {
  if (!existsSync(OUTPUT_DIR)) mkdirSync(OUTPUT_DIR, { recursive: true });

  const res = await fetch(`${SERVER}/api/apps/graph_list`);
  if (!res.ok) {
    console.error(`Failed to fetch app list: HTTP ${res.status}`);
    process.exit(1);
  }
  const apps = await res.json();
  console.log(`${apps.length} apps to export`);

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const manifest = {};

  for (const { app_name, display_name } of apps) {
    const slug = slugify(display_name);
    const filename = `workflow-${slug}.svg`;
    process.stdout.write(`  ${display_name} -> ${filename} ... `);

    const page = await browser.newPage();
    await page.setViewport({ width: 1400, height: 900 });
    await page.goto(`${SERVER}/workflow-export.html`, { waitUntil: 'networkidle0' });

    try {
      const svg = await page.evaluate(name => window.renderAndExport(name), app_name);
      if (svg) {
        writeFileSync(join(OUTPUT_DIR, filename), svg, 'utf-8');
        manifest[display_name] = filename;
        console.log(`OK (${(svg.length / 1024).toFixed(1)} KB)`);
      } else {
        console.log('SKIP (no SVG)');
      }
    } catch (e) {
      console.log(`ERROR: ${e.message}`);
    }

    await page.close();
  }

  writeFileSync(join(OUTPUT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2));
  await browser.close();
  console.log(`Done: ${Object.keys(manifest).length} SVGs written to ${OUTPUT_DIR}`);
}

main().catch(e => { console.error(e); process.exit(1); });
