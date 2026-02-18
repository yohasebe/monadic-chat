"""Unit tests for melody_generator.py"""

import pytest
import random
from melody_generator import (
    euclidean_rhythm,
    get_chord_scale,
    get_chord_tones,
    contour_arch,
    contour_descending,
    contour_ascending,
    contour_concave,
    weighted_choice,
    select_pitch,
    get_beat_strength,
    generate_melody,
    MELODY_STYLE_PARAMS,
    MELODY_LOW,
    MELODY_HIGH,
    CHORD_SCALE_MAP,
    SCALE_INTERVALS,
)


# --- Euclidean Rhythm ---


class TestEuclideanRhythm:
    def test_basic_pattern(self):
        pattern = euclidean_rhythm(3, 8)
        assert len(pattern) == 8
        assert sum(pattern) == 3

    def test_cinquillo(self):
        """E(5,16) - classic cinquillo pattern."""
        pattern = euclidean_rhythm(5, 16)
        assert len(pattern) == 16
        assert sum(pattern) == 5

    def test_full_pattern(self):
        """k >= n should return all True."""
        pattern = euclidean_rhythm(8, 8)
        assert all(pattern)

    def test_empty_pattern(self):
        """k <= 0 should return all False."""
        pattern = euclidean_rhythm(0, 8)
        assert not any(pattern)

    def test_single_onset(self):
        pattern = euclidean_rhythm(1, 8)
        assert sum(pattern) == 1
        assert pattern[0] is True

    def test_even_distribution(self):
        """E(4,16) - onsets should be roughly evenly spaced."""
        pattern = euclidean_rhythm(4, 16)
        assert sum(pattern) == 4
        indices = [i for i, v in enumerate(pattern) if v]
        # Check spacing: gaps should be 3 or 4
        for i in range(len(indices) - 1):
            gap = indices[i + 1] - indices[i]
            assert gap in (3, 4, 5)


# --- Chord-Scale Mapping ---


class TestChordScale:
    def test_major_chord_returns_major_scale(self):
        scale = get_chord_scale(0, "maj")
        assert 0 in scale  # root
        assert 4 in scale  # major 3rd
        assert 7 in scale  # perfect 5th

    def test_minor_chord_returns_dorian(self):
        scale = get_chord_scale(2, "m7")  # Dm7
        assert 2 in scale  # root D
        # Dorian has natural 6th: B = 11
        assert 11 in scale

    def test_dominant_returns_mixolydian(self):
        scale = get_chord_scale(7, "7")  # G7
        assert 7 in scale  # root G
        # Mixolydian has flat 7: F = 5
        assert 5 in scale

    def test_unknown_quality_defaults_to_major(self):
        scale = get_chord_scale(0, "unknown_xyz")
        expected = get_chord_scale(0, "maj")
        assert scale == expected

    def test_scale_has_correct_size(self):
        for quality in CHORD_SCALE_MAP:
            scale_name = CHORD_SCALE_MAP[quality]
            intervals = SCALE_INTERVALS[scale_name]
            scale = get_chord_scale(0, quality)
            assert len(scale) == len(intervals)

    def test_all_pitch_classes_in_range(self):
        for quality in CHORD_SCALE_MAP:
            for root in range(12):
                scale = get_chord_scale(root, quality)
                assert all(0 <= pc < 12 for pc in scale)


class TestChordTones:
    def test_major_triad(self):
        tones = get_chord_tones(0, "maj")  # C major
        assert set(tones) == {0, 4, 7}

    def test_minor_seventh(self):
        tones = get_chord_tones(2, "m7")  # Dm7
        assert set(tones) == {2, 5, 9, 0}  # D F A C

    def test_dominant_seventh(self):
        tones = get_chord_tones(7, "7")  # G7
        assert set(tones) == {7, 11, 2, 5}  # G B D F


# --- Contour Functions ---


