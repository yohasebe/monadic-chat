#!/usr/bin/env python3
"""
Algorithmic Melody Generator - Generates musical melodies over chord progressions.

Uses chord-scale theory, Euclidean rhythms, contour shaping, and weighted pitch
selection to produce melodies that sound musical rather than random.

Called by music_generator.py when melody_style is specified.
Returns [(midi_num|None, duration), ...] compatible with parse_melody() output.
"""

import math
import random

# --- Chord-Scale Mapping ---

CHORD_SCALE_MAP = {
    "maj": "major", "": "major", "M7": "major", "maj7": "major",
    "maj9": "major", "M9": "major", "6": "major", "add9": "major",
    "m": "dorian", "min": "dorian", "m7": "dorian", "min7": "dorian",
    "m9": "dorian", "min9": "dorian",
    "7": "mixolydian", "9": "mixolydian", "11": "mixolydian", "13": "mixolydian",
    "sus4": "mixolydian", "sus2": "mixolydian", "7sus4": "mixolydian",
    "dim": "locrian", "m7b5": "locrian",
    "dim7": "diminished",
    "aug": "whole_tone", "+": "whole_tone", "aug7": "whole_tone",
    "+7": "whole_tone", "7#5": "whole_tone",
    "m6": "melodic_minor",
    "7#9": "blues",
    "7b9": "phrygian_dominant",
    "7b5": "lydian_dominant",
    # Extended tensions
    "m11": "dorian", "min11": "dorian",
    "maj13": "major", "M13": "major",
    "m13": "dorian", "min13": "dorian",
    # Lydian / tritone sub
    "7#11": "lydian_dominant",
    "maj7#11": "lydian",
    # 6/9 chords
    "69": "major",
    "m69": "melodic_minor",
    # Other
    "5": "major",
    "madd9": "dorian",
    "7sus2": "mixolydian",
}

# Scale intervals from root (semitones)
SCALE_INTERVALS = {
    "major":          [0, 2, 4, 5, 7, 9, 11],
    "dorian":         [0, 2, 3, 5, 7, 9, 10],
    "mixolydian":     [0, 2, 4, 5, 7, 9, 10],
    "locrian":        [0, 1, 3, 5, 6, 8, 10],
    "diminished":     [0, 2, 3, 5, 6, 8, 9, 11],
    "whole_tone":     [0, 2, 4, 6, 8, 10],
    "melodic_minor":  [0, 2, 3, 5, 7, 9, 11],
    "blues":          [0, 3, 5, 6, 7, 10],
    "harmonic_minor":    [0, 2, 3, 5, 7, 8, 11],
    "phrygian_dominant": [0, 1, 4, 5, 7, 8, 10],
    "lydian":            [0, 2, 4, 6, 7, 9, 11],
    "lydian_dominant":   [0, 2, 4, 6, 7, 9, 10],
    "phrygian":          [0, 1, 3, 5, 7, 8, 10],
    "aeolian":           [0, 2, 3, 5, 7, 8, 10],
    "altered":           [0, 1, 3, 4, 6, 8, 10],
}

# Chord type intervals (subset used for chord-tone identification)
CHORD_INTERVALS = {
    "maj": [0, 4, 7], "": [0, 4, 7], "M7": [0, 4, 7, 11], "maj7": [0, 4, 7, 11],
    "maj9": [0, 4, 7, 11, 14], "M9": [0, 4, 7, 11, 14],
    "6": [0, 4, 7, 9], "add9": [0, 4, 7, 14],
    "m": [0, 3, 7], "min": [0, 3, 7], "m7": [0, 3, 7, 10], "min7": [0, 3, 7, 10],
    "m9": [0, 3, 7, 10, 14], "min9": [0, 3, 7, 10, 14],
    "7": [0, 4, 7, 10], "9": [0, 4, 7, 10, 14], "11": [0, 4, 7, 10, 14, 17],
    "13": [0, 4, 7, 10, 14, 21],
    "sus4": [0, 5, 7], "sus2": [0, 2, 7], "7sus4": [0, 5, 7, 10],
    "dim": [0, 3, 6], "m7b5": [0, 3, 6, 10],
    "dim7": [0, 3, 6, 9],
    "aug": [0, 4, 8], "+": [0, 4, 8], "aug7": [0, 4, 8, 10],
    "+7": [0, 4, 8, 10], "7#5": [0, 4, 8, 10],
    "m6": [0, 3, 7, 9],
    "7#9": [0, 4, 7, 10, 15], "7b9": [0, 4, 7, 10, 13],
    "7b5": [0, 4, 6, 10],
    # Extended tensions
    "m11": [0, 3, 7, 10, 14, 17], "min11": [0, 3, 7, 10, 14, 17],
    "maj13": [0, 4, 7, 11, 14, 21], "M13": [0, 4, 7, 11, 14, 21],
    "m13": [0, 3, 7, 10, 14, 21], "min13": [0, 3, 7, 10, 14, 21],
    # Lydian / tritone sub
    "7#11": [0, 4, 7, 10, 18], "maj7#11": [0, 4, 7, 11, 18],
    # 6/9 chords
    "69": [0, 4, 7, 9, 14], "m69": [0, 3, 7, 9, 14],
    # Other
    "5": [0, 7], "madd9": [0, 3, 7, 14], "7sus2": [0, 2, 7, 10],
}


