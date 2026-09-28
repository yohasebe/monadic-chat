# Bundled fonts

The Electron pages (`app/index.html`, `app/settings.html`) load these files
locally so that icons and text render the same without a network connection.
Every file except `montserrat/montserrat.css` is a byte-for-byte copy from the
npm package named below.

## Font Awesome Free 6.4.0

- Source: `@fortawesome/fontawesome-free@6.4.0` (npm integrity
  `sha512-0NyytTlPJwB/BF5LtRV8rrABDbe3TdTXqNB3PdZ+UUUZAEIrdOJdmABqKjt4AXwIoJNaRVVZEXxpNrqvE1GAYQ==`)
- Included: `css/all.min.css`, `webfonts/fa-solid-900.woff2`,
  `webfonts/fa-regular-400.woff2`, `webfonts/fa-brands-400.woff2`, `LICENSE.txt`
- Not included: the `.ttf` fallbacks and `fa-v4compatibility` (used only by
  the Font Awesome 4 `FontAwesome` family, which these pages do not use)
- License: icons CC BY 4.0, fonts SIL OFL 1.1, code MIT (see `LICENSE.txt`)
- Do not edit or re-minify `css/all.min.css`: its header comment carries the
  required attribution, and the file is identical to the CDN copy previously
  referenced with an integrity hash.

## Montserrat (variable, 100–900)

- Source: `@fontsource-variable/montserrat@5.3.0` (npm integrity
  `sha512-7PaZoxaxrWLAyrhO46v65An9LhUhfkTExWLhfbywYZCnZEgg/W1rEHnlNmZKjNZ3nJTVYyicqxlJt10z/26yTA==`)
- Included: the Latin and Latin Extended subsets, normal and italic
  (`montserrat-latin{,-ext}-wght-{normal,italic}.woff2`), and the license as
  `OFL.txt`. Other scripts fall back to system fonts.
- `montserrat.css` is written for this app: the package's `@font-face` rules
  for those four files, renamed from `Montserrat Variable` to `Montserrat` and
  pointing at files in the same directory.
- License: SIL OFL 1.1 (see `OFL.txt`)

## Updating

1. `npm pack <package>@<version>` and compare the tarball's SHA-512 with
   `npm view <package>@<version> dist.integrity`.
2. Copy the same set of files unchanged, and update the versions and integrity
   values above.
3. Keep `scripts/lint/tracked_paths.allow` in step: a file it does not name
   fails CI.
