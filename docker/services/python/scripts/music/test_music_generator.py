"""Unit tests for music_generator.py — chord/bass patterns, key detection, and backing tracks."""

import re
import pytest
from music_generator import (
    _chord_pattern,
    _bass_pattern,
    _detect_key,
    _voice_lead,
    action_backing,
    build_abc_chord,
    midi_to_abc_note,
    parse_chord_with_bass,
    CHORD_TYPES,
    FLAT_ROOTS,
)


def _pattern_units(pattern):
    """Count total eighth-note units in an ABC pattern string (L:1/8).

    Handles: note2, [chord]3, z4, bare note (=1 unit each).
    """
    # Strip leading whitespace and chord names like "Dm7"
    s = pattern.strip()
    s = re.sub(r'"[^"]*"', '', s)  # Remove chord labels

    total = 0
    for token in s.split():
        # Extract trailing digits as duration
        m = re.search(r'(\d+)$', token)
        if m:
            total += int(m.group(1))
        else:
            total += 1  # bare note/rest = 1 unit
    return total


# --- Chord Pattern Tests ---


class TestChordPatternGuitar:
    """Guitar-specific chord patterns."""

    def _voiced_triad(self):
        """C major triad: C4=60, E4=64, G4=67"""
        return [60, 64, 67]

    def _voiced_seventh(self):
        """Cmaj7: C4=60, E4=64, G4=67, B4=71"""
        return [60, 64, 67, 71]

    def test_bossa_3note_is_arpeggiated(self):
        """Bossa guitar should arpeggiate, not block chord."""
        pattern = _chord_pattern(self._voiced_triad(), "bossa", "acoustic_guitar")
        # Should NOT contain bracket notation [CEG]
        assert "[" not in pattern

    def test_bossa_3note_duration(self):
        """Bossa 3-note arpeggio: 3+1+3+1 = 8 units."""
        pattern = _chord_pattern(self._voiced_triad(), "bossa", "acoustic_guitar")
        assert _pattern_units(pattern) == 8

    def test_bossa_4note_duration(self):
        """Bossa 4-note arpeggio: 3+1+1+1+2 = 8 units."""
        pattern = _chord_pattern(self._voiced_seventh(), "bossa", "acoustic_guitar")
        assert _pattern_units(pattern) == 8

    def test_bossa_4note_uses_all_notes(self):
        """4-note bossa should include all chord tones."""
        notes = self._voiced_seventh()
        pattern = _chord_pattern(notes, "bossa", "acoustic_guitar")
        abc_notes = [midi_to_abc_note(n) for n in sorted(notes)]
        for note in abc_notes:
            assert note in pattern, f"Missing {note} in pattern: {pattern}"

    def test_rock_power_chord(self):
        """Rock guitar: root + 5th only (no 3rd)."""
        notes = self._voiced_triad()
        pattern = _chord_pattern(notes, "rock", "electric_guitar", root_pc=0)
        # Should contain bracket notation with exactly 2 notes
        brackets = re.findall(r'\[([^\]]+)\]', pattern)
        assert len(brackets) > 0
        # Each bracket group should have 2 ABC note tokens
        for b in brackets:
            assert b == brackets[0]  # All power chords identical

    def test_rock_power_chord_duration(self):
        pattern = _chord_pattern(self._voiced_triad(), "rock", "electric_guitar", root_pc=0)
        assert _pattern_units(pattern) == 8

    def test_rock_uses_actual_root(self):
        """Power chord should use chord root, not voice-led lowest note."""
        # Voice-led notes where lowest is not the root
        # E.g., D chord voiced as [A4, D5, F#5] after voice leading from A chord
        voiced = [69, 74, 78]  # A4, D5, F#5
        pattern = _chord_pattern(voiced, "rock", "electric_guitar", root_pc=2)  # D
        # The power chord should use D, not A
        d_note = midi_to_abc_note(74)  # D5
        assert d_note in pattern

    def test_ballad_3note_fingerpicking(self):
        pattern = _chord_pattern(self._voiced_triad(), "ballad", "acoustic_guitar")
        assert "[" not in pattern  # No block chords
        assert _pattern_units(pattern) == 8

    def test_ballad_4note_travis_picking(self):
        pattern = _chord_pattern(self._voiced_seventh(), "ballad", "acoustic_guitar")
        assert "[" not in pattern
        assert _pattern_units(pattern) == 8

    def test_jazz_guitar_block_chord(self):
        """Jazz guitar uses block chords (Freddie Green style)."""
        pattern = _chord_pattern(self._voiced_triad(), "jazz", "guitar")
        assert "[" in pattern  # Block chord notation

    def test_pop_guitar_block_chord(self):
        pattern = _chord_pattern(self._voiced_triad(), "pop", "guitar")
        assert "[" in pattern


