FROM python:3.11.10-slim-bookworm

ARG PROJECT_TAG=monadic-chat
ARG MODEL_NAME=intfloat/multilingual-e5-base

LABEL project=${PROJECT_TAG}

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch first so we do not pull the (much larger) CUDA wheels.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    "torch==2.4.1"

RUN pip install --no-cache-dir \
    "sentence-transformers==3.2.1" \
    "fastapi==0.115.0" \
    "uvicorn[standard]==0.30.6" \
    "numpy==1.26.4"

# Pre-download the embedding model at build time so the first request after
# container start does not pay the ~1 GB download cost.
ENV MODEL_NAME=${MODEL_NAME}
ENV HF_HOME=/models
RUN mkdir -p /models && \
    python - <<'PY'
import os
from sentence_transformers import SentenceTransformer
SentenceTransformer(os.environ["MODEL_NAME"], cache_folder=os.environ["HF_HOME"])
PY

COPY server.py /app/server.py

ENV PORT=8000
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/v1/health', timeout=2)" || exit 1

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
