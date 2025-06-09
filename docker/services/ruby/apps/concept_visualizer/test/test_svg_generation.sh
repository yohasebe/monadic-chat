#!/bin/bash

echo "=== SVG Generation Test Script ==="
echo "Testing 3D plot with pgfplots..."

cd ~/monadic/data

# Test file name
TIMESTAMP=$(date +%s)
BASE_NAME="test_3d_plot_${TIMESTAMP}"

# Create a simple 3D plot LaTeX file
cat > ${BASE_NAME}.tex << 'EOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{3d,perspective}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usepackage{tikz-3dplot}
\usetikzlibrary{calc,fit,backgrounds}
\usepackage{xcolor}
\usepackage[utf8]{inputenc}
\begin{document}
\begin{tikzpicture}
  \begin{axis}[
    xlabel=$x$,
    ylabel=$y$,
    zlabel=$z$,
    title={3D Surface Plot},
    colormap/viridis,
    view={60}{30}
  ]
  \addplot3[
    surf,
    domain=-2:2,
    domain y=-2:2,
    samples=25
  ] {exp(-x^2-y^2)};
  \end{axis}
\end{tikzpicture}
\end{document}
EOF

echo "LaTeX file created: ${BASE_NAME}.tex"

# Run in Docker container
echo "Running in Python container..."
docker exec monadic-chat-python-container bash -c "
cd /monadic/data

# Check LaTeX installation
echo '=== Checking LaTeX packages ==='
which latex
which dvisvgm

# Check for required packages
echo '=== Checking required packages ==='
for pkg in tikz.sty pgf.sty pgfplots.sty tikz-3dplot.sty; do
    if kpsewhich \$pkg >/dev/null 2>&1; then
        echo \"✓ \$pkg found\"
    else
        echo \"✗ \$pkg NOT FOUND\"
    fi
done

echo '=== Compiling LaTeX ==='
latex -interaction=nonstopmode ${BASE_NAME}.tex

if [ -f ${BASE_NAME}.dvi ]; then
    echo '=== DVI file created successfully ==='
    ls -la ${BASE_NAME}.dvi
    
    echo '=== Converting to SVG ==='
    # Try dvisvgm with verbose output
    dvisvgm --verbosity=3 --bbox=min --precision=3 ${BASE_NAME}.dvi -o ${BASE_NAME}.svg
    
    if [ -f ${BASE_NAME}.svg ]; then
        echo '=== SVG created successfully ==='
        ls -la ${BASE_NAME}.svg
        echo '=== First 10 lines of SVG ==='
        head -n 10 ${BASE_NAME}.svg
    else
        echo '=== SVG creation failed ==='
    fi
else
    echo '=== LaTeX compilation failed ==='
    echo '=== LaTeX log ==='
    tail -n 50 ${BASE_NAME}.log
fi
"

# Check results
echo ""
echo "=== Checking output files ==="
ls -la ~/monadic/data/${BASE_NAME}*

if [ -f ~/monadic/data/${BASE_NAME}.svg ]; then
    echo ""
    echo "✅ SUCCESS: SVG file was generated!"
    echo "File: ~/monadic/data/${BASE_NAME}.svg"
else
    echo ""
    echo "❌ FAILED: SVG file was not generated"
    echo "Check the output above for errors"
fi