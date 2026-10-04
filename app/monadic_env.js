'use strict';

// The settings from ~/monadic/config/env that monadic.sh and the compose
// files read from their environment. Only these are passed to monadic.sh.
//
// Passing the whole file used to put every API key into the environment of
// monadic.sh, docker and docker compose, visible to other processes of the
// same user, although none of them reads a key (the Ruby server reads them
// from the file itself). test/electron/monadic-env.test.js compares this list
// with the variables the scripts actually read.
const MONADIC_SH_ENV = Object.freeze([
  // Install options (PY_OPTIONS in monadic.sh, build args in compose)
  'INSTALL_LATEX', 'PYOPT_NLTK', 'PYOPT_SPACY', 'PYOPT_GENSIM', 'PYOPT_LIBROSA',
  'PYOPT_MEDIAPIPE', 'PYOPT_TRANSFORMERS', 'IMGOPT_IMAGEMAGICK',
  // Optional services and their runtime settings
  'PRIVACY_FILTER', 'PRIVACY_LANGS', 'PRIVACY_DEV_PORT',
  'EXTRACTOR_SERVICE', 'EXTRACTOR_LANGS', 'EXTRACTOR_OCR', 'EXTRACTOR_DEV_PORT',
  // Networking, logging, images and build switches
  'HOST_BINDING', 'EXTRA_LOGGING', 'MONADIC_IMAGE_TAG', 'MONADIC_DEV',
  'AUTO_REFRESH_RUBY_ON_HEALTH_FAIL', 'FORCE_RUBY_REBUILD_NO_CACHE', 'STALE_LOCK_MAX_SECS'
]);

// The part of a parsed env file that monadic.sh may see.
function monadicShEnv(envConfig) {
  const env = {};
  for (const key of MONADIC_SH_ENV) {
    if (envConfig && envConfig[key] !== undefined) env[key] = envConfig[key];
  }
  return env;
}

module.exports = { MONADIC_SH_ENV, monadicShEnv };
