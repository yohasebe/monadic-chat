#!/usr/bin/env python
"""Find speech in a video's or an audio file's audio and cut it into bounded segments for transcription.

Writes two files into the output directory:
  audio_24k.pcm   mono s16le at 24 kHz; sample 0 = the first video frame (--timeline video,
                  the default) or the first sample the audio track plays (--timeline audio)
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
PACK_GAP = 2 * RATE              # utterances closer than 2 s share a segment while it fits
MARGIN = RATE // 5               # 200 ms kept before and after detected speech
MAX_SAMPLES = 30 * RATE          # 30 s per segment, margins included
SEARCH_FROM = 25 * RATE          # start looking for a cut 25 s into a long segment
MIN_PAUSE_FRAMES = 5             # 160 ms of low speech probability counts as a pause
DEFAULT_MODEL = "/monadic/models/silero_vad.onnx"
POLICY = "bounded_segments_v2"


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def probe(video_path):
    """Return (origin seconds, duration seconds, has_audio) on the video's own clock."""
    # The first decoded video frame, read until it appears (reading a fixed
    # number of packets can see only audio when that stream comes first).
    proc = subprocess.Popen(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames",
                             "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0", video_path],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    origin = None
    try:
        for line in proc.stdout:
            field = line.split(",", 1)[0].strip()  # side data may follow on the same line
            if field:
                try:
                    origin = float(field)
                except ValueError:
                    pass
                break
    finally:
        proc.kill()
        proc.wait()
        proc.stdout.close()
    if origin is None:
        raise ValueError("Video has no valid presentation timestamps")
    info = json.loads(run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
                           "-of", "json", video_path]))
    duration = float(info.get("format", {}).get("duration") or 0)
    if duration <= 0:
        raise ValueError("Video has no duration")
    format_start = float(json.loads(run(["ffprobe", "-v", "error", "-show_entries", "format=start_time",
                                         "-of", "json", video_path])).get("format", {}).get("start_time") or 0)
    has_audio = any(s.get("codec_type") == "audio" for s in info.get("streams", []))
    return origin, duration - (origin - format_start), has_audio


def audio_streams(path):
    """The audio tracks, in order: [{"codec": ..., "default": bool, "language": ...}]."""
    info = json.loads(run(["ffprobe", "-v", "error", "-select_streams", "a",
                           "-show_entries", "stream=codec_name:stream_disposition=default:stream_tags=language",
                           "-of", "json", path]))
    return [{"codec": s.get("codec_name"), "default": bool((s.get("disposition") or {}).get("default")),
             "language": (s.get("tags") or {}).get("language")} for s in info.get("streams", [])]


def choose_audio_stream(streams, requested=None):
    """The track asked for, else the one marked default, else the first. Tracks are never mixed."""
    if requested is not None:
        if not 0 <= requested < len(streams):
            raise ValueError(f"No audio track {requested} (the file has {len(streams)})")
        return requested
    return next((i for i, s in enumerate(streams) if s["default"]), 0)