def get_chord_scale(root_pc, quality):
    """Get scale pitch classes for a chord quality rooted at root_pc."""
    scale_name = CHORD_SCALE_MAP.get(quality, "major")
    intervals = SCALE_INTERVALS.get(scale_name, SCALE_INTERVALS["major"])
    return [(root_pc + iv) % 12 for iv in intervals]


def get_chord_tones(root_pc, quality):
    """Get chord-tone pitch classes for a chord quality rooted at root_pc."""
    intervals = CHORD_INTERVALS.get(quality, [0, 4, 7])
    return [(root_pc + iv) % 12 for iv in intervals]


# --- Style Parameters ---

MELODY_STYLE_PARAMS = {
    "lyrical": {
        "euclidean_k": 5, "euclidean_n": 16,
        "syncopation": 0.15,
        "rest_probability": 0.12,
        "duration_weights": {0.5: 20, 1.0: 40, 1.5: 25, 2.0: 15},
        "contour_types": ["arch", "descending", "arch", "ascending"],
        "leap_probability": 0.15,
        "default_instrument": "strings",
    },
    "rhythmic": {
        "euclidean_k": 7, "euclidean_n": 16,
        "syncopation": 0.35,
        "rest_probability": 0.15,
        "duration_weights": {0.5: 45, 1.0: 35, 1.5: 10, 2.0: 10},
        "contour_types": ["arch", "ascending", "descending", "arch"],
        "leap_probability": 0.20,
        "default_instrument": "synth_lead",
    },
    "jazz": {
        "euclidean_k": 7, "euclidean_n": 16,
        "syncopation": 0.40,
        "rest_probability": 0.15,
        "duration_weights": {0.5: 35, 1.0: 30, 1.5: 20, 2.0: 15},
        "contour_types": ["arch", "descending", "ascending", "concave"],
        "leap_probability": 0.25,
        "default_instrument": "vibraphone",
        "swing": 0.167,
    },
    "latin": {
        "euclidean_k": 5, "euclidean_n": 16,
        "syncopation": 0.35,
        "rest_probability": 0.10,
        "duration_weights": {0.5: 40, 1.0: 35, 1.5: 15, 2.0: 10},
        "contour_types": ["ascending", "arch", "descending", "arch"],
        "leap_probability": 0.20,
        "default_instrument": "vibraphone",
    },
    "gentle": {
        "euclidean_k": 4, "euclidean_n": 16,
        "syncopation": 0.05,
        "rest_probability": 0.18,
        "duration_weights": {0.5: 10, 1.0: 35, 1.5: 30, 2.0: 25},
        "contour_types": ["arch", "descending", "arch", "descending"],
        "leap_probability": 0.10,
        "default_instrument": "piano",
    },
}


# --- Euclidean Rhythm (Bjorklund Algorithm) ---

