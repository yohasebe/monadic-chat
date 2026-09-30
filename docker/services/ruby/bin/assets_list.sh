#!/bin/bash
# Third-party files the web UI serves from /vendor, pinned by version and hash.
#
# Format: "type,url,filename,sha256"
#   type:    css, js, font (vendor/fonts) or webfont (vendor/webfonts)
#   url:     a versioned URL, so the same URL keeps returning the same bytes
#   sha256:  of the file as downloaded; nothing edits it afterwards
#
# Sourced by bin/assets.sh (host), scripts/download_assets.sh (Ruby image) and
# the packaging gates (through vendor_manifest), so all of them agree on what
# each vendor file is. A file that is not listed here does not ship.
ASSETS=(
  # CSS libraries
  "css,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.8/css/bootstrap.min.css,bootstrap.min.css,d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede"
  "css,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css,all.min.css,74005d7c17d4a02f2f25404ec0655d9bc2fdaa53166874c87d7b7eec69d9088a"
  "css,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/abcjs-audio.min.css,abcjs-audio.min.css,35a385f562654d2c7a16d37e638cecc2459a3e7dc19a989e52c34fc7e570851d"
  "css,https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/github.min.css,github.min.css,3a9a5def8b9c311e5ae43abde85c63133185eed4f0d9f67fea4b00a8308cf066"
  "css,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css,katex.min.css,19095127357ed6d29fe0a63a6b000c913a89f7f1963b765dd3715e97c9852e75"

  # JS libraries
  "js,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.8/js/bootstrap.bundle.min.js,bootstrap.bundle.min.js,e4fd49181388c48ec5040bd3fe66f57c29c8e67fcd8502b3354b96ec7ab47cc7"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/OpusMediaRecorder.umd.js,OpusMediaRecorder.umd.js,bcb406a8ed33ae1a2a1236707573efab3b62083823072187738ca8c46ffb3d7e"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/encoderWorker.umd.js,encoderWorker.umd.js,084c3fe284f45fb35e37652563fd8c72bb7b089c27e2acb72ab46d98008b241b"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/OggOpusEncoder.wasm,OggOpusEncoder.wasm,0329f6f157cda633f1a0c2cd021beecb23dc37f1dbc3f91b7eb64e03e7fb95f4"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/WebMOpusEncoder.wasm,WebMOpusEncoder.wasm,0d2f6d51da227fbe8a594a2fc1fc8eeb7a6ddd717da702d0305e734f5307b144"
  "js,https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js,mermaid.min.js,a43bc1afd446f9c4cc66ac5dd45d02e8d65e26fc5344ec0ef787f88d6ddb6f9e"
  "js,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.min.js,abcjs-basic-min.min.js,d8efef92e7dd28d3b58911a5427ce26270404f4f4bcfed2aa83d9639f827bdf4"
  "js,https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js,markdown-it.min.js,38c70a1e7ca91ab40e2d9e6e60129851a717ed1c7d4acbbdd41bf9503791cf68"
  "js,https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/highlight.min.js,highlight.min.js,471ef9ae90c407af440fcdc48edfeeb562106b3267bd12d99071c162fb52ed32"
  "js,https://cdn.jsdelivr.net/npm/dompurify@3.4.12/dist/purify.min.js,purify.min.js,c45ba939765574f96cbf35ee9b6d89f73756a17921814425e74b82f7c54603ce"
  "js,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js,katex.min.js,e8d885505949f3a5f4abdd5dd0d53696bd1371ad26ffbf4f310dcd77c8cdae89"
  # diagrams.net serves only its latest viewer; the tagged copy in the drawio
  # repository is the one that stays the same.
  "js,https://raw.githubusercontent.com/jgraph/drawio/v29.5.2/src/main/webapp/js/viewer-static.min.js,viewer-static.min.js,7b713ba84a781bb3f56507de60b490d820fc91a912480f5b1ad1a2daef852de5"
  # maxGraph has no browser build to download; `npm run build:maxgraph` makes
  # vendor/js/maxgraph.bundle.js from the locked @maxgraph/core.

  # Font Awesome Webfonts
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-solid-900.woff2,fa-solid-900.woff2,aa75998623a391e61c6901794ace832e3ecdd288b56d608f21bea0411acc0b8e"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-regular-400.woff2,fa-regular-400.woff2,e3456d1283b9d75337a773dfd147bf908fd02c01b4bf48576d8603a69b13cbe5"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-brands-400.woff2,fa-brands-400.woff2,d7236a19bf23cbb2027280e8f51dc99d6c45976a2ed60de73382b034b18a2b68"

  # Montserrat Font files
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtr6Hw5aXo.woff2,Montserrat-Regular.woff2,ddc148b8a0a27b1449fda6033f4a0defac9bd43210117b50d5d7ad1eda09f394"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtZ6Hw5aXo.woff2,Montserrat-Medium.woff2,ed121b1a8fbf30998a4ed0a7c8343abe9091ac4744f1c24b602b5d3f962bdb78"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCu173w5aXo.woff2,Montserrat-SemiBold.woff2,98be19bc78b5bc5d419e4fa6ea055ebd4671a963e2cc644aeed4362f15d14c31"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCuM73w5aXo.woff2,Montserrat-Bold.woff2,f31b80562610135edd91a86ec7f243c5eeaec2ec08337e6a20c2d135d8e217da"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq6R9WXZ0pg.woff2,Montserrat-Italic.woff2,55ac0fce6af393313fc9be2ff266ea61a91720d74a72209a6d2ca71b546bc565"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq5Z9WXZ0pg.woff2,Montserrat-MediumItalic.woff2,18d22bb0c768dbf707429938d52fe552da2b4367a5b04ba53f9ebfd8d4eb64d1"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq3p6WXZ0pg.woff2,Montserrat-SemiBoldItalic.woff2,e7c93612df5114e469ff5d43caa510cbe324f6b0158a919ec2d8ff20256b5c1b"

  # KaTeX fonts. katex.min.css loads them from fonts/ beside it, which
  # vendor_fetch links to vendor/fonts.
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_AMS-Regular.woff2,KaTeX_AMS-Regular.woff2,0cdd387c9590a1a9f9794560022dbb59654a7d86f187aa0c81495ad42d3a7308"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Caligraphic-Bold.woff2,KaTeX_Caligraphic-Bold.woff2,de7701e42cf1f4cf0b766c03fb27977207eee2f4fd5d76fa82188406da43ea4c"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Caligraphic-Regular.woff2,KaTeX_Caligraphic-Regular.woff2,5d53e70ad607c2352162dec9e0923fb54ecdafaccbf604cd8dcf7d00facb989b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Fraktur-Bold.woff2,KaTeX_Fraktur-Bold.woff2,74444efd593c005e3f4573b44524704c0af0a937fe911cca9e94068d0d140d3f"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Fraktur-Regular.woff2,KaTeX_Fraktur-Regular.woff2,51814d270d06ff0255dba0799994fa4d8c84d11f09951d47595f4abb1f3602dc"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Bold.woff2,KaTeX_Main-Bold.woff2,0f60d1b897938ec918c8ce073092411baf9438f6739465693ff18b0f9d20b021"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-BoldItalic.woff2,KaTeX_Main-BoldItalic.woff2,99cd42a3c072d918f2f44984a807cf7aa16e13545fd0875fc07c6c65f99e715b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Italic.woff2,KaTeX_Main-Italic.woff2,97479ca6cce906abc961ecac96faa5f9ca2e61b8e7670d475826bcdee9a7c267"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Regular.woff2,KaTeX_Main-Regular.woff2,c2342cd8b869e01752a9321dc17213fc40d4d04c79688c1d43f2cf316abd7866"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Math-BoldItalic.woff2,KaTeX_Math-BoldItalic.woff2,dc47344dbb6cb5b655c8460d561f4df5f501b90c804ad3c6cec65fe322351ab1"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Math-Italic.woff2,KaTeX_Math-Italic.woff2,7af58c5ec8f132a2ddde9027c6d7814decce4d3b822a11192a42a20e2e973264"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Bold.woff2,KaTeX_SansSerif-Bold.woff2,e99ae51144bf1232efcc1bfe5add36262c6866b0faab24fa75740e1b98577a62"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Italic.woff2,KaTeX_SansSerif-Italic.woff2,00b26ac825e2095056396e0553b8ac26d3f8ad158c3826e28b4c45b385c4714a"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Regular.woff2,KaTeX_SansSerif-Regular.woff2,68e8c73ef42afd3ccec58bf0fba302cce448938e7fc020a5e31f8a952eee1342"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Script-Regular.woff2,KaTeX_Script-Regular.woff2,036d4e95149b69ff9bcc0cd55771efeb25ffa3947293e69acd78d5ac328c684b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size1-Regular.woff2,KaTeX_Size1-Regular.woff2,6b47c40166b6dbe21a5dfca7718413f2147fd2399be1ba605d8ad39cedf25dfe"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size2-Regular.woff2,KaTeX_Size2-Regular.woff2,d04c54219f9eaec6d4d4fd42dfb28785975a4794d6b2fc71e566b9cd6db842dd"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size3-Regular.woff2,KaTeX_Size3-Regular.woff2,73d591271b1604960cb10bb90fee021670af7297017e0e98480b332d11f51995"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size4-Regular.woff2,KaTeX_Size4-Regular.woff2,a4af7d414440a1c1790825cfb700cf9cf43b0f2c4b04f0ebc523011ad9853ec0"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Typewriter-Regular.woff2,KaTeX_Typewriter-Regular.woff2,71d517d67827787cfabdf186914cc3358eda539e37931941f2b2fd4a21f68c0b"
)

