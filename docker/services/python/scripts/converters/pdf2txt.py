#!/usr/bin/env python

"""Extract text from PDF files.

Backend: pdfplumber (MIT) over pdfminer.six. Replaces the previous
PyMuPDF / pymupdf4llm path (AGPL-3.0) so that all PDF tooling in
Monadic Chat stays under permissive licenses.

CLI / JSON output schema is intentionally preserved so existing Ruby
callers (read_write_helper.rb, app.rb, pdf_text_extractor.rb) need no
changes. Heading detection (which pymupdf4llm provided heuristically
for `--format md`) is intentionally simplified here; Library imports
will route through the dedicated extractor_service container in a
later phase to recover layout-aware Markdown via Docling.
"""

import sys
import argparse
import json
import os
import warnings
from typing import Iterator, List

# Some PDF backends emit informational messages on import; silence them
# so they cannot interleave with our JSON output.
warnings.filterwarnings("ignore")

import pdfplumber  # noqa: E402


def _is_valid_pdf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(5).startswith(b"%PDF-")
    except IOError:
        return False


def _format_table_markdown(table: List[List[str]]) -> str:
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


def _format_table_html(table: List[List[str]]) -> str:
    if not table:
        return ""
    rows = []
    for row in table:
        cells = [(c or "").replace("\n", " ").strip() for c in row]
        rows.append("<tr>" + "".join(f"<td>{_escape_xml(c)}</td>" for c in cells) + "</tr>")
    return "<table>" + "".join(rows) + "</table>"


def _format_table_xml(table: List[List[str]]) -> str:
    if not table:
        return ""
    rows = []
    for row in table:
        cells = [(c or "").replace("\n", " ").strip() for c in row]
        rows.append("<row>" + "".join(f"<cell>{_escape_xml(c)}</cell>" for c in cells) + "</row>")
    return "<table>" + "".join(rows) + "</table>"


def _escape_xml(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def _render_page(page, output_format: str) -> str:
    text = (page.extract_text() or "").strip()
    try:
        tables = page.extract_tables() or []
    except Exception:
        tables = []

    if output_format == "txt":
        return text

    if output_format in ("md", "markdown"):
        parts = []
        if text:
            parts.append(text)
        for t in tables:
            md = _format_table_markdown(t)
            if md:
                parts.append(md)
        return "\n\n".join(parts)

    if output_format == "html":
        parts = []
        if text:
            for para in text.split("\n\n"):
                para = para.strip()
                if para:
                    parts.append(f"<p>{_escape_xml(para)}</p>")
        for t in tables:
            parts.append(_format_table_html(t))
        return "\n".join(parts)

    if output_format == "xml":
        parts = ["<page>"]
        if text:
            parts.append(f"<text>{_escape_xml(text)}</text>")
        for t in tables:
            parts.append(_format_table_xml(t))
        parts.append("</page>")
        return "\n".join(parts)

    raise ValueError(f"Invalid output format: {output_format}")


def extract_text(pdf_path: str, output_format: str, all_pages: bool, show_progress: bool = False) -> Iterator[str]:
    """Extract text from a PDF in the requested format.

    Yields one string per page (or one combined string when --all-pages).
    Raises ValueError on invalid format / corrupt input, FileNotFoundError
    on missing file.
    """
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"PDF file not found: {pdf_path}")

    if output_format not in ["markdown", "md", "txt", "html", "xml"]:
        raise ValueError(f"Invalid output format: {output_format}")

    if not _is_valid_pdf(pdf_path):
        raise ValueError("Error processing PDF: File is not a valid PDF document")

    try:
        pdf = pdfplumber.open(pdf_path)
    except Exception as e:
        raise ValueError(f"Error processing PDF: {str(e)}")

    try:
        if all_pages:
            pages = [_render_page(p, output_format) for p in pdf.pages]
            joiner = "\n\n" if output_format in ("md", "markdown") else "\n"
            yield joiner.join(p for p in pages if p)
        else:
            for p in pdf.pages:
                yield _render_page(p, output_format)
    finally:
        pdf.close()


def export_as_json(pdf_path: str, output_format: str, all_pages: bool, show_progress: bool = False) -> None:
    data = {"pages": []}
    try:
        for page_text in extract_text(pdf_path, output_format, all_pages, show_progress):
            data["pages"].append({"text": page_text.strip()})

        base_filename = os.path.splitext(os.path.basename(pdf_path))[0]
        output_filename = f"{base_filename}.{output_format}.json"
        json_data = json.dumps(data, ensure_ascii=False, indent=4)
        with open(output_filename, "w", encoding="utf-8") as f:
            f.write(json_data)
        print(json_data)

    except Exception as e:
        print(f"Error processing PDF: {str(e)}", file=sys.stderr)
        raise


def export_as_text(pdf_path: str, output_format: str, all_pages: bool, show_progress: bool = False) -> None:
    try:
        pages = []
        for page_text in extract_text(pdf_path, output_format, all_pages, show_progress):
            pages.append(page_text.strip())
        print("\n\n".join(pages))

    except Exception as e:
        print(f"Error processing PDF: {str(e)}", file=sys.stderr)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract text from a PDF file and output as JSON."
    )
    parser.add_argument("pdf_path", help="Path to the PDF file")
    parser.add_argument(
        "--format",
        choices=["md", "txt", "html", "xml"],
        default="md",
        help="Output format (md, txt, html, xml)",
    )
    parser.add_argument(
        "--all-pages",
        action="store_true",
        help="Combine all pages into a single output",
    )
    parser.add_argument(
        "--show-progress",
        action="store_true",
        help="(retained for CLI compatibility; pdfplumber backend has no progress bar)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON format (default is plain text)",
    )

    args = parser.parse_args()

    try:
        if args.json:
            export_as_json(
                args.pdf_path,
                args.format,
                args.all_pages,
                show_progress=args.show_progress,
            )
        else:
            export_as_text(
                args.pdf_path,
                args.format,
                args.all_pages,
                show_progress=args.show_progress,
            )
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
