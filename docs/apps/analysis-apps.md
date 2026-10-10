# Web & Media Analysis Apps

Apps that analyze external content: interactive web browsing with screenshot capture, and video content description.

## Web Insight :id=web-insight

Browse and capture web content with screenshots. When you provide a URL, the AI captures the page as viewport-sized screenshots. When interaction is needed (clicking, form filling, navigation), the AI opens a headless browser session and performs actions while returning screenshots for visual feedback.

**Key Features:**
- **Screenshot Capture**: Capture entire web pages as multiple viewport-sized images with automatic scrolling
- **Interactive Browsing**: The AI controls a headless Chrome browser — clicking links, filling forms, scrolling pages — and returns screenshots after each action
- **Customizable Viewports**: Desktop, tablet, mobile, and print presets
- **High Autonomy**: The AI operates with high autonomy, executing actions immediately without asking for confirmation at each step

**Interactive Browser Sessions:**

When you ask the AI to interact with a page, it starts a headless browser session in the Selenium container. The AI can click elements, type text, scroll pages, navigate between pages, and more — up to 20 actions per session. After each action, the AI receives a screenshot to verify the result.

When your instruction is ambiguous (e.g., "click the search button" when multiple candidates exist), the AI can annotate candidate elements with numbered labels on a screenshot and ask you to choose the correct one.

For live browser viewing, you can ask the AI to use non-headless mode. This enables real-time viewing via noVNC:

- **Electron app**: Open the noVNC window from **Open > Open noVNC** in the menu bar
- **Development mode**: Open `http://localhost:7900` in a separate browser tab

**Usage Examples:**
- `"Capture screenshots of https://github.com"` - Takes multiple screenshots
- `"Open https://example.com and click the About link"` - Interactive browsing
- `"Search for 'monadic chat' on Google"` - AI navigates and interacts with the page
- `"Take mobile screenshots of https://example.com"` - Uses mobile viewport preset

Web Insight is available with the providers marked in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

Get a detailed description of any video's content. The app analyzes a video by extracting keyframes and audio, then uses the AI to describe the visual and auditory information.

Frames are checked at the fps you give and selected so that the video's scenes and visible changes are covered, up to the number of images the provider accepts in one request. Each selected frame is sent with its time in the video, so the description can say when things happen; brief events between selected frames can be missed.

The audio track is transcribed separately. With OpenAI, the speech in the audio is found first and cut into segments of at most 30 seconds, and each segment is transcribed on its own, so every line of the transcript starts with the video times of its segment, for example `[01:02.300–01:05.100]`. The times come from where the segment lies in the audio, not from the transcription model. Sounds other than speech (music, applause, noise) are not transcribed. The transcript is also saved as `transcript.json` in a run folder of the chat's folder (`conversations/` in the Shared Folder). Timed transcripts need a Python container built for this version; with an older one, the transcript has no times and a note says to rebuild the container.

Before any frames are extracted, the file is checked: its format must match its extension (MP4, M4V, MOV, WebM, MKV, AVI or MPEG), it must contain a video track, last at most 50 minutes, and be at most 4096 pixels on each side. A file that does not pass is not processed, and the reason is shown. The audio is extracted as mono at 64 kbps, which keeps a 50-minute track within the size that speech-to-text accepts.

To use this app, place a video file in the `Shared Folder`, provide its name, and specify the frames per second (fps) for the analysis.
