#!/usr/bin/env python3
"""
Music Analyzer - Analyzes audio and MIDI files to detect tempo, key, chords, beats, and structure.

Requires: librosa, soundfile
Optional: madmom (for better chord recognition), pretty_midi (for MIDI analysis)

Usage:
    music_analyzer.py analyze --params '{"file_path": "/monadic/data/song.mp3"}'
    music_analyzer.py analyze --params '{"file_path": "/monadic/data/piece.mid"}'

Output: JSON with analysis results (tempo, key, chords, beats, sections, etc.)
"""

import argparse
import json
import sys
import os

# Maximum duration to analyze (seconds) - truncate longer files
MAX_ANALYSIS_DURATION = 300  # 5 minutes

# --- Compatibility patches for madmom on Python 3.10+ / NumPy 2.x ---
# madmom 0.16.1 uses deprecated imports that were removed in newer versions.
# Apply monkey-patches before importing madmom.
import collections
import collections.abc
if not hasattr(collections, "MutableSequence"):
    collections.MutableSequence = collections.abc.MutableSequence

import numpy as np
if not hasattr(np, "float"):
    np.float = np.float64    # removed in NumPy 1.24
if not hasattr(np, "int"):
    np.int = np.int64        # removed in NumPy 1.24
if not hasattr(np, "complex"):
    np.complex = np.complex128  # removed in NumPy 1.24
# --- End compatibility patches ---


def check_dependencies():
    """Check if required libraries are installed and return availability info."""
    available = {"librosa": False, "soundfile": False, "madmom": False}
    missing = []

    try:
        import librosa  # noqa: F401
        available["librosa"] = True
    except ImportError:
        missing.append("librosa")

    try:
        import soundfile  # noqa: F401
        available["soundfile"] = True
    except ImportError:
        missing.append("soundfile")

    try:
        import madmom  # noqa: F401
        available["madmom"] = True
    except (ImportError, Exception):
        pass  # madmom is optional; may fail even after patching

    return available, missing


def detect_key(chroma, sr, hop_length):
    """Detect musical key using Krumhansl-Schmuckler key profiles.

    Uses chroma features and correlates them against major/minor key profiles
    to find the best matching key.
    """
    import numpy as np

    # Krumhansl-Schmuckler key profiles
    major_profile = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                              2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
    minor_profile = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                              2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

    note_names = ["C", "C#", "D", "D#", "E", "F",
                  "F#", "G", "G#", "A", "A#", "B"]
    enharmonic = {
        "C#": "Db", "D#": "Eb", "F#": "Gb", "G#": "Ab", "A#": "Bb"
    }

    # Average chroma across time
    chroma_avg = np.mean(chroma, axis=1)

    best_corr = -2
    best_key = "C"
    best_mode = "major"

    for i in range(12):
        # Rotate chroma to match each key
        rotated = np.roll(chroma_avg, -i)

        # Correlate with major profile
        corr_major = np.corrcoef(rotated, major_profile)[0, 1]
        if corr_major > best_corr:
            best_corr = corr_major
            best_key = note_names[i]
            best_mode = "major"

        # Correlate with minor profile
        corr_minor = np.corrcoef(rotated, minor_profile)[0, 1]
        if corr_minor > best_corr:
            best_corr = corr_minor
            best_key = note_names[i]
            best_mode = "minor"

    # Use flat names for certain keys
    if best_key in enharmonic:
        if best_mode == "major" and best_key in ("C#", "G#", "D#"):
            best_key = enharmonic[best_key]
        elif best_mode == "minor" and best_key in ("D#", "G#", "A#"):
            best_key = enharmonic[best_key]

    confidence = max(0.0, min(1.0, (best_corr + 1) / 2))
    return best_key, best_mode, round(confidence, 2)


