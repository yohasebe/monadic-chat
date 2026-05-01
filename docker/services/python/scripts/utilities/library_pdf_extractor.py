#!/usr/bin/env python3
"""Extract text + metadata from a PDF for Library import.

Uses pymupdf4llm.to_markdown() so structural elements (headings, lists,
tables) survive into the extracted text. The Ruby PdfImporter consumes
the resulting markdown like a regular Markdown document, which lets a
single chunking strategy (heading-or-paragraph splitting) work for both.

Output is a JSON object on stdout:
{
  "title":      "<from PDF metadata or empty>",
  "author":     "<from PDF metadata or empty>",
  "page_count": <int>,
  "markdown":   "<full document content as markdown>"
}

Usage:
    python library_pdf_extractor.py /path/to/file.pdf
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import sys

# pymupdf prints recommendation notices ("Consider using the
# pymupdf_layout package…") to stdout on import / first use. Capture
# stdout while importing and using the libraries so the JSON we emit on
# stdout is never interleaved with library chatter.
_silenced = io.StringIO()
with contextlib.redirect_stdout(_silenced):
    import pymupdf  # noqa: E402
    import pymupdf4llm  # noqa: E402


def extract(pdf_path: str) -> dict:
    """Open the PDF and return a dict suitable for JSON serialisation."""
    # Re-silence stdout for the actual extraction calls — pymupdf may
    # print further notices when handed a real document.
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        doc = pymupdf.open(pdf_path)
        try:
            page_count = doc.page_count
            meta = doc.metadata or {}
            title = (meta.get("title") or "").strip()
            author = (meta.get("author") or "").strip()
        finally:
            doc.close()

        # pymupdf4llm.to_markdown reopens the file internally.
        md = pymupdf4llm.to_markdown(pdf_path)

    return {
        "title": title,
        "author": author,
        "page_count": page_count,
        "markdown": md,
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