# Montserrat CSS template with all font faces
MONTSERRAT_CSS=$(cat <<'EOF'
/* Montserrat Font */
@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 400;
  src: url('/vendor/fonts/Montserrat-Regular.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 500;
  src: url('/vendor/fonts/Montserrat-Medium.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 600;
  src: url('/vendor/fonts/Montserrat-SemiBold.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 700;
  src: url('/vendor/fonts/Montserrat-Bold.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 400;
  src: url('/vendor/fonts/Montserrat-Italic.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 500;
  src: url('/vendor/fonts/Montserrat-MediumItalic.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 600;
  src: url('/vendor/fonts/Montserrat-SemiBoldItalic.woff2') format('woff2');
}
EOF
)

vendor_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | cut -d' ' -f1
  else
    shasum -a 256 "$@" | cut -d' ' -f1
  fi
}

# Where a listed file goes, relative to the vendor directory.
vendor_asset_path() {
  case "$1" in
    css) echo "css/$2" ;;
    js) echo "js/$2" ;;
    font) echo "fonts/$2" ;;
    webfont) echo "webfonts/$2" ;;
    *) echo "Unknown asset type: $1" >&2; return 1 ;;
  esac
}

# "path<TAB>sha256" for every file vendor_fetch writes, relative to the vendor
# directory. The packaging gates read this instead of parsing the list.
vendor_manifest() {
  local asset type url filename sha rel
  for asset in "${ASSETS[@]}"; do
    IFS=',' read -r type url filename sha <<< "$asset"
    rel=$(vendor_asset_path "$type" "$filename") || return 1
    printf '%s\t%s\n' "$rel" "$sha"
  done
  printf '%s\t%s\n' "css/montserrat.css" "$(printf '%s\n' "$MONTSERRAT_CSS" | vendor_sha256)"
}

