# External JavaScript Libraries (Vendor Assets)

Monadic Chat vendors a small set of third-party libraries for offline/packaged use. Each one is pinned by version and sha256; see [CDN Assets Management](developer/assets.md) for how the list is read and checked.

Locations:
- List: `docker/services/ruby/bin/assets_list.sh`
- Installer: `bin/assets.sh`
- Destination: `docker/services/ruby/public/vendor/{css,js,fonts,webfonts,pdfjs,soundfont}`

## How to Add a Library

1) Download the file from a versioned URL and take its hash:
- `curl --fail -L -o lib.js "<url>" && shasum -a 256 lib.js`

2) Append an entry to `ASSETS` in `docker/services/ruby/bin/assets_list.sh`:
- Format: `"type,url,filename,sha256"`
- Types: `css`, `js`, `font`, `webfont`, `pdfjs`, `soundfont` (the last two may name a folder under theirs)

3) Run the installer:
- `rake download_vendor_assets`
  - Runs `./bin/assets.sh`, which downloads the files that are missing or differ from their pins and stops on a failed download or a hash mismatch.

Guidelines:
- Use a URL that names the version (cdnjs, jsdelivr `@x.y.z`, a git tag, or a commit for a repository without releases). A URL that serves the latest release stops matching its pin when upstream updates.
- To update a library, change the URL and the hash together.
- Avoid large libraries unless there is a clear need.

## Sounds for ABC playback

`vendor/soundfont/FluidR3_GM/` holds the sounds the ABC player plays (`public/js/monadic/abc-player.js`): the FluidR3 General MIDI instruments Music Lab writes (programs 0, 4, 11, 19, 25, 27, 33, 48, 61, 80 and 89), one mp3 per note, from the midi-js-soundfonts repository at a fixed commit. Its `LICENSE.txt` (the collection, MIT) and `README.md` (which names the FluidR3 sound font's license, CC BY 3.0) ship beside them. A tune that asks for another instrument is played with the carried one of its family, or the piano (`AbcPlayer.carriedProgram`). Adding an instrument means adding its `<name>-mp3/` files to `assets_list.sh` and its program to `abc-player.js`.

