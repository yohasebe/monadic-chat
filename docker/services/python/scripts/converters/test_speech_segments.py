"""Offline speech segmentation checks; run with Python and ffmpeg installed (detector checks need the model)."""
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import numpy as np

SCRIPT = Path(__file__).resolve().parent / "speech_segments.py"
spec = importlib.util.spec_from_file_location("speech_segments", SCRIPT)
seg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seg)

FRAMES_PER_SECOND = seg.RATE / seg.STEP  # 31.25
MODEL = os.environ.get("SILERO_VAD_MODEL", seg.DEFAULT_MODEL)


def frames(seconds):
    return int(round(seconds * FRAMES_PER_SECOND))


def probs(total_seconds, speech):
    """speech: [(start_s, end_s)] with probability 0.9, else 0.05."""
    p = np.full(frames(total_seconds), 0.05, np.float32)
    for a, b in speech:
        p[frames(a):frames(b)] = 0.9
    return p


def build(total_seconds, speech, p=None):
    p = probs(total_seconds, speech) if p is None else p
    total = len(p) * seg.STEP
    return seg.build_segments(p, total)[0], total


class SegmentationTest(unittest.TestCase):
    def assert_bounded(self, segments, total):
        previous = 0
        for s in segments:
            self.assertLessEqual(previous, s["start_sample"])
            self.assertLess(s["start_sample"], s["end_sample"])
            self.assertLessEqual(s["end_sample"], total)
            self.assertLessEqual(s["end_sample"] - s["start_sample"], seg.MAX_SAMPLES)
            for r in s["speech_regions"]:
                self.assertLessEqual(s["start_sample"], r["start_sample"])
                self.assertLessEqual(r["end_sample"], s["end_sample"])
            previous = s["end_sample"]

    def test_no_speech_gives_no_segments(self):
        segments, _ = build(10, [])
        self.assertEqual(segments, [])

    def test_separate_utterances_get_margins_and_do_not_overlap(self):
        segments, total = build(12, [(2, 4), (7, 8)])
        self.assertEqual(len(segments), 2)
        self.assert_bounded(segments, total)
        first = segments[0]
        self.assertEqual(first["speech_regions"][0]["start_sample"] - first["start_sample"], seg.MARGIN)
        self.assertEqual(first["end_sample"] - first["speech_regions"][0]["end_sample"], seg.MARGIN)
        self.assertEqual([s["end_reason"] for s in segments], ["silence", "silence"])
        self.assertEqual([s["segment_id"] for s in segments], ["seg000001", "seg000002"])

    def test_utterances_close_together_share_a_segment(self):
        segments, total = build(12, [(0.5, 1.2), (2.2, 3.0), (4.0, 9.0)])
        self.assertEqual(len(segments), 1)
        self.assertEqual(len(segments[0]["speech_regions"]), 3)
        self.assert_bounded(segments, total)

    def test_packing_stops_before_the_segment_limit(self):
        segments, total = build(40, [(1, 11), (12, 22), (23, 33)])
        self.assert_bounded(segments, total)
        self.assertEqual([len(s["speech_regions"]) for s in segments], [2, 1])
        self.assertEqual([s["end_reason"] for s in segments], ["silence", "silence"])

    def test_short_pause_stays_inside_one_segment(self):
        segments, _ = build(10, [(1, 3), (3.3, 5)])
        self.assertEqual(len(segments), 1)
        self.assertEqual(len(segments[0]["speech_regions"]), 2)

    def test_very_short_utterance_is_kept(self):
        segments, _ = build(5, [(2, 2.07)])
        self.assertEqual(len(segments), 1)

    def test_long_monologue_is_forced_into_bounded_segments(self):
        segments, total = build(75, [(0, 75)])
        self.assert_bounded(segments, total)
        self.assertEqual(len(segments), 3)
        self.assertEqual([s["end_reason"] for s in segments], ["max_duration", "max_duration", "end_of_audio"])
        self.assertEqual(segments[1]["start_reason"], "split_max_duration")
        self.assertEqual(segments[0]["end_sample"], segments[1]["start_sample"])
        self.assertEqual(segments[0]["speech_regions"][-1]["boundary_kind"], "forced")
        self.assertEqual(segments[1]["speech_regions"][0]["boundary_kind"], "forced")
        self.assertEqual(segments[-1]["end_sample"], total)

    def test_long_monologue_is_cut_in_a_short_pause_after_25_seconds(self):
        p = probs(50, [(1, 50)])
        p[frames(10):frames(10.2)] = 0.1   # too early to be used
        p[frames(27):frames(27.2)] = 0.1   # 200 ms pause in the search window
        segments, total = build(50, None, p)
        self.assert_bounded(segments, total)
        self.assertEqual(segments[0]["end_reason"], "pause")
        cut_seconds = segments[0]["end_sample"] / seg.RATE
        self.assertTrue(27 <= cut_seconds <= 27.2, cut_seconds)
        self.assertEqual(segments[1]["start_reason"], "split_pause")

    def test_low_speech_dip_is_preferred_to_a_forced_cut(self):
        p = probs(50, [(0, 50)])
        p[frames(28):frames(28.3)] = 0.4   # stays above OFF, but below ON on average
        segments, _ = build(50, None, p)
        self.assertEqual(segments[0]["end_reason"], "low_speech")
        self.assertTrue(28 <= segments[0]["end_sample"] / seg.RATE <= 28.3)

    def test_random_probabilities_keep_every_invariant(self):
        rng = np.random.default_rng(3)
        for _ in range(30):
            p = np.clip(rng.normal(0.5, 0.35, frames(300)), 0, 1).astype(np.float32)
            p = np.repeat(p[::7], 7)[:len(p)]
            segments, total = build(300, None, p)
            self.assert_bounded(segments, total)
            covered = sum(s["end_sample"] - s["start_sample"] for s in segments)
            speech = sum(b - a for a, b in seg.build_segments(p, total)[1])
            self.assertGreaterEqual(covered, speech)


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *args], check=True)


