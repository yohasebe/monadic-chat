#!/bin/bash
# Script to download third-party libraries for local use in Docker container

# Copy the assets list from host to container if needed and load it
if [ -f "/monadic/bin/assets_list.sh" ]; then
  source "/monadic/bin/assets_list.sh"
else
  echo "Assets list not found in container, creating a local copy..."
  mkdir -p /tmp
  cat > /tmp/assets_list.sh << 'EOF'
# Shared assets configuration file imported from host
ASSETS=(
  # CSS libraries
  "css,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css,bootstrap.min.css"
  "css,https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.14.1/themes/base/jquery-ui.min.css,jquery-ui.min.css"
  "css,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css,all.min.css"
  "css,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/abcjs-audio.min.css,abcjs-audio.min.css"
  
  # Example of how to add a new library
  # "css,https://cdn.example.com/newlib.min.css,newlib.min.css"
  
  # JS libraries
  "js,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.bundle.min.js,bootstrap.bundle.min.js"
  "js,https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.0/jquery.min.js,jquery.min.js"
  "js,https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.14.1/jquery-ui.min.js,jquery-ui.min.js"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/OpusMediaRecorder.umd.js,OpusMediaRecorder.umd.js"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/encoderWorker.umd.js,encoderWorker.umd.js"
  "js,https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-mml-chtml.min.js,tex-mml-chtml.min.js"
  "js,https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js,mermaid.min.js"
  "js,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.min.js,abcjs-basic-min.min.js"
  
  # Font Awesome Webfonts
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-solid-900.woff2,fa-solid-900.woff2"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-regular-400.woff2,fa-regular-400.woff2"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-brands-400.woff2,fa-brands-400.woff2"
  
  # Montserrat Font files
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtr6Hw5aXo.woff2,Montserrat-Regular.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtZ6Hw5aXo.woff2,Montserrat-Medium.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCu173w5aXo.woff2,Montserrat-SemiBold.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCuM73w5aXo.woff2,Montserrat-Bold.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq6R9WXZ0pg.woff2,Montserrat-Italic.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq5Z9WXZ0pg.woff2,Montserrat-MediumItalic.woff2"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq3p6WXZ0pg.woff2,Montserrat-SemiBoldItalic.woff2"
  
  # MathJax Fonts (for offline math rendering)
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Zero.woff,MathJax_Zero.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Main-Regular.woff,MathJax_Main-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Main-Bold.woff,MathJax_Main-Bold.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Main-Italic.woff,MathJax_Main-Italic.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Math-Italic.woff,MathJax_Math-Italic.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Math-BoldItalic.woff,MathJax_Math-BoldItalic.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Size1-Regular.woff,MathJax_Size1-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Size2-Regular.woff,MathJax_Size2-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Size3-Regular.woff,MathJax_Size3-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Size4-Regular.woff,MathJax_Size4-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_AMS-Regular.woff,MathJax_AMS-Regular.woff"
  "mathfont,https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Calligraphic-Regular.woff,MathJax_Calligraphic-Regular.woff"
)

# Montserrat CSS template with all font faces
MONTSERRAT_CSS=$(cat <<'EOFINNER'
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
EOFINNER
)
EOF
  source "/tmp/assets_list.sh"
fi

# Create necessary directories
mkdir -p /monadic/public/vendor/css
mkdir -p /monadic/public/vendor/js
mkdir -p /monadic/public/vendor/fonts
mkdir -p /monadic/public/vendor/webfonts
mkdir -p /monadic/public/vendor/js/output/chtml/fonts/woff-v2

# Define a function to download files
download_file() {
  url="$1"
  destination="$2"
  
  echo "Downloading: $url to $destination"
  if [ -f "$destination" ]; then
    echo "File already exists: $destination"
    return 0
  fi
  
  curl -L --silent "$url" -o "$destination"
  if [ $? -eq 0 ]; then
    echo "Downloaded successfully: $destination"
  else
    echo "Failed to download: $url"
    exit 1
  fi
}

# Process assets from the shared configuration
for asset in "${ASSETS[@]}"; do
  # Split the entry into type, url, and filename
  IFS=',' read -r type url filename <<< "$asset"
  
  # Determine the destination path based on the asset type
  case "$type" in
    css)
      dest="/monadic/public/vendor/css/${filename}"
      ;;
    js)
      dest="/monadic/public/vendor/js/${filename}"
      ;;
    font)
      dest="/monadic/public/vendor/fonts/${filename}"
      ;;
    webfont)
      dest="/monadic/public/vendor/webfonts/${filename}"
      ;;
    mathfont)
      dest="/monadic/public/vendor/js/output/chtml/fonts/woff-v2/${filename}"
      ;;
    *)
      echo "Unknown asset type: $type" >&2
      continue
      ;;
  esac
  
  # Download the file
  download_file "$url" "$dest"
done

# Fix Font Awesome webfont paths in the CSS file
if [ -f "/monadic/public/vendor/css/all.min.css" ]; then
  echo "Fixing Font Awesome webfont paths in CSS file..."
  # In Docker container, we're always on Linux
  sed -i 's|url("../webfonts/|url("/vendor/webfonts/|g' "/monadic/public/vendor/css/all.min.css"
  echo "Font Awesome paths fixed successfully"
fi

# Create a CSS file for local Montserrat font
echo "Creating Montserrat CSS file..."
echo "$MONTSERRAT_CSS" > "/monadic/public/vendor/css/montserrat.css"

echo "All vendor files have been downloaded"