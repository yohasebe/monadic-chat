"""Privacy Filter FastAPI server.

Endpoints:
  GET  /v1/health
  GET  /v1/info
  POST /v1/anonymize
  POST /v1/deanonymize

The server is stateless: registry is passed in/out per request so that
multiple workers and session restoration both work without server-side state.
"""
import logging
import re
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from registry_setup import build_analyzer, enabled_languages

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
LOG = logging.getLogger("privacy.server")

analyzer = build_analyzer()
app = FastAPI(title="Privacy Filter")

PLACEHOLDER_RE = re.compile(r"<<([A-Z_]+)_(\d+)>>")
JA_HONORIFICS = ("様", "さま", "さん", "くん", "君", "殿", "氏", "先生", "ちゃん")

# Higher = higher priority. Used for overlap resolution.
TYPE_PRIORITY = {
    "CREDIT_CARD": 100,
    "IBAN_CODE": 95,
    "PHONE_NUMBER": 90,
    "EMAIL_ADDRESS": 85,
    "URL": 80,
    "POSTAL_CODE": 75,
    "US_SSN": 70,
    "US_BANK_NUMBER": 65,
    "PERSON": 60,
    "ORGANIZATION": 55,
    "LOCATION": 50,
    "DATE_TIME": 5,
}
NUMERIC_TYPES = {"CREDIT_CARD", "PHONE_NUMBER", "POSTAL_CODE", "IBAN_CODE", "US_SSN"}


class AnalyzeOptions(BaseModel):
    score_threshold: float = 0.4
    honorific_trim: bool = True


class AnonymizeRequest(BaseModel):
    text: str
    languages: list[str] = Field(default_factory=lambda: ["en"])
    registry: dict[str, str] = Field(default_factory=dict)
    options: AnalyzeOptions = Field(default_factory=AnalyzeOptions)


class DeanonymizeRequest(BaseModel):
    text: str
    registry: dict[str, str]


