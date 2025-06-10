#!/bin/bash

echo "=== Testing LaTeX Error Recovery System ==="

# Create a LaTeX file with known errors (similar to the failed attempt)
cat > ~/monadic/data/test_error_recovery.tex << 'EOF'
\documentclass[tikz,border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{3d,perspective}
\usepackage{tikz-3dplot}
\usetikzlibrary{calc,fit,backgrounds}
\usepackage{xcolor}
\usepackage[utf8]{inputenc}
\begin{document}
\begin{tikzpicture}[tdplot_main_coords, scale=3]
    % This will cause "I do not know the key" error
    \tdplotsetmaincoords{70}{110}
    
    % Undefined variables
    \def\R{1.2}
    \def\r{0.4}
    
    % Axes
    \draw[->] (-2,0,0) -- (2,0,0) node[right]{$x$};
    \draw[->] (0,-2,0) -- (0,2,0) node[above]{$y$};
    \draw[->] (0,0,-1.5) -- (0,0,1.5) node[above]{$z$};
    
    % This will cause "Cannot parse plotting data" error
    \draw[black, thick] plot3[domain=0:360, samples=50,variable=\U,smooth] 
         ({ (\R+\r)*cos(\U*pi/180) },
          { (\R+\r)*sin(\U*pi/180) },
          { 0 });
          
    % Nested tikzpicture (will cause error)
    \begin{tikzpicture}
        \draw (0,0) circle (1);
    \end{tikzpicture}
\end{tikzpicture}
\end{document}
EOF

echo "Created test file with intentional errors"

# Simulate the concept visualizer compilation process
cd ~/monadic/data

# Function to compile LaTeX
compile_latex() {
    local tex_file=$1
    local attempt=$2
    echo "Compilation attempt $attempt..."
    docker exec monadic-chat-python-container bash -c "
        cd /monadic/data
        latex -interaction=nonstopmode $tex_file 2>&1 | tee ${tex_file%.tex}_compile.log
        # Check if DVI was created
        if [ -f ${tex_file%.tex}.dvi ]; then
            exit 0
        else
            exit 1
        fi
    "
    return $?
}

echo ""
echo "=== First compilation attempt (should fail) ==="
compile_latex test_error_recovery.tex 1

if [ $? -ne 0 ]; then
    echo ""
    echo "=== Applying automatic fixes ==="
    
    # Apply the same fixes as in concept_visualizer
    docker exec monadic-chat-python-container bash -c "
        cd /monadic/data
        
        # Save original
        cp test_error_recovery.tex test_error_recovery_original.tex
        
        # Fix tdplot_main_coords error
        if grep -q 'I do not know the key.*tdplot_main_coords' test_error_recovery.log; then
            echo 'Fixing: tdplot_main_coords error'
            sed -i 's/\\\\begin{tikzpicture}\\[.*tdplot_main_coords/\\\\tdplotsetmaincoords{70}{110}\\n\\\\begin{tikzpicture}[/' test_error_recovery.tex
        fi
        
        # Fix plot3 command
        if grep -q 'Undefined control sequence.*\\\\plot3\\|Cannot parse this plotting data' test_error_recovery.log; then
            echo 'Fixing: plot3 command'
            sed -i 's/plot3\\[/plot[/g' test_error_recovery.tex
        fi
        
        # Fix undefined variables
        if grep -q 'Undefined control sequence.*\\\\U' test_error_recovery.log; then
            echo 'Fixing: undefined variable \\U'
            sed -i 's/variable=\\\\U/variable=\\\\t/g' test_error_recovery.tex
            sed -i 's/\\\\U\\*/\\\\t\\*/g' test_error_recovery.tex
        fi
        
        # Fix nested tikzpicture
        echo 'Checking for nested tikzpicture...'
        # Count occurrences
        BEGIN_COUNT=\$(grep -c '\\\\begin{tikzpicture}' test_error_recovery.tex)
        END_COUNT=\$(grep -c '\\\\end{tikzpicture}' test_error_recovery.tex)
        echo \"Found \$BEGIN_COUNT begin and \$END_COUNT end tikzpicture\"
        
        if [ \$BEGIN_COUNT -gt 1 ]; then
            echo 'Fixing: Removing nested tikzpicture'
            # Remove the second begin{tikzpicture} and its matching end
            perl -i -0pe 's/(\\\\begin{tikzpicture}.*?)(\\\\begin{tikzpicture})/\$1/s' test_error_recovery.tex
            # Remove one end{tikzpicture} before the last one
            perl -i -0pe 's/(\\\\end{tikzpicture})(.*?\\\\end{tikzpicture})/\$2/s' test_error_recovery.tex
        fi
        
        # Show changes
        echo ''
        echo '=== Changes made ==='
        diff test_error_recovery_original.tex test_error_recovery.tex || true
    "
    
    echo ""
    echo "=== Second compilation attempt (should succeed) ==="
    compile_latex test_error_recovery.tex 2
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "=== Converting to SVG ==="
        docker exec monadic-chat-python-container bash -c "
            cd /monadic/data
            dvisvgm --bbox=min test_error_recovery.dvi -o test_error_recovery.svg
            ls -la test_error_recovery.svg
        "
        
        if [ -f ~/monadic/data/test_error_recovery.svg ]; then
            echo ""
            echo "✅ SUCCESS: Error recovery system works!"
            echo "Original file had errors, but was automatically fixed and compiled"
        else
            echo "❌ SVG creation failed"
        fi
    else
        echo "❌ Compilation still failed after fixes"
        docker exec monadic-chat-python-container bash -c "tail -n 30 /monadic/data/test_error_recovery.log"
    fi
else
    echo "Unexpected: First compilation succeeded (test file might not have errors)"
fi

echo ""
echo "=== Cleanup ==="
ls -la ~/monadic/data/test_error_recovery* | head -10