class TestContours:
    def test_arch_peak_at_center(self):
        assert contour_arch(0.5) == pytest.approx(1.0)
        assert contour_arch(0.0) == pytest.approx(0.0)
        assert contour_arch(1.0) == pytest.approx(0.0)

    def test_descending_monotonic(self):
        assert contour_descending(0.0) == pytest.approx(1.0)
        assert contour_descending(1.0) == pytest.approx(0.0)
        assert contour_descending(0.3) > contour_descending(0.7)

    def test_ascending_monotonic(self):
        assert contour_ascending(0.0) == pytest.approx(0.0)
        assert contour_ascending(1.0) == pytest.approx(1.0)
        assert contour_ascending(0.7) > contour_ascending(0.3)

    def test_concave_trough_at_center(self):
        assert contour_concave(0.5) == pytest.approx(0.0)
        assert contour_concave(0.0) == pytest.approx(1.0)
        assert contour_concave(1.0) == pytest.approx(1.0)


# --- Weighted Choice ---


class TestWeightedChoice:
    def test_single_item(self):
        result = weighted_choice([("a", 1)])
        assert result == "a"

    def test_zero_weights(self):
        result = weighted_choice([("a", 0), ("b", 0)])
        assert result == "a"

    def test_deterministic_when_one_weight_dominates(self):
        """With extreme weight difference, should almost always pick the heavy one."""
        counts = {"a": 0, "b": 0}
        for _ in range(100):
            result = weighted_choice([("a", 10000), ("b", 1)])
            counts[result] += 1
        assert counts["a"] > 90


# --- Beat Strength ---


class TestBeatStrength:
    def test_downbeats(self):
        assert get_beat_strength(0.0) == "downbeat"
        assert get_beat_strength(4.0) == "downbeat"  # beat 1 of next bar

    def test_strong_beats(self):
        assert get_beat_strength(2.0) == "strong"
        assert get_beat_strength(6.0) == "strong"  # beat 3 of next bar

    def test_medium_beats(self):
        assert get_beat_strength(1.0) == "medium"
        assert get_beat_strength(3.0) == "medium"

    def test_weak_beats(self):
        assert get_beat_strength(0.5) == "weak"
        assert get_beat_strength(1.5) == "weak"
        assert get_beat_strength(2.5) == "weak"


# --- Pitch Selection ---


class TestSelectPitch:
    def test_returns_integer(self):
        rng = random.Random(42)
        result = select_pitch(
            chord_tones_pc={0, 4, 7},
            scale_pc={0, 2, 4, 5, 7, 9, 11},
            contour_target=76,
            prev_midi=None,
            beat_strength="strong",
            leap_prob=0.15,
            rng=rng,
        )
        assert isinstance(result, int)

    def test_result_in_melody_range(self):
        rng = random.Random(42)
        for _ in range(50):
            result = select_pitch(
                chord_tones_pc={0, 4, 7},
                scale_pc={0, 2, 4, 5, 7, 9, 11},
                contour_target=78,
                prev_midi=76,
                beat_strength="strong",
                leap_prob=0.15,
                rng=rng,
            )
            # Should be within extended melody range
            assert MELODY_LOW - 2 <= result <= MELODY_HIGH + 2

    def test_strong_beat_prefers_chord_tones(self):
        """On strong beats, chord tones should be selected more often."""
        rng = random.Random(42)
        chord_tones_pc = {0, 4, 7}  # C E G
        scale_pc = {0, 2, 4, 5, 7, 9, 11}
        chord_tone_count = 0
        trials = 200
        for i in range(trials):
            rng = random.Random(i)
            result = select_pitch(
                chord_tones_pc, scale_pc, 78, 76, "strong", 0.15, rng
            )
            if result % 12 in chord_tones_pc:
                chord_tone_count += 1
        # Should be > 50% on strong beats
        assert chord_tone_count / trials > 0.5


# --- Full Melody Generation ---


