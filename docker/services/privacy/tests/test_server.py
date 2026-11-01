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


# Strings the user marked: every occurrence is masked, whole, with the type
# the user gave, whatever the detection finds.
def test_health_names_the_terms_capability():
    body = client.get("/v1/health").json()
    assert body["protocol"] >= 2
    assert "terms" in body["capabilities"]


def test_marked_terms_are_masked_wherever_they_occur(monkeypatch):
    import server

    text = "江戸川今太郎です。江戸川今太郎より"
    inner = [{"start": 3, "end": 6, "type": "PERSON", "score": 0.9, "lang_used": "ja"}]  # only 太郎 detected
    monkeypatch.setattr(server, "_analyze_per_language", lambda t, languages, threshold: [dict(s) for s in inner])
    r = client.post("/v1/anonymize", json={"text": text, "languages": ["en"],
                                           "terms": [{"text": "江戸川今太郎", "type": "PERSON"}]})
    assert r.status_code == 200
    body = r.json()
    assert body["masked_text"] == "<<PERSON_1>>です。<<PERSON_1>>より"
    assert body["registry"] == {"<<PERSON_1>>": "江戸川今太郎"}


def test_a_marked_term_keeps_its_type_and_its_honorific(monkeypatch):
    import server

    monkeypatch.setattr(server, "_analyze_per_language",
                        lambda t, languages, threshold: [{"start": 0, "end": 6, "type": "LOCATION", "score": 0.99, "lang_used": "ja"}])
    r = client.post("/v1/anonymize", json={"text": "Acme王様の件", "languages": ["ja"], "entity_types": ["PERSON"],
                                           "terms": [{"text": "Acme王様", "type": "ORGANIZATION"}]})
    assert r.json()["masked_text"] == "<<ORGANIZATION_1>>の件"


def test_an_unknown_term_type_is_refused():
    r = client.post("/v1/anonymize", json={"text": "x", "terms": [{"text": "x", "type": "NICKNAME"}]})
    assert r.status_code == 422


def test_an_empty_term_is_refused():
    r = client.post("/v1/anonymize", json={"text": "x", "terms": [{"text": "", "type": "PERSON"}]})
    assert r.status_code == 422


def test_the_honorific_rule_takes_the_whole_name_and_not_the_honorific():
    import re
    import yaml
    from pathlib import Path

    spec = yaml.safe_load((Path(__file__).parent.parent / "recognizers" / "jp_honorific_person.yaml").read_text())
    pattern = re.compile(spec["patterns"][0]["regex"])
    found = lambda text: [m.group(0) for m in pattern.finditer(text)]
    assert found("佐々木馬之助さんにメール") == ["佐々木馬之助"]
    assert found("山田さま") == ["山田"]
    assert found("ジョン・スミスさん") == ["ジョン・スミス"]
    assert found("𠮷田さん") == ["𠮷田"]
    assert found("一二三四五六七八九十一二三さん") == []  # longer than the rule takes: never only its tail
    assert found("森さん") == []
    assert found("僕の名前は江戸川今太郎です。") == []


def test_a_name_from_the_honorific_rule_is_not_trimmed_again():
    from server import _trim_japanese_honorifics

    spans = [{"start": 0, "end": 4, "type": "PERSON", "score": 0.6, "lang_used": "ja",
              "recognizer": "JpHonorificPersonRecognizer"}]
    assert _trim_japanese_honorifics("山田一君さん", spans)[0]["end"] == 4


def test_the_honorific_rule_runs_in_the_analyzer_with_its_name():
    import server

    if "ja" not in server.enabled_languages():
        return
    spans = server._analyze_per_language("山田一君さんへ", ["ja"], 0.4)
    assert any(s.get("recognizer") == "JpHonorificPersonRecognizer" and s["end"] - s["start"] == 4 for s in spans)
    r = client.post("/v1/anonymize", json={"text": "山田一君さんへ", "languages": ["ja"]}).json()
    assert r["masked_text"] == "<<PERSON_1>>さんへ"


def test_an_error_a_request_meets_is_logged_by_its_kind_only(monkeypatch, caplog):
    import server

    def fail(text, spans, registry):
        raise ValueError(f"could not mask: {text}")

    monkeypatch.setattr(server, "_build_masked", fail)
    r = client.post("/v1/anonymize", json={"text": "hello MARKER-7341", "languages": ["en"]})
    assert r.status_code == 500
    assert "MARKER-7341" not in r.text
    assert "MARKER-7341" not in caplog.text
    assert "POST /v1/anonymize failed: ValueError" in caplog.text
