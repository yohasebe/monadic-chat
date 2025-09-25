# Japanese Text Support in Jupyter Notebook

Monadic Chat's Jupyter Notebook applications now include automatic Japanese font configuration for matplotlib plots.

## Features

### Automatic Font Setup
When you create or run a Jupyter notebook that contains:
- Japanese text (Hiragana, Katakana, or Kanji characters)
- matplotlib imports or usage

The system automatically inserts a font configuration cell that:
1. Configures matplotlib to use Japanese fonts (Noto Sans CJK JP or IPAGothic)
2. Suppresses font-related warnings
3. Ensures proper display of Japanese characters in plots

### How It Works

The font setup code is automatically inserted:
- After the first matplotlib import statement (if present)
- Or at the beginning of the notebook (if no imports found)
- Only when Japanese text or matplotlib usage is detected
- Only if not already present (tagged with "font-setup" metadata)

### Supported Fonts

The system checks for the following fonts in order:
1. Noto Sans CJK JP (preferred)
2. IPA Gothic
3. System-configured Japanese fonts

### Example

When you create a notebook with Japanese text:

```python
import matplotlib.pyplot as plt
import numpy as np

# Plot with Japanese labels
plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

The system automatically adds the font configuration before your code runs, ensuring Japanese text displays correctly.

## Technical Details

### Font Paths
The system checks these font locations:
- `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/opentype/ipafont/ipag.ttf`
- `/usr/share/fonts/truetype/ipafont/ipag.ttf`

### Configuration
- Font family: sans-serif
- Unicode minus: disabled (prevents minus sign display issues)
- Warnings: suppressed for missing glyphs

## Troubleshooting

If Japanese text still doesn't display:
1. Restart the Jupyter kernel
2. Re-run all cells
3. Check that the font setup cell executed successfully
4. Verify fonts are installed in the Python container

## Notes

- This feature is available for all Jupyter Notebook apps (OpenAI, Claude, Gemini, Grok)
- The font setup is persistent within each notebook session
- No manual configuration required - it's automatic!