# External JavaScript Libraries (Vendor Assets)

Monadic Chat vendors a small set of third-party libraries for offline/packaged use. Each one is pinned by version and sha256; see [CDN Assets Management](developer/assets.md) for how the list is read and checked.

Locations:
- List: `docker/services/ruby/bin/assets_list.sh`
- Installer: `bin/assets.sh`
- Destination: `docker/services/ruby/public/vendor/{css,js,fonts,webfonts}`

## How to Add a Library

1) Download the file from a versioned URL and take its hash:
- `curl --fail -L -o lib.js "<url>" && shasum -a 256 lib.js`

2) Append an entry to `ASSETS` in `docker/services/ruby/bin/assets_list.sh`:
- Format: `"type,url,filename,sha256"`
- Types: `css`, `js`, `font`, `webfont`

3) Run the installer:
- `rake download_vendor_assets`
  - Runs `./bin/assets.sh`, which downloads the files that are missing or differ from their pins and stops on a failed download or a hash mismatch.

Guidelines:
- Use a URL that names the version (cdnjs, jsdelivr `@x.y.z`, a git tag). A URL that serves the latest release stops matching its pin when upstream updates.
- To update a library, change the URL and the hash together.
- Avoid large libraries unless there is a clear need.
