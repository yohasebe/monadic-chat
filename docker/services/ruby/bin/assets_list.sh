#!/bin/bash
# Shared assets configuration file
# Format: "type,url,filename"
# Where:
# - type: Asset type (css, js, font, webfont, mathfont)
# - url: Full URL to the asset on CDN
# - filename: Local filename to save the asset as

# This file is imported by both assets.sh and download_assets.sh

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
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@latest/OggOpusEncoder.wasm,OggOpusEncoder.wasm"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@latest/WebMOpusEncoder.wasm,WebMOpusEncoder.wasm"
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