# Brings every listed file under the given vendor directory to its pinned
# bytes. A file that already matches is kept, so a build needs no network
# once the files are in place; any other file is downloaded again. A failed
# download or a hash mismatch stops with an error: saving whatever the server
# returned once put an HTML error page where a stylesheet belonged.
vendor_fetch() {
  local dir="$1" asset type url filename sha rel dest got
  for asset in "${ASSETS[@]}"; do
    IFS=',' read -r type url filename sha <<< "$asset"
    rel=$(vendor_asset_path "$type" "$filename") || return 1
    dest="${dir}/${rel}"
    if [ -f "$dest" ] && [ "$(vendor_sha256 "$dest")" = "$sha" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    echo "Downloading: $url"
    if ! curl --fail --location --silent --show-error --retry 2 \
         --connect-timeout 15 --max-time 300 -o "${dest}.download" "$url"; then
      rm -f "${dest}.download"
      echo "Failed to download: $url" >&2
      return 1
    fi
    got=$(vendor_sha256 "${dest}.download")
    if [ "$got" != "$sha" ]; then
      rm -f "${dest}.download"
      echo "Hash mismatch for $url: expected $sha, got $got" >&2
      return 1
    fi
    mv -f "${dest}.download" "$dest"
  done
  # A Windows payload carries the link as a copy of the directory; keep that.
  if [ ! -e "${dir}/css/fonts" ] || [ -L "${dir}/css/fonts" ]; then
    ln -sfn ../fonts "${dir}/css/fonts"
  fi
  printf '%s\n' "$MONTSERRAT_CSS" > "${dir}/css/montserrat.css"
}
