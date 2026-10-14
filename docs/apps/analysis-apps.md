# Web & Media Analysis Apps

Apps that analyze external content: interactive web browsing with screenshot capture, and video content description.

## Web Insight :id=web-insight

Browse and capture web content with screenshots. When you provide a URL, the AI captures the page as viewport-sized screenshots. When interaction is needed (clicking, form filling, navigation), the AI opens a headless browser session and performs actions while returning screenshots for visual feedback.

**Key Features:**
- **Screenshot Capture**: Capture entire web pages as multiple viewport-sized images with automatic scrolling
- **Interactive Browsing**: The AI controls a headless Chrome browser — clicking links, filling forms, scrolling pages — and returns screenshots after each action
- **Customizable Viewports**: Desktop, tablet, mobile, and print presets
- **Few confirmations**: The AI carries out each action without asking for confirmation first

**Interactive Browser Sessions:**

When you ask the AI to interact with a page, it starts a headless browser session in the Selenium container. The AI can click elements, type text, scroll pages, navigate between pages, and more — up to 20 actions per session. After each action, the AI receives a screenshot to verify the result.

When your instruction is ambiguous (e.g., "click the search button" when multiple candidates exist), the AI can annotate candidate elements with numbered labels on a screenshot and ask you to choose the correct one.

To watch the browser while the AI works, ask the AI to use a visible (non-headless) browser, and open noVNC with **Open > Open noVNC** in the menu bar, or open `http://localhost:7900` in a browser.

**Usage Examples:**
- `"Capture screenshots of https://github.com"` - Takes multiple screenshots
- `"Open https://example.com and click the About link"` - Interactive browsing
- `"Search for 'monadic chat' on Google"` - AI navigates and interacts with the page
- `"Take mobile screenshots of https://example.com"` - Uses mobile viewport preset

Web Insight is available with the providers marked in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

Get a detailed description of a video. The app extracts frames and the audio from the video, and the AI describes what is seen and heard. Video Describer is available with OpenAI, Google Gemini, and xAI (Grok).

**How to use**: attach a video with the attach button below the message box (`Attach file` or `Image`, depending on the model), or place a video file in the shared folder and give its name. Give the frames per second (fps) to check. You can send the video with or without text. The answer plays the video.

**Video files**: MP4, M4V, MOV, WebM, MKV, AVI, or MPEG, with a video track, up to 50 minutes long and 4096 pixels on each side. The format must match the file extension. A file that does not meet these conditions is not processed, and the reason is shown.

**Frames**: frames are selected to cover the scenes and visible changes of the video, up to the number of images the provider accepts in one request, and the description says when things happen. Brief events between the selected frames can be missed. For a video longer than 10 minutes, ask for a detailed or thorough analysis: the video is described in parts of up to 10 minutes, so brief events are less likely to be missed. This takes longer and costs more. Parts that could not be described are reported as such.

**Audio**: the speech is transcribed with the speech-to-text of the app's provider, and each line of the transcript starts with its time in the video, for example `[01:02–01:06]`. The description relates what is said to what is shown. The full transcript is shown in its own section. Sounds other than speech (music, applause, noise) are not transcribed. With xAI Grok, speech that mixes languages, such as English words in Japanese speech, may come back in another script or translated; use OpenAI or Google Gemini for such recordings. The transcript is saved in the chat's folder (`conversations/` in the shared folder) with subtitle files (WebVTT and SRT), and the video in the answer plays with the subtitles. If the picture of a video starts later than its audio, the times in the transcript differ from the player's time by that amount, and the answer says so.

The detailed analysis and timed transcripts need an up-to-date Python container. If the container is older than the app, the answer says to rebuild it with **Actions → Build Python Container**.