def probe_audio(path, stream):
    """Return (origin seconds, duration seconds, player offset seconds) of an audio file.

    The origin is the time of the first sample the track plays, after the
    decoder drops what the encoder put before the sound (codec delay, edit
    lists): leading silence in the recording stays, speech is not the origin.
    """
    proc = subprocess.Popen(["ffprobe", "-v", "error", "-select_streams", f"a:{stream}", "-show_frames",
                             "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0", path],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    origin = None
    try:
        for line in proc.stdout:
            field = line.split(",", 1)[0].strip()
            if field:
                try:
                    origin = float(field)
                except ValueError:
                    pass
                break
    finally:
        proc.kill()
        proc.wait()
        proc.stdout.close()
    if origin is None:
        raise ValueError("Audio has no valid presentation timestamps")
    info = json.loads(run(["ffprobe", "-v", "error", "-show_entries", "format=duration,start_time", "-of", "json", path]))
    fmt = info.get("format", {})
    # A player counts from the first packet of the track, never before zero:
    # it hides what the decoder skips (encoder delay, priming) without moving
    # its clock, which ffmpeg's decoded frame times do move (MP3 by the LAME
    # delay). So the first packet, not the origin, tells where a player shows
    # sample 0.
    packets = run(["ffprobe", "-v", "error", "-select_streams", f"a:{stream}", "-show_packets",
                   "-show_entries", "packet=pts_time", "-read_intervals", "%+#1", "-of", "csv=p=0", path])
    first_packet = None
    for line in packets.splitlines():
        try:
            first_packet = float(line.split(",", 1)[0])
            break
        except ValueError:
            continue
    duration = float(fmt.get("duration") or 0)
    if duration <= 0:
        raise ValueError("Audio has no duration")
    format_start = float(fmt.get("start_time") or 0)
    player_offset = max(first_packet if first_packet is not None else origin, 0.0)
    return origin, duration - (origin - format_start), player_offset


def normalize_audio(video_path, pcm_path, origin_s, total, stream=0):
    """Decode one audio track to exactly `total` samples, sample 0 at `origin_s` on the file's clock."""
    flt = (f"asetpts=PTS-{origin_s:.6f}/TB,aresample={RATE}:async=1:first_pts=0,"
           f"aformat=sample_fmts=s16:channel_layouts=mono,apad=whole_len={total},atrim=end_sample={total}")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-copyts", "-i", video_path, "-map", f"0:a:{stream}", "-vn",
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
    utterances = []
    for a, b in regions:
        if utterances and a - utterances[-1][-1][1] < MERGE_GAP:
            utterances[-1].append((a, b))
        else:
            utterances.append([(a, b)])
    # A short utterance sent on its own often comes back empty: the model
    # needs the speech around it. Utterances closer than PACK_GAP go into one
    # segment as long as it stays within MAX_SAMPLES with its margins; one
    # that is longer by itself is split below.
    groups = []
    for utterance in utterances:
        if groups and utterance[0][0] - groups[-1][-1][1] < PACK_GAP and \
                utterance[-1][1] - groups[-1][0][0] + 2 * MARGIN <= MAX_SAMPLES:
            groups[-1].extend(utterance)
        else:
            groups.append(list(utterance))
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


def document(status, total, origin_s, segments=(), regions=(), detector=None, source=None):
    audio = (source or {}).get("timeline") == "audio"
    return {
        "schema": "speech-segments", "schema_version": 1,
        "timebase": "audio_relative_samples" if audio else "video_relative_samples", "sample_rate_hz": RATE,
        "interval_convention": "start_inclusive_end_exclusive",
        "timeline_origin_ms": round(origin_s * 1000, 3),
        "status": status, "total_samples": total,
        **({"source": source} if source else {}),
        "detector": detector,
        "segmentation": {"policy": POLICY, "max_samples": MAX_SAMPLES, "margin_samples": MARGIN,
                         "merge_gap_samples": MERGE_GAP, "pack_gap_samples": PACK_GAP,
                         "search_from_samples": SEARCH_FROM,
                         "overlap_samples": 0},
        "segments": list(segments),
        "coverage": {"scanned_samples": total if detector else 0,
                     "speech_samples": int(sum(b - a for a, b in regions)),
                     "segment_samples": int(sum(s["end_sample"] - s["start_sample"] for s in segments)),
                     "segment_count": len(segments)},
    }


def analyze(video_path, output_dir, model_path, timeline="video", audio_stream=None):
    os.makedirs(output_dir, exist_ok=True)
    source = None
    stream = 0
    if timeline == "audio":
        # An audio file: its own clock, whatever picture (album art) it carries.
        streams = audio_streams(video_path)
        if not streams:
            raise ValueError("The file has no audio track")
        stream = choose_audio_stream(streams, audio_stream)
        origin, duration, player_offset = probe_audio(video_path, stream)
        # Measured in Chrome: an Ogg Vorbis file that starts after zero plays
        # from its first sample at 0 (unlike Opus and MP4 audio, which keep
        # their start), so nothing is added for Vorbis.
        if streams[stream]["codec"] == "vorbis":
            player_offset = 0.0
        has_audio = True
        source = {"timeline": "audio", "origin_policy": "first_presented_audio_sample",
                  "audio_stream": stream, "audio_stream_count": len(streams),
                  "codec": streams[stream]["codec"], "language": streams[stream]["language"],
                  "origin_pts_ms": round(origin * 1000, 3),
                  # where a player shows sample 0 (subtitles add this)
                  "player_offset_ms": round(player_offset * 1000, 3)}
    else:
        origin, duration, has_audio = probe(video_path)
    total = int(round(duration * RATE))
    if not has_audio:
        doc = document("absent", total, origin)
    else:
        if not os.path.isfile(model_path):
            raise FileNotFoundError(f"Speech detection model not found: {model_path}")
        pcm_path = os.path.join(output_dir, "audio_24k.pcm")
        normalize_audio(video_path, pcm_path, origin, total, stream)
        probs = speech_probabilities(pcm_path, model_path)
        segments, regions = build_segments(probs, total)
        import onnxruntime
        detector = {"name": "silero_onnx", "model_sha256": sha256(model_path),
                    "analysis_sample_rate_hz": DETECT_RATE, "frame_samples": STEP,
                    "threshold_on": ON, "threshold_off": OFF,
                    "onnxruntime": onnxruntime.__version__, "numpy": np.__version__}
        doc = document("complete" if segments else "no_speech_detected", total, origin, segments, regions, detector,
                       source)
    path = os.path.join(output_dir, "segments.json")
    with open(path, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    return path, doc


def main():
    parser = argparse.ArgumentParser(description="Detect speech in a video's audio and write bounded segments.")
    parser.add_argument("video_path")
    parser.add_argument("output_dir")
    parser.add_argument("--model", default=os.environ.get("SILERO_VAD_MODEL", DEFAULT_MODEL))
    parser.add_argument("--timeline", choices=["video", "audio"], default="video",
                        help="video: sample 0 is the first video frame; audio: the first sample the track plays")
    parser.add_argument("--audio-stream", type=int, default=None,
                        help="audio track (0-based, audio tracks only) for --timeline audio")
    args = parser.parse_args()
    try:
        path, doc = analyze(args.video_path, args.output_dir, args.model, args.timeline, args.audio_stream)
    except (subprocess.CalledProcessError, ValueError, FileNotFoundError, RuntimeError) as e:
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) and e.stderr else str(e)
        print(f"Error: {detail}", file=sys.stderr)
        sys.exit(1)
    print(f"Speech segments written to {path} ({doc['status']}, {len(doc['segments'])} segments)")


if __name__ == "__main__":
    main()