def euclidean_rhythm(k, n):
    """Generate a Euclidean rhythm pattern E(k, n).

    Returns a list of n booleans where True = onset.
    Uses the Bjorklund algorithm to distribute k onsets as evenly as possible.
    """
    if k >= n:
        return [True] * n
    if k <= 0:
        return [False] * n

    # Bjorklund's algorithm
    groups = [[True]] * k + [[False]] * (n - k)
    while True:
        # Count trailing identical groups
        last = groups[-1]
        remainder = 0
        for i in range(len(groups) - 1, -1, -1):
            if groups[i] == last:
                remainder += 1
            else:
                break
        if remainder <= 1 or remainder == len(groups):
            break
        # Distribute remainder into front groups
        new_groups = []
        front_count = len(groups) - remainder
        for i in range(min(front_count, remainder)):
            new_groups.append(groups[i] + groups[len(groups) - remainder + i])
        # Remaining front groups
        for i in range(remainder, front_count):
            new_groups.append(groups[i])
        # Remaining back groups
        for i in range(front_count, len(groups) - remainder + min(front_count, remainder)):
            pass
        if remainder > front_count:
            for i in range(front_count, remainder):
                new_groups.append(groups[len(groups) - remainder + i])
        groups = new_groups

    # Flatten
    pattern = []
    for g in groups:
        pattern.extend(g)
    return pattern


# --- Contour Functions ---

def contour_arch(t):
    """Arch shape: rises then falls. t in [0, 1]."""
    return 1.0 - 4.0 * (t - 0.5) ** 2


def contour_descending(t):
    """Descending: starts high, ends low."""
    return 1.0 - t


def contour_ascending(t):
    """Ascending: starts low, ends high."""
    return t


def contour_concave(t):
    """Concave: dips down then rises."""
    return 4.0 * (t - 0.5) ** 2


CONTOUR_FUNCTIONS = {
    "arch": contour_arch,
    "descending": contour_descending,
    "ascending": contour_ascending,
    "concave": contour_concave,
}


# --- Pitch Selection ---

# Melody range
MELODY_LOW = 60   # C4
MELODY_HIGH = 84  # C6

# Interval weights for stepwise preference (semitones -> weight)
INTERVAL_WEIGHTS = {
    1: 30, 2: 40, 3: 30, 4: 15, 5: 10, 6: 5, 7: 8,
}


def weighted_choice(items_weights):
    """Choose from (item, weight) pairs using weighted random selection."""
    total = sum(w for _, w in items_weights)
    if total <= 0:
        return items_weights[0][0] if items_weights else None
    r = random.random() * total
    cumulative = 0
    for item, weight in items_weights:
        cumulative += weight
        if r <= cumulative:
            return item
    return items_weights[-1][0]


def select_pitch(chord_tones_pc, scale_pc, contour_target, prev_midi,
                 beat_strength, leap_prob, rng, diatonic_pcs=None):
    """Select a pitch using weighted probability distribution.

    Args:
        chord_tones_pc: pitch classes of chord tones
        scale_pc: pitch classes of the scale
        contour_target: target MIDI note from contour mapping
        prev_midi: previous note's MIDI number (or None)
        beat_strength: 'strong' (beats 1,3), 'medium' (beats 2,4), 'weak' (offbeats)
        leap_prob: probability of allowing larger intervals
        rng: random.Random instance
        diatonic_pcs: optional pitch classes of the parent key's diatonic scale
    """
    # Use diatonic key constraint when provided (pop/rock/ballad/bossa styles)
    allowed_scale_pcs = diatonic_pcs if diatonic_pcs is not None else scale_pc

    # Build candidate pitches in melody range
    candidates = []
    for midi_num in range(MELODY_LOW - 2, MELODY_HIGH + 3):
        pc = midi_num % 12
        is_chord_tone = pc in chord_tones_pc
        is_scale_tone = pc in allowed_scale_pcs

        if not is_chord_tone and not is_scale_tone:
            continue

        # Beat-strength weighting (downbeat strongly favors chord tones)
        if beat_strength == "downbeat":
            tone_weight = 100 if is_chord_tone else 15
        elif beat_strength == "strong":
            tone_weight = 70 if is_chord_tone else 25
        elif beat_strength == "medium":
            tone_weight = 50 if is_chord_tone else 40
        else:  # weak
            tone_weight = 30 if is_chord_tone else 50

        # Contour proximity weight (closer to target = higher weight)
        distance = abs(midi_num - contour_target)
        contour_weight = max(1, 40 - distance * 5)

        # Interval weight from previous note
        interval_weight = 20  # default
        if prev_midi is not None:
            semitones = abs(midi_num - prev_midi)
            if semitones in INTERVAL_WEIGHTS:
                interval_weight = INTERVAL_WEIGHTS[semitones]
            elif semitones > 7:
                # Penalize large leaps, modulated by leap_prob
                interval_weight = max(1, int(leap_prob * 40))
            elif semitones == 0:
                interval_weight = 15  # repeated note

        total_weight = tone_weight + contour_weight + interval_weight
        candidates.append((midi_num, total_weight))

    if not candidates:
        return contour_target

    return weighted_choice(candidates)


