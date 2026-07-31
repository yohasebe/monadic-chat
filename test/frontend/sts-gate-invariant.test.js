/**
 * Single-point derivation of the speech-to-speech mode.
 *
 * Both STS integration gaps in this cycle had the same shape: two layers
 * derived "are we in STS mode?" from different inputs (the dropdown filter
 * from one place, the recording path from the STT model, the server from the
 * chat model). Each layer was locally correct and the seam between them was
 * broken.
 *
 * The defence is to make the derivation single-point per side and pin it:
 *
 *   client behaviour  → window.SttGate.isStsModelSelected()  (stt-gate.js)
 *   server behaviour  → sts_session_capable?                 (sts_stream_handler.rb)
 *   raw property read → model_spec.js / model_spec.rb        (the SSOT pair)
 *   display & listing → utilities.js label, model_utils.js show-all filter
 *
 * Any new file touching `supports_speech_to_speech` fails this test until it
 * is deliberately added to the allowlist — which is the moment to ask whether
 * it should be calling the gate instead.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

// Strip full-line comments so a mention in prose does not count as a reader.
// Deliberately crude: inline trailing comments still count, which errs on the
// side of flagging too much rather than letting a real read hide in one.
function codeLines(text, commentPrefix) {
  return text.split('\n')
    .filter(line => !line.trim().startsWith(commentPrefix))
    .join('\n');
}

function scan(dir, ext, commentPrefix, skip = []) {
  const hits = [];
  const walk = (d) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.name.endsWith(ext)) continue;
      if (skip.some(s => entry.name.includes(s))) continue;
      if (codeLines(fs.readFileSync(full, 'utf8'), commentPrefix).includes('supports_speech_to_speech')) {
        hits.push(path.relative(ROOT, full).replace(/\\/g, '/'));
      }
    }
  };
  walk(dir);
  return hits.sort();
}

describe('speech-to-speech mode is derived at a single point per side', () => {
  it('client: only the SSOT, the gate, the show-all filter and the display label read the flag', () => {
    const hits = scan(
      path.join(ROOT, 'docker/services/ruby/public/js'), '.js', '//',
      ['.min.js', 'monadic.bundle']
    );

    expect(hits).toEqual([
      'docker/services/ruby/public/js/monadic/model_spec.js',   // SSOT definition
      'docker/services/ruby/public/js/monadic/model_utils.js',  // show-all exclusion
      'docker/services/ruby/public/js/monadic/stt-gate.js',     // THE behavioural gate
      'docker/services/ruby/public/js/monadic/utilities.js'     // "(realtime)" label
    ]);
  });

  it('server: only the SSOT accessor and the session gate read the flag', () => {
    const hits = scan(path.join(ROOT, 'docker/services/ruby/lib'), '.rb', '#');

    expect(hits).toEqual([
      'docker/services/ruby/lib/monadic/utils/model_spec.rb',                   // SSOT accessor
      'docker/services/ruby/lib/monadic/utils/websocket/sts_stream_handler.rb'  // sts_session_capable?
    ]);
  });

  it('behavioural call sites go through the gate, not the raw flag', () => {
    // Under the Live Conversation design (STS = dedicated app), the primary
    // wall is app separation: STS models never appear in ordinary apps'
    // selectors. The remaining gate consumers are defense-in-depth:
    // recording.js (capture transport) and the stt-message guards below.
    // monadic.js no longer consults the gate — its mode-switch branches were
    // retired with the integrated design.
    const recording = fs.readFileSync(
      path.join(ROOT, 'docker/services/ruby/public/js/monadic/recording.js'), 'utf8');
    const monadic = fs.readFileSync(
      path.join(ROOT, 'docker/services/ruby/public/js/monadic.js'), 'utf8');

    expect(recording).toMatch(/SttGate\.isStsModelSelected/);
    expect(recording).not.toContain('supports_speech_to_speech');
    expect(monadic).not.toContain('supports_speech_to_speech');
  });

  // Defense-in-depth: even though ordinary apps can no longer select STS
  // models, the stt-message consumers keep their guards so a Live
  // Conversation turn's transcript can never leak into the textarea /
  // easy-submit path of the ordinary pipeline.
  it('stt-message consumers keep their STS guards', () => {
    const wsHandlers = fs.readFileSync(
      path.join(ROOT, 'docker/services/ruby/public/js/monadic/websocket-handlers.js'), 'utf8');
    const sessionHandler = fs.readFileSync(
      path.join(ROOT, 'docker/services/ruby/public/js/monadic/ws-session-handler.js'), 'utf8');

    expect(wsHandlers).toMatch(/isStsModelSelected/);
    expect(sessionHandler).toMatch(/isStsModelSelected/);
  });
});
