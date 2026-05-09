FROM python:3.11.10-slim-bookworm

ARG PROJECT_TAG=monadic-chat
ARG PRIVACY_LANGS=en

LABEL project=${PROJECT_TAG}

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "presidio-analyzer==2.2.355" \
    "spacy>=3.7,<3.8" \
    "fastapi==0.115.0" \
    "uvicorn[standard]==0.30.6" \
    "pyyaml==6.0.2"

COPY language_map.json /app/language_map.json

ENV PRIVACY_LANGS_BUILD=${PRIVACY_LANGS}
RUN python - <<'PY'
import json, os, subprocess, sys
langs = [s.strip() for s in os.environ.get("PRIVACY_LANGS_BUILD", "en").split(",") if s.strip()]
mapping = json.load(open("/app/language_map.json"))
unknown = [l for l in langs if l not in mapping]
if unknown:
    sys.exit(f"Unknown PRIVACY_LANGS entries: {unknown}. Allowed: {sorted(mapping)}")
for lang in langs:
    print(f"==> spaCy download for {lang}: {mapping[lang]}", flush=True)
    subprocess.check_call([sys.executable, "-m", "spacy", "download", mapping[lang]])
PY

COPY recognizers /app/recognizers
COPY registry_setup.py /app/registry_setup.py
COPY server.py /app/server.py

ENV PRIVACY_LANGS_RUNTIME=${PRIVACY_LANGS}

EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
