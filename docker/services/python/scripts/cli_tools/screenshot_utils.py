#!/usr/bin/env python3
"""
Shared screenshot utilities for Web Insight tools.
"""

import logging
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)


def trim_screenshot(filepath, padding=8, threshold=12, min_trim_pct=0.03):
    """Trim uniform-color borders from a screenshot.

    Scans from each edge inward. Rows/columns whose pixel standard deviation
    is below *threshold* are considered "uniform" (empty margin). The content
    bounding box is expanded by *padding* pixels and the image is cropped.

    Only writes to disk if at least *min_trim_pct* (default 3%) of the width
    or height would be removed.

    Args:
        filepath: Path to the PNG screenshot (modified in-place).
        padding: Pixels of margin to keep around the content.
        threshold: Std-dev cutoff; lower = stricter (only trims very uniform areas).
        min_trim_pct: Minimum fraction of width/height to remove before cropping.
    """
    try:
        img = Image.open(filepath)
        arr = np.array(img, dtype=np.float32)

        if arr.ndim < 3:
            return  # grayscale — skip

        h, w, _c = arr.shape

        # Per-row std: average the channel-wise std across the width axis
        row_std = np.mean(np.std(arr, axis=1), axis=1)   # shape (h,)
        # Per-col std: average the channel-wise std across the height axis
        col_std = np.mean(np.std(arr, axis=0), axis=1)   # shape (w,)

        content_rows = np.where(row_std > threshold)[0]
        content_cols = np.where(col_std > threshold)[0]

        if len(content_rows) == 0 or len(content_cols) == 0:
            return  # entirely uniform — leave as-is

        top = max(0, int(content_rows[0]) - padding)
        bottom = min(h, int(content_rows[-1]) + 1 + padding)
        left = max(0, int(content_cols[0]) - padding)
        right = min(w, int(content_cols[-1]) + 1 + padding)

        trimmed_w = w - (right - left)
        trimmed_h = h - (bottom - top)

        # Only crop if we're removing a meaningful amount
        if trimmed_w < w * min_trim_pct and trimmed_h < h * min_trim_pct:
            return

        cropped = img.crop((left, top, right, bottom))
        cropped.save(filepath)
        logger.info(f"Trimmed {filepath}: {w}x{h} -> {right - left}x{bottom - top}")

    except Exception as e:
        # Never fail the screenshot pipeline due to a trim error
        logger.warning(f"Screenshot trim failed for {filepath}: {e}")
