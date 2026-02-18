#!/usr/bin/env python3
"""
Music Generator - Generates ABC notation from music theory parameters.

ABCJS in the browser handles rendering and MIDI playback via WebAudio synthesis.

Usage:
    music_generator.py <action> --params '<JSON>'

Actions:
    chord       - Play a single chord
    scale       - Play a scale
    interval    - Play an interval
    progression - Play a chord progression
    backing     - Generate a backing track
"""

import argparse
import json
import sys

# --- Constants ---

GM_INSTRUMENTS = {
    "piano": 0,
    "electric_piano": 4,
    "organ": 19,
    "guitar": 25,
    "acoustic_guitar": 25,
    "electric_guitar": 27,
    "bass": 33,
    "electric_bass": 33,
    "strings": 48,
    "ensemble": 48,
    "brass": 61,
    "synth_lead": 80,
    "synth_pad": 89,
    "vibraphone": 11,
}

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Enharmonic mappings
ENHARMONIC = {
    "Db": "C#", "Eb": "D#", "Fb": "E", "Gb": "F#", "Ab": "G#", "Bb": "A#",
    "Cb": "B", "E#": "F", "B#": "C",
    "db": "C#", "eb": "D#", "fb": "E", "gb": "F#", "ab": "G#", "bb": "A#",
}

# ABC note names with sharps vs flats
ABC_NOTES_SHARP = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
ABC_NOTES_FLAT  = ["C", "_D", "D", "_E", "E", "F", "_G", "G", "_A", "A", "_B", "B"]
FLAT_ROOTS = {1, 3, 5, 8, 10}  # Db, Eb, F, Ab, Bb — keys that use flat spelling

# Chord type definitions (intervals in semitones from root)
CHORD_TYPES = {
    "maj":    [0, 4, 7],
    "":       [0, 4, 7],
    "min":    [0, 3, 7],
    "m":      [0, 3, 7],
    "dim":    [0, 3, 6],
    "aug":    [0, 4, 8],
    "+":      [0, 4, 8],
    "sus4":   [0, 5, 7],
    "sus2":   [0, 2, 7],
    "7":      [0, 4, 7, 10],
    "maj7":   [0, 4, 7, 11],
    "M7":     [0, 4, 7, 11],
    "min7":   [0, 3, 7, 10],
    "m7":     [0, 3, 7, 10],
    "dim7":   [0, 3, 6, 9],
    "m7b5":   [0, 3, 6, 10],
    "aug7":   [0, 4, 8, 10],
    "+7":     [0, 4, 8, 10],
    "6":      [0, 4, 7, 9],
    "m6":     [0, 3, 7, 9],
    "9":      [0, 4, 7, 10, 14],
    "maj9":   [0, 4, 7, 11, 14],
    "M9":     [0, 4, 7, 11, 14],
    "min9":   [0, 3, 7, 10, 14],
    "m9":     [0, 3, 7, 10, 14],
    "11":     [0, 4, 7, 10, 14, 17],
    "13":     [0, 4, 7, 10, 14, 21],
    "add9":   [0, 4, 7, 14],
    "7sus4":  [0, 5, 7, 10],
    "7#9":    [0, 4, 7, 10, 15],
    "7b9":    [0, 4, 7, 10, 13],
    "7#5":    [0, 4, 8, 10],
    "7b5":    [0, 4, 6, 10],
    # Extended tensions
    "m11":     [0, 3, 7, 10, 14, 17],
    "min11":   [0, 3, 7, 10, 14, 17],
    "maj13":   [0, 4, 7, 11, 14, 21],
    "M13":     [0, 4, 7, 11, 14, 21],
    "m13":     [0, 3, 7, 10, 14, 21],
    "min13":   [0, 3, 7, 10, 14, 21],
    # Lydian / tritone sub tensions
    "7#11":    [0, 4, 7, 10, 18],
    "maj7#11": [0, 4, 7, 11, 18],
    # 6/9 chords
    "69":      [0, 4, 7, 9, 14],
    "m69":     [0, 3, 7, 9, 14],
    # Other common types
    "5":       [0, 7],
    "madd9":   [0, 3, 7, 14],
    "7sus2":   [0, 2, 7, 10],
}

