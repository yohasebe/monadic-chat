#!/usr/bin/env python
"""Find speech in a video's audio and cut it into bounded segments for transcription.

Writes two files into the output directory:
  audio_24k.pcm   mono s16le at 24 kHz, sample 0 = the first video frame
  segments.json   segment boundaries in samples of that PCM (no API calls are made)
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys

import numpy as np

RATE = 24000
DETECT_RATE = 16000
CHUNK = 512                      # Silero input at 16 kHz (32 ms)
CONTEXT = 64                     # samples carried over between Silero chunks
STEP = CHUNK * RATE // DETECT_RATE  # one detector frame in output samples (768)
ON, OFF = 0.5, 0.35              # hysteresis on the speech probability
MERGE_GAP = RATE // 2            # pauses shorter than 500 ms stay inside one segment
MARGIN = RATE // 5               # 200 ms kept before and after detected speech
MAX_SAMPLES = 30 * RATE          # 30 s per segment, margins included
SEARCH_FROM = 25 * RATE          # start looking for a cut 25 s into a long segment
MIN_PAUSE_FRAMES = 5             # 160 ms of low speech probability counts as a pause
DEFAULT_MODEL = "/monadic/models/silero_vad.onnx"
POLICY = "bounded_segments_v1"


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def probe(video_path):
    """Return (origin seconds, duration seconds, has_audio) on the video's own clock."""
    first = json.loads(run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-read_intervals", "%+#1",
                            "-show_frames", "-show_entries", "frame=best_effort_timestamp_time",
                            "-of", "json", video_path])).get("frames", [])
    if not first or first[0].get("best_effort_timestamp_time") in (None, "N/A"):
        raise ValueError("Video has no valid presentation timestamps")
    origin = float(first[0]["best_effort_timestamp_time"])
    info = json.loads(run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
                           "-of", "json", video_path]))
    duration = float(info.get("format", {}).get("duration") or 0)
    if duration <= 0:
        raise ValueError("Video has no duration")
    format_start = float(json.loads(run(["ffprobe", "-v", "error", "-show_entries", "format=start_time",
                                         "-of", "json", video_path])).get("format", {}).get("start_time") or 0)
    has_audio = any(s.get("codec_type") == "audio" for s in info.get("streams", []))
    return origin, duration - (origin - format_start), has_audio


def normalize_audio(video_path, pcm_path, origin_s, total):
    """Decode the first audio track to exactly `total` samples aligned to the first video frame."""
    flt = (f"asetpts=PTS-{origin_s:.6f}/TB,aresample={RATE}:async=1:first_pts=0,"
           f"aformat=sample_fmts=s16:channel_layouts=mono,apad=whole_len={total},atrim=end_sample={total}")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-copyts", "-i", video_path, "-map", "0:a:0", "-vn",
                    "-af", flt, "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", "-f", "s16le", pcm_path],
                   capture_output=True, text=True, check=True)


def speech_probabilities(pcm_path, model_path):
    """Silero probabilities per 32 ms frame, streamed so memory does not grow with the audio length."""
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(model_path, sess_options=options, providers=["CPUExecutionProvider"])
    proc = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1",
                             "-i", pcm_path, "-af", f"aresample={DETECT_RATE}", "-f", "f32le", "-"],
                            stdout=subprocess.PIPE)
    state = np.zeros((2, 1, 128), np.float32)
    context = np.zeros(CONTEXT, np.float32)
    rate = np.array(DETECT_RATE, np.int64)
    probs, pending = [], np.zeros(0, np.float32)
    block = CHUNK * 4 * 256
    try:
        while True:
            data = proc.stdout.read(block)
            if data:
                pending = np.concatenate([pending, np.frombuffer(data, "<f4")])
            elif len(pending) % CHUNK:
                pending = np.concatenate([pending, np.zeros(CHUNK - len(pending) % CHUNK, np.float32)])
            usable = len(pending) - len(pending) % CHUNK
            for i in range(0, usable, CHUNK):
                frame = np.concatenate([context, pending[i:i + CHUNK]])[None, :]
                out, state = session.run(None, {"input": frame, "state": state, "sr": rate})
                probs.append(float(out[0][0]))
                context = pending[i + CHUNK - CONTEXT:i + CHUNK]
            pending = pending[usable:]
            if not data:
                break
    finally:
        proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError("ffmpeg failed while resampling audio for speech detection")
    return np.array(probs, np.float32)


def speech_runs(probs):
    """Hysteresis over frames -> [(first_frame, end_frame)] half-open."""
    runs, start, on = [], 0, False
    for i, p in enumerate(probs):
        if not on and p > ON:
            on, start = True, i
        elif on and p < OFF:
            on = False
            runs.append((start, i))
    if on:
        runs.append((start, len(probs)))
    return runs


