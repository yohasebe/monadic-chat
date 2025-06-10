#!/bin/bash

echo "=== Testing Different 3D Plot Variations ==="

cd ~/monadic/data

# Test 1: Simple tikz-3dplot
echo "Test 1: Simple tikz-3dplot"
cat > test_3d_simple.tex << 'EOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{tikz}
\usepackage{tikz-3dplot}
\begin{document}
\tdplotsetmaincoords{70}{110}
\begin{tikzpicture}[tdplot_main_coords]
    \draw[->] (0,0,0) -- (2,0,0) node[right]{$x$};
    \draw[->] (0,0,0) -- (0,2,0) node[above]{$y$};
    \draw[->] (0,0,0) -- (0,0,2) node[above]{$z$};
    \draw[red,thick] (0,0,0) -- (1,1,1);
\end{tikzpicture}
\end{document}
EOF

docker exec monadic-chat-python-container bash -c "
cd /monadic/data
echo '--- Compiling test_3d_simple.tex ---'
latex -interaction=nonstopmode test_3d_simple.tex > test_3d_simple_compile.log 2>&1
if [ -f test_3d_simple.dvi ]; then
    echo 'DVI created, converting to SVG...'
    dvisvgm --bbox=min test_3d_simple.dvi -o test_3d_simple.svg
    if [ -f test_3d_simple.svg ]; then
        echo '✓ test_3d_simple.svg created'
    fi
else
    echo '✗ LaTeX compilation failed'
    tail -n 20 test_3d_simple.log
fi
"

echo ""

# Test 2: pgfplots 3D
echo "Test 2: pgfplots 3D surface"
cat > test_3d_pgfplots.tex << 'EOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\begin{document}
\begin{tikzpicture}
\begin{axis}[
    xlabel=$x$,
    ylabel=$y$,
    zlabel=$z$,
    view={60}{30}
]
\addplot3[surf,domain=-2:2,samples=20] {x^2+y^2};
\end{axis}
\end{tikzpicture}
\end{document}
EOF

docker exec monadic-chat-python-container bash -c "
cd /monadic/data
echo '--- Compiling test_3d_pgfplots.tex ---'
latex -interaction=nonstopmode test_3d_pgfplots.tex > test_3d_pgfplots_compile.log 2>&1
if [ -f test_3d_pgfplots.dvi ]; then
    echo 'DVI created, converting to SVG...'
    dvisvgm --bbox=min test_3d_pgfplots.dvi -o test_3d_pgfplots.svg
    if [ -f test_3d_pgfplots.svg ]; then
        echo '✓ test_3d_pgfplots.svg created'
    fi
else
    echo '✗ LaTeX compilation failed'
    tail -n 20 test_3d_pgfplots.log
fi
"

echo ""

# Test 3: Mixed approach (tikz-3dplot setup + regular tikz)
echo "Test 3: Mixed tikz-3dplot"
cat > test_3d_mixed.tex << 'EOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{tikz}
\usepackage{tikz-3dplot}
\usetikzlibrary{3d,calc}
\begin{document}
\tdplotsetmaincoords{60}{110}
\begin{tikzpicture}[tdplot_main_coords,scale=2]
    % Axes
    \draw[->] (-1.5,0,0) -- (1.5,0,0) node[right]{$x$};
    \draw[->] (0,-1.5,0) -- (0,1.5,0) node[above]{$y$};
    \draw[->] (0,0,-1) -- (0,0,1.5) node[above]{$z$};
    
    % Simple parametric curve
    \draw[red,thick,domain=0:720,samples=100,smooth] 
        plot ({cos(\x)},{sin(\x)},{0.01*\x});
\end{tikzpicture}
\end{document}
EOF

docker exec monadic-chat-python-container bash -c "
cd /monadic/data
echo '--- Compiling test_3d_mixed.tex ---'
latex -interaction=nonstopmode test_3d_mixed.tex > test_3d_mixed_compile.log 2>&1
if [ -f test_3d_mixed.dvi ]; then
    echo 'DVI created, converting to SVG...'
    dvisvgm --bbox=min test_3d_mixed.dvi -o test_3d_mixed.svg
    if [ -f test_3d_mixed.svg ]; then
        echo '✓ test_3d_mixed.svg created'
    fi
else
    echo '✗ LaTeX compilation failed'
    tail -n 20 test_3d_mixed.log
fi
"

echo ""
echo "=== Results ==="
ls -la ~/monadic/data/test_3d_*.svg 2>/dev/null || echo "No SVG files created"