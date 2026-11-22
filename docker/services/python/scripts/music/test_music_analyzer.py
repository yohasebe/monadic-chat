"""Unit tests for music_analyzer.py — the result it prints."""

import json
import numpy as np
import pytest
from music_analyzer import _track_name, to_json


def test_numpy_numbers_are_printed_as_plain_numbers():
    result = {"tracks": [{"program": np.int64(33), "note_count": 12}],
              "tempo": {"bpm": np.float64(92.5)},
              "is_drum": np.bool_(False)}
    assert json.loads(to_json(result)) == {
        "tracks": [{"program": 33, "note_count": 12}],
        "tempo": {"bpm": 92.5},
        "is_drum": False,
    }


def test_numpy_arrays_are_printed_as_lists():
    assert json.loads(to_json({"beats": np.array([0.5, 1.0])})) == {"beats": [0.5, 1.0]}


def test_a_value_json_cannot_carry_is_still_refused():
    with pytest.raises(TypeError):
        to_json({"file": object()})


def test_a_track_name_written_in_shift_jis_is_read_as_text():
    assert _track_name("\u30d4\u30a2\u30ce".encode("cp932").decode("latin-1")) == "\u30d4\u30a2\u30ce"


def test_a_track_name_written_in_utf8_is_read_as_text():
    assert _track_name("\u30d4\u30a2\u30ce".encode("utf-8").decode("latin-1")) == "\u30d4\u30a2\u30ce"


def test_a_latin1_track_name_is_kept():
    assert _track_name("Fl\u00f6te  ") == "Fl\u00f6te"


def test_a_missing_track_name_is_empty():
    assert _track_name(None) == ""