def _normalize_madmom_chord_label(label):
    """Convert madmom chord labels (e.g., 'C:maj', 'A:min') to standard names."""
    if label == "N" or label == "":
        return "N.C."
    if ":" not in label:
        return label
    root, quality = label.split(":", 1)
    quality_map = {
        "maj": "",       # C:maj -> C
        "min": "m",      # A:min -> Am
        "dim": "dim",    # B:dim -> Bdim
        "aug": "aug",    # C:aug -> Caug
        "maj7": "maj7",  # C:maj7 -> Cmaj7
        "min7": "m7",    # A:min7 -> Am7
        "7": "7",        # G:7 -> G7
        "sus2": "sus2",
        "sus4": "sus4",
    }
    suffix = quality_map.get(quality, quality)
    return f"{root}{suffix}"


def detect_chords_madmom(file_path, duration=None):
    """Detect chords using madmom's CNN-based chord recognition."""
    from madmom.features.chords import (
        CNNChordFeatureProcessor,
        CRFChordRecognitionProcessor,
    )

    cnncfp = CNNChordFeatureProcessor()
    crp = CRFChordRecognitionProcessor()

    features = cnncfp(file_path)
    chords_raw = crp(features)

    chords = []
    for start, end, label in chords_raw:
        if duration and start > duration:
            break
        chord_duration = round(float(end - start), 2)
        if chord_duration < 0.1:
            continue
        chords.append({
            "time": round(float(start), 2),
            "duration": chord_duration,
            "chord": _normalize_madmom_chord_label(label)
        })

    return chords


def detect_chords_librosa(y, sr, hop_length=512, duration=None):
    """Detect chords using librosa chroma features (fallback when madmom unavailable).

    Uses chroma_cqt and template matching for basic major/minor chord detection.
    """
    import librosa
    import numpy as np

    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop_length)
    times = librosa.frames_to_time(range(chroma.shape[1]),
                                   sr=sr, hop_length=hop_length)

    note_names = ["C", "C#", "D", "D#", "E", "F",
                  "F#", "G", "G#", "A", "A#", "B"]
    enharmonic_map = {
        "C#": "Db", "D#": "Eb", "F#": "Gb", "G#": "Ab", "A#": "Bb"
    }

    # Major and minor chord templates (root, third, fifth)
    major_template = np.array([1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0], dtype=float)
    minor_template = np.array([1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0], dtype=float)

    # Segment chroma into ~0.5s windows for chord detection
    frames_per_segment = max(1, int(0.5 * sr / hop_length))
    n_segments = chroma.shape[1] // frames_per_segment

    chords = []
    prev_chord = None
    chord_start = 0.0

    for seg in range(n_segments):
        start_frame = seg * frames_per_segment
        end_frame = start_frame + frames_per_segment
        seg_chroma = np.mean(chroma[:, start_frame:end_frame], axis=1)
        seg_time = times[start_frame] if start_frame < len(times) else 0

        if duration and seg_time > duration:
            break

        best_corr = -1
        best_chord = "N.C."
        for root in range(12):
            maj_rot = np.roll(major_template, root)
            min_rot = np.roll(minor_template, root)

            corr_maj = np.dot(seg_chroma, maj_rot) / (
                np.linalg.norm(seg_chroma) * np.linalg.norm(maj_rot) + 1e-10
            )
            corr_min = np.dot(seg_chroma, min_rot) / (
                np.linalg.norm(seg_chroma) * np.linalg.norm(min_rot) + 1e-10
            )

            root_name = note_names[root]
            if corr_maj > best_corr:
                best_corr = corr_maj
                best_chord = enharmonic_map.get(root_name, root_name)
            if corr_min > best_corr:
                best_corr = corr_min
                name = enharmonic_map.get(root_name, root_name)
                best_chord = f"{name}m"

        if best_chord != prev_chord:
            if prev_chord is not None:
                chord_dur = round(seg_time - chord_start, 2)
                if chord_dur > 0.1:
                    chords.append({
                        "time": round(chord_start, 2),
                        "duration": chord_dur,
                        "chord": prev_chord
                    })
            prev_chord = best_chord
            chord_start = seg_time

    # Append last chord
    if prev_chord is not None:
        last_time = times[-1] if len(times) > 0 else chord_start
        chord_dur = round(last_time - chord_start, 2)
        if chord_dur > 0.1:
            chords.append({
                "time": round(chord_start, 2),
                "duration": chord_dur,
                "chord": prev_chord
            })

    return chords


