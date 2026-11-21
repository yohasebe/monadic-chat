// monadic.sh output arrives in chunks that are not cut at lines, and a chunk
// holding a known message is shown as its translation instead. A warning
// printed just before that message (for one, an image that could not be
// downloaded, so the installed one stays in use) would go with it. The
// warnings of a replaced chunk are kept in front of the translation (chunks
// are whole lines; see createLineBuffer).
const WARNING_LINE = /^\[HTML\]:.*color:\s*#FF7F07/i;

function keepWarnings(original, translated) {
  if (translated === original) return translated;
  const warnings = String(original).split('\n').filter((line) => WARNING_LINE.test(line) && !translated.includes(line));
  return warnings.length ? `${warnings.join('\n')}\n${translated}` : translated;
}

// Whole lines only: a chunk is cut after its last newline and the rest
// waits for the next one, so no line (a warning, a marker) is split between
// two calls of `handle`. flush() passes on what is left when the output ends.
function createLineBuffer(handle) {
  let pending = '';
  return {
    push(chunk) {
      const text = pending + String(chunk);
      const cut = text.lastIndexOf('\n');
      if (cut < 0) {
        pending = text;
        return;
      }
      pending = text.slice(cut + 1);
      handle(text.slice(0, cut + 1));
    },
    flush() {
      const rest = pending;
      pending = '';
      if (rest) handle(rest);
    }
  };
}

// The versions in monadic.sh's line "Monadic Chat app vA ... Container image
// vB</p>": { app, container }, with container null when there is no Ruby
// image yet (monadic.sh writes "None"). null for any other line.
function versionsIn(output) {
  const app = /Monadic Chat app v([^\s<]+)/.exec(output);
  const container = /Container image v([^\s<]+)/.exec(output);
  if (!app || !container) return null;
  return { app: app[1], container: container[1] === 'None' ? null : container[1] };
}

// monadic.sh's lines for a server that did not start, in the interface
// language; the engine's own message between them stays as it is. `t` gives
// the translation of a key. Any other output comes back unchanged.
const START_FAILURE = [
  ['The Ruby container did not start, so Monadic Chat is not running.', 'messages.rubyNotStarted'],
  ['Fix the cause and press <b>Start</b> again.', 'messages.fixAndStartAgain']
];

function translateStartFailure(output, t) {
  return START_FAILURE.reduce((text, [english, key]) => text.split(english).join(t(key)), String(output));
}

module.exports = { keepWarnings, createLineBuffer, versionsIn, translateStartFailure };
