# External JavaScript Libraries (Vendor Assets)

Monadic Chat vendors a small set of third‑party libraries for offline/packaged use. Use the provided scripts to add or update libraries.

Locations:
- List: `docker/services/ruby/bin/assets_list.sh`
- Installer: `bin/assets.sh`
- Destination: `docker/services/ruby/public/vendor/{css,js,fonts,webfonts}`

## How to Add a Library

1) Edit `docker/services/ruby/bin/assets_list.sh` and append a new entry to `ASSETS`:
- Format: `"type,url,filename"`
- Types: `css`, `js`, `font`, `webfont`, `mathfont`

2) Run the installer:
- `rake download_vendor_assets`
  - Internally runs `./bin/assets.sh` and populates `public/vendor`.

3) Verify:
- Check files under `docker/services/ruby/public/vendor`.
- For CSS like Font Awesome, `assets.sh` rewrites webfont URLs to `/vendor/webfonts/`.

Guidelines:
- Prefer well‑known CDNs (cdnjs, jsdelivr) with fixed versions.
- Keep filenames stable for cacheability.
- Avoid large libraries unless there is a clear need.

