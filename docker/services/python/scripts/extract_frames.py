#!/usr/bin/env python

import cv2
import os
import argparse
import base64
import json
from datetime import datetime
from moviepy.editor import VideoFileClip
import sys
import contextlib

@contextlib.contextmanager
def suppress_output():
    with open(os.devnull, 'w') as devnull:
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = devnull
        sys.stderr = devnull
        try:
            yield
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

def extract_frames(video_path, output_dir, output_format, frame_limit, fps, output_json, resize_width):
    # Create the output directory based on the timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_folder = os.path.join(output_dir, f"frames_{timestamp}")
    os.makedirs(output_folder, exist_ok=True)

    # Open the video file
    video = cv2.VideoCapture(video_path)
    if not video.isOpened():
        print(f"Error: Could not open video {video_path}")
        return

    # Get the original FPS and total frame count of the video
    original_fps = video.get(cv2.CAP_PROP_FPS)
    total_frames = int(video.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / original_fps

    # Calculate the frame interval based on the desired FPS or frame limit
    if frame_limit:
        frame_interval = max(1, total_frames // frame_limit)
    else:
        frame_interval = max(1, int(original_fps // fps))

    frame_count = 0
    extracted_count = 0
    base64_frames = []
    while video.isOpened() and (frame_limit is None or extracted_count < frame_limit):
        success, frame = video.read()
        if not success:
            break

        # Save the frame if it matches the frame interval
        if frame_count % frame_interval == 0:
            # Resize the frame
            height = int(frame.shape[0] * (resize_width / frame.shape[1]))
            resized_frame = cv2.resize(frame, (resize_width, height))

            frame_filename = os.path.join(output_folder, f"frame_{extracted_count:04d}.{output_format}")
            cv2.imwrite(frame_filename, resized_frame)
            extracted_count += 1

            # Convert the frame to base64 and add to the list
            _, buffer = cv2.imencode(f".{output_format}", resized_frame)
            base64_frames.append(base64.b64encode(buffer).decode("utf-8"))

        frame_count += 1

    video.release()
    if output_json:
        print(f"{extracted_count} frames extracted")
    else:
        print(f"{extracted_count} frames extracted to {output_folder}")

    # Write the base64 frames to a JSON file if requested
    if output_json:
        json_filename = os.path.join(output_dir, f"frames_{timestamp}.json")
        with open(json_filename, 'w') as json_file:
            json.dump(base64_frames, json_file)
        print(f"Base64-encoded frames saved to {json_filename}")

def extract_audio(video_path, output_dir):
    # Create the output filename based on the timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    audio_filename = os.path.join(output_dir, f"audio_{timestamp}.mp3")

    # Extract audio from the video
    with suppress_output():
        video_clip = VideoFileClip(video_path)
        audio_clip = video_clip.audio
        audio_clip.write_audiofile(audio_filename)
        audio_clip.close()
        video_clip.close()

    print(f"Audio extracted to {audio_filename}")

def main():
    parser = argparse.ArgumentParser(description="Extract frames and audio from a video file.")
    parser.add_argument("video_path", type=str, help="Path to the video file (mp4, mpeg, mpg).")
    parser.add_argument("output_dir", type=str, help="Directory to save the extracted frames and audio.")
    parser.add_argument("--format", type=str, choices=["jpg", "png"], default="jpg", help="Output image format (jpg or png).")
    parser.add_argument("--frames", type=int, default=None, help="Number of frames to extract (default: all frames).")
    parser.add_argument("--fps", type=float, default=1.0, help="Number of frames to extract per second (default: 1.0).")
    parser.add_argument("--json", action="store_true", help="Output a JSON file with base64-encoded image strings.")
    parser.add_argument("--width", type=int, default=768, help="Width to resize the images to (default: 768).")
    parser.add_argument("--audio", action="store_true", help="Extract audio from the video and save as an mp3 file.")

    args = parser.parse_args()

    extract_frames(args.video_path, args.output_dir, args.format, args.frames, args.fps, args.json, args.width)

    if args.audio:
        extract_audio(args.video_path, args.output_dir)

if __name__ == "__main__":
    main()
