// Single source of truth for Monadic Chat install options.
//
// What lives here:
//   - The canonical list of optional Python container packages
//     (PYOPT_*, IMGOPT_*, INSTALL_LATEX) — each with the env name,
//     the matching HTML checkbox id, and a default English label.
//   - The Privacy Filter and Extractor language code lists.
//   - "Always-installed" languages that the UI pins as
//     `checked disabled` (English baseline for both Privacy and
//     Extractor).
//
// What does NOT live here (intentional):
//   - HTML markup for the checkboxes — `app/settings.html` still owns
//     the visual layout. The runtime code there reads from this file
//     to populate Save / Load / pyKeys lookup tables, but the DOM
//     itself is hand-authored to keep i18n attributes (`data-i18n`)
//     declarative.
//   - Dockerfile ARG declarations / `RUN if [ ... ]` blocks. The
//     Dockerfile remains the build-time contract; this file describes
//     the runtime UI ↔ env wiring. Adding a new option requires two
//     coordinated edits (this file + the Dockerfile); the doc at
//     `docs_dev/install_options_ssot.md` is the checklist.
//   - i18n labels — `docker/services/ruby/public/js/i18n/translations.js`
//     owns those. This file's `label` is the English fallback only.
//
// File format note: this is a plain CommonJS module so it can be
// `require()`'d from Electron's `app/main.js` (Node) AND read by
// `monadic.sh` via `node -e "console.log(require('./install_options.config').…)"`
// without a bundler step.
'use strict';

// Python container build-time options. Each entry maps:
//   id    → HTML element id (`<input id="..."/>`)
//   env   → env var written to ~/monadic/config/env (also the
//           Dockerfile ARG name that monadic.sh passes via --build-arg)
//   label → English fallback when no i18n key is set
//   group → 'python' (Python Libraries CPU), 'system' (apt),
//           'music' (Music Lab requirement), 'tools' (CLI utilities)
const PYTHON_OPTIONS = Object.freeze([
  Object.freeze({ id: 'install-latex',        env: 'INSTALL_LATEX',       label: 'LaTeX (minimal set for diagrams)', group: 'system' }),
  Object.freeze({ id: 'pyopt-nltk',           env: 'PYOPT_NLTK',          label: 'nltk',                              group: 'python' }),
  Object.freeze({ id: 'pyopt-spacy',          env: 'PYOPT_SPACY',         label: 'spaCy (3.7.5)',                     group: 'python' }),
  Object.freeze({ id: 'pyopt-gensim',         env: 'PYOPT_GENSIM',        label: 'gensim',                            group: 'python' }),
  Object.freeze({ id: 'pyopt-mediapipe',      env: 'PYOPT_MEDIAPIPE',     label: 'mediapipe (CPU)',                   group: 'python' }),
  Object.freeze({ id: 'pyopt-transformers',   env: 'PYOPT_TRANSFORMERS',  label: 'transformers (CPU only)',           group: 'python' }),
  Object.freeze({ id: 'pyopt-librosa',        env: 'PYOPT_LIBROSA',       label: 'librosa + madmom',                  group: 'music' }),
  Object.freeze({ id: 'imgopt-imagemagick',   env: 'IMGOPT_IMAGEMAGICK',  label: 'ImageMagick (convert/mogrify)',     group: 'tools' })
]);

// Privacy Filter language codes. English is mandatory (always
// installed) and pinned `checked disabled` in the HTML; the others
// are opt-in. Adding a new language: append it to PRIVACY_OPTIONAL,
// add an HTML checkbox row in `app/settings.html`, and add the
// translation strings to translations.js.
const PRIVACY_LANG_BASE = Object.freeze(['en']);
const PRIVACY_LANG_OPTIONAL = Object.freeze(['de', 'es', 'fr', 'it', 'ja', 'nl', 'pt', 'zh']);

// Extractor (Knowledge Base Quality Pack) OCR language codes. English
// is the foundational layer (Latin alphabet appears in nearly every
// document regardless of dominant language) and is pinned `checked
// disabled`. The others are opt-in once the master toggle is on.
const EXTRACTOR_LANG_BASE = Object.freeze(['en']);
const EXTRACTOR_LANG_OPTIONAL = Object.freeze(['ja', 'zh', 'ko']);

// Helpers used by app/main.js and (via node -e) by monadic.sh.
const ENV_KEYS_PYTHON = Object.freeze(PYTHON_OPTIONS.map(o => o.env));

module.exports = Object.freeze({
  PYTHON_OPTIONS,
  ENV_KEYS_PYTHON,
  PRIVACY_LANG_BASE,
  PRIVACY_LANG_OPTIONAL,
  PRIVACY_LANG_ALL: Object.freeze([...PRIVACY_LANG_BASE, ...PRIVACY_LANG_OPTIONAL]),
  EXTRACTOR_LANG_BASE,
  EXTRACTOR_LANG_OPTIONAL,
  EXTRACTOR_LANG_ALL: Object.freeze([...EXTRACTOR_LANG_BASE, ...EXTRACTOR_LANG_OPTIONAL])
});
