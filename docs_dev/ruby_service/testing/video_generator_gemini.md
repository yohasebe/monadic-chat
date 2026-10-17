# Video Generator (Gemini) Tests

The Gemini variant of Video Generator generates with Gemini Omni over the Interactions API. Three layers are tested with HTTP stubbed; no API is called. The class spec saves into a temporary folder and checks the files it writes.

| Spec | What is checked |
|---|---|
| `spec/unit/utils/gemini_omni_video_spec.rb` | `Monadic::Utils::GeminiOmniVideo`: the request (stateless and synchronous, `response_format` with aspect ratio, 720p and duration, an image as the first frame, what to avoid folded into the prompt); inputs refused before any request; a completed reply saved under a new name with no partial file left; a video given as an address downloaded only from the API host; replies without a usable MP4; refusals, provider errors and interactions that did not complete; a request whose reply never arrived, or broke while being read, is not sent again; the deadline; saving that never replaces or removes another file; provider messages without quoted data |
| `spec/unit/scripts/generators/video_generator_gemini_spec.rb` | `scripts/generators/video_generator_gemini.rb`: the key and the save folder, images read only from the shared folder (PNG, JPEG, WebP, up to 10 MB), the arguments passed to the generator, the options callers wrote for Veo accepted and ignored, one JSON line on stdout |
| `spec/unit/adapters/vendors/gemini_video_tool_spec.rb` | `generate_video_with_gemini` in `GeminiHelper`: the command it runs, the generator's JSON returned, and `generate_video_with_veo` answering with a note on the Veo-only settings Omni ignores |
| `spec/unit/utils/gemini_key_header_spec.rb` | The key goes in the `x-goog-api-key` header for generation and download, and is taken off any redirect that leaves the API host |

## Running

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/utils/gemini_omni_video_spec.rb spec/unit/scripts/generators/video_generator_gemini_spec.rb spec/unit/adapters/vendors/gemini_video_tool_spec.rb
```

The app-level tools are tested in `spec/unit/apps/video_generator_tools_spec.rb`.
