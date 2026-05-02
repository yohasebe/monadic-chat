# Extractor Service (Knowledge Base Quality Pack)

## Purpose

`extractor_service` is the persistent ML microservice that runs Docling
2.x + RapidOCR for layout-aware document extraction. It is the
"heavy / quality" path of the Library import pipeline; the "light /
speed" path through `pdfplumber` continues to live in the python
container and is what runs when this pack is not installed.

The service exists primarily so that:

- Library imports survive on **scanned PDFs** (no text layer at all),
  which the lightweight `pdfplumber` path silently returns empty for
- Multilingual / CJK / RTL scripts get a layout-aware reading order
  rather than the raw PDF text-stream order
- Tables, formulas, and figure captions become structured Markdown
  rather than a heuristic guess

## Why a dedicated container

Same architecture pattern as `embeddings_service` and `privacy_service`:

- Models load **once** at container startup and stay resident, so the
  per-document overhead is small and predictable
- The user-code execution environment (`python_service` /
  `monadic-chat-python-container`) is kept clean of large ML
  dependencies (`docling` alone pulls ~2-3 GB of PyTorch + model
  weights)
- Install can be opt-in: a user who never imports a paper-grade PDF
  pays no install cost
- Languages and OCR backend are build-time decisions, settable via
  Compose `args`

## Service surface

### Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/health` | Liveness; always returns 200 once Docling has loaded |
| GET | `/v1/info` | Pipeline name, OCR backend, configured languages |
| POST | `/v1/extract` | Body `{path, format, ocr, language_hint}` → extracted document |

### Extract request body

```json
{
  "path": "/monadic/data/foo.pdf",
  "format": "auto",
  "ocr": "auto",
  "language_hint": ["en", "ja"]
}
```

- `path` is **container-side**; the Ruby caller maps host paths to
  `/monadic/data/...` before calling. The service does not stream
  bytes — it relies on the shared volume.
- `format` is currently advisory; Docling auto-detects from file
  extension. It exists for future routing of Office formats through
  Docling pipelines.
- `ocr` is advisory; the converter is built with `do_ocr=True` at
  startup and Docling decides per-page based on text-layer presence.

### Response

```json
{
  "title": "...",
  "author": "...",
  "page_count": 12,
  "markdown": "# Section 1\n\n...",
  "chunks": [
    { "text": "...", "metadata": { "index": 0, "start": 0, "end": 1500, "token_count": 300 } },
    ...
  ],
  "extractor_meta": {
    "pipeline": "docling-2.x",
    "ocr_backend": "rapidocr",
    "chunker": "chonkie-recursive",
    "chunk_count": 8,
    "duration_ms": 18432
  }
}
```

`title` / `author` / `page_count` / `markdown` are the "compatibility
shape" that mirrors what the lightweight `library_pdf_extractor.py`
emits, so `Monadic::Library::Importers::Pdf.import_extraction_json`
consumes both response shapes interchangeably.

`chunks` is new in beta.16: when present, the importer adopts the
pre-segmented array directly, bypassing its own heading/paragraph
splitter. See "Chunking" below.

## Chunking

The server runs Chonkie's `RecursiveChunker` (MIT) over the Docling
markdown after extraction. Defaults:

- `chunk_size`: 1500 characters (≈250-400 tokens for English prose,
  comfortably below the 512-token e5-base context used downstream)
- `chunk_overlap`: 200 characters (server-side fallback uses this; the
  Chonkie `RecursiveChunker` has its own boundary heuristic)
- `tokenizer`: `"character"` — deliberately avoids pulling a HuggingFace
  tokenizer model into the image. The embedding model
  (`multilingual-e5-base`) lives in the embeddings_service, not here.

If Chonkie fails to load or chunk a particular document, the server
falls back to a sliding character window with the same window/overlap
parameters. The response shape stays stable so the importer never
special-cases an empty `chunks` array — it falls back to its own
heading splitter only when `chunks` is missing entirely.