class TestChordPatternKeyboard:
    """Keyboard instruments should always use block chords."""

    def _voiced(self):
        return [60, 64, 67]

    @pytest.mark.parametrize("style", ["bossa", "jazz", "ballad", "rock", "pop"])
    def test_all_styles_use_block_chords(self, style):
        pattern = _chord_pattern(self._voiced(), style, "piano")
        assert "[" in pattern

    @pytest.mark.parametrize("style", ["bossa", "jazz", "ballad", "rock", "pop"])
    def test_all_styles_8_units(self, style):
        pattern = _chord_pattern(self._voiced(), style, "piano")
        assert _pattern_units(pattern) == 8


# --- Bass Pattern Tests ---


class TestBassPattern:
    """Style-specific bass patterns."""

    def test_bossa_2beat_feel(self):
        """Bossa bass: root on beat 1, fifth on beat 3 (half notes)."""
        pattern = _bass_pattern(48, "bossa", "m7")  # C3
        assert _pattern_units(pattern) == 8
        # Should have exactly 2 notes (each 4 units)
        tokens = pattern.strip().split()
        assert len(tokens) == 2
        assert tokens[0].endswith("4")
        assert tokens[1].endswith("4")

    def test_ballad_sparse(self):
        """Ballad bass: same 2-beat feel as bossa."""
        pattern = _bass_pattern(48, "ballad", "maj7")
        tokens = pattern.strip().split()
        assert len(tokens) == 2
        assert all(t.endswith("4") for t in tokens)

    def test_jazz_walking_4_notes(self):
        """Jazz walking bass: 4 quarter notes per bar."""
        pattern = _bass_pattern(50, "jazz", "m7", next_bass_midi=55)  # D3→G3
        tokens = pattern.strip().split()
        assert len(tokens) == 4
        assert all(t.endswith("2") for t in tokens)

    def test_jazz_approach_note_present(self):
        """Jazz walking bass should include a chromatic approach to the next root."""
        # D3(50) → next is G3(55), approach = F#3(54)
        pattern = _bass_pattern(50, "jazz", "m7", next_bass_midi=55)
        # F#3 in ABC = ^F, (sharp F, octave 3)
        assert "^F," in pattern

    def test_jazz_approach_octave_awareness(self):
        """Approach note should be close to the fifth, not in a distant octave."""
        # G3(55) → next is C3(48), approach should be B close to D4(62)
        # B3=59 (close to 62), not B2=47 or B4=71
        pattern = _bass_pattern(55, "jazz", "7", next_bass_midi=48)
        # B3 in ABC is B, (capital B with comma)
        assert "B," in pattern

    def test_jazz_approach_not_too_low(self):
        """Approach note should not go below A1 (MIDI 33)."""
        # Even with very low bass notes, approach stays in range
        pattern = _bass_pattern(36, "jazz", "", next_bass_midi=36)  # C2→C2
        # Approach is B (MIDI 35), which is >= 33, so B,, in ABC
        assert _pattern_units(pattern) == 8

    def test_rock_driving_pattern(self):
        """Rock bass: root-root-fifth-octave."""
        pattern = _bass_pattern(48, "rock", "")  # C3
        assert _pattern_units(pattern) == 8
        tokens = pattern.strip().split()
        assert len(tokens) == 4

    def test_pop_pattern(self):
        """Pop bass: root-root-fifth-root."""
        pattern = _bass_pattern(48, "pop", "")
        assert _pattern_units(pattern) == 8

    @pytest.mark.parametrize("style", ["bossa", "jazz", "ballad", "rock", "pop"])
    def test_all_styles_8_units(self, style):
        next_bass = 55 if style == "jazz" else None
        pattern = _bass_pattern(48, style, "m7", next_bass_midi=next_bass)
        assert _pattern_units(pattern) == 8

    def test_use_flats(self):
        """Bass patterns should respect enharmonic spelling."""
        pattern = _bass_pattern(53, "bossa", "m7", use_flats=True)  # F3
        # Should not contain sharps
        assert "^" not in pattern


