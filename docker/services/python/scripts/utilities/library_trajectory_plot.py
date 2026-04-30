#!/usr/bin/env python3
"""Render Level T trajectory embeddings as a 2D plot for the Knowledge Base.

Reads a JSON file describing one or more conversations' trajectory points
(each point is a 768-dimensional embedding paired with metadata), projects
them down to 2D via numpy SVD-based PCA, and writes:
  - a PNG file (publication-quality static figure)
  - an interactive HTML file (Plotly)

Output paths are printed as JSON on stdout so the Ruby caller can parse
them.

Input format (JSON):
{
  "title": "Optional figure title",
  "conversations": [
    {
      "conversation_id": "conv-1",
      "label": "Talk A",
      "points": [
        { "vector": [768 floats], "turn_idx": 0 },
        ...
      ]
    },
    ...
  ]
}
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any, Dict, List

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

import plotly.graph_objects as go


def pca_2d(matrix: np.ndarray) -> np.ndarray:
    """Project an (N, D) matrix to (N, 2) using mean-centred SVD.

    Avoids the scikit-learn dependency (which is gated by an optional
    install switch in the python container).
    """
    if matrix.shape[0] == 0:
        return np.zeros((0, 2))
    centred = matrix - matrix.mean(axis=0, keepdims=True)
    # SVD: centred = U S Vt, principal components are the columns of V.
    _u, s, vt = np.linalg.svd(centred, full_matrices=False)
    components = vt[:2].T  # (D, 2)
    projected = centred @ components  # (N, 2)
    # Scale-correct so the two axes have comparable variance to s[:2].
    return projected


def render_png(
    conversations: List[Dict[str, Any]],
    title: str,
    out_path: str,
) -> None:
    fig, ax = plt.subplots(figsize=(8, 6), dpi=150)
    palette = plt.rcParams["axes.prop_cycle"].by_key()["color"]
    for conv_idx, conv in enumerate(conversations):
        if not conv["points_2d"].size:
            continue
        coords = conv["points_2d"]
        colour = palette[conv_idx % len(palette)]
        # Draw the trajectory as a line in temporal order …
        ax.plot(coords[:, 0], coords[:, 1], color=colour, alpha=0.4, linewidth=1.0)
        # … and the points coloured by turn index, so the gradient shows
        # which way the conversation progresses.
        scatter = ax.scatter(
            coords[:, 0],
            coords[:, 1],
            c=conv["turn_indices"],
            cmap="viridis",
            s=30,
            edgecolors=colour,
            linewidths=0.6,
            label=conv["label"],
        )
    cbar_axes = [c for c in conversations if c["points_2d"].size > 0]
    if cbar_axes:
        cbar = fig.colorbar(scatter, ax=ax, shrink=0.7)
        cbar.set_label("turn index")
    ax.set_xlabel("PC 1")
    ax.set_ylabel("PC 2")
    ax.set_title(title)
    if len(conversations) > 1:
        ax.legend(loc="best", fontsize=9)
    fig.tight_layout()
    fig.savefig(out_path, format="png")
    plt.close(fig)


def render_html(
    conversations: List[Dict[str, Any]],
    title: str,
    out_path: str,
) -> None:
    fig = go.Figure()
    for conv in conversations:
        if not conv["points_2d"].size:
            continue
        coords = conv["points_2d"]
        hover = [
            f"{conv['label']} · turn {t}"
            for t in conv["turn_indices"]
        ]
        fig.add_trace(
            go.Scatter(
                x=coords[:, 0],
                y=coords[:, 1],
                mode="lines+markers",
                marker=dict(
                    size=8,
                    color=conv["turn_indices"],
                    colorscale="Viridis",
                    showscale=True,
                    colorbar=dict(title="turn index"),
                ),
                line=dict(width=1),
                name=conv["label"],
                hovertext=hover,
                hoverinfo="text",
            )
        )
    fig.update_layout(
        title=title,
        xaxis_title="PC 1",
        yaxis_title="PC 2",
        template="plotly_white",
        height=640,
    )
    fig.write_html(out_path, include_plotlyjs="cdn")


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Input JSON file")
    parser.add_argument(
        "--output-dir",
        default="/monadic/data/library/trajectories",
        help="Directory for the generated PNG/HTML",
    )
    args = parser.parse_args(argv)

    with open(args.input, "r", encoding="utf-8") as fh:
        spec = json.load(fh)

    title = spec.get("title") or "Discourse Trajectory"
    raw_convs = spec.get("conversations") or []
    if not raw_convs:
        print(json.dumps({"error": "no conversations in input"}))
        return 1

    # Fit a single PCA over the whole dataset so multi-conversation plots
    # share a common projection space.
    all_vectors: List[np.ndarray] = []
    for conv in raw_convs:
        for p in conv.get("points", []):
            all_vectors.append(np.asarray(p["vector"], dtype=np.float64))
    if not all_vectors:
        print(json.dumps({"error": "no trajectory points"}))
        return 1
    matrix = np.vstack(all_vectors)
    projected = pca_2d(matrix)

    cursor = 0
    conversations: List[Dict[str, Any]] = []
    for conv in raw_convs:
        n = len(conv.get("points", []))
        coords = projected[cursor : cursor + n]
        cursor += n
        # Sort by turn index so the line follows the actual time order.
        order = sorted(range(n), key=lambda i: conv["points"][i].get("turn_idx", i))
        ordered_coords = coords[order] if n > 0 else coords
        ordered_turns = [conv["points"][i].get("turn_idx", i) for i in order]
        conversations.append(
            {
                "conversation_id": conv.get("conversation_id"),
                "label": conv.get("label") or conv.get("conversation_id") or "(unnamed)",
                "points_2d": ordered_coords,
                "turn_indices": ordered_turns,
            }
        )

    os.makedirs(args.output_dir, exist_ok=True)
    timestamp = int(time.time())
    base = f"library_trajectory_{timestamp}"
    png_path = os.path.join(args.output_dir, base + ".png")
    html_path = os.path.join(args.output_dir, base + ".html")

    render_png(conversations, title, png_path)
    render_html(conversations, title, html_path)

    print(json.dumps({
        "png_path": png_path,
        "html_path": html_path,
        "conversations": [
            {
                "conversation_id": c["conversation_id"],
                "label": c["label"],
                "points": int(c["points_2d"].shape[0]),
            }
            for c in conversations
        ],
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
