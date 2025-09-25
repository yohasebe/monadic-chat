#!/usr/bin/env python3
"""
Template code for Japanese support in Jupyter notebooks
Include this at the beginning of notebooks that need Japanese text support
"""

JAPANESE_SETUP_CODE = """
# Japanese font configuration for matplotlib
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import warnings

# Suppress font warnings
warnings.filterwarnings('ignore', message='Glyph .* missing from font')

# Configure Japanese fonts
try:
    # Try to use Noto Sans CJK JP if available
    font_path = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
    if os.path.exists(font_path):
        fm.fontManager.addfont(font_path)
        font_prop = fm.FontProperties(fname=font_path)
        plt.rcParams['font.sans-serif'] = [font_prop.get_name()] + plt.rcParams['font.sans-serif']
    else:
        # Fallback to system configuration
        plt.rcParams['font.sans-serif'] = ['Noto Sans CJK JP', 'IPAGothic', 'IPAPGothic'] + plt.rcParams['font.sans-serif']

    plt.rcParams['font.family'] = 'sans-serif'
    plt.rcParams['axes.unicode_minus'] = False
    print("Japanese font support enabled")
except Exception as e:
    print(f"Warning: Could not configure Japanese fonts: {e}")
    print("Japanese text may not display correctly in plots")
"""

def create_japanese_notebook_template():
    """Create a notebook template with Japanese support"""
    template = {
        "cells": [
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["# Notebook with Japanese Support\n",
                          "This notebook is configured to properly display Japanese text in matplotlib plots."]
            },
            {
                "cell_type": "code",
                "metadata": {},
                "source": ["# Import basic libraries\n",
                          "import os\n",
                          "import numpy as np\n",
                          "import pandas as pd\n",
                          "import matplotlib.pyplot as plt\n",
                          "%matplotlib inline"]
            },
            {
                "cell_type": "code",
                "metadata": {},
                "source": JAPANESE_SETUP_CODE.strip().split('\n')
            },
            {
                "cell_type": "code",
                "metadata": {},
                "source": ["# Test Japanese display\n",
                          "plt.figure(figsize=(8, 4))\n",
                          "plt.plot([1, 2, 3, 4], [1, 4, 2, 3])\n",
                          "plt.title('日本語タイトルのテスト')\n",
                          "plt.xlabel('横軸（時間）')\n",
                          "plt.ylabel('縦軸（値）')\n",
                          "plt.grid(True)\n",
                          "plt.show()"]
            }
        ],
        "metadata": {
            "language_info": {
                "name": "python"
            }
        }
    }
    return template

if __name__ == "__main__":
    import json
    template = create_japanese_notebook_template()
    print(json.dumps(template, indent=2, ensure_ascii=False))