"""Extractor service: layout-aware document extraction via Docling.

Endpoints:
  GET  /v1/health
  GET  /v1/info
  POST /v1/extract

Stateless apart from the singleton DocumentConverter loaded at import
time. The Ruby side talks to this service via HTTP through the
Compose network, passing file paths under /monadic/data (shared
volume) rather than uploading bytes.
"""
from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions
from docling.document_converter import DocumentConverter, PdfFormatOption

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
LOG = logging.getLogger("extractor.server")

PIPELINE_NAME = "docling-2.x"

# Chunking knobs. Character-based to keep the image free of heavy
# tokenizer downloads — these sizes track ~250-400 tokens of English
# prose per chunk, which is comfortably within the e5-base 512-token
# context used downstream by embeddings_service.
CHUNK_SIZE_CHARS = 1500
CHUNK_OVERLAP_CHARS = 200


def _build_converter() -> DocumentConverter:
    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = True
    pipeline_options.do_table_structure = True

    return DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options),
        },
    )


CONVERTER = _build_converter()
LOG.info("Docling converter initialised (pipeline=%s)", PIPELINE_NAME)


def _build_chunker():
    """Recursive token-aware chunker with overlap. Built lazily so a
    failure in chonkie does not block the converter from serving.
    """
    try:
        from chonkie import RecursiveChunker
        return RecursiveChunker(
            tokenizer_or_token_counter="character",
            chunk_size=CHUNK_SIZE_CHARS,
            min_characters_per_chunk=200,
        )
    except Exception as exc:  # noqa: BLE001
        LOG.warning("chonkie not available, will fall back to character split: %s", exc)
        return None


CHUNKER = _build_chunker()
if CHUNKER is not None:
    LOG.info("Chonkie RecursiveChunker initialised (chunk_size=%d chars)", CHUNK_SIZE_CHARS)

app = FastAPI(title="Monadic Extractor Service")


class ExtractRequest(BaseModel):
    path: str
    # `format` is advisory; Docling auto-detects from extension. Kept
    # here so future Office/HTML routing can dispatch by hint.
    format: str = "auto"
    # OCR strategy: 'auto' lets Docling decide based on text-layer
    # presence; 'always' / 'never' override. Currently advisory — the
    # converter is built once at startup with do_ocr=True.
    ocr: str = "auto"
    language_hint: list[str] = Field(default_factory=list)


@app.get("/v1/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "pipeline": PIPELINE_NAME}


@app.get("/v1/info")
def info() -> dict[str, Any]:
    return {
        "pipeline": PIPELINE_NAME,
        "ocr_backend": os.environ.get("EXTRACTOR_OCR_RUNTIME", "rapidocr"),
        "languages": os.environ.get("EXTRACTOR_LANGS_RUNTIME", "").split(","),
        "supported_formats": ["pdf"],
    }


def _safe_export_markdown(doc: Any) -> str:
    try:
        return doc.export_to_markdown() or ""
    except Exception as exc:  # noqa: BLE001
        LOG.warning("export_to_markdown failed: %s", exc)
        return ""


def _safe_chunks(markdown: str) -> list[dict]:
    """Run RecursiveChunker over the markdown blob. Returns [] when
    chunking is disabled or fails — the importer side falls back to its
    own splitter in that case.
    """
    if not markdown or not markdown.strip():
        return []
    if CHUNKER is None:
        return _character_window_chunks(markdown)
    try:
        chunks = CHUNKER.chunk(markdown)
    except Exception as exc:  # noqa: BLE001
        LOG.warning("chunker failed, falling back to char window: %s", exc)
        return _character_window_chunks(markdown)
    out: list[dict] = []
    for i, c in enumerate(chunks):
        text = getattr(c, "text", "") or ""
        if not text.strip():
            continue
        out.append({
            "text": text,
            "metadata": {
                "index": i,
                "start": int(getattr(c, "start_index", 0) or 0),
                "end": int(getattr(c, "end_index", 0) or 0),
                "token_count": int(getattr(c, "token_count", 0) or 0),
            },
        })
    return out


def _character_window_chunks(markdown: str) -> list[dict]:
    """Lightweight fallback: sliding character window with overlap.
    Used when chonkie is unavailable or raises. Keeps the response
    schema stable so the importer never has to special-case empties.
    """
    out: list[dict] = []
    if not markdown:
        return out
    cursor = 0
    idx = 0
    n = len(markdown)
    while cursor < n:
        end = min(cursor + CHUNK_SIZE_CHARS, n)
        text = markdown[cursor:end]
        if text.strip():
            out.append({
                "text": text,
                "metadata": {
                    "index": idx,
                    "start": cursor,
                    "end": end,
                    "token_count": len(text),
                },
            })
            idx += 1
        if end >= n:
            break
        cursor = end - CHUNK_OVERLAP_CHARS
        if cursor < 0:
            cursor = 0
    return out


def _safe_metadata(doc: Any, result: Any) -> tuple[str, str, int]:
    title = ""
    author = ""
    page_count = 0
    try:
        if getattr(doc, "name", None):
            title = str(doc.name)
    except Exception:
        pass
    try:
        meta = getattr(doc, "metadata", None) or {}
        if isinstance(meta, dict):
            title = title or str(meta.get("title", ""))
            author = str(meta.get("author", ""))
    except Exception:
        pass
    try:
        pages_obj = getattr(result, "pages", None) or getattr(doc, "pages", None)
        if pages_obj is not None and hasattr(pages_obj, "__len__"):
            page_count = len(pages_obj)
    except Exception:
        pass
    return title, author, page_count


@app.post("/v1/extract")
def extract(req: ExtractRequest) -> dict[str, Any]:
    p = Path(req.path)
    if not p.exists():
        raise HTTPException(status_code=404, detail=f"file not found: {req.path}")

    started = time.time()
    try:
        result = CONVERTER.convert(p)
    except Exception as exc:  # noqa: BLE001
        LOG.exception("convert failed")
        raise HTTPException(status_code=500, detail=f"extraction_failed: {exc}")

    doc = getattr(result, "document", None)
    if doc is None:
        raise HTTPException(status_code=500, detail="extraction_failed: no document returned")

    markdown = _safe_export_markdown(doc)
    title, author, page_count = _safe_metadata(doc, result)
    chunks = _safe_chunks(markdown)
    elapsed_ms = int((time.time() - started) * 1000)

    return {
        "title": title,
        "author": author,
        "page_count": page_count,
        "markdown": markdown,
        "chunks": chunks,
        "extractor_meta": {
            "pipeline": PIPELINE_NAME,
            "ocr_backend": os.environ.get("EXTRACTOR_OCR_RUNTIME", "rapidocr"),
            "chunker": "chonkie-recursive" if CHUNKER is not None else "character-window",
            "chunk_count": len(chunks),
            "duration_ms": elapsed_ms,
        },
    }
