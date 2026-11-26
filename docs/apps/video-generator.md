# Video Generator

Create videos from text descriptions or existing images using provider video models.

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

Create videos from text descriptions (text-to-video) or from an image (image-to-video). Video Generator is available with Google Gemini (Gemini Omni) and xAI (Grok).

**Key Features:**
-   **Text-to-video generation**: Create videos from text descriptions
-   **Image-to-video generation**: Ask for a video from an image on the [work screen](../basic-usage/web-interface.md#work-screen) ("make a video from this image"): the image is read as it is when the video starts, and a work screen image is used only when you ask for it

**Options by provider:**
-   **Google Gemini (Gemini Omni)**: 720p in 16:9 or 9:16, lasting 3 to 10 seconds (8 by default), with generated audio. The image you ask for becomes the first frame. You can also describe what to avoid in the video.
-   **xAI (Grok)**: aspect ratio 16:9, 9:16, or 1:1, and a resolution of 720p or 480p. Text-to-video lasts 1 to 15 seconds, and image-to-video 6 to 15 seconds.

**Usage:**
1. For text-to-video: describe the video you want. Include the shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: put an image on the work screen and describe how it should move

?> **Note:** Generated videos are kept in the chat's folder in the shared folder and shown on the work screen beside the chat.

**Example requests:**
- "Create a video of a sunset over mountains" → text-to-video
- "Make a 5-second vertical video of falling leaves" → text-to-video in 9:16 (Gemini)
- "Turn this image into a video of waves gently moving" → image-to-video
- "Make a 10-second vertical video of a city at night" → text-to-video in 9:16 (xAI)

Video Generator is available with the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability).
