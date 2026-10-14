# Video Generator

Create videos from text descriptions or existing images using provider video models.

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

Create videos from text descriptions (text-to-video) or from an image (image-to-video). Video Generator is available with Google Gemini (Veo) and xAI (Grok).

**Key Features:**
-   **Text-to-video generation**: Create videos from text descriptions
-   **Image-to-video generation**: Animate an image you upload in the conversation; the uploaded image is used without your naming it

**Options by provider:**
-   **Google Gemini (Veo)**: short videos in 16:9, with generated audio. A fast model is used by default; ask for "high quality" or "professional" to use the quality model. You can also describe what to avoid in the video.
-   **xAI (Grok)**: aspect ratio 16:9, 9:16, or 1:1, and a resolution of 720p or 480p. Text-to-video lasts 1 to 15 seconds, and image-to-video 6 to 15 seconds.

**Usage:**
1. For text-to-video: describe the video you want. Include the shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: upload an image and describe how it should move

?> **Note:** Generated videos are saved in the shared folder and shown in the chat.

**Example requests:**
- "Create a video of a sunset over mountains" → text-to-video
- "Create a high-quality marketing video" → text-to-video with the quality model (Gemini)
- "Turn this image into a video of waves gently moving" → image-to-video
- "Make a 10-second vertical video of a city at night" → text-to-video in 9:16 (xAI)

Video Generator is available with the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability).
