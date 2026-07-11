# Video Generator

Create videos from text descriptions or existing images using provider video models.

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

Create videos using state-of-the-art AI models. This app supports both text-to-video and image-to-video generation with different aspect ratios and durations, intelligently leveraging session context for continuous workflows.

Some providers offer both fast and high-quality models. If you prefer higher quality, use keywords like "high quality" or "production" in your request.

**Key Features:**
-   **Text-to-video generation**: Create videos from text descriptions
-   **Image-to-video generation**: Animate existing images by using them as the first frame, automatically detecting uploaded images from the conversation session.
-   **Remix**: Modify existing videos with new prompts (supported by some providers), automatically referencing the last generated video from the conversation session.
-   **Multiple aspect ratios**: Choose between landscape and portrait formats

**Usage:**
1. For text-to-video: Provide a detailed description of the video you want to create
   - Include shot type, subject, action, setting, lighting, and camera movement
2. For image-to-video: Upload an image and describe how it should be animated; the system will automatically use the uploaded image from the session.
3. For remix (supported by some providers): After generating a video, simply request modifications (e.g., "make it longer") without re-specifying the video ID; the system will use the last generated video.
4. Specify quality preferences if needed by using keywords in your prompt

?> **Note:** Generated videos are saved in the `Shared Folder` and displayed in the chat interface.

**Example requests:**
- "Create a video of a sunset over mountains" → text-to-video generation
- "Create a high-quality marketing video" → text-to-video with high-quality model
- "Turn this image into a video of waves gently moving" → image-to-video generation
- "Make the video more colorful" (after generating) → remix with modifications (supported by some providers)

Video Generator is available with the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability).
