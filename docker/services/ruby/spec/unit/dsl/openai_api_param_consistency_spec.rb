# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting invariant: any production code that POSTs a request body
# to OpenAI's chat/completions or responses endpoint must use
# `max_completion_tokens` (and omit `temperature`) instead of `max_tokens`,
# because GPT-5.x rejects the legacy parameter names with a 400 Bad Request.
#
# Why this spec exists: `OpenAIHelper#api_request` migrated to
# `max_completion_tokens` long ago, but ad-hoc HTTP POSTs in Vision/Audio
# agents (`video_analyze_agent`, `image_analysis_agent`) kept using the
# legacy `max_tokens: 1000` hash literal because they bypass the helper.
# That divergence stayed hidden until Video Describer started shipping
# frames to gpt-5.4 (commit `8b8b7c9a` for the fix).
#
# Detection strategy: many agent files host *multiple* provider-specific
# methods (e.g. `vision_query_openai`, `vision_query_claude`,
# `vision_query_grok`) where each method points at a different vendor
# endpoint. A file-level grep would flag legitimate Claude usage of
# `max_tokens` (Anthropic's API requires it), so we instead split each
# file into "URI windows" — slices that start at every `uri = "..."`
# assignment and end just before the next one. A window is flagged
# only when (a) its URI string contains `api.openai.com` AND (b) the
# window body contains the bug pattern `max_tokens: <int>`.
RSpec.describe "OpenAI API parameter consistency" do
  ROOT_OAI = File.expand_path("../../..", __dir__)

  # Files that legitimately accept `max_tokens` as an input parameter and
  # convert it to `max_completion_tokens` before POSTing. The helper is
  # the *only* place this conversion is performed.
  EXEMPT_OAI_PATHS = [
    "lib/monadic/adapters/vendors/openai_helper.rb"
  ].freeze

  CANDIDATE_OAI_FILES = (
    Dir.glob(File.join(ROOT_OAI, "lib/**/*.rb")) +
    Dir.glob(File.join(ROOT_OAI, "apps/**/*.rb"))
  ).freeze

  # Bug pattern: Ruby symbol-style hash key with a numeric literal.
  #   max_tokens: 1000    → match
  #   options["max_tokens"] → no match (string-key options read)
  #   max_completion_tokens: 1000 → no match (different key)
  ANTI_PATTERN_OAI = /(?:^|[^_\w])max_tokens:\s*\d/

  # A "URI window" is the set of source lines spanning from one
  # `uri = "..."` assignment to the line just before the next one (or
  # to end of file). We attribute a `max_tokens:` literal to whichever
  # window encloses it. Implemented as a lambda so it is reachable
  # from inside the example block (RSpec hides describe-level
  # `def self.foo` methods from `it`).
  uri_windows = ->(content) {
    lines = content.lines
    starts = lines.each_with_index
                  .select { |line, _| line.match?(/^\s*uri\s*=\s*["']/) }
                  .map { |_, idx| idx }
    next [] if starts.empty?

    starts.each_with_index.map do |start, i|
      stop = (starts[i + 1] || lines.size) - 1
      uri_line = lines[start]
      body = lines[start..stop]
      uri = uri_line[/["']([^"']+)["']/, 1].to_s
      [uri, start + 1, body.join] # 1-based line number for human reading
    end
  }

  it "no provider-specific method that targets api.openai.com sends max_tokens" do
    offenders = CANDIDATE_OAI_FILES.each_with_object([]) do |path, acc|
      relative = path.sub("#{ROOT_OAI}/", "")
      next if EXEMPT_OAI_PATHS.include?(relative)

      content = File.read(path)
      next unless content.include?("api.openai.com")

      uri_windows.call(content).each do |uri, start_line, body|
        next unless uri.include?("api.openai.com")
        next unless body =~ ANTI_PATTERN_OAI

        body.lines.each_with_index do |line, offset|
          next unless line.match?(ANTI_PATTERN_OAI)
          acc << "#{relative}:#{start_line + offset}  #{line.strip}"
        end
      end
    end

    expect(offenders).to be_empty, <<~MSG
      The following lines POST `max_tokens` to OpenAI, which GPT-5.x rejects.
      Use `max_completion_tokens` (works on every current OpenAI model) and
      omit `temperature` (GPT-5.x rejects it; default 1.0 is fine for
      single-shot vision/audio queries).

      Offenders:
        #{offenders.join("\n  ")}
    MSG
  end
end