def get_beat_strength(beat_position):
    """Classify beat position into downbeat/strong/medium/weak."""
    # beat_position is in quarter-note beats (0-based within bar)
    beat_in_bar = beat_position % 4
    if abs(beat_in_bar - 0.0) < 0.01:
        return "downbeat"
    elif abs(beat_in_bar - 2.0) < 0.01:
        return "strong"
    elif abs(beat_in_bar - 1.0) < 0.01 or abs(beat_in_bar - 3.0) < 0.01:
        return "medium"
    else:
        return "weak"


# --- Melody Generation ---

def generate_melody(chord_sequence, style_name, total_bars, seed=None, diatonic_pcs=None):
    """Generate an algorithmic melody over a chord progression.

    Args:
        chord_sequence: list of dicts with keys:
            - root_pc (int): pitch class 0-11
            - quality (str): chord quality string
            - name (str): display name
        style_name: one of MELODY_STYLE_PARAMS keys
        total_bars: number of bars
        seed: optional random seed for reproducibility

    Returns:
        list of (midi_num|None, duration) tuples, compatible with parse_melody()
    """
    rng = random.Random(seed)
    # Also seed the module-level random for weighted_choice
    if seed is not None:
        random.seed(seed)

    style = MELODY_STYLE_PARAMS.get(style_name, MELODY_STYLE_PARAMS["lyrical"])
    beats_per_bar = 4
    total_beats = total_bars * beats_per_bar

    # Extend chord sequence to fill bars
    chords = list(chord_sequence)
    while len(chords) < total_bars:
        chords.extend(chord_sequence[:total_bars - len(chords)])
    chords = chords[:total_bars]

    # --- Layer 1: Generate rhythm using Euclidean pattern ---
    # Scale pattern to cover the full piece (avoids 2-bar repetition)
    k = style["euclidean_k"]
    n = style["euclidean_n"]
    slots_total = total_bars * 8
    scaled_k = max(1, int(k * slots_total / n))
    full_pattern = euclidean_rhythm(scaled_k, slots_total)

    syncopation = style["syncopation"]
    rest_prob = style["rest_probability"]
    swing = style.get("swing", 0.0)

    # Build onset times for the entire piece
    onsets = []
    slot_duration = 0.5  # each slot = eighth note
    for slot_idx in range(slots_total):
        if full_pattern[slot_idx]:
            bar_idx = slot_idx // 8
            slot_in_bar = slot_idx % 8
            beat_time = bar_idx * beats_per_bar + slot_in_bar * slot_duration
            # Swing: delay offbeat eighth notes (triplet feel)
            if swing > 0 and slot_in_bar % 2 == 1:
                beat_time += swing
            # Syncopation: randomly shift onset by half a beat
            if rng.random() < syncopation and slot_in_bar < 7:
                beat_time += 0.5
            onsets.append(beat_time)

    # Remove duplicates and sort
    onsets = sorted(set(onsets))

    # Insert rests (mark some onsets as rests)
    is_rest = [rng.random() < rest_prob for _ in onsets]

    # --- Layer 2: Assign durations ---
    dur_weights = style["duration_weights"]
    dur_items = list(dur_weights.items())

    melody_events = []
    for i, onset in enumerate(onsets):
        # Calculate max duration until next onset
        if i + 1 < len(onsets):
            max_dur = onsets[i + 1] - onset
        else:
            max_dur = total_beats - onset

        if max_dur <= 0:
            continue

        # Choose duration (weighted), capped by max_dur
        available_durs = [(d, w) for d, w in dur_items if d <= max_dur]
        if not available_durs:
            dur = min(0.5, max_dur)
        else:
            dur = weighted_choice(available_durs)

        if is_rest[i]:
            melody_events.append((onset, None, dur))
        else:
            melody_events.append((onset, "note", dur))

    # --- Fill gaps between events with explicit rests ---
    # Without this, melody events get packed into early bars and later bars are empty.
    filled_events = []
    current_time = 0.0
    for onset, event_type, duration in melody_events:
        gap = onset - current_time
        if gap > 0.05:
            gap_q = round(gap * 2) / 2  # quantize to nearest eighth note
            if gap_q > 0:
                filled_events.append((current_time, None, gap_q))
        filled_events.append((onset, event_type, duration))
        current_time = onset + duration
    remaining_time = total_beats - current_time
    if remaining_time > 0.05:
        remaining_q = round(remaining_time * 2) / 2
        if remaining_q > 0:
            filled_events.append((current_time, None, remaining_q))
    melody_events = filled_events

    # --- Layer 3: Assign pitches using contour + chord-scale theory ---
    contour_types = style["contour_types"]
    leap_prob = style["leap_probability"]
    phrase_bars = 4  # 4 bars per phrase

    prev_midi = None
    result = []

    for i, (onset, event_type, duration) in enumerate(melody_events):
        if event_type is None:
            result.append((None, duration))
            continue

        bar_idx = int(onset / beats_per_bar)
        bar_idx = min(bar_idx, len(chords) - 1)
        chord = chords[bar_idx]

        chord_tones_pc = get_chord_tones(chord["root_pc"], chord["quality"])
        scale_pc = get_chord_scale(chord["root_pc"], chord["quality"])

        # Contour: determine target pitch
        phrase_idx = bar_idx // phrase_bars
        contour_name = contour_types[phrase_idx % len(contour_types)]
        contour_fn = CONTOUR_FUNCTIONS[contour_name]

        # Position within phrase (0 to 1)
        bar_in_phrase = bar_idx % phrase_bars
        beat_in_bar = onset - bar_idx * beats_per_bar
        t = (bar_in_phrase * beats_per_bar + beat_in_bar) / (phrase_bars * beats_per_bar)
        t = max(0.0, min(1.0, t))

        contour_val = contour_fn(t)
        contour_target = int(MELODY_LOW + contour_val * (MELODY_HIGH - MELODY_LOW))

        # Beat strength
        beat_strength = get_beat_strength(onset)

        # Select pitch
        midi_num = select_pitch(
            chord_tones_pc, scale_pc, contour_target, prev_midi,
            beat_strength, leap_prob, rng, diatonic_pcs
        )

        result.append((midi_num, duration))
        prev_midi = midi_num

    # --- Layer 6: Final note resolution ---
    if result and chords:
        last_chord = chords[-1]
        root_pc = last_chord["root_pc"]
        # Resolve to root or 3rd of last chord in melody range
        resolution_targets = []
        intervals = CHORD_INTERVALS.get(last_chord["quality"], [0, 4, 7])
        for iv in [0, intervals[1] if len(intervals) > 1 else 4]:
            target_pc = (root_pc + iv) % 12
            # Find nearest instance in melody range
            for midi_num in range(MELODY_LOW, MELODY_HIGH + 1):
                if midi_num % 12 == target_pc:
                    resolution_targets.append(midi_num)

        if resolution_targets and result[-1][0] is not None:
            # Pick the resolution target closest to the last note
            last_note = result[-1][0]
            best = min(resolution_targets, key=lambda t: abs(t - last_note))
            # Replace last note with resolution, minimum 2 beats
            last_dur = max(2.0, result[-1][1])
            result[-1] = (best, last_dur)

    return result


# --- Self-test ---

if __name__ == "__main__":
    NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    def midi_to_name(m):
        if m is None:
            return "R"
        octave = (m // 12) - 1
        return f"{NOTE_NAMES[m % 12]}{octave}"

    # Test chord sequence: ii-V-I in C
    test_chords = [
        {"root_pc": 2, "quality": "m7", "name": "Dm7"},
        {"root_pc": 7, "quality": "7", "name": "G7"},
        {"root_pc": 0, "quality": "maj7", "name": "Cmaj7"},
        {"root_pc": 0, "quality": "maj7", "name": "Cmaj7"},
    ]

    print("=== Algorithmic Melody Generator Self-Test ===\n")
    for style_name in MELODY_STYLE_PARAMS:
        melody = generate_melody(test_chords, style_name, total_bars=4, seed=42)
        notes_str = " ".join(
            f"{midi_to_name(m)}:{d}" for m, d in melody
        )
        print(f"Style: {style_name}")
        print(f"  Notes: {notes_str}")
        print(f"  Count: {len(melody)} events")
        total_dur = sum(d for _, d in melody)
        print(f"  Total duration: {total_dur} beats")
        print()
