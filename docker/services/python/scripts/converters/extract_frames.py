#!/usr/bin/env python

import cv2
import re
import numpy as np
import math
import os
import argparse
import base64
import json
import subprocess
from datetime import datetime

def probe_timeline(video_path):
    """Use decoded presentation timestamps, never requested sampling FPS."""
    result = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_frames", "-show_entries",
        "frame=best_effort_timestamp_time,pkt_duration_time,duration_time:stream=duration",
        "-of", "json", video_path
    ], capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    frames = data.get("frames", [])
    times = [float(f["best_effort_timestamp_time"]) * 1000 for f in frames]
    if not times or not all(math.isfinite(t) for t in times):
        raise ValueError("Video has no valid presentation timestamps")
    if any(b <= a for a, b in zip(times, times[1:])):
        raise ValueError("Video presentation timestamps are not strictly increasing")
    origin = times[0]
    times = [t - origin for t in times]
    tail = float(frames[-1].get("duration_time", frames[-1].get("pkt_duration_time", 0))) * 1000
    durations = [float(s["duration"]) * 1000 for s in data.get("streams", [])
                 if s.get("duration") not in (None, "N/A")]
    duration = max([times[-1] + max(0, tail)] + [d for d in durations if math.isfinite(d)])
    return times, duration, origin


def frame_features(frame):
    # Preserve local text changes that would disappear in a global average.
    width = min(384, frame.shape[1])
    small = cv2.resize(frame, (width, max(8, round(frame.shape[0] * width / frame.shape[1]))))
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 60, 120)
    signature = cv2.resize(small, (16, 16)).astype("float32")
    return gray, edges, signature, small


def feature_difference(a, b):
    delta = np.maximum(cv2.absdiff(a[0], b[0]), cv2.absdiff(a[3], b[3]).max(axis=2))
    edge_delta = cv2.absdiff(a[1], b[1])
    local = 0.0
    for rows in np.array_split(np.arange(delta.shape[0]), 4):
        for cols in np.array_split(np.arange(delta.shape[1]), 4):
            patch = delta[np.ix_(rows, cols)]
            edges = edge_delta[np.ix_(rows, cols)]
            local = max(local, float(np.mean(patch > 8)), float(np.mean(edges > 0)))
    return max(float(delta.mean()) / 255.0, local)