# Scale definitions (intervals in semitones)
SCALE_TYPES = {
    "major":             [0, 2, 4, 5, 7, 9, 11],
    "minor":             [0, 2, 3, 5, 7, 8, 10],
    "natural_minor":     [0, 2, 3, 5, 7, 8, 10],
    "harmonic_minor":    [0, 2, 3, 5, 7, 8, 11],
    "melodic_minor":     [0, 2, 3, 5, 7, 9, 11],
    "dorian":            [0, 2, 3, 5, 7, 9, 10],
    "phrygian":          [0, 1, 3, 5, 7, 8, 10],
    "lydian":            [0, 2, 4, 6, 7, 9, 11],
    "mixolydian":        [0, 2, 4, 5, 7, 9, 10],
    "locrian":           [0, 1, 3, 5, 6, 8, 10],
    "pentatonic":        [0, 2, 4, 7, 9],
    "minor_pentatonic":  [0, 3, 5, 7, 10],
    "blues":             [0, 3, 5, 6, 7, 10],
    "whole_tone":        [0, 2, 4, 6, 8, 10],
    "diminished":        [0, 2, 3, 5, 6, 8, 9, 11],
    "chromatic":         [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    "bebop_dominant":    [0, 2, 4, 5, 7, 9, 10, 11],
}

# Interval definitions
INTERVAL_TYPES = {
    "unison":          0,
    "minor_2nd":       1,
    "major_2nd":       2,
    "minor_3rd":       3,
    "major_3rd":       4,
    "perfect_4th":     5,
    "tritone":         6,
    "perfect_5th":     7,
    "minor_6th":       8,
    "major_6th":       9,
    "minor_7th":       10,
    "major_7th":       11,
    "octave":          12,
    "minor_9th":       13,
    "major_9th":       14,
    "minor_10th":      15,
    "major_10th":      16,
}


# --- Helper Functions ---

def note_name_to_midi(note_str):
    """Convert note name like 'C4', 'F#3', 'Bb5' to MIDI number."""
    note_str = note_str.strip()
    if not note_str:
        raise ValueError("Empty note string")

    # Extract note name and octave
    i = 1
    if len(note_str) > 1 and note_str[1] in ('#', 'b'):
        i = 2

    name_part = note_str[:i]
    octave_part = note_str[i:]

    # Handle enharmonic
    if name_part in ENHARMONIC:
        name_part = ENHARMONIC[name_part]

    if name_part not in NOTE_NAMES:
        raise ValueError(f"Unknown note: {name_part}")

    octave = int(octave_part) if octave_part else 4
    return NOTE_NAMES.index(name_part) + (octave + 1) * 12


def midi_to_note_name(midi_num):
    """Convert MIDI number to note name like 'C4'."""
    octave = (midi_num // 12) - 1
    note_idx = midi_num % 12
    return f"{NOTE_NAMES[note_idx]}{octave}"


def parse_root(root_str):
    """Parse root note name (without octave) to pitch class (0-11)."""
    root_str = root_str.strip()
    if root_str in ENHARMONIC:
        root_str = ENHARMONIC[root_str]
    if root_str not in NOTE_NAMES:
        raise ValueError(f"Unknown root note: {root_str}")
    return NOTE_NAMES.index(root_str), root_str


def parse_chord_name(chord_name):
    """Parse chord name like 'Cmaj7', 'F#m', 'Bbdim7' into root and intervals."""
    chord_name = chord_name.strip()
    if not chord_name:
        raise ValueError("Empty chord name")

    # Extract root note
    i = 1
    if len(chord_name) > 1 and chord_name[1] in ('#', 'b'):
        i = 2

    root_str = chord_name[:i]
    quality_str = chord_name[i:]

    root_pc, root_name = parse_root(root_str)

    # Match chord quality (try longest match first)
    intervals = None
    matched_quality = ""
    for length in range(len(quality_str), -1, -1):
        candidate = quality_str[:length]
        if candidate in CHORD_TYPES:
            intervals = CHORD_TYPES[candidate]
            matched_quality = candidate
            break

    if intervals is None:
        raise ValueError(f"Unknown chord quality: {quality_str} in {chord_name}")

    display_quality = matched_quality if matched_quality else "maj"
    return root_pc, root_name, intervals, display_quality


def parse_chord_with_bass(chord_name):
    """Parse chord name with optional slash bass (e.g., 'C/E', 'Am7/G').

    Returns (root_pc, root_name, intervals, quality, bass_pc).
    bass_pc is None if no slash notation.
    """
    bass_pc = None
    if "/" in chord_name:
        parts = chord_name.split("/", 1)
        chord_part = parts[0].strip()
        bass_str = parts[1].strip()
        if bass_str:
            bass_pc, _ = parse_root(bass_str)
        chord_name = chord_part

    root_pc, root_name, intervals, quality = parse_chord_name(chord_name)
    return root_pc, root_name, intervals, quality, bass_pc


def apply_voicing(intervals, voicing):
    """Apply voicing transformation to chord intervals."""
    if not voicing or voicing == "root":
        return intervals

    if voicing == "first_inv" and len(intervals) >= 3:
        return intervals[1:] + [intervals[0] + 12]
    elif voicing == "second_inv" and len(intervals) >= 3:
        return intervals[2:] + [intervals[0] + 12, intervals[1] + 12]
    elif voicing == "drop2" and len(intervals) >= 4:
        # Drop the second voice from top down an octave
        sorted_iv = sorted(intervals)
        second_from_top = sorted_iv[-2]
        result = [iv for iv in sorted_iv if iv != second_from_top]
        result.insert(0, second_from_top - 12)
        return sorted(result)
    elif voicing == "drop3" and len(intervals) >= 4:
        sorted_iv = sorted(intervals)
        third_from_top = sorted_iv[-3]
        result = [iv for iv in sorted_iv if iv != third_from_top]
        result.insert(0, third_from_top - 12)
        return sorted(result)
    elif voicing == "spread" and len(intervals) >= 3:
        # Spread voicing: alternating octave displacement
        result = []
        for idx, iv in enumerate(intervals):
            if idx % 2 == 1:
                result.append(iv + 12)
            else:
                result.append(iv)
        return result
    return intervals


def midi_to_abc_note(midi_num, use_flats=False):
    """Convert MIDI number to ABC notation note.

    Args:
        use_flats: If True, spell accidentals as flats (_B=Bb) instead of sharps (^A=A#).
    """
    octave = (midi_num // 12) - 1
    note_idx = midi_num % 12
    abc_notes = ABC_NOTES_FLAT if use_flats else ABC_NOTES_SHARP
    note = abc_notes[note_idx]

    if octave >= 5:
        # Lowercase for octave 5, add apostrophes for higher
        if note.startswith("^"):
            base = "^" + note[-1].lower()
        elif note.startswith("_"):
            base = "_" + note[-1].lower()
        else:
            base = note[0].lower()
        return base + "'" * (octave - 5)
    elif octave == 4:
        return note
    elif octave == 3:
        return note + ","
    else:
        return note + "," * (4 - octave)


def build_abc_chord(midi_notes, duration="", use_flats=False):
    """Build ABC notation chord from MIDI note numbers."""
    if len(midi_notes) == 1:
        return midi_to_abc_note(midi_notes[0], use_flats) + duration
    abc_notes = [midi_to_abc_note(n, use_flats) for n in midi_notes]
    return "[" + "".join(abc_notes) + "]" + duration


def output_result(abc_notation, description, notes):
    """Output result as JSON with ABC notation for browser-side ABCJS playback."""
    return {
        "success": True,
        "abc": abc_notation,
        "description": description,
        "notes": notes,
    }


# --- Input Validation ---

def validate_octave(params):
    """Validate and return octave (default 4, range 1-7)."""
    octave = int(params.get("octave", 4))
    return max(1, min(7, octave))


def validate_tempo(params):
    """Validate and return tempo (default 120, range 20-300)."""
    tempo = int(params.get("tempo", 120))
    return max(20, min(300, tempo))


def parse_melody(melody_str, max_notes=64):
    """Parse melody string like 'E5:1 D5:0.5 C5:0.5 R:1' into [(midi_num|None, duration), ...].

    Returns list of (midi_note_or_None_for_rest, duration_in_beats) or None on failure.
    """
    if not melody_str or not isinstance(melody_str, str):
        return None

    notes = []
    for token in melody_str.strip().split():
        parts = token.split(":")
        if len(parts) != 2:
            continue
        note_str, dur_str = parts
        try:
            duration = float(dur_str)
            if duration <= 0 or duration > 16:
                continue
            if note_str.upper() == "R":
                notes.append((None, duration))
            else:
                midi_num = note_name_to_midi(note_str)
                notes.append((midi_num, duration))
        except (ValueError, IndexError):
            continue

        if len(notes) >= max_notes:
            break

    return notes if notes else None


# --- Action Handlers ---

def action_chord(params):
    """Generate a single chord."""
    chord_name = params.get("chord_name")
    if not chord_name:
        return {"success": False, "error": "chord_name is required"}

    voicing = params.get("voicing", "root")
    instrument = params.get("instrument", "piano")
    octave = validate_octave(params)

    root_pc, root_name, intervals, quality, bass_pc = parse_chord_with_bass(chord_name)
    use_flats = root_pc in FLAT_ROOTS
    intervals = apply_voicing(intervals, voicing)

    base_midi = root_pc + (octave + 1) * 12
    midi_notes = [base_midi + iv for iv in intervals]

    # Add slash bass note below the chord
    if bass_pc is not None:
        bass_midi = bass_pc + octave * 12
        while bass_midi >= min(midi_notes):
            bass_midi -= 12
        midi_notes = sorted([bass_midi] + midi_notes)

    note_names = [midi_to_note_name(n) for n in midi_notes]

    # Build ABC
    voicing_label = f", {voicing} position" if voicing and voicing != "root" else ", root position"
    title = chord_name  # Preserve slash notation in title
    abc_chord_str = build_abc_chord(midi_notes, "4", use_flats)
    gm_prog = GM_INSTRUMENTS.get(instrument, 0)
    abc = f"X:1\nT:{title}\nM:4/4\nL:1/8\nQ:1/4=120\nK:C clef=treble\n%%MIDI program {gm_prog}\n| {abc_chord_str} z4 |"

    description = f"{title} chord{voicing_label}, {instrument}"
    return output_result(abc, description, note_names)


def action_scale(params):
    """Generate a scale."""
    root = params.get("root")
    scale_name = params.get("scale_name")
    if not root or not scale_name:
        return {"success": False, "error": "root and scale_name are required"}

    octave = validate_octave(params)
    direction = params.get("direction", "ascending")
    instrument = params.get("instrument", "piano")

    root_pc, root_name = parse_root(root)
    use_flats = root_pc in FLAT_ROOTS
    scale_key = scale_name.lower().replace(" ", "_").replace("-", "_")
    intervals = SCALE_TYPES.get(scale_key)
    if intervals is None:
        available = ", ".join(sorted(SCALE_TYPES.keys()))
        return {"success": False, "error": f"Unknown scale: {scale_name}. Available: {available}"}

    base_midi = root_pc + (octave + 1) * 12
    scale_notes = [base_midi + iv for iv in intervals] + [base_midi + 12]

    if direction == "descending":
        scale_notes = list(reversed(scale_notes))
    elif direction == "both":
        scale_notes = scale_notes + list(reversed(scale_notes[:-1]))

    note_names = [midi_to_note_name(n) for n in scale_notes]

    # Build ABC
    abc_notes = " ".join([midi_to_abc_note(n, use_flats) for n in scale_notes])
    title = f"{root_name} {scale_name}"
    gm_prog = GM_INSTRUMENTS.get(instrument, 0)
    abc = f"X:1\nT:{title}\nM:4/4\nL:1/4\nQ:1/4=120\nK:C clef=treble\n%%MIDI program {gm_prog}\n{abc_notes} |"

    description = f"{title} scale, {direction}, {instrument}"
    return output_result(abc, description, note_names)


def action_interval(params):
    """Generate an interval (two notes)."""
    root = params.get("root")
    interval = params.get("interval")
    if not root or not interval:
        return {"success": False, "error": "root and interval are required"}

    octave = validate_octave(params)
    instrument = params.get("instrument", "piano")

    root_pc, root_name = parse_root(root)
    use_flats = root_pc in FLAT_ROOTS
    interval_key = interval.lower().replace(" ", "_").replace("-", "_")
    semitones = INTERVAL_TYPES.get(interval_key)
    if semitones is None:
        available = ", ".join(sorted(INTERVAL_TYPES.keys()))
        return {"success": False, "error": f"Unknown interval: {interval}. Available: {available}"}

    base_midi = root_pc + (octave + 1) * 12
    midi_notes = [base_midi, base_midi + semitones]
    note_names = [midi_to_note_name(n) for n in midi_notes]

    # Build ABC — sequential then simultaneous
    abc_n1 = midi_to_abc_note(midi_notes[0], use_flats)
    abc_n2 = midi_to_abc_note(midi_notes[1], use_flats)
    abc_chord = build_abc_chord(midi_notes, "4", use_flats)
    title = f"{root_name} {interval}"
    gm_prog = GM_INSTRUMENTS.get(instrument, 0)
    abc = f"X:1\nT:{title}\nM:4/4\nL:1/8\nQ:1/4=120\nK:C clef=treble\n%%MIDI program {gm_prog}\n| {abc_n1}2 {abc_n2}2 z {abc_chord} z |"

    description = f"{interval} from {root_name}, {instrument}"
    return output_result(abc, description, note_names)


def _format_bars(bar_list, bars_per_line=4):
    """Join bars with line breaks every bars_per_line bars."""
    result_lines = []
    for i in range(0, len(bar_list), bars_per_line):
        chunk = bar_list[i:i + bars_per_line]
        result_lines.append("|" + " |".join(chunk) + " |")
    return "\n".join(result_lines)


def action_progression(params):
    """Play a chord progression."""
    chords = params.get("chords")
    if not chords:
        return {"success": False, "error": "chords is required (list of chord names)"}

    if isinstance(chords, str):
        chords = [c.strip() for c in chords.split(",")]

    tempo = validate_tempo(params)
    instrument = params.get("instrument", "piano")
    bars_per_chord = max(1, min(4, int(params.get("bars_per_chord", 1))))
    octave = validate_octave(params)

    chord_data = []
    for chord_name in chords:
        try:
            root_pc, root_name, intervals, quality, bass_pc = parse_chord_with_bass(chord_name)
            base_midi = root_pc + (octave + 1) * 12
            midi_notes = [base_midi + iv for iv in intervals]
            # Add slash bass note below the chord
            if bass_pc is not None:
                bass_midi = bass_pc + octave * 12
                while bass_midi >= min(midi_notes):
                    bass_midi -= 12
                midi_notes = sorted([bass_midi] + midi_notes)
            chord_data.append({
                "name": chord_name,
                "root_pc": root_pc,
                "root_name": root_name,
                "quality": quality,
                "midi_notes": midi_notes,
                "note_names": [midi_to_note_name(n) for n in midi_notes],
            })
        except ValueError as e:
            return {"success": False, "error": f"Invalid chord '{chord_name}': {e}"}

    # Determine enharmonic spelling from key analysis
    chord_seq = [{"root_pc": cd["root_pc"], "quality": cd["quality"]} for cd in chord_data]
    key_pcs = _detect_key(chord_seq)
    use_flats = key_pcs[0] in FLAT_ROOTS

    # Build ABC with line breaks every 4 bars
    gm_prog = GM_INSTRUMENTS.get(instrument, 0)
    abc_bars = []
    for cd in chord_data:
        abc_chord = build_abc_chord(cd["midi_notes"], "2", use_flats)
        bar_content = f' "{cd["name"]}"{abc_chord} {abc_chord} {abc_chord} {abc_chord}'
        for _ in range(bars_per_chord):
            abc_bars.append(bar_content)

    progression_str = " - ".join(chords)
    title = f"Progression: {progression_str}"
    header = f"X:1\nT:{title}\nM:4/4\nL:1/8\nQ:1/4={tempo}\nK:C clef=treble\n%%MIDI program {gm_prog}"
    abc = header + "\n" + _format_bars(abc_bars)

    all_notes = []
    for cd in chord_data:
        all_notes.extend(cd["note_names"])

    description = f"Chord progression: {progression_str}, tempo={tempo}, {instrument}"
    return output_result(abc, description, all_notes)


def _chord_pattern(voiced_notes, style, chord_instrument="piano", use_flats=False, root_pc=None):
    """Return a bar of chord voicing with style-appropriate rhythm (L:1/8, 8 units/bar).

    Guitar instruments use arpeggiated patterns; keyboard instruments use block chords.
    root_pc is needed for rock power chords (root + 5th from actual chord root).
    """
    abc_chord = build_abc_chord(voiced_notes, "", use_flats)
    is_guitar = "guitar" in chord_instrument

    if is_guitar:
        # Convert voiced notes to sorted ABC note names
        notes = sorted(voiced_notes)
        n = len(notes)
        abc_n = [midi_to_abc_note(m, use_flats) for m in notes]

        if style == "bossa":
            # Bossa nova: syncopated arpeggio (João Gilberto-inspired)
            if n >= 4:
                # 4-note: low3 top mid_high mid_low top2 (3+1+1+1+2=8)
                return f" {abc_n[0]}3 {abc_n[3]} {abc_n[2]} {abc_n[1]} {abc_n[3]}2"
            elif n >= 3:
                # 3-note: low3 high mid3 high (3+1+3+1=8)
                return f" {abc_n[0]}3 {abc_n[2]} {abc_n[1]}3 {abc_n[2]}"
            else:
                return f" {abc_n[0]}3 {abc_n[-1]} {abc_n[0]}3 {abc_n[-1]}"
        elif style == "rock":
            # Rock: power chord (root + 5th only, no 3rd)
            if root_pc is not None:
                root_candidates = [m for m in notes if m % 12 == root_pc]
                root_midi = root_candidates[0] if root_candidates else notes[0]
            else:
                root_midi = notes[0]
            power = build_abc_chord([root_midi, root_midi + 7], "", use_flats)
            return f" {power}2 z {power} {power}2 z2"
        elif style == "ballad":
            # Ballad: Travis-style fingerpicking
            if n >= 4:
                # thumb-finger-thumb-finger cycle (1*8=8)
                return f" {abc_n[0]} {abc_n[2]} {abc_n[1]} {abc_n[3]} {abc_n[0]} {abc_n[2]} {abc_n[1]} {abc_n[3]}"
            elif n >= 3:
                # low-mid-high-mid cycle (1*8=8)
                return f" {abc_n[0]} {abc_n[1]} {abc_n[2]} {abc_n[1]} {abc_n[0]} {abc_n[1]} {abc_n[2]} {abc_n[1]}"
            else:
                return f" {abc_n[0]} {abc_n[-1]} {abc_n[0]} {abc_n[-1]} {abc_n[0]} {abc_n[-1]} {abc_n[0]} {abc_n[-1]}"
        elif style == "jazz":
            # Jazz guitar: Freddie Green-style comp with syncopation
            return f" z2 {abc_chord}3 z {abc_chord}2"
        else:  # pop
            return f" {abc_chord}4 z2 {abc_chord}2"

    # Keyboard instruments: block chords with style rhythm
    if style == "bossa":
        return f" {abc_chord}3 z {abc_chord}2 z2"
    elif style == "jazz":
        return f" z2 {abc_chord}3 z {abc_chord}2"
    elif style == "ballad":
        return f" {abc_chord}4 z2 {abc_chord}2"
    elif style == "rock":
        return f" {abc_chord}2 z {abc_chord} {abc_chord}2 z2"
    else:  # pop
        return f" {abc_chord}4 z2 {abc_chord}2"


def _bass_pattern(bass_note_midi, style, quality="", use_flats=False, next_bass_midi=None):
    """Return a bar of bass with style-appropriate rhythm (L:1/8, 8 units/bar).

    Jazz uses walking bass with chromatic approach to the next chord root.
    Bossa/ballad use sparse 2-beat feel. Rock drives with root-fifth-octave.
    """
    root = midi_to_abc_note(bass_note_midi, use_flats)
    fifth = midi_to_abc_note(bass_note_midi + 7, use_flats)
    intervals = CHORD_TYPES.get(quality, [0, 4, 7])
    color_interval = intervals[1] if len(intervals) >= 2 else 4
    color_tone = midi_to_abc_note(bass_note_midi + color_interval, use_flats)
    octave_up = midi_to_abc_note(bass_note_midi + 12, use_flats)
    if style == "bossa":
        # 2-beat feel: root on beat 1, fifth on beat 3
        return f" {root}4 {fifth}4"
    elif style == "jazz":
        # Walking bass: root → chord tone → 5th → chromatic approach to next root
        if next_bass_midi is not None:
            # Find approach note (half step below next root) closest to the fifth
            fifth_midi = bass_note_midi + 7
            approach_pc = (next_bass_midi - 1) % 12
            approach_base = approach_pc + (fifth_midi // 12) * 12
            # Pick octave closest to the fifth within bass range (A1=33 to C4=60)
            candidates = [approach_base + ofs for ofs in (-12, 0, 12)
                          if 33 <= approach_base + ofs <= 60]
            if not candidates:
                candidates = [approach_base]
            approach_midi = min(candidates, key=lambda c: abs(c - fifth_midi))
            approach = midi_to_abc_note(approach_midi, use_flats)
            return f" {root}2 {color_tone}2 {fifth}2 {approach}2"
        else:
            return f" {root}2 {color_tone}2 {fifth}2 {octave_up}2"
    elif style == "ballad":
        # Sparse half notes: root and fifth
        return f" {root}4 {fifth}4"
    elif style == "rock":
        # Driving root + fifth with octave push
        return f" {root}2 {root}2 {fifth}2 {octave_up}2"
    else:  # pop
        return f" {root}2 {root}2 {fifth}2 {root}2"


def _voice_lead(prev_notes, root_pc, intervals, base_octave):
    """Find the chord inversion that minimizes voice movement from prev_notes."""
    base = root_pc + (base_octave + 1) * 12
    root_pos = sorted(base + iv for iv in intervals)

    if prev_notes is None:
        return root_pos

    prev_sorted = sorted(prev_notes)
    n = len(intervals)
    best = root_pos
    best_cost = float('inf')

    for inv in range(n):
        # Create inversion: rotate intervals, raise lower ones by octave
        rotated = []
        for i in range(n):
            iv = intervals[(i + inv) % n]
            if (i + inv) % n < inv:
                iv += 12
            rotated.append(iv)

        # Try base octave and ±1 to find closest voicing
        for oct_shift in [-12, 0, 12]:
            candidate = sorted(base + iv + oct_shift for iv in rotated)
            if len(candidate) == len(prev_sorted):
                cost = sum(abs(c - p) for c, p in zip(candidate, prev_sorted))
            else:
                center = sum(prev_sorted) / len(prev_sorted)
                cost = sum(abs(c - center) for c in candidate)
            if cost < best_cost:
                best_cost = cost
                best = candidate

    return best


def _detect_key(chord_seq):
    """Detect the most likely major key by analyzing all chord tones.

    Uses a circle-of-fifths approach: scores each of the 12 major keys by
    counting how many of the progression's pitch classes are diatonic.
    Tiebreaker: prefer keys that contain more of the chord roots.
    """
    major_intervals = [0, 2, 4, 5, 7, 9, 11]

    # Collect unique pitch classes from all chords
    all_pcs = set()
    chord_roots = [cd["root_pc"] for cd in chord_seq]
    for cd in chord_seq:
        root = cd["root_pc"]
        quality = cd.get("quality", "")
        intervals = CHORD_TYPES.get(quality, CHORD_TYPES.get("", [0, 4, 7]))
        for iv in intervals:
            all_pcs.add((root + iv) % 12)

    # Score each candidate key: (diatonic_tone_count, diatonic_root_count)
    best_key = 0
    best_score = (-1, -1)
    for key_root in range(12):
        key_pcs = set((key_root + iv) % 12 for iv in major_intervals)
        tone_score = len(all_pcs & key_pcs)
        root_score = sum(1 for r in chord_roots if r in key_pcs)
        score = (tone_score, root_score)
        if score > best_score:
            best_score = score
            best_key = key_root

    return [(best_key + iv) % 12 for iv in major_intervals]


def action_backing(params):
    """Generate a backing track with multiple instrument layers using multi-voice ABC."""
    chords = params.get("chords")
    if not chords:
        return {"success": False, "error": "chords is required (list of chord names)"}

    if isinstance(chords, str):
        chords = [c.strip() for c in chords.split(",")]

    tempo = validate_tempo(params)
    style = params.get("style", "pop")
    bars = max(1, min(64, int(params.get("bars", len(chords)))))
    instruments = params.get("instruments", {})
    octave = validate_octave(params)

    # Default instruments by style
    style_defaults = {
        "pop":   {"chords": "piano", "bass": "bass"},
        "jazz":  {"chords": "piano", "bass": "bass"},
        "rock":  {"chords": "electric_guitar", "bass": "electric_bass"},
        "bossa": {"chords": "acoustic_guitar", "bass": "bass"},
        "ballad": {"chords": "piano", "bass": "bass"},
    }
    defaults = style_defaults.get(style, style_defaults["pop"])
    chord_instrument = instruments.get("chords", defaults.get("chords", "piano"))
    bass_instrument = instruments.get("bass", defaults.get("bass", "bass"))

    # Parse chords (with optional slash bass)
    chord_data = []
    for chord_name in chords:
        try:
            root_pc, root_name, intervals, quality, bass_pc = parse_chord_with_bass(chord_name)
            base_midi = root_pc + (octave + 1) * 12
            midi_notes = [base_midi + iv for iv in intervals]
            # Slash bass overrides the default root bass note
            bass_note = (bass_pc if bass_pc is not None else root_pc) + octave * 12
            chord_data.append({
                "name": chord_name,
                "root_name": root_name,
                "root_pc": root_pc,
                "quality": quality,
                "intervals": intervals,
                "midi_notes": midi_notes,
                "bass_note": bass_note,
                "note_names": [midi_to_note_name(n) for n in midi_notes],
            })
        except ValueError as e:
            return {"success": False, "error": f"Invalid chord '{chord_name}': {e}"}

    # Extend chord sequence to fill requested bars (copy dicts for independent voicing)
    original_chords = list(chord_data)
    while len(chord_data) < bars:
        chord_data.extend(dict(cd) for cd in original_chords[:bars - len(chord_data)])
    chord_data = chord_data[:bars]

    # Apply voice leading to smooth chord transitions
    prev_voicing = None
    for cd in chord_data:
        voiced = _voice_lead(prev_voicing, cd["root_pc"], cd["intervals"], octave)
        cd["voiced_notes"] = voiced
        prev_voicing = voiced

    # Determine enharmonic spelling from key analysis
    key_seq = [{"root_pc": cd["root_pc"], "quality": cd["quality"]} for cd in chord_data]
    detected_key = _detect_key(key_seq)
    use_flats = detected_key[0] in FLAT_ROOTS

    # Parse optional melody (D-mode: LLM-specified notes)
    melody_data = parse_melody(params.get("melody"))

    # Algorithmic melody generation: if no explicit melody but melody_style is given
    if melody_data is None and params.get("melody_style"):
        try:
            from melody_generator import generate_melody, MELODY_STYLE_PARAMS
            pc_map = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
                      "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
            chord_seq = []
            for cd in chord_data:
                root_pc = pc_map.get(cd["root_name"], 0)
                chord_seq.append({
                    "root_pc": root_pc,
                    "quality": cd["quality"],
                    "name": cd["name"],
                })
            melody_seed = params.get("melody_seed")
            if melody_seed is not None:
                melody_seed = int(melody_seed)
            # For non-jazz styles, detect parent key using circle-of-fifths
            # chord analysis (prevents non-diatonic notes like F# over Am in C)
            key_pcs = None
            if style != "jazz" and chord_seq:
                key_pcs = _detect_key(chord_seq)
            melody_data = generate_melody(
                chord_seq, params["melody_style"], bars, melody_seed,
                diatonic_pcs=key_pcs
            )
            if not params.get("melody_instrument"):
                style_params = MELODY_STYLE_PARAMS.get(params["melody_style"], {})
                params["melody_instrument"] = style_params.get("default_instrument", "vibraphone")
        except ImportError:
            pass  # melody_generator not available; proceed without melody

    melody_instrument = params.get("melody_instrument", "vibraphone")
    has_melody = melody_data is not None

    # GM program numbers for each voice
    chord_prog = GM_INSTRUMENTS.get(chord_instrument, 0)
    bass_prog = GM_INSTRUMENTS.get(bass_instrument, 33)
    melody_prog = GM_INSTRUMENTS.get(melody_instrument, 11)

    progression_str = " - ".join([cd["name"] for cd in chord_data[:len(chords)]])

    # Build multi-voice ABC using interleaved layout per system (4 bars per line).
    # Interleaved layout: V:1 bars | V:2 bars | V:1 bars | V:2 bars ...
    # This is more reliable for ABCJS multi-voice rendering than block layout.
    lines = []
    lines.append("X:1")
    if has_melody:
        title = f"Backing: {progression_str} ({style}) + melody"
    else:
        title = f"Backing Track: {progression_str} ({style})"
    lines.append(f"T:{title}")
    lines.append("M:4/4")
    lines.append("L:1/8")
    lines.append(f"Q:1/4={tempo}")
    lines.append("K:C")

    # --- Prepare bars for each voice ---

    # Melody bars (if present)
    melody_bars = []
    if has_melody:
        abc_melody_tokens = []
        for midi_num, duration in melody_data:
            abc_dur = int(round(duration * 2))
            if abc_dur < 1:
                abc_dur = 1
            dur_str = str(abc_dur) if abc_dur != 1 else ""
            if midi_num is None:
                abc_melody_tokens.append(f"z{dur_str}")
            else:
                abc_melody_tokens.append(f"{midi_to_abc_note(midi_num, use_flats)}{dur_str}")

        token_idx = 0
        for cd in chord_data:
            bar_tokens = []
            bar_units = 0
            while token_idx < len(abc_melody_tokens):
                tok = abc_melody_tokens[token_idx]
                # Parse duration from token
                dur_digits = ""
                for ch in reversed(tok):
                    if ch.isdigit():
                        dur_digits = ch + dur_digits
                    else:
                        break
                units = int(dur_digits) if dur_digits else 1
                if bar_units + units > 8:
                    break  # Would overflow bar
                bar_tokens.append(tok)
                bar_units += units
                token_idx += 1
            # Fill remaining beats with rest
            remaining = 8 - bar_units
            if remaining > 0 and bar_tokens:
                bar_tokens.append(f"z{remaining}" if remaining > 1 else "z")
            if bar_tokens:
                melody_bars.append(f' "{cd["name"]}"' + " ".join(bar_tokens))
            else:
                melody_bars.append(f' "{cd["name"]}"z8')

    # Chord bars with voice-led voicings and style-appropriate rhythm
    chord_bars = []
    for cd in chord_data:
        pattern = _chord_pattern(cd["voiced_notes"], style, chord_instrument, use_flats,
                                 root_pc=cd["root_pc"])
        if not has_melody:
            pattern = f' "{cd["name"]}"' + pattern.lstrip()
        chord_bars.append(pattern)

    # Bass bars with style-appropriate rhythm (jazz gets next-chord info for walking bass)
    bass_bars = []
    for i, cd in enumerate(chord_data):
        next_bass = chord_data[i + 1]["bass_note"] if i + 1 < len(chord_data) else chord_data[0]["bass_note"]
        bass_bars.append(_bass_pattern(cd["bass_note"], style, quality=cd["quality"],
                                       use_flats=use_flats, next_bass_midi=next_bass))

    # --- Emit interleaved voice blocks, 4 bars per system ---
    bars_per_line = 4
    for start in range(0, len(chord_data), bars_per_line):
        end = min(start + bars_per_line, len(chord_data))
        chunk_size = end - start

        if has_melody:
            # Voice 1: Melody
            mel_chunk = melody_bars[start:end]
            midi_line = f"%%MIDI program {melody_prog}" if start == 0 else ""
            lines.append(f'V:1 clef=treble name="Melody"' if start == 0 else "V:1")
            if midi_line:
                lines.append(midi_line)
            lines.append("|" + " |".join(mel_chunk) + " |")

            # Voice 2: Chords
            ch_chunk = chord_bars[start:end]
            midi_line = f"%%MIDI program {chord_prog}" if start == 0 else ""
            lines.append(f'V:2 clef=treble name="Chords"' if start == 0 else "V:2")
            if midi_line:
                lines.append(midi_line)
            lines.append("|" + " |".join(ch_chunk) + " |")

            # Voice 3: Bass
            ba_chunk = bass_bars[start:end]
            midi_line = f"%%MIDI program {bass_prog}" if start == 0 else ""
            lines.append(f'V:3 clef=bass name="Bass"' if start == 0 else "V:3")
            if midi_line:
                lines.append(midi_line)
            lines.append("|" + " |".join(ba_chunk) + " |")
        else:
            # Voice 1: Chords
            ch_chunk = chord_bars[start:end]
            midi_line = f"%%MIDI program {chord_prog}" if start == 0 else ""
            lines.append(f'V:1 clef=treble name="Chords"' if start == 0 else "V:1")
            if midi_line:
                lines.append(midi_line)
            lines.append("|" + " |".join(ch_chunk) + " |")

            # Voice 2: Bass
            ba_chunk = bass_bars[start:end]
            midi_line = f"%%MIDI program {bass_prog}" if start == 0 else ""
            lines.append(f'V:2 clef=bass name="Bass"' if start == 0 else "V:2")
            if midi_line:
                lines.append(midi_line)
            lines.append("|" + " |".join(ba_chunk) + " |")

    abc = "\n".join(lines)

    all_notes = []
    for cd in chord_data[:len(chords)]:
        all_notes.extend(cd["note_names"])

    desc_parts = [f"Backing track: {progression_str}", f"style={style}", f"tempo={tempo}",
                  f"chords={chord_instrument}", f"bass={bass_instrument}"]
    if has_melody:
        desc_parts.append(f"melody={melody_instrument}")
    description = ", ".join(desc_parts)
    return output_result(abc, description, all_notes)


# --- Main ---

ACTIONS = {
    "chord": action_chord,
    "scale": action_scale,
    "interval": action_interval,
    "progression": action_progression,
    "backing": action_backing,
}


def main():
    parser = argparse.ArgumentParser(description="Music Generator")
    parser.add_argument("action", choices=ACTIONS.keys(), help="Action to perform")
    parser.add_argument("--params", required=True, help="JSON parameters")

    args = parser.parse_args()

    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as e:
        print(json.dumps({"success": False, "error": f"Invalid JSON params: {e}"}))
        sys.exit(1)

    try:
        result = ACTIONS[args.action](params)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
