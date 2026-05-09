"""Smoke tests for the Privacy Filter FastAPI server.

Run inside the privacy container:
  docker exec -it monadic-chat-privacy-container python -m pytest /app/tests
"""
from fastapi.testclient import TestClient

from server import app

client = TestClient(app)


def test_health():
    r = client.get("/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "languages" in body
    assert "en" in body["languages"]


def test_info_lists_recognizers():
    r = client.get("/v1/info")
    assert r.status_code == 200
    body = r.json()
    names = {rec["name"] for rec in body["recognizers"]}
    # Email/URL/CC must be present in en
    assert any(n.startswith("Email") for n in names)
    assert any(n.startswith("Url") for n in names)


def test_anonymize_english_email():
    r = client.post("/v1/anonymize", json={
        "text": "Contact john.smith@acme.com please.",
        "languages": ["en"],
        "registry": {},
    })
    assert r.status_code == 200
    body = r.json()
    assert "<<EMAIL_ADDRESS_1>>" in body["masked_text"]
    assert body["registry"]["<<EMAIL_ADDRESS_1>>"] == "john.smith@acme.com"


def test_anonymize_reuses_placeholder_for_duplicate():
    r = client.post("/v1/anonymize", json={
        "text": "Email john@x.com or john@x.com again.",
        "languages": ["en"],
        "registry": {},
    })
    body = r.json()
    # Same value should map to one placeholder
    assert body["masked_text"].count("<<EMAIL_ADDRESS_1>>") == 2
    assert "<<EMAIL_ADDRESS_2>>" not in body["masked_text"]


def test_anonymize_extends_existing_registry():
    r = client.post("/v1/anonymize", json={
        "text": "Call 415-555-0100 today.",
        "languages": ["en"],
        "registry": {"<<EMAIL_ADDRESS_1>>": "old@x.com"},
    })
    body = r.json()
    assert "<<EMAIL_ADDRESS_1>>" in body["registry"]
    assert body["registry"]["<<EMAIL_ADDRESS_1>>"] == "old@x.com"


def test_deanonymize_restores_known_placeholders():
    r = client.post("/v1/deanonymize", json={
        "text": "Hi <<PERSON_1>>, your code is <<EMAIL_ADDRESS_1>>.",
        "registry": {
            "<<PERSON_1>>": "Alice",
            "<<EMAIL_ADDRESS_1>>": "alice@x.com",
        },
    })
    body = r.json()
    assert body["restored_text"] == "Hi Alice, your code is alice@x.com."
    assert body["stats"]["replacements"] == 2
    assert body["stats"]["missing_placeholders"] == []


def test_deanonymize_reports_missing():
    r = client.post("/v1/deanonymize", json={
        "text": "Hi <<PERSON_99>>, see <<EMAIL_ADDRESS_1>>.",
        "registry": {"<<EMAIL_ADDRESS_1>>": "a@x.com"},
    })
    body = r.json()
    assert "<<PERSON_99>>" in body["stats"]["missing_placeholders"]
    assert body["stats"]["replacements"] == 1


def test_entity_types_whitelist_excludes_date_time():
    # Without entity_types filter: DATE_TIME ("Friday") would be masked.
    # With entity_types=[PERSON, EMAIL_ADDRESS]: only those two are masked.
    r = client.post("/v1/anonymize", json={
        "text": "Email Alice at alice@x.com about the Friday meeting.",
        "languages": ["en"],
        "registry": {},
        "entity_types": ["PERSON", "EMAIL_ADDRESS"],
    })
    body = r.json()
    assert "<<PERSON_1>>" in body["masked_text"]
    assert "<<EMAIL_ADDRESS_1>>" in body["masked_text"]
    assert "<<DATE_TIME_1>>" not in body["masked_text"]
    assert "Friday" in body["masked_text"]


def test_entity_types_none_keeps_legacy_behavior():
    # When entity_types is omitted, all detected types are masked (including
    # DATE_TIME), preserving backward compatibility.
    r = client.post("/v1/anonymize", json={
        "text": "Meet on Monday at noon.",
        "languages": ["en"],
        "registry": {},
    })
    body = r.json()
    # Presidio detects "Monday" as DATE_TIME
    assert "<<DATE_TIME_1>>" in body["masked_text"]


def test_entity_types_empty_list_is_no_filter():
    # An empty list means "no filter" — same as omitting the field. This
    # avoids a footgun where users send [] thinking it disables masking.
    r = client.post("/v1/anonymize", json={
        "text": "Meet on Monday.",
        "languages": ["en"],
        "registry": {},
        "entity_types": [],
    })
    body = r.json()
    assert "<<DATE_TIME_1>>" in body["masked_text"]
