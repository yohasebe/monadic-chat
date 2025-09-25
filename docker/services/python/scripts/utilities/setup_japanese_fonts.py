#!/usr/bin/env python3
"""
Setup Japanese fonts for matplotlib in Jupyter notebooks
This script configures matplotlib to properly display Japanese text
"""

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import warnings
import os

def setup_japanese_fonts():
    """Configure matplotlib to use Japanese fonts"""

    # Suppress font-related warnings
    warnings.filterwarnings('ignore', message='Glyph .* missing from font')

    # List of Japanese fonts to try
    japanese_fonts = [
        'Noto Sans CJK JP',
        'NotoSansCJK-Regular',
        'IPAGothic',
        'IPAPGothic',
        'IPAMincho',
        'IPAPMincho',
        'TakaoGothic',
        'TakaoPGothic',
        'TakaoMincho',
        'TakaoPMincho'
    ]

    # Find available Japanese fonts
    available_fonts = []
    font_list = fm.findSystemFonts()

    for font_path in font_list:
        try:
            font_prop = fm.FontProperties(fname=font_path)
            font_name = font_prop.get_name()
            if any(jf.lower() in font_name.lower() for jf in japanese_fonts):
                available_fonts.append(font_name)
        except:
            pass

    # Remove duplicates
    available_fonts = list(set(available_fonts))

    if available_fonts:
        # Set the first available Japanese font
        plt.rcParams['font.sans-serif'] = [available_fonts[0]] + plt.rcParams['font.sans-serif']
        plt.rcParams['font.family'] = 'sans-serif'
        print(f"Japanese font configured: {available_fonts[0]}")
        if len(available_fonts) > 1:
            print(f"Other available Japanese fonts: {', '.join(available_fonts[1:])}")
    else:
        # Fallback to font file path
        font_path = os.environ.get('FONT_PATH', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
        if os.path.exists(font_path):
            font_prop = fm.FontProperties(fname=font_path)
            fm.fontManager.addfont(font_path)
            font_name = font_prop.get_name()
            plt.rcParams['font.sans-serif'] = [font_name] + plt.rcParams['font.sans-serif']
            plt.rcParams['font.family'] = 'sans-serif'
            print(f"Japanese font configured from path: {font_name}")
        else:
            print("Warning: No Japanese fonts found. Japanese text may not display correctly.")

    # Ensure minus signs display correctly
    plt.rcParams['axes.unicode_minus'] = False

    return available_fonts

def get_font_info():
    """Display current font configuration"""
    print("Current matplotlib font configuration:")
    print(f"  font.family: {plt.rcParams['font.family']}")
    print(f"  font.sans-serif: {plt.rcParams['font.sans-serif'][:3]}...")
    print(f"  axes.unicode_minus: {plt.rcParams['axes.unicode_minus']}")

if __name__ == "__main__":
    setup_japanese_fonts()
    get_font_info()