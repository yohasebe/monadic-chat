FROM python:3.11.10-slim-bookworm

ARG PROJECT_TAG=monadic-chat

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

# Bake every supported spaCy model into the image (each is a small _sm
# model, ~50 MB). Which languages are actually loaded is selected at
# runtime via PRIVACY_LANGS_RUNTIME (injected by compose from the user's
# PRIVACY_LANGS), so changing languages is a container restart, not a
# rebuild — and the image content is user-independent (prebuilt-friendly).
RUN python - <<'PY'
import json, subprocess, sys
mapping = json.load(open("/app/language_map.json"))
for lang, model in sorted(mapping.items()):
    print(f"==> spaCy download for {lang}: {model}", flush=True)
    subprocess.check_call([sys.executable, "-m", "spacy", "download", model])
PY

COPY recognizers /app/recognizers
COPY registry_setup.py /app/registry_setup.py
COPY server.py /app/server.py

EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