## Build & deployment

### Compose

`docker/services/extractor/compose.yml` declares the service under
profile `["extractor"]`:

```yaml
services:
  extractor_service:
    profiles: ["extractor"]
    image: yohasebe/monadic-extractor
    build:
      args:
        EXTRACTOR_OCR: ${EXTRACTOR_OCR:-rapidocr}
        EXTRACTOR_LANGS: ${EXTRACTOR_LANGS:-en,ja,zh,ko}
    volumes:
      - data:/monadic/data
      - ~/monadic/data:/monadic/data
    healthcheck: ...
```

The profile gate ensures `docker compose up` does not start it unless
the user explicitly opted in (Settings → Install Options → "Knowledge
Base Quality Pack" sets `EXTRACTOR_SERVICE=true` in
`~/monadic/config/env`, which `monadic.sh ensure-service extractor`
checks).

### Build arguments

| Arg | Default | Effect |
|---|---|---|
| `EXTRACTOR_OCR` | `rapidocr` | Which OCR backend to bake in. Currently only `rapidocr` is wired; Tesseract is a possible future fallback. |
| `EXTRACTOR_LANGS` | `en,ja,zh,ko` | Comma-separated ISO 639-1 codes exposed in `/v1/info`. Advisory — RapidOCR auto-detects per page. |

### `monadic.sh` integration

- `build_extractor_container` — builds the image when
  `EXTRACTOR_SERVICE=true`.
- `ensure-service extractor` — starts the container on demand. Returns
  `EXTRACTOR_DISABLED` / `EXTRACTOR_NOT_BUILT` / `STARTED` /
  `ALREADY_RUNNING` so the caller can branch.

### Dev mode port

`compose.dev.yml` maps port 8000 to host `127.0.0.1:8003` (overridable
via `EXTRACTOR_DEV_PORT`). The Ruby side resolves the URL via
`Monadic::Extractor::Endpoint`, mirroring the `Monadic::Embeddings::Endpoint`
convention (in-container: `http://extractor_service:8000`; dev:
`http://localhost:8003`).

## Image size

Roughly **12 GB** total (≈4.5 GB on disk after dedup). This is larger
than originally planned (~3 GB) and is dominated by:

- PyTorch with NVIDIA CUDA bindings pulled in transitively by Docling
- Pre-downloaded Docling models (~500 MB-1.5 GB)

Future optimisation: install CPU-only torch via
`--index-url https://download.pytorch.org/whl/cpu` to drop the CUDA
weights, which we never use on macOS / Apple Silicon. Estimated savings
~2-3 GB.

## Failure & fallback semantics

- The Ruby side calls `Monadic::Extractor::Client#health` before each
  PDF import (cheap, ~ms when the service is up). On `false` it falls
  back to the lightweight `pdfplumber` subprocess in the python
  container.
- HTTP timeouts: 600s for `/v1/extract` (large OCR runs can take
  several minutes), 2s for health/info probes.
- The client surfaces two classes of error: `ServiceUnavailableError`
  (host unreachable) and `ExtractionFailedError` (service responded
  non-200 or non-JSON). Both are wrapped in
  `Monadic::Library::FileImporter::ExtractionError` before bubbling up
  to the WebSocket handler.

## Why not also Office?

Office formats (`.docx` / `.xlsx` / `.pptx`) continue to flow through
the python container's `library_office_extractor.py` (python-docx +
openpyxl + python-pptx, all MIT). Reasons:

- The libraries are already permissively licensed
- Office text extraction is not the weak link Library users actually
  hit (PDF is)
- Adding Office to Docling pipelines doubles the per-document latency
  for negligible quality gain in the typical case

The plan keeps the door open: the `format` field in
`POST /v1/extract` accepts `pdf`/`docx`/`xlsx`/`pptx` so a future
"Office layout-aware path" can plug in without a new endpoint.