def choose_cut(probs, start, limit):
    """Pick where to split a long segment between start+25 s and start+30 s (sample positions)."""
    lo = -(-(start + SEARCH_FROM) // STEP)
    hi = min(len(probs), (start + MAX_SAMPLES) // STEP)
    best = None
    i = lo
    while i < hi:
        if probs[i] < OFF:
            j = i
            while j < hi and probs[j] < OFF:
                j += 1
            if j - i >= MIN_PAUSE_FRAMES and (best is None or j - i > best[1] - best[0]):
                best = (i, j)
            i = j
        else:
            i += 1
    if best:
        return min(limit, (best[0] + best[1]) // 2 * STEP), "pause"
    if hi - lo >= MIN_PAUSE_FRAMES:
        window = np.convolve(probs[lo:hi], np.ones(MIN_PAUSE_FRAMES) / MIN_PAUSE_FRAMES, "valid")
        k = int(np.argmin(window))
        if window[k] < ON:
            return min(limit, (lo + k + MIN_PAUSE_FRAMES // 2) * STEP), "low_speech"
    return limit, "max_duration"


def build_segments(probs, total):
    """Turn per-frame probabilities into non-overlapping segments of at most MAX_SAMPLES."""
    regions = [(a * STEP, min(total, b * STEP)) for a, b in speech_runs(probs)]
    regions = [(a, b) for a, b in regions if b > a]
    groups = []
    for a, b in regions:
        if groups and a - groups[-1][-1][1] < MERGE_GAP:
            groups[-1].append((a, b))
        else:
            groups.append([(a, b)])
    segments, prev_end = [], 0
    for gi, group in enumerate(groups):
        start = max(group[0][0] - MARGIN, prev_end, 0)
        end = min(group[-1][1] + MARGIN, total)
        if gi + 1 < len(groups):
            end = min(end, groups[gi + 1][0][0] - MARGIN)
        start_reason = "speech_onset"
        while end - start > MAX_SAMPLES:
            cut, reason = choose_cut(probs, start, start + MAX_SAMPLES)
            segments.append(segment(start, cut, group, start_reason, reason))
            start, start_reason = cut, f"split_{reason}"
        end_reason = "end_of_audio" if end == total and group[-1][1] >= total - STEP else "silence"
        segments.append(segment(start, end, group, start_reason, end_reason))
        prev_end = end
    for i, seg in enumerate(segments, 1):
        seg["segment_id"] = f"seg{i:06d}"
    return segments, regions


def segment(start, end, group, start_reason, end_reason):
    inside = []
    for a, b in group:
        a2, b2 = max(a, start), min(b, end)
        if b2 > a2:
            forced = (a2 > a and start_reason == "split_max_duration") or (b2 < b and end_reason == "max_duration")
            kind = "forced" if forced else "estimated_speech"
            inside.append({"start_sample": a2, "end_sample": b2, "boundary_kind": kind})
    return {"segment_id": None, "start_sample": start, "end_sample": end, "speech_regions": inside,
            "start_reason": start_reason, "end_reason": end_reason}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def document(status, total, origin_s, segments=(), regions=(), detector=None):
    return {
        "schema": "speech-segments", "schema_version": 1,
        "timebase": "video_relative_samples", "sample_rate_hz": RATE,
        "interval_convention": "start_inclusive_end_exclusive",
        "timeline_origin_ms": round(origin_s * 1000, 3),
        "status": status, "total_samples": total,
        "detector": detector,
        "segmentation": {"policy": POLICY, "max_samples": MAX_SAMPLES, "margin_samples": MARGIN,
                         "merge_gap_samples": MERGE_GAP, "search_from_samples": SEARCH_FROM,
                         "overlap_samples": 0},
        "segments": list(segments),
        "coverage": {"scanned_samples": total if detector else 0,
                     "speech_samples": int(sum(b - a for a, b in regions)),
                     "segment_samples": int(sum(s["end_sample"] - s["start_sample"] for s in segments)),
                     "segment_count": len(segments)},
    }


def analyze(video_path, output_dir, model_path):
    os.makedirs(output_dir, exist_ok=True)
    origin, duration, has_audio = probe(video_path)
    total = int(round(duration * RATE))
    if not has_audio:
        doc = document("absent", total, origin)
    else:
        if not os.path.isfile(model_path):
            raise FileNotFoundError(f"Speech detection model not found: {model_path}")
        pcm_path = os.path.join(output_dir, "audio_24k.pcm")
        normalize_audio(video_path, pcm_path, origin, total)
        probs = speech_probabilities(pcm_path, model_path)
        segments, regions = build_segments(probs, total)
        import onnxruntime
        detector = {"name": "silero_onnx", "model_sha256": sha256(model_path),
                    "analysis_sample_rate_hz": DETECT_RATE, "frame_samples": STEP,
                    "threshold_on": ON, "threshold_off": OFF,
                    "onnxruntime": onnxruntime.__version__, "numpy": np.__version__}
        doc = document("complete" if segments else "no_speech_detected", total, origin, segments, regions, detector)
    path = os.path.join(output_dir, "segments.json")
    with open(path, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    return path, doc


def main():
    parser = argparse.ArgumentParser(description="Detect speech in a video's audio and write bounded segments.")
    parser.add_argument("video_path")
    parser.add_argument("output_dir")
    parser.add_argument("--model", default=os.environ.get("SILERO_VAD_MODEL", DEFAULT_MODEL))
    args = parser.parse_args()
    try:
        path, doc = analyze(args.video_path, args.output_dir, args.model)
    except (subprocess.CalledProcessError, ValueError, FileNotFoundError, RuntimeError) as e:
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) and e.stderr else str(e)
        print(f"Error: {detail}", file=sys.stderr)
        sys.exit(1)
    print(f"Speech segments written to {path} ({doc['status']}, {len(doc['segments'])} segments)")


if __name__ == "__main__":
    main()
