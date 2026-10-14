# Extractor Service (Knowledge Base Quality Pack)

`extractor_service` (`docker/services/extractor/`) extracts PDFs for Library imports with Docling 2.x and RapidOCR, including scanned pages, reading order and tables. It is optional; without it, PDFs are extracted by `library_pdf_extractor.py` (pdfplumber) in the Python container. Office files always go through `library_office_extractor.py` in the Python container.

## Endpoints (`server.py`, FastAPI on port 8000)

| Method | Path | Returns |
|---|---|---|
| GET | `/v1/health` | `{status: "ok", pipeline}` |
| GET | `/v1/info` | `pipeline`, `ocr_backend`, `languages`, `supported_formats: ["pdf"]` |
| POST | `/v1/extract` | The extracted document (below); 404 when the file does not exist, 500 when conversion fails |

Request body:

```json
{ "path": "/monadic/data/foo.pdf", "format": "auto", "ocr": "auto", "language_hint": ["en", "ja"] }
```

- `path` is a container path under `/monadic/data`; the service reads the file from the shared volume.
- `format`, `ocr` and `language_hint` are accepted but do not change the conversion: the converter is built once at startup with `do_ocr = True`, and Docling decides OCR per page.

Response:

```json
{
  "title": "...", "author": "...", "page_count": 12,
  "markdown": "# Section 1\n\n...",
  "chunks": [ { "text": "...", "metadata": { "index": 0, "start": 0, "end": 1500, "token_count": 300 } } ],
  "extractor_meta": { "pipeline": "docling-2.x", "ocr_backend": "rapidocr", "chunker": "chonkie-recursive", "chunk_count": 8, "duration_ms": 18432 }
}
```

`title`, `author`, `page_count` and `markdown` have the same shape as the output of `library_pdf_extractor.py`, so `Monadic::Library::Importers::Pdf.import_extraction_json` reads both.

## Chunking

After extraction the Markdown is split by Chonkie's `RecursiveChunker` (`tokenizer="character"`, `chunk_size` 1500 characters). If Chonkie is not available or raises, a sliding window of 1500 characters with 200 characters of overlap is used, and `extractor_meta.chunker` is `character-window`.

When `chunks` is a non-empty array, the importer stores those chunks as they are (`pre_segmented_chunks`). Otherwise it splits the Markdown with its own splitter.

## Compose and Runtime Settings

`docker/services/extractor/compose.yml` defines `extractor_service` (container `monadic-chat-extractor-container`) under the profile `extractor`, with the image `ghcr.io/yohasebe/monadic-extractor:${MONADIC_IMAGE_TAG:-latest}`. The image is published by `.github/workflows/publish-images.yml`; `compose.yml` has no `build:` section. It mounts `~/monadic/data` at `/monadic/data`, with `apps`, `helpers` and `services` read-only.

The image sets `HF_HUB_OFFLINE=1`; every model it uses is in the image, and it runs without network access.

| User setting → container variable | Default | Effect |
|---|---|---|
| `EXTRACTOR_OCR` → `EXTRACTOR_OCR_RUNTIME` | `rapidocr` | Reported as `ocr_backend`; RapidOCR is the only backend |
| `EXTRACTOR_LANGS` → `EXTRACTOR_LANGS_RUNTIME` | `en,ja,zh,ko` | Reported as `languages`; RapidOCR detects the script per page |

Saving these settings runs `monadic.sh refresh-service extractor`, which recreates the container when it is running (`compose up -d`). No rebuild is needed.

## `monadic.sh`

- `build_extractor_container`: when `EXTRACTOR_SERVICE=true`, pulls the image, or builds it with the `compose.build.yml` overlay when `MONADIC_DEV=true`.
- `ensure-service extractor`: pulls the image if it is missing, then starts the container. Prints `EXTRACTOR_DISABLED`, `EXTRACTOR_NOT_BUILT`, `STARTED` or `ALREADY_RUNNING`.
- `refresh-service extractor`: prints `REFRESHED` or `NOT_RUNNING`.

**Settings → Install Options → Knowledge Base Quality Pack** sets `EXTRACTOR_SERVICE=true` in `~/monadic/config/env`.

## Ruby Side

- `Monadic::Extractor::Endpoint` gives the URL: `EXTRACTOR_URL` when set, otherwise `http://extractor_service:8000` in the container and `http://localhost:8003` in development mode (`EXTRACTOR_DEV_PORT`, mapped by `compose.dev.yml`).
- `Monadic::Extractor::Client` has `health`, `info` and `extract`. Timeouts: 600 seconds for `extract`, 2 seconds for `health` and `info`. It raises `ServiceUnavailableError` (not reachable) and `ExtractionFailedError` (non-200 or non-JSON).
- `Monadic::Library::FileImporter#import_pdf` uses the service when `EXTRACTOR_SERVICE=true` and `health` succeeds, checked on every import. Otherwise it runs `library_pdf_extractor.py`; if the pack is enabled but the service is unreachable, `DegradationNotifier` reports a warning. Client errors are raised as `FileImporter::ExtractionError`.
