"""Presidio AnalyzerEngine setup for multi-language detection.

Responsibilities:
1. Build NlpEngine for the languages enabled at build time (PRIVACY_LANGS).
2. Re-register PatternRecognizers (CC, Phone, Email, etc.) under every
   enabled language so they fire regardless of input language.
3. Remove noisy country-specific recognizers that hurt global usage.
4. Load custom YAML recognizers from /app/recognizers.
"""
import json
import logging
import os
from pathlib import Path

import yaml
from presidio_analyzer import AnalyzerEngine, Pattern, PatternRecognizer
from presidio_analyzer.nlp_engine import NlpEngineProvider
from presidio_analyzer.predefined_recognizers import (
    CreditCardRecognizer,
    EmailRecognizer,
    IbanRecognizer,
    IpRecognizer,
    MedicalLicenseRecognizer,
    PhoneRecognizer,
    UrlRecognizer,
    UsBankRecognizer,
    UsItinRecognizer,
    UsLicenseRecognizer,
    UsPassportRecognizer,
    UsSsnRecognizer,
)

LOG = logging.getLogger("privacy.registry_setup")

LANGUAGE_MAP_PATH = Path(__file__).parent / "language_map.json"
RECOGNIZERS_DIR = Path(__file__).parent / "recognizers"

DISABLED_RECOGNIZER_CLASSES = {
    "InPanRecognizer",
    "InAadhaarRecognizer",
    "InVehicleRegistrationRecognizer",
    "AuAbnRecognizer",
    "AuAcnRecognizer",
    "AuMedicareRecognizer",
    "AuTfnRecognizer",
    "UkNhsRecognizer",
    "EsNifRecognizer",
    "EsNieRecognizer",
    "ItDriverLicenseRecognizer",
    "ItVatCodeRecognizer",
    "ItIdentityCardRecognizer",
    "ItPassportRecognizer",
    "ItFiscalCodeRecognizer",
    "PlPeselRecognizer",
    "FiPersonalIdentityCodeRecognizer",
    "SgFinRecognizer",
    "SgUenRecognizer",
    "KrRrnRecognizer",
    "CryptoRecognizer",
}

# Pattern recognizers Presidio ships with English-only registration.
# Reinstantiate them per enabled language so they fire on, e.g., Japanese input.
LANGUAGE_AGNOSTIC_PATTERN_CLASSES = (
    EmailRecognizer,
    UrlRecognizer,
    PhoneRecognizer,
    CreditCardRecognizer,
    IbanRecognizer,
    IpRecognizer,
    MedicalLicenseRecognizer,
    UsSsnRecognizer,
    UsItinRecognizer,
    UsPassportRecognizer,
    UsBankRecognizer,
    UsLicenseRecognizer,
)


def enabled_languages() -> list[str]:
    raw = os.environ.get("PRIVACY_LANGS_RUNTIME") or os.environ.get("PRIVACY_LANGS") or "en"
    langs = [s.strip() for s in raw.split(",") if s.strip()]
    return langs or ["en"]


def build_nlp_engine(languages: list[str]):
    mapping = json.loads(LANGUAGE_MAP_PATH.read_text())
    models = []
    for lang in languages:
        if lang not in mapping:
            raise ValueError(f"Unknown language code: {lang}. Allowed: {sorted(mapping)}")
        models.append({"lang_code": lang, "model_name": mapping[lang]})
    config = {"nlp_engine_name": "spacy", "models": models}
    return NlpEngineProvider(nlp_configuration=config).create_engine()


def remove_disabled_recognizers(analyzer: AnalyzerEngine) -> int:
    removed = 0
    for recognizer in list(analyzer.registry.recognizers):
        if recognizer.__class__.__name__ in DISABLED_RECOGNIZER_CLASSES:
            analyzer.registry.remove_recognizer(recognizer.name)
            removed += 1
    return removed


def reregister_pattern_recognizers(analyzer: AnalyzerEngine, languages: list[str]) -> int:
    """Add a copy of each language-agnostic PatternRecognizer for every
    enabled language so it fires regardless of the request's language code."""
    added = 0
    for cls in LANGUAGE_AGNOSTIC_PATTERN_CLASSES:
        for lang in languages:
            if lang == "en":
                continue
            try:
                instance = cls(supported_language=lang)
            except TypeError:
                instance = cls()
                instance.supported_language = lang
            analyzer.registry.add_recognizer(instance)
            added += 1
    return added


def load_yaml_recognizers(analyzer: AnalyzerEngine, enabled_langs: list[str]) -> int:
    if not RECOGNIZERS_DIR.exists():
        return 0
    added = 0
    for yaml_file in sorted(RECOGNIZERS_DIR.glob("*.yaml")):
        spec = yaml.safe_load(yaml_file.read_text())
        lang = spec["supported_language"]
        if lang not in enabled_langs:
            LOG.info("skipping %s: language %s not enabled", yaml_file.name, lang)
            continue
        patterns = [
            Pattern(name=p["name"], regex=p["regex"], score=p["score"])
            for p in spec["patterns"]
        ]
        recognizer = PatternRecognizer(
            supported_entity=spec["supported_entity"],
            supported_language=lang,
            patterns=patterns,
            context=spec.get("context", []),
            name=spec["name"],
        )
        analyzer.registry.add_recognizer(recognizer)
        added += 1
    return added


def build_analyzer() -> AnalyzerEngine:
    languages = enabled_languages()
    nlp_engine = build_nlp_engine(languages)
    analyzer = AnalyzerEngine(nlp_engine=nlp_engine, supported_languages=languages)

    removed = remove_disabled_recognizers(analyzer)
    pattern_added = reregister_pattern_recognizers(analyzer, languages)
    yaml_added = load_yaml_recognizers(analyzer, languages)

    LOG.info(
        "AnalyzerEngine ready: languages=%s removed=%d pattern_added=%d yaml=%d",
        languages, removed, pattern_added, yaml_added,
    )
    return analyzer
