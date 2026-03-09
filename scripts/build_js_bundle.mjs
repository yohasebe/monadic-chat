#!/usr/bin/env node
/**
 * Build script: Concatenate and minify custom JS files into a single bundle.
 *
 * Usage:
 *   node scripts/build_js_bundle.mjs            # build (minified if esbuild available)
 *   node scripts/build_js_bundle.mjs --verify   # verify bundle (syntax check + size report)
 *
 * The file order matches index.erb exactly. Source files are kept for
 * development and testing; the bundle is the production artifact loaded
 * by index.erb in Docker.
 *
 * When esbuild is not available (e.g., inside Docker), the script falls
 * back to plain concatenation (still reduces 68 HTTP requests to 1).
 */
import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = join(__dirname, "..", "docker", "services", "ruby", "public");
const OUT_FILE = join(PUBLIC_DIR, "js", "monadic.bundle.min.js");

// File order must match index.erb script tags exactly.
const FILES = [
  "js/debug-config.js",
  "js/monadic/syntax-highlight.js",
  "js/monadic/markdown-renderer.js",
  "js/monadic/storage-helper.js",
  "js/monadic/theme-manager.js",
  "js/monadic/theme-ui.js",
  "js/monadic/status-config.js",
  "js/monadic/model_spec.js",
  "js/monadic/reasoning-mapper.js",
  "js/monadic/reasoning-labels.js",
  "js/monadic/reasoning-ui-manager.js",
  "js/monadic/model_loader.js",
  "js/monadic/version-utils.js",
  "js/monadic/cards.js",
  "js/monadic/card-renderer.js",
  "js/monadic/session_state.js",
  "js/monadic/model_utils.js",
  "js/monadic/text-utils.js",
  "js/monadic/cookie-utils.js",
  "js/monadic/model-capabilities.js",
  "js/monadic/json-tree-toggle.js",
  "js/monadic/alert-manager.js",
  "js/monadic/utilities.js",
  "js/monadic/badge-renderer.js",
  "js/monadic/shims.js",
  "js/monadic/ui-config.js",
  "js/monadic/ui-state.js",
  "js/monadic/error-handler.js",
  "js/monadic/dom-cache.js",
  "js/monadic/ui-utilities.js",
  "js/monadic/context-panel.js",
  "js/monadic/workflow-viewer.js",
  "js/monadic/form-handlers.js",
  "js/monadic/ws-audio-constants.js",
  "js/monadic/ws-content-renderer.js",
  "js/monadic/ws-auto-speech.js",
  "js/monadic/ws-audio-playback.js",
  "js/monadic/ws-audio-queue.js",
  "js/monadic/ws-ui-helpers.js",
  "js/monadic/ws-app-data-handlers.js",
  "js/monadic/ws-message-renderer.js",
  "js/monadic/ws-ai-user-handler.js",
  "js/monadic/ws-session-handler.js",
  "js/monadic/ws-tts-handler.js",
  "js/monadic/ws-connection-handler.js",
  "js/monadic/ws-thinking-handler.js",
  "js/monadic/ws-tool-handler.js",
  "js/monadic/ws-error-handler.js",
  "js/monadic/ws-info-handler.js",
  "js/monadic/ws-streaming-handler.js",
  "js/monadic/ws-html-handler.js",
  "js/monadic/ws-fragment-handler.js",
  "js/monadic/ws-reconnect-handler.js",
  "js/monadic/ws-visibility-handler.js",
  "js/monadic/ws-audio-handler.js",
  "js/monadic/websocket-handlers.js",
  "js/monadic/websocket.js",
  "js/monadic/websearch_tavily_check.js",
  "js/monadic/tts.js",
  "js/monadic/recording.js",
  "js/monadic/select_image.js",
  "js/monadic/mask_editor.js",
  "js/syntax-theme-handler.js",
  "js/i18n/translations.js",
  "js/monadic/pdf_export.js",
  "js/monadic.js",
  "js/monadic/utilities_websearch_patch.js",
  "js/monadic-improvements.js",
];

/**
 * Try to load esbuild. Returns null if not available.
 */
async function tryLoadEsbuild() {
  try {
    const mod = await import("esbuild");
    return mod;
  } catch {
    return null;
  }
}

async function build() {
  const parts = [];
  let totalSourceSize = 0;

  for (const relPath of FILES) {
    const absPath = join(PUBLIC_DIR, relPath);
    const src = readFileSync(absPath, "utf8");
    totalSourceSize += Buffer.byteLength(src, "utf8");
    // Separator comment aids debugging; stripped by minifier
    parts.push(`/* === ${relPath} === */`);
    parts.push(src);
  }

  const concatenated = parts.join(";\n");

  // Try minification with esbuild; fall back to concatenation-only
  const esbuild = await tryLoadEsbuild();
  let code;
  let minified = false;

  if (esbuild) {
    const result = esbuild.transformSync(concatenated, {
      minify: true,
      target: "es2020",
      keepNames: true,
    });
    code = result.code;
    minified = true;
  } else {
    console.log("Note: esbuild not available, using concatenation only (no minification)");
    code = concatenated;
  }

  writeFileSync(OUT_FILE, code);

  const bundleSize = Buffer.byteLength(code, "utf8");
  const ratio = ((1 - bundleSize / totalSourceSize) * 100).toFixed(1);

  console.log(`Bundle: ${FILES.length} files`);
  console.log(`Source: ${(totalSourceSize / 1024).toFixed(0)} KB`);
  console.log(`Output: ${(bundleSize / 1024).toFixed(0)} KB (${ratio}% reduction${minified ? ", minified" : ", concatenated only"})`);
  console.log(`Written: ${OUT_FILE}`);

  return { totalSourceSize, bundleSize };
}

async function verify() {
  const esbuild = await tryLoadEsbuild();
  try {
    const src = readFileSync(OUT_FILE, "utf8");
    if (esbuild) {
      // Syntax check via esbuild transform (will throw on invalid JS)
      esbuild.transformSync(src, { minify: false, target: "es2020" });
      console.log(`Verify: ${OUT_FILE} is valid JavaScript (esbuild syntax check)`);
    } else {
      // Basic check: file is non-empty
      console.log(`Verify: ${OUT_FILE} exists (esbuild not available for syntax check)`);
    }
    console.log(`Size: ${(Buffer.byteLength(src, "utf8") / 1024).toFixed(0)} KB`);
    return true;
  } catch (e) {
    console.error(`Verify FAILED: ${e.message}`);
    process.exit(1);
  }
}

const args = process.argv.slice(2);
if (args.includes("--verify")) {
  await verify();
} else {
  await build();
}