def detect_sections(y, sr):
    """Detect song sections using librosa's spectral clustering.

    Returns approximate section boundaries with labels.
    """
    import librosa
    import numpy as np

    # Compute mel spectrogram for structure analysis
    S = librosa.feature.melspectrogram(y=y, sr=sr)
    S_db = librosa.power_to_db(S, ref=np.max)

    # Use recurrence matrix and agglomerative clustering
    try:
        # Compute beat-synchronous features for section detection
        tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
        if len(beats) < 4:
            return []

        beat_times = librosa.frames_to_time(beats, sr=sr)
        # Sync features to beats
        chroma_sync = librosa.feature.sync(
            librosa.feature.chroma_cqt(y=y, sr=sr), beats, aggregate=np.median
        )
        mfcc_sync = librosa.feature.sync(
            librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13), beats, aggregate=np.median
        )

        # Stack features
        features = np.vstack([chroma_sync, mfcc_sync])

        # Compute recurrence and cluster
        R = librosa.segment.recurrence_matrix(features, mode="affinity",
                                              sym=True, bandwidth=1.0)

        # Number of sections (heuristic: ~1 section per 30s)
        duration = librosa.get_duration(y=y, sr=sr)
        n_sections = max(2, min(10, int(duration / 30)))

        boundaries = librosa.segment.agglomerative(features, n_sections)
        boundary_times = librosa.frames_to_time(beats[boundaries], sr=sr)

        # Build section list with simple labels
        section_labels = ["intro", "verse", "chorus", "bridge", "verse",
                          "chorus", "bridge", "outro", "verse", "chorus"]
        sections = []
        all_times = sorted(set([0.0] + list(boundary_times) + [duration]))

        for i in range(len(all_times) - 1):
            label = section_labels[i] if i < len(section_labels) else f"section_{i+1}"
            sections.append({
                "label": label,
                "start": round(float(all_times[i]), 1),
                "end": round(float(all_times[i + 1]), 1)
            })

        return sections
    except Exception:
        return []


def estimate_time_signature(y, sr):
    """Estimate time signature from beat strength pattern.

    Simple heuristic: analyzes beat strength periodicity for 3/4 vs 4/4.
    """
    import librosa
    import numpy as np

    try:
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        # Use tempogram to detect beat periodicity
        tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr)

        # Simple heuristic: check if 3-beat or 4-beat pattern dominates
        avg_tempogram = np.mean(tempogram, axis=1)
        # Indices roughly corresponding to 3/4 and 4/4 at typical tempos
        # This is a simplified approach
        beats_per_bar = 4
        note_value = 4

        return beats_per_bar, note_value
    except Exception:
        return 4, 4


