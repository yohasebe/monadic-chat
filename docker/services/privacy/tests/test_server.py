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


def test_enabled_languages_skips_unknown_codes(monkeypatch):
    # PRIVACY_LANGS is user-editable at runtime; a typo must not crash the
    # server at startup — unknown codes are warned about and skipped.
    import registry_setup

    monkeypatch.setenv("PRIVACY_LANGS_RUNTIME", "en,xx,ja")
    assert registry_setup.enabled_languages() == ["en", "ja"]


def test_enabled_languages_falls_back_to_english(monkeypatch):
    import registry_setup

    monkeypatch.setenv("PRIVACY_LANGS_RUNTIME", "zz")
    assert registry_setup.enabled_languages() == ["en"]


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


# Overlapping detections are masked as one span: a detection that loses on
# type must not leave its characters in the clear.
def _span(start, end, type_, score):
    return {"start": start, "end": end, "type": type_, "score": score, "lang_used": "en"}


def test_partly_overlapping_spans_are_masked_together():
    from server import _resolve_overlaps, _build_masked

    text = "ABCDEFGHIJ"
    merged = _resolve_overlaps([_span(0, 6, "PERSON", 1.0), _span(4, 10, "LOCATION", 0.8)])
    assert [(s["start"], s["end"], s["type"]) for s in merged] == [(0, 10, "PERSON")]
    masked, registry, _ = _build_masked(text, merged, {})
    assert masked == "<<PERSON_1>>"
    assert registry == {"<<PERSON_1>>": "ABCDEFGHIJ"}


def test_a_chain_of_overlaps_is_one_span_and_others_stay_apart():
    from server import _resolve_overlaps

    merged = _resolve_overlaps([
        _span(0, 4, "PERSON", 0.9), _span(3, 7, "LOCATION", 0.85), _span(6, 9, "ORGANIZATION", 0.85),
        _span(12, 15, "EMAIL_ADDRESS", 1.0),
    ])
    assert [(s["start"], s["end"]) for s in merged] == [(0, 9), (12, 15)]


def test_an_inner_span_takes_the_outer_spans_type_and_range():
    from server import _resolve_overlaps

    merged = _resolve_overlaps([_span(2, 6, "PERSON", 1.0), _span(0, 10, "LOCATION", 0.8)])
    assert [(s["start"], s["end"], s["type"]) for s in merged] == [(0, 10, "LOCATION")]


def test_masking_never_leaves_a_detected_character():
    import random
    from server import _resolve_overlaps

    rng = random.Random(7)
    types = ["PERSON", "LOCATION", "ORGANIZATION", "DATE_TIME", "PHONE_NUMBER"]
    for _ in range(500):
        spans = []
        for _ in range(rng.randint(1, 6)):
            start = rng.randint(0, 30)
            spans.append(_span(start, start + rng.randint(1, 8), rng.choice(types), rng.random()))
        covered = {i for s in spans for i in range(s["start"], s["end"])}
        merged = _resolve_overlaps(spans)
        kept = {i for s in merged for i in range(s["start"], s["end"])}
        assert covered <= kept
        ends = [(s["start"], s["end"]) for s in merged]
        assert all(a[1] <= b[0] for a, b in zip(ends, ends[1:]))  # in order, no overlap


def test_an_honorific_trim_does_not_uncover_another_detection():
    from server import _resolve_overlaps, _trim_japanese_honorifics, _build_masked

    text = "AB王様"
    spans = [
        {"start": 0, "end": 3, "type": "PERSON", "score": 0.95, "lang_used": "ja"},
        {"start": 2, "end": 4, "type": "LOCATION", "score": 0.8, "lang_used": "ja"},
    ]
    merged = _resolve_overlaps(_trim_japanese_honorifics(text, spans))  # the order anonymize uses
    masked, _, _ = _build_masked(text, merged, {})
    assert masked == "<<PERSON_1>>"


def test_anonymize_keeps_what_another_detection_covers_after_the_trim(monkeypatch):
    import server

    spans = [
        {"start": 0, "end": 3, "type": "PERSON", "score": 0.95, "lang_used": "ja"},
        {"start": 2, "end": 4, "type": "LOCATION", "score": 0.8, "lang_used": "ja"},
    ]
    monkeypatch.setattr(server, "_analyze_per_language", lambda text, languages, threshold: [dict(s) for s in spans])
    r = client.post("/v1/anonymize", json={"text": "AB王様", "languages": ["ja"]})
    assert r.status_code == 200
    assert r.json()["masked_text"] == "<<PERSON_1>>"
