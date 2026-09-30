# CDN Assets Management for Developers

## Overview

The web UI serves third-party libraries from `/vendor` so that it works offline. They are downloaded, not tracked, so `assets_list.sh` is the only record of what they are: each entry pins a versioned URL and the sha256 of the file.

## Files

- `/docker/services/ruby/bin/assets_list.sh`: the list, and the shell functions every consumer uses to read it (`vendor_manifest`, `vendor_fetch`)
- `/bin/assets.sh`: fetches into the source tree (`rake download_vendor_assets`, also run by `rake build`)
- `/docker/services/ruby/scripts/download_assets.sh`: runs during the Ruby image build
- `/scripts/build_products.rb`: the packaging gates' view of the same list

## How to Add New Assets

1. Download the file from a versioned URL and take its sha256.
2. Add an entry to the `ASSETS` array:
   ```
   "type,url,filename,sha256"
   ```
   - `type`: `css` (vendor/css), `js` (vendor/js), `font` (vendor/fonts), `webfont` (vendor/webfonts)
   - `url`: a URL that names the version, so it keeps returning the same bytes
   - `sha256`: of the file as downloaded; nothing edits it afterwards
3. Run `rake download_vendor_assets`.

## How Fetching Works

`vendor_fetch` keeps a file whose hash matches its pin and downloads any other (`curl --fail`). A failed download or a hash mismatch stops with an error, so an HTTP error page is never saved as an asset. It also writes `css/montserrat.css` from `MONTSERRAT_CSS` and links `css/fonts` to `../fonts`, where `katex.min.css` looks for the KaTeX fonts.

maxGraph has no browser build to download. `npm run build:maxgraph` builds `vendor/js/maxgraph.bundle.js` from the locked `@maxgraph/core`.

## Docker Integration

The Ruby image copies `public/` from the app payload, which already holds the vendor files, and then runs `download_assets.sh`. The hashes match, so an image build needs no network for them. The files served in production are the ones in the payload.

## Packaging Gates

- `stage_docker_payload.rb` ships exactly the files `vendor_manifest` lists, plus the font link and the maxGraph bundle. Other files in the vendor directory do not ship. A listed file whose hash differs from its pin stops staging.
- `verify_bundle_payload.rb` compares every vendor file in each archive with its pin. It also builds the JS bundle and the maxGraph bundle again in a clean worktree of the commit staging read, and compares those with the packed copies.