@app.get("/v1/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "languages": enabled_languages()}


@app.get("/v1/info")
def info() -> dict[str, Any]:
    return {
        "languages": enabled_languages(),
        "recognizers": [
            {
                "name": r.name,
                "supported_entity": getattr(r, "supported_entity", None),
                "supported_language": r.supported_language,
            }
            for r in analyzer.registry.recognizers
        ],
    }


def _analyze_per_language(text: str, languages: list[str], score_threshold: float) -> list[dict]:
    spans = []
    for lang in languages:
        try:
            results = analyzer.analyze(text=text, language=lang, score_threshold=score_threshold)
        except Exception as exc:  # noqa: BLE001
            LOG.warning("analyze(lang=%s) failed: %s", lang, exc)
            continue
        for r in results:
            spans.append({
                "type": r.entity_type,
                "start": r.start,
                "end": r.end,
                "score": float(r.score),
                "lang_used": lang,
            })
    return spans


def _resolve_overlaps(spans: list[dict]) -> list[dict]:
    """Drop spans that lose to a higher-priority overlapping span.

    Rules:
      1. Strict containment: outer wins (longer span absorbs inner).
      2. Score gap >= 0.1: higher score wins.
      3. Otherwise: TYPE_PRIORITY decides.
      4. DATE_TIME never beats numeric ID types when overlapping.
    """
    spans = sorted(spans, key=lambda s: (s["start"], -(s["end"] - s["start"])))
    kept: list[dict] = []
    for cand in spans:
        loser = False
        for i, k in enumerate(list(kept)):
            if cand["end"] <= k["start"] or cand["start"] >= k["end"]:
                continue
            winner = _pick_winner(cand, k)
            if winner is k:
                loser = True
                break
            kept[i] = cand
            loser = True
            break
        if not loser:
            kept.append(cand)
    return sorted(kept, key=lambda s: s["start"])


def _pick_winner(a: dict, b: dict) -> dict:
    # DATE_TIME always loses to numeric ID types
    if a["type"] == "DATE_TIME" and b["type"] in NUMERIC_TYPES:
        return b
    if b["type"] == "DATE_TIME" and a["type"] in NUMERIC_TYPES:
        return a
    # Strict containment: outer wins
    if a["start"] <= b["start"] and a["end"] >= b["end"] and (a["end"] - a["start"]) > (b["end"] - b["start"]):
        return a
    if b["start"] <= a["start"] and b["end"] >= a["end"] and (b["end"] - b["start"]) > (a["end"] - a["start"]):
        return b
    # Score gap
    if abs(a["score"] - b["score"]) >= 0.1:
        return a if a["score"] > b["score"] else b
    # Priority fallback
    pa = TYPE_PRIORITY.get(a["type"], 0)
    pb = TYPE_PRIORITY.get(b["type"], 0)
    return a if pa >= pb else b


def _trim_japanese_honorifics(text: str, spans: list[dict]) -> list[dict]:
    out = []
    for s in spans:
        if s["type"] != "PERSON" or s.get("lang_used") != "ja":
            out.append(s)
            continue
        surface = text[s["start"]:s["end"]]
        trimmed_end = s["end"]
        for h in JA_HONORIFICS:
            if surface.endswith(h):
                trimmed_end = s["end"] - len(h)
                break
        if trimmed_end <= s["start"]:
            continue  # honorific consumed entire span
        out.append({**s, "end": trimmed_end})
    return out


def _seed_counters(registry: dict[str, str]) -> dict[str, int]:
    counters: dict[str, int] = {}
    for ph in registry:
        m = PLACEHOLDER_RE.fullmatch(ph)
        if not m:
            continue
        t, n = m.group(1), int(m.group(2))
        counters[t] = max(counters.get(t, 0), n)
    return counters


def _build_masked(
    text: str,
    spans: list[dict],
    registry: dict[str, str],
) -> tuple[str, dict[str, str], list[dict]]:
    """Walk text, replace each span with <<TYPE_N>>.

    Same original value reuses the same placeholder. New entities increment
    a per-type counter seeded from the existing registry.
    """
    counters = _seed_counters(registry)
    reverse: dict[tuple[str, str], str] = {}
    for ph, original in registry.items():
        m = PLACEHOLDER_RE.fullmatch(ph)
        if m:
            reverse[(m.group(1), original)] = ph

    out_parts = []
    cursor = 0
    entities: list[dict] = []
    new_registry = dict(registry)

    for s in sorted(spans, key=lambda s: s["start"]):
        if s["start"] < cursor:
            continue
        out_parts.append(text[cursor:s["start"]])
        original = text[s["start"]:s["end"]]
        key = (s["type"], original)
        if key in reverse:
            placeholder = reverse[key]
        else:
            counters[s["type"]] = counters.get(s["type"], 0) + 1
            placeholder = f"<<{s['type']}_{counters[s['type']]}>>"
            reverse[key] = placeholder
            new_registry[placeholder] = original
        out_parts.append(placeholder)
        entities.append({
            "placeholder": placeholder,
            "type": s["type"],
            "original": original,
            "score": round(s["score"], 3),
            "start": s["start"],
            "end": s["end"],
            "lang_used": s.get("lang_used"),
        })
        cursor = s["end"]

    out_parts.append(text[cursor:])
    return "".join(out_parts), new_registry, entities


@app.post("/v1/anonymize")
def anonymize(req: AnonymizeRequest) -> dict[str, Any]:
    if not req.languages:
        raise HTTPException(status_code=400, detail="languages must not be empty")

    raw_spans = _analyze_per_language(req.text, req.languages, req.options.score_threshold)
    detected = len(raw_spans)
    merged = _resolve_overlaps(raw_spans)
    after_merge = len(merged)
    if req.options.honorific_trim:
        merged = _trim_japanese_honorifics(req.text, merged)
    masked_text, new_registry, entities = _build_masked(req.text, merged, req.registry)
    return {
        "masked_text": masked_text,
        "entities": entities,
        "registry": new_registry,
        "stats": {
            "detected": detected,
            "kept_after_merge": after_merge,
            "kept_after_trim": len(entities),
        },
    }


@app.post("/v1/deanonymize")
def deanonymize(req: DeanonymizeRequest) -> dict[str, Any]:
    text = req.text
    placeholders_in_text = PLACEHOLDER_RE.findall(text)
    seen = set()
    replacements = 0
    missing: list[str] = []
    for type_str, num_str in placeholders_in_text:
        ph = f"<<{type_str}_{num_str}>>"
        if ph in seen:
            continue
        seen.add(ph)
        if ph in req.registry:
            text = text.replace(ph, req.registry[ph])
            replacements += 1
        else:
            missing.append(ph)
    return {
        "restored_text": text,
        "stats": {
            "replacements": replacements,
            "missing_placeholders": missing,
        },
    }