class TestGenerateMelody:
    @pytest.fixture
    def ii_v_i_chords(self):
        return [
            {"root_pc": 2, "quality": "m7", "name": "Dm7"},
            {"root_pc": 7, "quality": "7", "name": "G7"},
            {"root_pc": 0, "quality": "maj7", "name": "Cmaj7"},
            {"root_pc": 0, "quality": "maj7", "name": "Cmaj7"},
        ]

    def test_returns_list_of_tuples(self, ii_v_i_chords):
        melody = generate_melody(ii_v_i_chords, "lyrical", 4, seed=42)
        assert isinstance(melody, list)
        assert len(melody) > 0
        for item in melody:
            assert isinstance(item, tuple)
            assert len(item) == 2

    def test_midi_values_or_none(self, ii_v_i_chords):
        melody = generate_melody(ii_v_i_chords, "jazz", 4, seed=42)
        for midi_num, duration in melody:
            assert midi_num is None or isinstance(midi_num, int)
            assert isinstance(duration, (int, float))
            assert duration > 0

    def test_seed_reproducibility(self, ii_v_i_chords):
        melody1 = generate_melody(ii_v_i_chords, "jazz", 4, seed=123)
        melody2 = generate_melody(ii_v_i_chords, "jazz", 4, seed=123)
        assert melody1 == melody2

    def test_different_seeds_different_melodies(self, ii_v_i_chords):
        melody1 = generate_melody(ii_v_i_chords, "jazz", 4, seed=1)
        melody2 = generate_melody(ii_v_i_chords, "jazz", 4, seed=999)
        assert melody1 != melody2

    def test_all_styles_produce_output(self, ii_v_i_chords):
        for style in MELODY_STYLE_PARAMS:
            melody = generate_melody(ii_v_i_chords, style, 4, seed=42)
            assert len(melody) > 0, f"Style '{style}' produced empty melody"

    def test_unknown_style_defaults_to_lyrical(self, ii_v_i_chords):
        melody = generate_melody(ii_v_i_chords, "nonexistent_style", 4, seed=42)
        melody_lyrical = generate_melody(ii_v_i_chords, "lyrical", 4, seed=42)
        assert melody == melody_lyrical

    def test_final_note_resolves(self, ii_v_i_chords):
        """Last note should resolve to root or 3rd of last chord."""
        melody = generate_melody(ii_v_i_chords, "lyrical", 4, seed=42)
        last_midi, last_dur = melody[-1]
        if last_midi is not None:
            last_pc = last_midi % 12
            # Last chord is Cmaj7, root=0, 3rd=4
            assert last_pc in (0, 4), f"Last note {last_pc} not root or 3rd"
            assert last_dur >= 2.0, "Final note should be at least 2 beats"

    def test_single_bar(self, ii_v_i_chords):
        """Should work with just 1 bar."""
        melody = generate_melody(ii_v_i_chords[:1], "gentle", 1, seed=42)
        assert len(melody) > 0

    def test_many_bars(self, ii_v_i_chords):
        """Should handle long progressions."""
        melody = generate_melody(ii_v_i_chords, "rhythmic", 16, seed=42)
        assert len(melody) > 10

    def test_total_duration_reasonable(self, ii_v_i_chords):
        """Total duration should not wildly exceed or fall short of total beats."""
        melody = generate_melody(ii_v_i_chords, "jazz", 4, seed=42)
        total_dur = sum(d for _, d in melody)
        total_beats = 4 * 4  # 4 bars * 4 beats
        assert total_dur > 0
        # Should be within reasonable bounds
        assert total_dur <= total_beats + 4


# --- Style Parameters Validation ---


class TestStyleParams:
    def test_all_styles_have_required_keys(self):
        required_keys = {
            "euclidean_k", "euclidean_n", "syncopation",
            "rest_probability", "duration_weights", "contour_types",
            "leap_probability", "default_instrument",
        }
        for style_name, params in MELODY_STYLE_PARAMS.items():
            missing = required_keys - set(params.keys())
            assert not missing, f"Style '{style_name}' missing keys: {missing}"

    def test_euclidean_k_less_than_n(self):
        for style_name, params in MELODY_STYLE_PARAMS.items():
            assert params["euclidean_k"] < params["euclidean_n"], \
                f"Style '{style_name}': k >= n"

    def test_probabilities_in_range(self):
        for style_name, params in MELODY_STYLE_PARAMS.items():
            assert 0.0 <= params["syncopation"] <= 1.0
            assert 0.0 <= params["rest_probability"] <= 1.0
            assert 0.0 <= params["leap_probability"] <= 1.0

    def test_contour_types_valid(self):
        from melody_generator import CONTOUR_FUNCTIONS
        for style_name, params in MELODY_STYLE_PARAMS.items():
            for ct in params["contour_types"]:
                assert ct in CONTOUR_FUNCTIONS, \
                    f"Style '{style_name}' has invalid contour '{ct}'"