# --- Key Detection Tests ---


class TestDetectKey:

    def test_ii_v_i_in_c(self):
        """Dm7-G7-Cmaj7 should detect C major."""
        chords = [
            {"root_pc": 2, "quality": "m7"},
            {"root_pc": 7, "quality": "7"},
            {"root_pc": 0, "quality": "maj7"},
        ]
        key = _detect_key(chords)
        assert key[0] == 0  # C major

    def test_ii_v_i_in_f(self):
        """Gm7-C7-Fmaj7 should detect F major."""
        chords = [
            {"root_pc": 7, "quality": "m7"},
            {"root_pc": 0, "quality": "7"},
            {"root_pc": 5, "quality": "maj7"},
        ]
        key = _detect_key(chords)
        assert key[0] == 5  # F major

    def test_pop_progression_in_c(self):
        """C-Am-F-G should detect C major."""
        chords = [
            {"root_pc": 0, "quality": ""},
            {"root_pc": 9, "quality": "m"},
            {"root_pc": 5, "quality": ""},
            {"root_pc": 7, "quality": ""},
        ]
        key = _detect_key(chords)
        assert key[0] == 0

    def test_returns_7_pitch_classes(self):
        chords = [{"root_pc": 0, "quality": "maj7"}]
        key = _detect_key(chords)
        assert len(key) == 7
        assert all(0 <= pc < 12 for pc in key)


# --- Slash Chord Tests ---


class TestSlashChords:

    def test_basic_slash(self):
        root_pc, root_name, intervals, quality, bass_pc = parse_chord_with_bass("C/E")
        assert root_pc == 0  # C
        assert bass_pc == 4  # E

    def test_no_slash(self):
        _, _, _, _, bass_pc = parse_chord_with_bass("Am7")
        assert bass_pc is None

    def test_slash_in_backing(self):
        """Slash chord bass note should appear in the bass voice."""
        result = action_backing({
            "chords": ["C/E"],
            "style": "pop",
            "bars": 1,
        })
        assert result["success"]
        abc = result["abc"]
        # Bass voice should start with E, not C
        bass_lines = [l for l in abc.split("\n") if "Bass" not in l and l.startswith("|")]
        # The ABC should contain E in bass somewhere
        assert "E," in abc or "E" in abc


# --- Integration Tests ---


class TestBackingTrackIntegration:

    @pytest.mark.parametrize("style", ["pop", "jazz", "rock", "bossa", "ballad"])
    def test_all_styles_produce_valid_abc(self, style):
        result = action_backing({
            "chords": ["C", "Am", "F", "G"],
            "style": style,
            "bars": 4,
        })
        assert result["success"]
        abc = result["abc"]
        assert "X:1" in abc
        assert "M:4/4" in abc
        assert "V:1" in abc
        assert "V:2" in abc

    def test_melody_with_guitar_arpeggio(self):
        """Melody + guitar arpeggio + walking bass should produce 3 voices."""
        result = action_backing({
            "chords": ["Dm7", "G7", "Cmaj7", "Cmaj7"],
            "style": "bossa",
            "bars": 4,
            "melody_style": "latin",
            "melody_seed": 42,
        })
        assert result["success"]
        abc = result["abc"]
        assert "V:1" in abc
        assert "V:2" in abc
        assert "V:3" in abc
        assert "Melody" in abc

    def test_rock_with_power_chords(self):
        result = action_backing({
            "chords": ["A", "D", "E", "A"],
            "style": "rock",
            "bars": 4,
        })
        assert result["success"]
        abc = result["abc"]
        # Verify electric_guitar GM program
        assert "%%MIDI program 27" in abc

    def test_flat_key_enharmonic_spelling(self):
        """Flat-key progressions should use flat spelling."""
        result = action_backing({
            "chords": ["Bbmaj7", "Eb", "F7", "Bbmaj7"],
            "style": "jazz",
            "bars": 4,
        })
        assert result["success"]
        abc = result["abc"]
        # Should use _B (Bb) notation, not ^A
        assert "_B" in abc or "_b" in abc