def select_frames(candidates, limit):
    """Reserve temporal coverage, then add distinct changes; always chronological."""
    if not limit or len(candidates) <= limit:
        return candidates
    if limit == 1:
        return candidates[:1]
    chosen = {0, len(candidates) - 1}
    coverage = max(2, (limit + 1) // 2)
    start, end = candidates[0]["timestamp_ms"], candidates[-1]["timestamp_ms"]
    for target in np.linspace(start, end, coverage):
        chosen.add(min(range(len(candidates)), key=lambda i: abs(candidates[i]["timestamp_ms"] - target)))
    signatures = np.stack([item["signature"] for item in candidates])
    times = np.array([item["timestamp_ms"] for item in candidates])
    scores = np.array([item["change_score"] for item in candidates])
    novelty = np.full(len(candidates), np.inf)
    distance = np.full(len(candidates), np.inf)

    def include(index):
        np.minimum(novelty, np.mean(np.abs(signatures - signatures[index]), axis=(1, 2, 3)) / 255,
                   out=novelty)
        np.minimum(distance, np.abs(times - times[index]), out=distance)

    for index in chosen:
        include(index)
    while len(chosen) < limit:
        priority = scores * (0.25 + novelty) + distance / max(end - start, 1) * 0.1
        priority[list(chosen)] = -np.inf
        index = int(np.argmax(priority))
        chosen.add(index)
        include(index)
    return [candidates[i] for i in sorted(chosen)]


def fit_within(width, height, longest):
    """(width, height) scaled so the longer side is at most `longest`, never enlarged.

    Scaling the width to a fixed value let a tall, narrow video ask for an
    image hundreds of times its own size (2x4096 became 768x1572864).
    """
    scale = min(1.0, longest / max(width, height))
    return max(1, round(width * scale)), max(1, round(height * scale))


def extract_frames(video_path, output_dir, output_format, frame_limit, fps, output_json, resize_width):
    if fps <= 0 or not math.isfinite(fps) or resize_width < 8 or (frame_limit is not None and frame_limit < 1):
        raise ValueError("FPS, width and frame limit must be positive (width >= 8)")
    video = cv2.VideoCapture(video_path)
    if not video.isOpened():
        print(f"Error: Could not open video {video_path}")
        return
    try:
        times, duration, origin = probe_timeline(video_path)
        candidates = []
        previous = anchor = previous_item = None
        anchor_time = next_sample = 0.0
        index = 0
        while True:
            success, frame = video.read()
            if not success:
                break
            if index >= len(times):
                raise ValueError("Decoded frame count does not match presentation timestamps")
            time = times[index]
            if time >= next_sample or index == len(times) - 1:
                features = frame_features(frame)
                adjacent = feature_difference(features, previous) if previous is not None else 1.0
                cumulative = feature_difference(features, anchor) if anchor is not None else 1.0
                change = max(adjacent, cumulative)
                # Preserve the last sampled state before a strong transition.
                if adjacent >= 0.15 and previous_item is not None and candidates[-1]["source_frame_index"] != previous_item["source_frame_index"]:
                    candidates.append(dict(previous_item, change_score=adjacent))
                item = {"frame_id": f"f{index:06d}", "source_frame_index": index,
                        "timestamp_ms": round(time, 3), "change_score": change, "signature": features[2]}
                # Only near-duplicates are dropped; keep periodic anchors and endpoints.
                if anchor is None or change >= 0.015 or time - anchor_time >= 5000 or index == len(times) - 1:
                    candidates.append(item)
                    anchor, anchor_time = features, time
                previous, previous_item = features, item
                next_sample = (math.floor(time * fps / 1000) + 1) * 1000 / fps
            index += 1
        if index != len(times):
            raise ValueError("Decoded frame count does not match presentation timestamps")
    finally:
        video.release()

    selected = select_frames(candidates, frame_limit)
    # Second decode avoids retaining/encoding full images before selection.
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    output_folder = os.path.join(output_dir, f"frames_{timestamp}")
    os.makedirs(output_folder, exist_ok=True)
    selected_by_index = {f["source_frame_index"]: f for f in selected}
    output_frames = []
    video = cv2.VideoCapture(video_path)
    try:
        for index in range(len(times)):
            success, frame = video.read()
            if not success:
                raise ValueError("Video decode failed while exporting selected frames")
            if index not in selected_by_index:
                continue
            item = {k: v for k, v in selected_by_index[index].items() if k != "signature"}
            resized = cv2.resize(frame, fit_within(frame.shape[1], frame.shape[0], resize_width))
            success, buffer = cv2.imencode(f".{output_format}", resized)
            if not success:
                raise ValueError("Could not encode selected frame")
            filename = os.path.join(output_folder, f"{item['frame_id']}.{output_format}")
            with open(filename, "wb") as image_file:
                image_file.write(buffer.tobytes())
            item["image"] = base64.b64encode(buffer).decode("ascii")
            item["mime_type"] = "image/png" if output_format == "png" else "image/jpeg"
            output_frames.append(item)
    finally:
        video.release()
    print(f"{len(output_frames)} frames extracted to {output_folder}")
    if output_json:
        document = {"schema_version": 1, "duration_ms": round(duration, 3),
                    "timestamp_source": "ffprobe_best_effort_pts", "timeline_origin_ms": origin,
                    "frames": output_frames}
        json_filename = os.path.join(output_dir, f"frames_{timestamp}.json")
        with open(json_filename, "w") as json_file:
            json.dump(document, json_file, allow_nan=False)
        print(f"Base64-encoded frames saved to {json_filename}")

def extract_audio(video_path, output_dir, bitrate=None, channels=None):
    # Extract the audio track to MP3 by invoking system ffmpeg directly.
    # ffmpeg is provided by the python container's apt layer; calling it
    # via subprocess removes the need for moviepy + imageio-ffmpeg, which
    # together added ~50 MB of Python deps for this single operation.
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    audio_filename = os.path.join(output_dir, f"audio_{timestamp}.mp3")

    # A fixed bitrate (and channel count) keeps the file size proportional to
    # the length, so a caller can tell in advance whether a transcription
    # service's size limit will hold. Without them, variable high quality.
    quality = ["-b:a", bitrate] if bitrate else ["-q:a", "2"]
    layout = ["-ac", str(channels)] if channels else []
    result = subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", video_path,
            "-vn", "-acodec", "libmp3lame", *quality, *layout,
            audio_filename,
        ],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Error: ffmpeg failed to extract audio: {result.stderr.strip()}")
        return

    print(f"Audio extracted to {audio_filename}")

def main():
    parser = argparse.ArgumentParser(description="Extract frames and audio from a video file.")
    parser.add_argument("video_path", type=str, help="Path to the video file (mp4, mpeg, mpg, webm).")
    parser.add_argument("output_dir", type=str, help="Directory to save the extracted frames and audio.")
    parser.add_argument("--format", type=str, choices=["jpg", "png"], default="jpg", help="Output image format (jpg or png).")
    parser.add_argument("--frames", type=int, default=None, help="Maximum selected frames (default: no limit).")
    parser.add_argument("--fps", type=float, default=1.0, help="Number of frames to extract per second (default: 1.0).")
    parser.add_argument("--json", action="store_true", help="Output versioned JSON with timestamps and base64 images.")
    parser.add_argument("--width", type=int, default=768, help="Longest side of the saved images; smaller frames are not enlarged (default: 768).")
    parser.add_argument("--audio", action="store_true", help="Extract audio from the video and save as an mp3 file.")
    parser.add_argument("--audio-bitrate", type=str, default=None,
                        help="Constant audio bitrate such as 64k (default: variable high quality).")
    parser.add_argument("--audio-channels", type=int, choices=[1, 2], default=None,
                        help="Audio channels: 1 for mono, 2 for stereo (default: as in the source).")

    args = parser.parse_args()

    extract_frames(args.video_path, args.output_dir, args.format, args.frames, args.fps, args.json, args.width)

    if args.audio_bitrate is not None and not re.fullmatch(r"[1-9][0-9]{0,2}k", args.audio_bitrate):
        parser.error("--audio-bitrate must look like 64k")

    if args.audio:
        extract_audio(args.video_path, args.output_dir, args.audio_bitrate, args.audio_channels)

if __name__ == "__main__":
    main()
