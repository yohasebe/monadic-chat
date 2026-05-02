#!/usr/bin/env python3
"""Extract text + metadata from a PDF for Library import.

Backend: pdfplumber (MIT) over pdfminer.six. Replaces the previous
PyMuPDF / pymupdf4llm path (AGPL-3.0).

Output is a JSON object on stdout:
{
  "title":      "<from PDF metadata or empty>",
  "author":     "<from PDF metadata or empty>",
  "page_count": <int>,
  "markdown":   "<full document content as markdown-ish text + tables>"
}

This is a transitional implementation. Once the dedicated
extractor_service container (Docling + RapidOCR) ships, Library
imports will route through that service for layout-aware extraction
with OCR support, formula recognition, and structured tables.

Usage:
    python library_pdf_extractor.py /path/to/file.pdf
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")
import pdfplumber  # noqa: E402


def _format_table_markdown(table):
    if not table or not table[0]:
        return ""
    width = max(len(row) for row in table)
    lines = []
    for i, row in enumerate(table):
        cells = [(c or "").replace("\n", " ").strip() for c in row]
        cells += [""] * (width - len(cells))
        lines.append("| " + " | ".join(cells) + " |")
        if i == 0:
            lines.append("| " + " | ".join(["---"] * width) + " |")
    return "\n".join(lines)


def _render_page_markdown(page) -> str:
    text = (page.extract_text() or "").strip()
    try:
        tables = page.extract_tables() or []
    except Exception:
        tables = []

    parts = []
    if text:
        parts.append(text)
    for t in tables:
        md = _format_table_markdown(t)
        if md:
            parts.append(md)
    return "\n\n".join(parts)


def extract(pdf_path: str) -> dict:
    """Open the PDF and return a dict suitable for JSON serialisation."""
    pdf = pdfplumber.open(pdf_path)
    try:
        meta = pdf.metadata or {}
        title = (meta.get("Title") or "").strip()
        author = (meta.get("Author") or "").strip()
        page_count = len(pdf.pages)

        pages_md = [_render_page_markdown(p) for p in pdf.pages]
        markdown = "\n\n".join(p for p in pages_md if p)
    finally:
        pdf.close()

    return {
        "title": title,
        "author": author,
        "page_count": page_count,
        "markdown": markdown,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf_path", help="Path to the PDF file to extract")
    args = parser.parse_args(argv)

    try:
        result = extract(args.pdf_path)
    except FileNotFoundError:
        print(json.dumps({"error": "file_not_found", "path": args.pdf_path}), file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive
        print(json.dumps({"error": "extraction_failed", "message": str(exc)}), file=sys.stderr)
        return 1

    json.dump(result, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
