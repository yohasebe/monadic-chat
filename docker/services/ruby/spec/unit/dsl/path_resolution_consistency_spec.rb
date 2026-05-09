# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting invariant: shared-volume path resolution must go through
# the canonical `Monadic::Utils::Environment.shared_volume` accessor
# (per CLAUDE.md "Dual-Mode Execution"), never through lexical
# `defined?(SHARED_VOL)` / `defined?(LOCAL_SHARED_VOL)` checks.
#
# Why this spec exists: the legacy `defined?(SHARED_VOL)` pattern silently
# fails in production whenever the calling module lives outside MonadicApp's
# lexical chain — Ruby's `defined?` does not walk the receiver's class
# hierarchy, only Module.nesting. Tests previously masked the bug by
# calling `stub_const("SHARED_VOL", ...)`, which creates a *top-level*
# constant visible from every module — a namespace that production code
# never enjoys. Three agents (`video_analyze_agent`, `audio_transcription_agent`,
# `image_analysis_agent`) carried this bug for ~8 months before it surfaced
# in Video Describer (commit `0403fc68` for the fix).
#
# This spec walks every production Ruby file under `lib/` AND `apps/`
# and fails CI the moment a new occurrence of the anti-pattern is
# introduced. The `apps/` coverage was added 2026-05-09 after the
# Video Describer dogfood: `apps/auto_forge/utils/path_config.rb` had
# a `defined?(MonadicApp::SHARED_VOL)` form (fully qualified, so
# safe), but apps are a likely future site for the same bug if a
# new tool author copies the unqualified form from older code. The
# walk is cheap (file read + regex), so the broader coverage costs
# almost nothing.
RSpec.describe "Shared-volume path resolution consistency" do
  ROOT = File.expand_path("../../..", __dir__)

  # Files where the constants are legitimately defined or shadowed.
  EXEMPT_RELATIVE_PATHS = [
    "lib/monadic/app.rb"  # Defines SHARED_VOL / LOCAL_SHARED_VOL on MonadicApp
  ].freeze

  PRODUCTION_RUBY_FILES = (
    Dir.glob(File.join(ROOT, "lib/**/*.rb")) +
    Dir.glob(File.join(ROOT, "apps/**/*.rb"))
  ).freeze

  # Namespaced to avoid collision with other consistency specs in this
  # directory: `openai_api_param_consistency_spec` defines its own
  # bare-name `ANTI_PATTERN` (a max_tokens regex), and constants declared
  # inside `RSpec.describe do ... end` are written to the surrounding
  # scope (typically top-level), so the second-loaded spec silently
  # overwrites the first. We hit this when running both specs in one
  # rspec invocation: the SHARED_VOL check would match max_tokens lines.
  ANTI_PATTERN_PATH = /defined\?\(\s*(?:SHARED_VOL|LOCAL_SHARED_VOL)\s*\)/

  it "no production module relies on defined?(SHARED_VOL) / defined?(LOCAL_SHARED_VOL)" do
    offenders = PRODUCTION_RUBY_FILES.each_with_object([]) do |path, acc|
      relative = path.sub("#{ROOT}/", "")
      next if EXEMPT_RELATIVE_PATHS.include?(relative)

      content = File.read(path)
      next unless content =~ ANTI_PATTERN_PATH

      hits = content.lines.each_with_index.select { |line, _| line.match?(ANTI_PATTERN_PATH) }
      hits.each { |_, idx| acc << "#{relative}:#{idx + 1}" }
    end

    expect(offenders).to be_empty, <<~MSG
      The following lines use `defined?(SHARED_VOL)` or `defined?(LOCAL_SHARED_VOL)`,
      which never resolves outside MonadicApp's lexical scope and silently fails
      in production. Replace with `Monadic::Utils::Environment.shared_volume`
      (the canonical accessor — handles container vs. dev mode automatically).

      Offenders:
        #{offenders.join("\n  ")}
    MSG
  end
end
