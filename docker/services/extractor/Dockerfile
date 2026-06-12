FROM python:3.11.10-slim-bookworm

ARG PROJECT_TAG=monadic-chat

LABEL project=${PROJECT_TAG}

WORKDIR /app

# Native libs Docling / OpenCV / RapidOCR rely on transitively.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Docling (MIT, IBM) + RapidOCR ONNX backend (Apache-2.0) +
# Chonkie token-aware chunker (MIT) + FastAPI server. Pinned to
# compatible majors; bump cautiously.
RUN pip install --no-cache-dir \
      "docling>=2.0,<3.0" \
      "rapidocr-onnxruntime>=1.3,<2.0" \
      "chonkie[semantic]>=0.5,<2.0" \
      "fastapi==0.115.0" \
      "uvicorn[standard]==0.30.6"

# Pre-download Docling default models so first /v1/extract call does not
# block on a network fetch. Skipping this would still work but the first
# request would silently download ~500MB-1.5GB.
RUN python - <<'PY'
import sys
print("==> Pre-downloading Docling models...", flush=True)
try:
    from docling.utils.model_downloader import download_models
    download_models()
    print("==> Docling models cached.", flush=True)
except Exception as exc:
    print(f"!! Model pre-download failed: {exc}. First request will download on demand.", file=sys.stderr, flush=True)
PY

# Warm-up conversion. download_models() alone does NOT cover everything the
# runtime resolves: pipeline initialization performs pinned-revision HF Hub
# snapshot lookups and fetches the remaining artifacts (e.g. tableformer
# weights) on the user's first extract (verified 2026-06-12: first online
# extract took ~15s with dozens of Hub requests; after this warm-up an
# offline extract takes ~2s). Converting one blank PDF with the same
# pipeline options as server.py forces all of that to resolve at build
# time. This RUN must fail the image build (no try/except) — a missing
# artifact here would otherwise surface as a runtime failure under the
# offline mode set below. pypdfium2 is already a docling dependency.
RUN python - <<'PY'
import pypdfium2 as pdfium
pdf = pdfium.PdfDocument.new()
pdf.new_page(612, 792)
pdf.save("/tmp/warmup.pdf")

from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions

# Keep in sync with _build_converter in server.py.
opts = PdfPipelineOptions()
opts.do_ocr = True
opts.do_table_structure = True
conv = DocumentConverter(format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)})
result = conv.convert("/tmp/warmup.pdf")
assert len(result.document.pages) == 1
print("==> Warm-up conversion OK; all runtime artifacts cached.", flush=True)
PY

# Every model artifact is now baked in, so never touch the HF Hub at
# runtime: kills first-request revalidation latency and unauthenticated
# rate-limit warnings, and makes extraction work fully offline. If a
# future docling bump starts needing an uncached artifact, the warm-up
# step above fails the image build instead of the user's first import.
ENV HF_HUB_OFFLINE=1

COPY server.py /app/server.py

# EXTRACTOR_OCR_RUNTIME / EXTRACTOR_LANGS_RUNTIME are injected by compose
# (environment:) from the user's settings — runtime config, not baked in.

EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
