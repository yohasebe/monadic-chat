"""Smoke tests for the Extractor Service FastAPI server.

Run inside the extractor container:
  docker exec -it monadic-chat-extractor-container python -m pytest /app/tests

Heavy ML behaviour (Docling extraction) is not exercised here — the
intent is to verify the HTTP surface and that the converter loaded
without raising at import time.
"""
from fastapi.testclient import TestClient

from server import app

client = TestClient(app)


def test_health():
    r = client.get("/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["pipeline"].startswith("docling-")


def test_info_lists_supported_formats():
    r = client.get("/v1/info")
    assert r.status_code == 200
    body = r.json()
    assert "pdf" in body["supported_formats"]
    assert body["pipeline"].startswith("docling-")


def test_extract_404_for_missing_file():
    r = client.post("/v1/extract", json={"path": "/no/such/file.pdf"})
    assert r.status_code == 404
    assert "not found" in r.json()["detail"]


def test_extract_request_schema_rejects_extra_required_fields():
    # path is the only required field; format/ocr/language_hint default
    r = client.post("/v1/extract", json={})
    assert r.status_code == 422
