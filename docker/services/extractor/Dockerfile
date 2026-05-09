FROM python:3.11.10-slim-bookworm

ARG PROJECT_TAG=monadic-chat
ARG EXTRACTOR_OCR=rapidocr
ARG EXTRACTOR_LANGS=en,ja,zh,ko

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
ENV EXTRACTOR_OCR_BUILD=${EXTRACTOR_OCR}
ENV EXTRACTOR_LANGS_BUILD=${EXTRACTOR_LANGS}
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

COPY server.py /app/server.py

ENV EXTRACTOR_OCR_RUNTIME=${EXTRACTOR_OCR}
ENV EXTRACTOR_LANGS_RUNTIME=${EXTRACTOR_LANGS}

EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