class AudioAlignmentTest(unittest.TestCase):
    """A white flash and an audio click at the same moment must land at the same time."""

    def make(self, directory, audio_offset=0.0, video_offset=0.0, ts_offset=None, audio_first=False):
        flash = "geq=lum='if(between(T,2.0,2.0999)+between(T,5.5,5.5999),235,16)':cb=128:cr=128"
        click = "aevalsrc=exprs='if(between(t,2.0,2.002)+between(t,5.5,5.502),0.9,0)':s=48000:d=8"
        v, a = os.path.join(directory, "v.mp4"), os.path.join(directory, "a.wav")
        ffmpeg("-f", "lavfi", "-i", f"color=c=black:s=160x96:r=10:d=8,format=yuv420p,{flash}",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", v)
        ffmpeg("-f", "lavfi", "-i", click, "-c:a", "pcm_s16le", a)
        out = os.path.join(directory, "clip.mp4")
        ffmpeg("-itsoffset", str(video_offset), "-i", v, "-itsoffset", str(audio_offset), "-i", a,
               *(["-map", "1:a", "-map", "0:v"] if audio_first else ["-map", "0:v", "-map", "1:a"]),
               "-c:v", "copy", "-c:a", "aac", out)
        if ts_offset is not None:
            shifted = os.path.join(directory, "shifted.mp4")
            ffmpeg("-i", out, "-c", "copy", "-output_ts_offset", str(ts_offset), shifted)
            out = shifted
        return out

    def clicks_ms(self, path):
        x = np.fromfile(path, "<i2")
        hits = np.flatnonzero(np.abs(x) > 8000)
        starts = hits[np.insert(np.diff(hits) > 2400, 0, True)]
        return x, [i * 1000 / seg.RATE for i in starts]

    def check(self, expected, **kwargs):
        with tempfile.TemporaryDirectory(prefix="speech-segments-") as directory:
            clip = self.make(directory, **kwargs)
            origin, duration, has_audio = seg.probe(clip)
            self.assertTrue(has_audio)
            total = int(round(duration * seg.RATE))
            pcm = os.path.join(directory, "audio.pcm")
            seg.normalize_audio(clip, pcm, origin, total)
            samples, clicks = self.clicks_ms(pcm)
            self.assertEqual(len(samples), total)
            self.assertEqual(len(clicks), len(expected))
            for got, want in zip(clicks, expected):
                self.assertAlmostEqual(got, want, delta=1.0)

    def test_aligned_clip(self):
        self.check([2000, 5500])

    def test_audio_starting_late(self):
        self.check([2700, 6200], audio_offset=0.7)

    def test_video_starting_late(self):
        self.check([1300, 4800], video_offset=0.7)

    def test_clip_cut_by_stream_copy(self):
        # Audio stored first, B-frames, and an edit list from a stream-copy cut:
        # the first video frame needs several packets before it decodes.
        with tempfile.TemporaryDirectory(prefix="speech-segments-") as directory:
            clip = self.make(directory, audio_first=True)
            cut = os.path.join(directory, "cut.mp4")
            ffmpeg("-ss", "1.05", "-i", clip, "-c", "copy", cut)
            origin, duration, _ = seg.probe(cut)
            total = int(round(duration * seg.RATE))
            pcm = os.path.join(directory, "audio.pcm")
            seg.normalize_audio(cut, pcm, origin, total)
            samples, clicks = self.clicks_ms(pcm)
            self.assertEqual(len(samples), total)
            self.assertEqual(len(clicks), 2)
            self.assertAlmostEqual(clicks[1] - clicks[0], 3500, delta=1.0)

    def test_whole_file_offset(self):
        self.check([2000, 5500], ts_offset=5)

    def test_video_without_audio_is_absent(self):
        with tempfile.TemporaryDirectory(prefix="speech-segments-") as directory:
            clip = os.path.join(directory, "silent.mp4")
            ffmpeg("-f", "lavfi", "-i", "color=c=black:s=160x96:r=10:d=3", "-c:v", "libx264",
                   "-pix_fmt", "yuv420p", clip)
            _, doc = seg.analyze(clip, directory, MODEL)
            self.assertEqual(doc["status"], "absent")
            self.assertEqual(doc["segments"], [])
            self.assertFalse(os.path.exists(os.path.join(directory, "audio_24k.pcm")))


@unittest.skipUnless(os.path.isfile(MODEL) and importlib.util.find_spec("onnxruntime"), "speech model not installed")
class DetectorTest(unittest.TestCase):
    def test_noise_and_tones_are_not_speech(self):
        with tempfile.TemporaryDirectory(prefix="speech-segments-") as directory:
            clip = os.path.join(directory, "noise.mp4")
            ffmpeg("-f", "lavfi", "-i", "color=c=black:s=160x96:r=10:d=20",
                   "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.05:d=10",
                   "-f", "lavfi", "-i", "sine=f=440:d=10",
                   "-filter_complex", "[1:a][2:a]concat=n=2:v=0:a=1[a]", "-map", "0:v", "-map", "[a]",
                   "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", clip)
            path, doc = seg.analyze(clip, directory, MODEL)
            self.assertEqual(doc["status"], "no_speech_detected")
            self.assertEqual(doc["coverage"]["scanned_samples"], doc["total_samples"])
            self.assertEqual(json.loads(Path(path).read_text())["detector"]["name"], "silero_onnx")

    def test_probabilities_cover_the_whole_audio(self):
        with tempfile.TemporaryDirectory(prefix="speech-segments-") as directory:
            pcm = os.path.join(directory, "a.pcm")
            np.zeros(seg.RATE * 7 + 100, "<i2").tofile(pcm)
            p = seg.speech_probabilities(pcm, MODEL)
            self.assertEqual(len(p), -(-(seg.RATE * 7 + 100) * 2 // 3 // seg.CHUNK))


if __name__ == "__main__":
    unittest.main()
