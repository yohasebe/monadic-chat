"""Offline video extraction checks; run with Python, OpenCV and ffmpeg installed."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np

SCRIPT = Path(__file__).resolve().parent / "extract_frames.py"
spec = importlib.util.spec_from_file_location("video_frames", SCRIPT)
video_frames = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video_frames)


class VideoFramesTest(unittest.TestCase):
    def extract(self, frames, fps=10, sample_fps=10, limit=50, vfr=False):
        with tempfile.TemporaryDirectory(prefix="video-frames-") as directory:
            path = Path(directory) / "source.avi"
            writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"FFV1"), fps, (160, 96))
            self.assertTrue(writer.isOpened())
            for frame in frames:
                writer.write(frame)
            writer.release()
            if vfr:
                target = Path(directory) / "variable.mkv"
                subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf",
                                "setpts=N*N/(25*TB)", "-fps_mode", "vfr", "-c:v", "ffv1", str(target)], check=True)
                path = target
            timeline, _, _ = video_frames.probe_timeline(str(path))
            video_frames.extract_frames(str(path), directory, "png", limit, sample_fps, True, 160)
            document = json.loads(next(Path(directory).glob("frames_*.json")).read_text())
            return document, timeline

    @staticmethod
    def blank(value=0):
        return np.full((96, 160, 3), value, dtype=np.uint8)

    def test_pts_not_requested_fps_and_endpoints(self):
        document, timeline = self.extract([self.blank()] * 21, fps=7.5, sample_fps=2)
        frames = document["frames"]
        self.assertEqual(document["schema_version"], 1)
        self.assertEqual(document["timestamp_source"], "ffprobe_best_effort_pts")
        self.assertEqual(frames[0]["source_frame_index"], 0)
        self.assertEqual(frames[-1]["source_frame_index"], 20)
        self.assertAlmostEqual(frames[-1]["timestamp_ms"], 20 / 7.5 * 1000, delta=1)
        self.assertLess(len(frames), 21)
        for frame in frames:
            self.assertAlmostEqual(frame["timestamp_ms"], timeline[frame["source_frame_index"]], delta=0.001)

    def test_variable_frame_rate(self):
        document, timeline = self.extract([self.blank(i * 20) for i in range(12)], vfr=True)
        self.assertGreater(len(set(round(b-a) for a, b in zip(timeline, timeline[1:]))), 1)
        for frame in document["frames"]:
            self.assertAlmostEqual(frame["timestamp_ms"], timeline[frame["source_frame_index"]], delta=0.001)
        self.assertEqual(document["frames"][-1]["source_frame_index"], len(timeline)-1)

    def test_text_only_change_survives(self):
        base = self.blank(255)
        changed = base.copy()
        cv2.putText(changed, "42", (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)
        document, _ = self.extract([base] * 5 + [changed] * 5 + [base] * 5)
        indices = [f["source_frame_index"] for f in document["frames"]]
        self.assertIn(5, indices)
        self.assertIn(10, indices)

    def test_gradual_change_accumulates(self):
        document, _ = self.extract([self.blank(i) for i in range(40)])
        indices = [f["source_frame_index"] for f in document["frames"]]
        self.assertGreater(len(indices), 2)
        self.assertLess(len(indices), 40)
        self.assertTrue(any(10 < i < 30 for i in indices))

    def test_temporal_anchors_on_static_video(self):
        document, _ = self.extract([self.blank()] * 121, fps=10, sample_fps=1)
        times = [f["timestamp_ms"] for f in document["frames"]]
        self.assertIn(5000, times)
        self.assertIn(10000, times)
        self.assertEqual(times[-1], 12000)

    def test_budget_preserves_coverage_and_brief_event_before_encoding(self):
        frames = [self.blank(i % 2 * 10) for i in range(100)]
        frames[43] = self.blank(255)
        original = cv2.imencode
        with patch.object(video_frames.cv2, "imencode", wraps=original) as encode:
            document, _ = self.extract(frames, limit=10)
            self.assertEqual(encode.call_count, 10)
        indices = [f["source_frame_index"] for f in document["frames"]]
        self.assertEqual(len(indices), 10)
        self.assertEqual(indices, sorted(indices))
        self.assertEqual(indices[0], 0)
        self.assertEqual(indices[-1], 99)
        self.assertIn(43, indices)
        for target in (25, 50, 74):
            self.assertTrue(any(abs(i-target) <= 1 for i in indices))

    def test_color_change_with_similar_luminance(self):
        blue = self.blank()
        blue[:, :, 0] = 255
        red = self.blank()
        red[:, :, 2] = 97
        document, _ = self.extract([blue] * 5 + [red] * 5)
        self.assertIn(5, [f["source_frame_index"] for f in document["frames"]])

    def test_preserves_sample_before_scene_transition(self):
        document, _ = self.extract([self.blank()] * 10 + [self.blank(255)] * 10)
        indices = [f["source_frame_index"] for f in document["frames"]]
        self.assertIn(9, indices)
        self.assertIn(10, indices)

    def test_images_fit_the_longest_side_without_enlarging(self):
        self.assertEqual(video_frames.fit_within(1920, 1080, 768), (768, 432))
        self.assertEqual(video_frames.fit_within(1080, 1920, 768), (432, 768))
        self.assertEqual(video_frames.fit_within(2, 4096, 768), (1, 768))
        self.assertEqual(video_frames.fit_within(320, 240, 768), (320, 240))

    def test_tall_narrow_video_stays_small(self):
        with tempfile.TemporaryDirectory(prefix="video-frames-") as directory:
            path = Path(directory) / "tall.avi"
            writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"FFV1"), 5, (8, 400))
            self.assertTrue(writer.isOpened())
            for value in (0, 255):
                writer.write(np.full((400, 8, 3), value, dtype=np.uint8))
            writer.release()
            video_frames.extract_frames(str(path), directory, "png", 5, 5, False, 160)
            image = cv2.imread(str(next(Path(directory).glob("frames_*/*.png"))))
            self.assertLessEqual(max(image.shape[:2]), 160)

    def test_single_frame(self):
        document, _ = self.extract([self.blank()])
        self.assertEqual(len(document["frames"]), 1)
        self.assertEqual(document["frames"][0]["timestamp_ms"], 0)

    def test_rejects_invalid_timeline(self):
        result = type("Probe", (), {"stdout": json.dumps({"frames": [
            {"best_effort_timestamp_time": "0"}, {"best_effort_timestamp_time": "0"}]})})()
        with patch.object(video_frames.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "strictly increasing"):
                video_frames.probe_timeline("unused")



class AudioExtractionTest(unittest.TestCase):
    """Real ffmpeg: the file size must follow the length for the caller's limit to hold."""

    def source(self, directory, seconds=4):
        path = Path(directory) / "talk.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", f"testsrc=duration={seconds}:size=160x96:rate=10",
                        "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-ac", "2", "-shortest",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2", str(path)], check=True)
        return path

    @staticmethod
    def audio_stream(path):
        out = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_entries",
                              "stream=channels,bit_rate", str(path)], capture_output=True, text=True, check=True)
        return json.loads(out.stdout)["streams"][0]

    def test_constant_mono_bitrate_when_asked(self):
        with tempfile.TemporaryDirectory(prefix="audio-") as directory:
            video_frames.extract_audio(str(self.source(directory)), directory, "64k", 1)
            audio = next(Path(directory).glob("audio_*.mp3"))
            stream = self.audio_stream(audio)
            self.assertEqual(stream["channels"], 1)
            self.assertEqual(int(stream["bit_rate"]), 64000)
            self.assertLess(audio.stat().st_size, 4 * 8000 * 1.2)

    def test_source_layout_and_variable_quality_by_default(self):
        with tempfile.TemporaryDirectory(prefix="audio-") as directory:
            video_frames.extract_audio(str(self.source(directory)), directory)
            self.assertEqual(self.audio_stream(next(Path(directory).glob("audio_*.mp3")))["channels"], 2)

    def test_rejects_a_malformed_bitrate(self):
        result = subprocess.run(["python", str(SCRIPT), "in.mp4", ".", "--audio", "--audio-bitrate", "64k; rm -rf /"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--audio-bitrate must look like 64k", result.stderr)


if __name__ == "__main__":
    unittest.main()