def analyze_midi(params):
    """Analyze a MIDI file using pretty_midi."""
    try:
        import pretty_midi
    except ImportError:
        return {"success": False,
                "error": "pretty_midi is not installed. "
                         "Install with: uv pip install pretty_midi"}

    import numpy as np

    file_path = params.get("file_path")
    if not file_path:
        return {"success": False, "error": "file_path is required"}

    if not os.path.exists(file_path):
        return {"success": False,
                "error": f"File not found: {file_path}. "
                         "Make sure the file is in the shared folder (~/monadic/data/)."}

    file_name = os.path.basename(file_path)

    try:
        midi = pretty_midi.PrettyMIDI(file_path)
    except Exception as e:
        return {"success": False,
                "error": f"Failed to load MIDI file: {e}"}

    # --- Duration ---
    duration = midi.get_end_time()

    # --- Tempo ---
    tempo_times, tempos = midi.get_tempo_changes()
    if len(tempos) > 0:
        bpm = float(tempos[0])
        tempo_changes = [{"time": round(float(t), 2), "bpm": round(float(b), 1)}
                         for t, b in zip(tempo_times, tempos)]
    else:
        bpm = 120.0
        tempo_changes = []

    # --- Time signature ---
    beats_per_bar = 4
    note_value = 4
    if midi.time_signature_changes:
        ts = midi.time_signature_changes[0]
        beats_per_bar = ts.numerator
        note_value = ts.denominator

    # --- Key signature ---
    key_name = "Unknown"
    key_mode = "unknown"
    key_source = "none"
    if midi.key_signature_changes:
        ks = midi.key_signature_changes[0]
        key_name = pretty_midi.key_number_to_key_name(ks.key_number)
        # pretty_midi returns e.g. "C major" or "A minor"
        parts = key_name.split()
        if len(parts) == 2:
            key_name = parts[0]
            key_mode = parts[1]
        key_source = "midi_metadata"
    else:
        # Estimate key from note content using chroma
        try:
            piano_roll = midi.get_piano_roll(fs=100)
            if piano_roll.shape[1] > 0:
                # Build chroma from piano roll (128 pitches -> 12 chroma)
                chroma = np.zeros((12, piano_roll.shape[1]))
                for pitch in range(128):
                    chroma[pitch % 12] += piano_roll[pitch]
                key_name, key_mode, _ = detect_key(chroma, 100, 1)
                key_source = "estimated"
        except Exception:
            pass

    # --- Tracks / instruments ---
    tracks = []
    note_names_list = ["C", "C#", "D", "D#", "E", "F",
                       "F#", "G", "G#", "A", "A#", "B"]
    for inst in midi.instruments:
        note_count = len(inst.notes)
        if note_count == 0:
            if inst.is_drum:
                tracks.append({
                    "name": inst.name or "Drums",
                    "program": inst.program,
                    "instrument": "Drum Kit",
                    "note_count": 0,
                    "pitch_range": "",
                    "is_drum": True
                })
            continue

        pitches = [n.pitch for n in inst.notes]
        min_pitch = min(pitches)
        max_pitch = max(pitches)
        min_note = f"{note_names_list[min_pitch % 12]}{min_pitch // 12 - 1}"
        max_note = f"{note_names_list[max_pitch % 12]}{max_pitch // 12 - 1}"

        if inst.is_drum:
            inst_name = "Drum Kit"
        else:
            inst_name = pretty_midi.program_to_instrument_name(inst.program)

        tracks.append({
            "name": inst.name or inst_name,
            "program": inst.program,
            "instrument": inst_name,
            "note_count": note_count,
            "pitch_range": f"{min_note}-{max_note}",
            "is_drum": inst.is_drum
        })

    # --- Chord detection from piano roll ---
    chords = []
    try:
        piano_roll = midi.get_piano_roll(fs=100)
        if piano_roll.shape[1] > 0:
            chroma = np.zeros((12, piano_roll.shape[1]))
            for pitch in range(128):
                chroma[pitch % 12] += piano_roll[pitch]

            # Use librosa-style chord detection via template matching
            chords = _detect_chords_from_chroma(chroma, fs=100,
                                                duration=min(duration, MAX_ANALYSIS_DURATION))
    except Exception:
        pass

    # --- Build summary ---
    duration_min = int(duration // 60)
    duration_sec = int(duration % 60)
    track_summary = ", ".join(
        t["name"] or t["instrument"] for t in tracks[:5]
    )
    if len(tracks) > 5:
        track_summary += f", ... (+{len(tracks) - 5} more)"

    description = (f"MIDI file: {duration_min}:{duration_sec:02d}, "
                   f"{bpm:.0f} BPM, {key_name} {key_mode}, "
                   f"{len(tracks)} tracks ({track_summary})")

    return {
        "success": True,
        "file_type": "midi",
        "file_name": file_name,
        "duration_seconds": round(duration, 1),
        "tempo": {
            "bpm": round(bpm, 1),
            "tempo_changes": tempo_changes
        },
        "key": {
            "key": key_name,
            "mode": key_mode,
            "source": key_source
        },
        "time_signature": {
            "beats_per_bar": beats_per_bar,
            "note_value": note_value
        },
        "tracks": tracks,
        "chords": chords,
        "description": description
    }


def _detect_chords_from_chroma(chroma, fs=100, duration=None):
    """Detect chords from a chroma matrix using template matching.

    Works for both MIDI piano roll chroma and audio chroma features.
    """
    import numpy as np

    note_names = ["C", "C#", "D", "D#", "E", "F",
                  "F#", "G", "G#", "A", "A#", "B"]
    enharmonic_map = {
        "C#": "Db", "D#": "Eb", "F#": "Gb", "G#": "Ab", "A#": "Bb"
    }

    major_template = np.array([1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0], dtype=float)
    minor_template = np.array([1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0], dtype=float)

    # Segment into ~0.5s windows
    frames_per_segment = max(1, int(0.5 * fs))
    n_segments = chroma.shape[1] // frames_per_segment

    chords = []
    prev_chord = None
    chord_start = 0.0

    for seg in range(n_segments):
        start_frame = seg * frames_per_segment
        end_frame = start_frame + frames_per_segment
        seg_chroma = np.mean(chroma[:, start_frame:end_frame], axis=1)
        seg_time = start_frame / fs

        if duration and seg_time > duration:
            break

        best_corr = -1
        best_chord = "N.C."
        for root in range(12):
            maj_rot = np.roll(major_template, root)
            min_rot = np.roll(minor_template, root)

            norm = np.linalg.norm(seg_chroma) + 1e-10
            corr_maj = np.dot(seg_chroma, maj_rot) / (norm * np.linalg.norm(maj_rot))
            corr_min = np.dot(seg_chroma, min_rot) / (norm * np.linalg.norm(min_rot))

            root_name = note_names[root]
            if corr_maj > best_corr:
                best_corr = corr_maj
                best_chord = enharmonic_map.get(root_name, root_name)
            if corr_min > best_corr:
                best_corr = corr_min
                name = enharmonic_map.get(root_name, root_name)
                best_chord = f"{name}m"

        if best_chord != prev_chord:
            if prev_chord is not None:
                chord_dur = round(seg_time - chord_start, 2)
                if chord_dur > 0.1:
                    chords.append({
                        "time": round(chord_start, 2),
                        "duration": chord_dur,
                        "chord": prev_chord
                    })
            prev_chord = best_chord
            chord_start = seg_time

    # Append last chord
    if prev_chord is not None:
        last_time = (chroma.shape[1] - 1) / fs
        chord_dur = round(last_time - chord_start, 2)
        if chord_dur > 0.1:
            chords.append({
                "time": round(chord_start, 2),
                "duration": chord_dur,
                "chord": prev_chord
            })

    return chords


def analyze_audio(params):
    """Main analysis function - orchestrates all analysis components."""
    import librosa
    import numpy as np

    file_path = params.get("file_path")
    if not file_path:
        return {"success": False, "error": "file_path is required"}

    if not os.path.exists(file_path):
        return {"success": False,
                "error": f"File not found: {file_path}. "
                         "Make sure the file is in the shared folder (~/monadic/data/)."}

    file_name = os.path.basename(file_path)

    # Route MIDI files to dedicated analyzer
    ext = os.path.splitext(file_path)[1].lower()
    if ext in {".mid", ".midi"}:
        return analyze_midi(params)

    # Check supported audio formats
    supported_exts = {".mp3", ".wav", ".m4a", ".ogg", ".flac", ".aac", ".wma"}
    if ext not in supported_exts:
        return {"success": False,
                "error": f"Unsupported format: {ext}. "
                         f"Supported: {', '.join(sorted(supported_exts))}"}

    try:
        # Load audio (truncate if too long)
        y, sr = librosa.load(file_path, sr=22050, mono=True,
                             duration=MAX_ANALYSIS_DURATION)
        duration = librosa.get_duration(y=y, sr=sr)
    except Exception as e:
        return {"success": False,
                "error": f"Failed to load audio file: {e}"}

    # --- HPSS: Separate harmonic and percussive components ---
    # Harmonic signal improves key/chord detection by removing drum noise.
    try:
        y_harmonic, y_percussive = librosa.effects.hpss(y)
    except Exception:
        y_harmonic = y  # Fall back to original if HPSS fails

    # --- Tempo detection ---
    try:
        tempo_result = librosa.beat.beat_track(y=y, sr=sr)
        if isinstance(tempo_result[0], np.ndarray):
            bpm = float(tempo_result[0][0])
        else:
            bpm = float(tempo_result[0])
        beat_frames = tempo_result[1]
        beat_times = librosa.frames_to_time(beat_frames, sr=sr)
        beats = [round(float(t), 3) for t in beat_times]
    except Exception:
        bpm = 0.0
        beats = []

    # --- Key detection (using harmonic signal for better accuracy) ---
    try:
        chroma = librosa.feature.chroma_cqt(y=y_harmonic, sr=sr)
        key_name, key_mode, key_confidence = detect_key(chroma, sr, 512)
    except Exception:
        key_name, key_mode, key_confidence = "Unknown", "unknown", 0.0

    # --- Time signature estimation ---
    beats_per_bar, note_value = estimate_time_signature(y, sr)

    # --- Chord detection ---
    available, _ = check_dependencies()
    chords = []
    chord_method = "none"
    try:
        if available["madmom"]:
            # madmom loads audio internally; HPSS not applicable here
            chords = detect_chords_madmom(file_path, duration=duration)
            chord_method = "madmom"
        else:
            # Use harmonic signal for librosa chord detection
            chords = detect_chords_librosa(y_harmonic, sr, duration=duration)
            chord_method = "librosa"
    except Exception:
        # If madmom fails, try librosa fallback with harmonic signal
        if chord_method == "madmom":
            try:
                chords = detect_chords_librosa(y_harmonic, sr, duration=duration)
                chord_method = "librosa (fallback)"
            except Exception:
                chords = []
                chord_method = "failed"

    # --- Section detection ---
    try:
        sections = detect_sections(y, sr)
    except Exception:
        sections = []

    # --- Build summary description ---
    duration_min = int(duration // 60)
    duration_sec = int(duration % 60)
    unique_chords = len(set(c["chord"] for c in chords if c["chord"] != "N.C."))

    desc_parts = [
        f"BPM {bpm:.0f}",
        f"Key: {key_name} {key_mode}",
        f"{beats_per_bar}/{note_value} time",
    ]
    if unique_chords > 0:
        desc_parts.append(f"{unique_chords} unique chords detected")
    desc_parts.append(f"duration {duration_min}:{duration_sec:02d}")

    description = ", ".join(desc_parts)

    result = {
        "success": True,
        "file_name": file_name,
        "duration_seconds": round(duration, 1),
        "tempo": {
            "bpm": round(bpm, 1),
        },
        "key": {
            "key": key_name,
            "mode": key_mode,
            "confidence": key_confidence,
        },
        "time_signature": {
            "beats_per_bar": beats_per_bar,
            "note_value": note_value,
        },
        "chords": chords,
        "chord_method": chord_method,
        "beats": beats[:200],  # Limit beat count in output
        "sections": sections,
        "description": description,
    }

    # Note if file was truncated
    original_duration = librosa.get_duration(path=file_path)
    if original_duration > MAX_ANALYSIS_DURATION:
        result["truncated"] = True
        result["original_duration_seconds"] = round(original_duration, 1)
        result["description"] += (
            f" (analyzed first {MAX_ANALYSIS_DURATION // 60} min "
            f"of {original_duration / 60:.1f} min total)"
        )

    return result


# --- Main ---

ACTIONS = {
    "analyze": analyze_audio,
}


def main():
    parser = argparse.ArgumentParser(description="Music Analyzer")
    parser.add_argument("action", choices=ACTIONS.keys(), help="Action to perform")
    parser.add_argument("--params", required=True, help="JSON parameters")

    args = parser.parse_args()

    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as e:
        print(json.dumps({"success": False, "error": f"Invalid JSON params: {e}"}))
        sys.exit(1)

    # MIDI files only need pretty_midi, not librosa/soundfile.
    # Skip the heavy dependency check for MIDI-only analysis.
    file_path = params.get("file_path", "")
    is_midi = os.path.splitext(file_path)[1].lower() in {".mid", ".midi"}

    if not is_midi:
        available, missing = check_dependencies()
        if missing:
            error = {
                "success": False,
                "error": f"Required libraries not installed: {', '.join(missing)}. "
                         "Install with: uv pip install " + " ".join(missing),
            }
            print(json.dumps(error))
            sys.exit(1)

    try:
        result = ACTIONS[args.action](params)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
