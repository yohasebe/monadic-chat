# Concept Visualizer Diagnostics

This directory contains small utilities to test and diagnose SVG generation from LaTeX/TikZ for the Concept Visualizer app.

## Scripts

### `diagnose_concept_visualizer.rb`
- Purpose: Quick sanity check of the SVG generation pipeline
- What it does: Generates a simple 3D surface plot
- Usage: `ruby diagnose_concept_visualizer.rb`

### `test_concept_visualizer_simple.sh`
- Purpose: Verify basic 2D plot generation
- What it does: Creates a simple sine-wave SVG
- Usage: `./test_concept_visualizer_simple.sh`

### `test_3d_variations.sh`
- Purpose: Exercise several 3D plotting patterns
- What it does: Generates multiple 3D plot types (surface, mesh, contour, etc.)
- Usage: `./test_3d_variations.sh`

### `test_dvisvgm_direct.sh`
- Purpose: Validate the dvisvgm command in isolation
- What it does: Runs LaTeX → DVI → SVG conversion end-to-end
- Usage: `./test_dvisvgm_direct.sh`

### `test_error_recovery.sh`
- Purpose: Test error handling and recovery
- What it does: Tries various failure scenarios (syntax errors, missing packages, etc.)
- Usage: `./test_error_recovery.sh`

### `test_svg_generation.sh`
- Purpose: End-to-end test of the whole SVG generation pipeline
- What it does: Simulates the app flow and validates output
- Usage: `./test_svg_generation.sh`

## Prerequisites

1. The Python container is running
2. Required LaTeX packages are installed
   - tikz
   - pgfplots
   - amsmath
   - tikz-3dplot (for 3D plots)

## Troubleshooting

### Common errors and fixes

1. "LaTeX package not found"
   - Install required packages inside the Python container: `apt-get install texlive-pictures texlive-science`

2. "dvisvgm command not found"
   - Install dvisvgm: `apt-get install dvisvgm`

3. "File not found"
   - Check permissions for the output directory (`~/monadic/data/`)

4. Empty SVG or error output
   - Check your LaTeX code for syntax errors
   - Inspect logs for detailed messages

## Output

Generated SVG files are saved under:
- `~/monadic/data/concept_*.svg`

Open them in a browser or an SVG viewer and verify they render correctly.
