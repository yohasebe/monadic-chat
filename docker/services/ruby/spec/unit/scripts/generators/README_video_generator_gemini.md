# Video Generator (Gemini) Specs

`video_generator_gemini_spec.rb` covers `scripts/generators/video_generator_gemini.rb`, the command-line generator the Gemini variant of Video Generator runs. The request itself (Gemini Omni over the Interactions API) is covered in `spec/unit/utils/gemini_omni_video_spec.rb`.

See `docs_dev/ruby_service/testing/video_generator_gemini.md` for what each spec checks.

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/scripts/generators/video_generator_gemini_spec.rb
```
